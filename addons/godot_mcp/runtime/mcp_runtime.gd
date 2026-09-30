extends Node
const WireText = preload("res://addons/godot_mcp/utils/wire_text.gd")
## MCPRuntime — autoload that lives inside the user's running game and exposes
## a small set of "runtime" tools to the MCP server (take_screenshot,
## send_input, query_runtime_node, get_runtime_log, list_signal_connections).
##
## Connects to the same MCP WebSocket server as the editor plugin, but
## identifies itself with role="runtime" in its hello message so the server
## can route runtime tool calls to it.
##
## Auto-registered as an autoload by the godot_mcp editor plugin on
## _enable_plugin(); removed on _disable_plugin().

const PathGuard = preload("res://addons/godot_mcp/utils/path_guard.gd")

const MCPClientScript = preload("res://addons/godot_mcp/mcp_client.gd")
const CACHE_SCREENSHOT_DIR := "res://addons/godot_mcp/cache/screenshots/"
const LOG_RING_CAPACITY := 500

var _socket: WebSocketPeer = WebSocketPeer.new()
var _connected := false
var _reconnect_at_msec := 0
var _project_path := ""

# Circular buffer of recent runtime log lines, grown only by push_runtime_log():
# MCPRuntime's own connection events, plus whatever user scripts opt into by
# calling it. There is no supported way to intercept engine errors from inside a
# running game, so those are NOT here — the editor sees them over the debugger
# channel instead, and the debugger plugin in plugin.gd reports them as activity.
var _log_ring: Array = []
var _started_at_msec := 0
# Active monitor_properties jobs: each samples get_indexed() on a node's
# properties once per _process frame for N frames, then sends its tool_result.
var _monitor_jobs: Array = []
var _replay_jobs: Array = []

## Caps for the deterministic-testing tools. These bound a single call, not the
## session: an agent that asks for a million frames has made a mistake, and
## blocking the game for minutes while it finds out is the wrong way to say so.
const _STEP_FRAMES_MAX := 3600         # a minute at 60fps
const _TIME_SCALE_MAX := 10.0
const _AWAIT_CONDITION_MAX_MS := 60000

var _step_jobs: Array = []
var _condition_jobs: Array = []
## Batches waiting out their settle_frames before answering.
var _batch_jobs: Array = []

# Activity the agent is told about as it happens, over the same push channel the
# editor plugin uses. Scoped to what only the running game can see: the editor
# has no way to know that change_scene_to_file() just swapped the scene out, and
# every runtime node path the agent is holding is relative to that scene.
# Ids are this instance's own sequence, not the editor activity log's — the two
# streams are told apart by `source`, not by id.
var _activity_seq := 0
var _last_scene: Node = null


func _ready() -> void:
	# Spawned multiplayer test peers pass --no-mcp so they don't fight the primary
	# game instance for the single runtime slot on the bridge. They just run as
	# network clients; the agent inspects the server instance instead.
	if OS.get_cmdline_user_args().has("--no-mcp"):
		set_process(false)
		set_physics_process(false)
		return
	_project_path = ProjectSettings.globalize_path("res://")
	_started_at_msec = Time.get_ticks_msec()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_consume_debug_collisions_marker()
	push_runtime_log("info", "MCPRuntime starting (project=%s)" % _project_path)
	_attempt_connect()


## Set by run_scene(debug_collisions=true) just before Play launches this
## process, so this runs before any scene node exists — the one point
## SceneTree.debug_collisions_hint is documented to reliably apply from.
## Consumed once so it does not leak into a manual Play the developer runs by
## hand later.
const _DEBUG_COLLISIONS_MARKER := "res://addons/godot_mcp/cache/.debug_collisions"

func _consume_debug_collisions_marker() -> void:
	if not FileAccess.file_exists(_DEBUG_COLLISIONS_MARKER):
		return
	get_tree().debug_collisions_hint = true
	DirAccess.remove_absolute(_DEBUG_COLLISIONS_MARKER)
	push_runtime_log("info", "debug_collisions_hint enabled for this run (run_scene debug_collisions=true).")


func _process(_delta: float) -> void:
	_socket.poll()
	var st := _socket.get_ready_state()

	if st == WebSocketPeer.STATE_OPEN:
		if not _connected:
			_connected = true
			var hello := {
				"type": "godot_ready",
				"role": "runtime",
				"project_path": _project_path,
				"started_at": _started_at_msec,
			}
			# Same secret as the editor client, resolved the same way — a server
			# started with one configured would otherwise refuse the runtime and
			# every runtime-only tool would look like "game not running".
			var secret := MCPClientScript.resolve_secret()
			if not secret.is_empty():
				hello["secret"] = secret
			_send(hello)
			push_runtime_log("info", "MCPRuntime connected to MCP server.")

		while _socket.get_available_packet_count() > 0:
			var raw := _socket.get_packet().get_string_from_utf8()
			_handle_message(raw)

		_tick_monitors()
		_tick_replays()
		_tick_scene_awareness()
		_tick_step_jobs("process")

	elif st == WebSocketPeer.STATE_CLOSED:
		if _connected:
			_connected = false
			push_runtime_log("warn", "MCPRuntime disconnected; will retry.")
		var now := Time.get_ticks_msec()
		if now >= _reconnect_at_msec:
			_attempt_connect()


## Physics frames are what move bodies, so they are what a game-state assertion
## actually cares about — and they tick at a fixed rate regardless of frame rate,
## which is what makes step_frames reproducible across machines. await_condition
## samples here for the same reason.
func _physics_process(_delta: float) -> void:
	_tick_step_jobs("physics")
	_tick_condition_jobs()
	_tick_batch_jobs()


func _attempt_connect() -> void:
	_socket = WebSocketPeer.new()
	_socket.outbound_buffer_size = 8 * 1024 * 1024  # screenshots can be big
	_socket.inbound_buffer_size = 256 * 1024
	# Same resolution as the editor client (env var, then project setting, then
	# 6505) so a project on a non-default port doesn't leave the running game
	# dialling the wrong server.
	var err := _socket.connect_to_url(MCPClientScript.default_url())
	_reconnect_at_msec = Time.get_ticks_msec() + 2000
	if err != OK:
		push_runtime_log("warn", "MCPRuntime connect_to_url failed: %d (%s)" % [err, error_string(err)])


func _handle_message(json_string: String) -> void:
	var msg = JSON.parse_string(json_string)
	if msg == null or not msg is Dictionary:
		return
	var msg_type: String = str(msg.get("type", ""))
	match msg_type:
		"ping":
			_send({"type": "pong"})
		"tool_invoke":
			var rid: String = str(msg.get("id", ""))
			var tool_name: String = str(msg.get("tool", ""))
			var args = msg.get("args", {})
			if not args is Dictionary:
				args = {}
			_parse_stringified_args(args)
			# monitor_properties samples over N frames — it can't return a value
			# synchronously. Register a job that samples in _process and sends its
			# own tool_result when finished, then return here without sending.
			if tool_name == "monitor_properties":
				_start_monitor(rid, args)
				return
			# replay_input_sequence feeds events over N frames — also async.
			if tool_name == "replay_input_sequence":
				_start_replay(rid, args)
				return
			if tool_name == "await_signal_runtime":
				_start_await_signal(rid, args)
				return
			# step_frames and await_condition both resolve over frames rather
			# than immediately, so they answer from their own tick like the above.
			if tool_name == "step_frames":
				_start_step_frames(rid, args)
				return
			if tool_name == "await_condition":
				_start_await_condition(rid, args)
				return
			# A batch asked to settle answers after those frames, so it takes the
			# async path too. Without settle_frames it stays synchronous, which
			# is the common case and the cheap one.
			if tool_name == "batch_runtime" and int(args.get("settle_frames", 0)) > 0:
				_start_batch_runtime(rid, args)
				return
			var result := _dispatch(tool_name, args)
			var success: bool = bool(result.get("ok", false))
			result.erase("ok")
			_send({
				"type": "tool_result",
				"id": rid,
				"success": success,
				# The payload goes back on FAILURE too, which the editor side has
				# always done and this side never did: everything a failed tool
				# says beyond its error string — which operation of a batch broke,
				# what it found instead, what was clamped — was being dropped, and
				# the caller got a bare "Tool execution failed".
				"result": result,
				"error": str(result.get("error", "")) if not success else "",
			})
		_:
			pass


## The runtime WebSocket bridge does NOT go through tool_executor.gd's
## _parse_stringified_args, so compound/scalar args that some MCP clients
## stringify (e.g. `event` as '{"type":"key",...}', `properties` as '["x"]',
## or a bool as "false") arrive here as raw Strings. A typed local like
## `var event_desc: Dictionary = args.get("event")` then hard-crashes the
## dispatch and NO tool_result is ever sent — the call hangs to timeout.
## Repair args in place, mirroring the editor-side fix, so every runtime tool
## receives real types. (Per-tool guards like _parse_tween_value/_parse_bool_arg
## stay as defense in depth.)
func _parse_stringified_args(args: Dictionary) -> void:
	for key in args:
		var val = args[key]
		if val is String:
			var s: String = val.strip_edges()
			if s == "true":
				args[key] = true
			elif s == "false":
				args[key] = false
			elif (s.begins_with("{") and s.ends_with("}")) or (s.begins_with("[") and s.ends_with("]")):
				var parsed = JSON.parse_string(s)
				if parsed != null:
					args[key] = parsed


## Tools that answer LATER, through the async job queues (rid + tick), rather
## than returning a Dictionary here. A batch cannot carry them: one request id
## cannot fan out into several deferred answers, and pretending otherwise would
## return "ok" for work that had not happened — the failure this surface is
## most careful about.
const _ASYNC_RUNTIME_TOOLS := {
	"step_frames": "it answers after N frames",
	"await_condition": "it answers when the condition holds",
	"await_signal_runtime": "it answers when the signal fires",
	"monitor_properties": "it answers after sampling N frames — and it takes setup_code, which is the one-call version of trigger-then-watch",
	"replay_input_sequence": "it answers after playing the sequence — which is itself the batched form of send_input",
	"wait": "it answers after the wait",
}


## Run several runtime tools in ONE round trip.
##
## Driving a running game is inherently several calls — press, look, press,
## look — and each one is a WebSocket round trip through the bridge while the
## game keeps running underneath. The editor side has had batch_execute for
## this; the runtime side, where the round trips actually hurt, had nothing.
##
## Synchronous tools only, by construction (see _ASYNC_RUNTIME_TOOLS). Runs in
## order, stops at the first failure when stop_on_error, and reports each
## result positionally so a caller can tell which step went wrong.
func _batch_runtime(args: Dictionary) -> Dictionary:
	var ops = args.get("operations", [])
	if ops is String:
		var parsed = JSON.parse_string(ops)
		if parsed is Array:
			ops = parsed
	if not (ops is Array) or (ops as Array).is_empty():
		return {"ok": false, "error": "Missing 'operations' (non-empty array of {tool, args})"}
	if (ops as Array).size() > 50:
		return {"ok": false, "error": "Too many operations (max 50 per runtime batch)"}

	var stop_on_error := bool(args.get("stop_on_error", false))
	var results: Array = []
	var all_ok := true

	for i in range((ops as Array).size()):
		var op_v = (ops as Array)[i]
		if not (op_v is Dictionary) or not (op_v as Dictionary).has("tool"):
			results.append({"ok": false, "error": "Operation %d must be an object with a 'tool' field" % i})
			all_ok = false
			if stop_on_error:
				break
			continue

		var op: Dictionary = op_v
		var op_tool := str(op.get("tool", ""))
		if _ASYNC_RUNTIME_TOOLS.has(op_tool):
			results.append({"ok": false, "error": "'%s' cannot be batched: %s. Call it on its own." % [op_tool, _ASYNC_RUNTIME_TOOLS[op_tool]]})
			all_ok = false
			if stop_on_error:
				break
			continue
		if op_tool == "batch_runtime":
			results.append({"ok": false, "error": "batch_runtime cannot be nested"})
			all_ok = false
			if stop_on_error:
				break
			continue

		var op_args: Dictionary = op.get("args", {}) if op.get("args", {}) is Dictionary else {}
		_parse_stringified_args(op_args)
		var res := _dispatch(op_tool, op_args)
		results.append(res)
		if not res.get("ok", false):
			all_ok = false
			if stop_on_error:
				break

	return {
		"ok": all_ok,
		"count": results.size(),
		"requested": (ops as Array).size(),
		"all_ok": all_ok,
		"results": results,
	}


## A batch that has to let the game move before it answers.
##
## "Press, let some frames pass, look" is the shape driving a game actually
## takes, and it was the one thing a batch could not express: `wait` and
## `step_frames` answer later, so they cannot be operations inside one. This
## runs the operations now, lets `settle_frames` physics frames pass, and then
## answers — one round trip for the whole shape.
func _start_batch_runtime(rid: String, args: Dictionary) -> void:
	var frames := clampi(int(args.get("settle_frames", 0)), 1, _STEP_FRAMES_MAX)
	var out := _batch_runtime(args)
	var ok: bool = bool(out.get("ok", false))
	out.erase("ok")
	out["settled_frames"] = frames
	_batch_jobs.append({"rid": rid, "remaining": frames, "payload": out, "ok": ok})


func _tick_batch_jobs() -> void:
	if _batch_jobs.is_empty():
		return
	var still_running: Array = []
	for job in _batch_jobs:
		job["remaining"] = int(job["remaining"]) - 1
		if int(job["remaining"]) > 0:
			still_running.append(job)
			continue
		_send_async_result(str(job["rid"]), bool(job["ok"]), job["payload"])
	_batch_jobs = still_running


func _dispatch(tool_name: String, args: Dictionary) -> Dictionary:
	match tool_name:
		"batch_runtime":
			return _batch_runtime(args)
		"take_screenshot":
			return _take_screenshot(args)
		"send_input":
			return _send_input(args)
		"query_runtime_node":
			return _query_runtime_node(args)
		"get_runtime_log":
			return _get_runtime_log(args)
		"list_signal_connections":
			return _list_signal_connections(args)
		"connect_signal_runtime":
			return _connect_signal_runtime(args)
		"disconnect_signal_runtime":
			return _disconnect_signal_runtime(args)
		"tween_property_runtime":
			return _tween_property_runtime(args)
		"play_animation_runtime":
			return _play_animation_runtime(args)
		"dump_control_tree":
			return _dump_control_tree(args)
		"click_control_runtime":
			return _click_control_runtime(args)
		"get_focused_control":
			return _get_focused_control(args)
		"assert_screen_text":
			return _assert_screen_text(args)
		"game_eval":
			return _game_eval(args)
		"serialize_runtime_tree":
			return _serialize_runtime_tree(args)
		"call_method_runtime":
			return _call_method_runtime(args)
		"set_runtime_property":
			return _set_runtime_property(args)
		"start_input_recording":
			return _start_input_recording(args)
		"stop_input_recording":
			return _stop_input_recording(args)
		"get_multiplayer_status":
			return _get_multiplayer_status(args)
		"call_rpc_runtime":
			return _call_rpc_runtime(args)
		"seed_rng":
			return _seed_rng(args)
		"time_scale":
			return _time_scale(args)
		_:
			return {"ok": false, "error": "Unknown runtime tool: %s" % tool_name}


# =============================================================================
# Deterministic testing — seed_rng / time_scale / step_frames / await_condition
# =============================================================================
# Testing a game that involves chance or motion is only meaningful if a run can
# be repeated. `wait` cannot give that: it waits wall-clock milliseconds, so the
# number of frames that elapse depends on the machine and the frame rate, and a
# test that passes here fails on a slower box for no reason anyone can see.

## Pin the global RNG so a run involving chance can be replayed.
func _seed_rng(args: Dictionary) -> Dictionary:
	if not args.has("seed"):
		return {"ok": false, "error": "Missing 'seed' (an integer)"}
	var s := int(args.get("seed"))
	seed(s)
	return {
		"ok": true,
		"seed": s,
		# Said out loud rather than left to be discovered: a run that LOOKS
		# reproducible but is not is worse than one that never claimed to be.
		"note": "Seeds the global functions only (randi, randf, randi_range, ...). A RandomNumberGenerator the game created itself keeps its own state — seed that instance through set_runtime_property if the code under test uses one.",
	}


## Speed the game up or slow it down. 0 freezes it without pausing the tree, so
## frames still process and step_frames still advances.
func _time_scale(args: Dictionary) -> Dictionary:
	if not args.has("scale"):
		return {"ok": false, "error": "Missing 'scale' (1.0 = normal, 0.5 = half speed, 0 = frozen)"}
	var requested := float(args.get("scale"))
	# Negative time is not meaningful, and a very large scale makes physics
	# tunnel through colliders rather than fast-forward, which reads as a bug in
	# the game under test.
	var scale := clampf(requested, 0.0, _TIME_SCALE_MAX)
	Engine.time_scale = scale
	var out := {"ok": true, "time_scale": scale}
	if not is_equal_approx(scale, requested):
		out["clamped"] = true
		out["requested"] = requested
		out["note"] = "Clamped to 0..%d. Above that, physics tunnels instead of fast-forwarding." % _TIME_SCALE_MAX
	return out


## Advance an exact number of frames, then answer. Deterministic where `wait` is
## not: the same call advances the same amount of simulation on every machine.
func _start_step_frames(rid: String, args: Dictionary) -> void:
	var requested := int(args.get("frames", 1))
	if requested < 1:
		_send_async_result(rid, false, {"error": "'frames' must be at least 1"})
		return
	var mode := str(args.get("mode", "physics")).to_lower()
	if mode != "physics" and mode != "process":
		_send_async_result(rid, false, {"error": "'mode' must be \"physics\" (default) or \"process\""})
		return
	var frames := mini(requested, _STEP_FRAMES_MAX)
	_step_jobs.append({
		"rid": rid, "mode": mode, "remaining": frames,
		"frames": frames, "requested": requested,
		"started_ms": Time.get_ticks_msec(),
	})


func _tick_step_jobs(mode: String) -> void:
	if _step_jobs.is_empty():
		return
	var still_running: Array = []
	for job in _step_jobs:
		if str(job["mode"]) != mode:
			still_running.append(job)
			continue
		job["remaining"] = int(job["remaining"]) - 1
		if int(job["remaining"]) > 0:
			still_running.append(job)
			continue
		var out := {
			"frames": int(job["frames"]),
			"mode": mode,
			"elapsed_ms": Time.get_ticks_msec() - int(job["started_ms"]),
		}
		if int(job["requested"]) > int(job["frames"]):
			out["clamped"] = true
			out["requested"] = int(job["requested"])
		_send_async_result(str(job["rid"]), true, out)
	_step_jobs = still_running


## Wait until a GDScript expression is true, rather than for a fixed time or a
## specific signal. Compiled once, then evaluated once per physics frame.
func _start_await_condition(rid: String, args: Dictionary) -> void:
	var code := str(args.get("condition", ""))
	if code.strip_edges().is_empty():
		_send_async_result(rid, false, {"error": "Missing 'condition' (a GDScript expression, e.g. \"node.is_on_floor()\")"})
		return

	# Expression, NOT a compiled GDScript. Building a GDScript from a string
	# inside a running game and calling reload() on it reports any parse error
	# through the engine's global error handler, and when the game was launched
	# from the editor that handler makes the debugger BREAK: the game freezes
	# mid-call and the failure surfaces ~25s later as a disconnect. Measured both
	# ways — the same bad source from a CLI-launched game returns cleanly in 0s,
	# so it is the attached debugger, not the reload. Expression.parse returns an
	# error code and a message and never involves the debugger at all. game_eval
	# cannot use it (it needs statements) and is pre-checked in the editor
	# instead; see validate_eval_snippet.
	var expr := Expression.new()
	var parse_err := expr.parse(code, ["tree", "node"])
	if parse_err != OK:
		_send_async_result(rid, false, {
			"error": "Could not parse the condition: %s" % expr.get_error_text(),
			"hint": "It is an expression, not a function body — write `node.is_on_floor()`, not `return node.is_on_floor()`. `tree` and `node` are in scope.",
		})
		return

	var node_path := str(args.get("node_path", ""))
	var node: Node = null
	if not node_path.is_empty():
		node = _resolve_runtime_node(node_path)
		if node == null:
			_send_async_result(rid, false, {"error": "Node not found: " + node_path})
			return

	var timeout_ms := clampi(int(args.get("timeout_ms", 5000)), 1, _AWAIT_CONDITION_MAX_MS)
	_condition_jobs.append({
		"rid": rid, "expression": expr, "node": node, "source": code,
		"deadline_ms": Time.get_ticks_msec() + timeout_ms,
		"timeout_ms": timeout_ms,
		"started_ms": Time.get_ticks_msec(),
		"frames": 0, "last": null,
	})


func _tick_condition_jobs() -> void:
	if _condition_jobs.is_empty():
		return
	var still_running: Array = []
	var now := Time.get_ticks_msec()
	for job in _condition_jobs:
		job["frames"] = int(job["frames"]) + 1
		var expr: Expression = job["expression"]
		var value = expr.execute([get_tree(), job["node"]], null, false)
		if expr.has_execute_failed():
			# A parse-clean expression can still fail at runtime (a null node, a
			# method that does not exist). Report it once and stop, rather than
			# re-failing every frame until the timeout.
			# `return x` parses cleanly — Expression reads `return` as an unknown
			# identifier and only fails here, looking it up on a null self. The
			# engine's message for that says nothing about the real mistake, and
			# it is the mistake callers make, since every other snippet argument
			# here IS a function body.
			var failure := {
				"error": "The condition failed while evaluating: %s" % expr.get_error_text(),
				"frames_waited": int(job["frames"]),
			}
			if str(job.get("source", "")).strip_edges().begins_with("return"):
				failure["hint"] = "Drop the `return`: this argument is an expression, not a function body. Write `node.is_on_floor()`, not `return node.is_on_floor()`. `tree` and `node` are in scope."
			_send_async_result(str(job["rid"]), false, failure)
			continue
		job["last"] = value
		if _is_truthy(value):
			_send_async_result(str(job["rid"]), true, {
				"met": true,
				"value": _serialize(value),
				"frames_waited": int(job["frames"]),
				"elapsed_ms": now - int(job["started_ms"]),
			})
			continue
		if now >= int(job["deadline_ms"]):
			# Not an error: "it never became true" is a result a test asserts on.
			# The last value is included because that is what makes it debuggable.
			_send_async_result(str(job["rid"]), true, {
				"met": false,
				"value": _serialize(value),
				"frames_waited": int(job["frames"]),
				"elapsed_ms": now - int(job["started_ms"]),
				"note": "Condition never became true within timeout_ms; the last value it evaluated to is above.",
			})
			continue
		still_running.append(job)
	_condition_jobs = still_running


## GDScript truthiness for the values a condition realistically returns. An empty
## array or dictionary counts as false so `return get_tree().get_nodes_in_group("enemies")`
## behaves the way the caller obviously meant.
func _is_truthy(value) -> bool:
	match typeof(value):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return value
		TYPE_INT, TYPE_FLOAT:
			return value != 0
		TYPE_STRING, TYPE_STRING_NAME:
			return not str(value).is_empty()
		TYPE_ARRAY:
			return not (value as Array).is_empty()
		TYPE_DICTIONARY:
			return not (value as Dictionary).is_empty()
		_:
			return value != null

## Shared node resolver: absolute paths (starting with "/") are looked up
## from tree.root; relative paths try current_scene first, then tree.root —
## mirrors _query_runtime_node's resolution rules.
func _resolve_runtime_node(node_path: String) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	if node_path.begins_with("/"):
		return tree.root.get_node_or_null(NodePath(node_path))
	var current := tree.current_scene
	if current:
		var found := current.get_node_or_null(NodePath(node_path))
		if found:
			return found
	return tree.root.get_node_or_null(NodePath(node_path))


# =============================================================================
# game_eval — run a GDScript snippet inside the running game (like a REPL)
# =============================================================================
## The snippet becomes the body of a function receiving `tree` (the SceneTree) and
## `node` (the node at node_path, or null). `return X` to get a value back. Powerful
## — arbitrary code in your own running game — and runtime-only. Note: a RUNTIME
## error inside the snippet can't be caught from GDScript and will time out the call;
## the compile step is guarded, the execution is on you.
##
## The compile below is the second line of defence: the MCP server already tried
## the same source in the editor (validate_eval_snippet), because a parse error
## HERE breaks the attached debugger and freezes the game. This branch is what
## catches it when no editor is connected, where the freeze cannot happen.
func _game_eval(args: Dictionary) -> Dictionary:
	var code := str(args.get("code", ""))
	if code.strip_edges().is_empty():
		return {"ok": false, "error": "Missing 'code' (a GDScript snippet; use `return X` for a result)"}
	var node_path := str(args.get("node_path", ""))

	var compiled := _compile_eval(code)
	if not compiled.get("ok", false):
		return compiled

	# A node_path that does not resolve is checked HERE rather than being handed
	# to the snippet as null. GDScript cannot catch the "Invalid access on a null
	# instance" that follows, the attached debugger breaks on it, and the helper
	# stops answering — so one stale path in a query costs the whole runtime
	# connection and a scene restart. Measured: that is exactly how it was lost,
	# on a node that had been freed a few seconds earlier.
	var node = null
	if not node_path.is_empty():
		node = _resolve_runtime_node(node_path)
		if node == null:
			return {
				"ok": false,
				"error": "No node at '%s'. It may have been freed, or the path may be missing the runtime root prefix (run_scene reports it as runtime_root, e.g. \"/root/Main/Player\"). Nothing was executed — passing a null node into the snippet would break the debugger and drop this connection." % node_path,
			}

	var result = compiled["instance"].call("_mcp_eval", get_tree(), node)
	return {"ok": true, "result": _serialize(result)}


## Compile a GDScript snippet into a callable `_mcp_eval(tree, node)`.
##
## Shared by game_eval and await_condition: the latter compiles ONCE and then
## calls the result every frame, so re-parsing per frame would be the whole cost
## of the tool.
func _compile_eval(code: String) -> Dictionary:
	var src := "extends RefCounted\nfunc _mcp_eval(tree, node):\n"
	for line in code.split("\n"):
		src += "\t" + line + "\n"

	var gd := GDScript.new()
	gd.source_code = src
	var err := gd.reload()
	if err != OK:
		return {"ok": false, "error": "Compile error in eval snippet (err=%d). The snippet is a function body — indent-free, and `return X` for a value." % err}
	var inst = gd.new()
	if inst == null or not inst.has_method("_mcp_eval"):
		return {"ok": false, "error": "Eval snippet did not compile into a runnable method"}
	return {"ok": true, "instance": inst}

# =============================================================================
# serialize_runtime_tree — snapshot the running scene tree to JSON
# =============================================================================
## Walk the live tree from node_path (default: current_scene) and return a JSON
## structure of name/class per node, optionally with a chosen set of properties.
## Full-state introspection without screenshots — good for asserting game state.
func _serialize_runtime_tree(args: Dictionary) -> Dictionary:
	var node_path := str(args.get("node_path", ""))
	var max_depth := clampi(int(args.get("max_depth", 5)), 1, 20)
	var props: Array = []
	var props_arg = args.get("properties", [])
	if props_arg is Array:
		for p in props_arg:
			props.append(str(p))

	var root: Node
	if node_path.is_empty():
		root = get_tree().current_scene if get_tree() else null
	else:
		root = _resolve_runtime_node(node_path)
	if root == null:
		return {"ok": false, "error": "Node not found: " + (node_path if not node_path.is_empty() else "(current_scene)")}

	return {"ok": true, "node_path": node_path, "tree": _serialize_node_tree(root, props, max_depth, 0)}

func _serialize_node_tree(node: Node, props: Array, max_depth: int, depth: int) -> Dictionary:
	var d := {"name": str(node.name), "class": node.get_class()}
	if not props.is_empty():
		var pv := {}
		for p in props:
			pv[p] = _serialize(node.get(p))
		d["properties"] = pv
	if depth < max_depth:
		var kids: Array = []
		for c in node.get_children():
			kids.append(_serialize_node_tree(c, props, max_depth, depth + 1))
		if not kids.is_empty():
			d["children"] = kids
	elif node.get_child_count() > 0:
		d["children_truncated"] = node.get_child_count()
	return d


# =============================================================================
# call_method_runtime / set_runtime_property — drive a live node directly
# =============================================================================
## Call a method on a node in the running game and return its result. General
## way to trigger game logic or query state (e.g. call "take_damage" with [10]).
func _call_method_runtime(args: Dictionary) -> Dictionary:
	var node_path := str(args.get("node_path", "")).strip_edges()
	var method := str(args.get("method", "")).strip_edges()
	if node_path.is_empty() or method.is_empty():
		return {"ok": false, "error": "node_path and method are required"}
	var node := _resolve_runtime_node(node_path)
	if not node:
		return {"ok": false, "error": "Node not found: " + node_path}
	if not node.has_method(method):
		return {"ok": false, "error": "Node '%s' (%s) has no method '%s'" % [node_path, node.get_class(), method]}
	var call_args: Array = []
	var raw = args.get("args", [])
	if raw is Array:
		for a in raw:
			call_args.append(_parse_tween_value(a))
	var result = node.callv(method, call_args)
	return {"ok": true, "node_path": node_path, "method": method, "result": _serialize(result)}

## Set a property on a live node, with get_indexed() sub-path support ("position:x").
## Reads the value back so the caller sees what actually landed.
func _set_runtime_property(args: Dictionary) -> Dictionary:
	var node_path := str(args.get("node_path", "")).strip_edges()
	var property := str(args.get("property", "")).strip_edges()
	if node_path.is_empty() or property.is_empty():
		return {"ok": false, "error": "node_path and property are required"}
	if not args.has("value"):
		return {"ok": false, "error": "Missing 'value'"}
	var node := _resolve_runtime_node(node_path)
	if not node:
		return {"ok": false, "error": "Node not found: " + node_path}
	node.set_indexed(NodePath(property), _parse_tween_value(args.get("value")))
	return {"ok": true, "node_path": node_path, "property": property,
		"value": _serialize(node.get_indexed(NodePath(property)))}

# =============================================================================
# get_multiplayer_status / call_rpc_runtime — inspect & drive networking
# =============================================================================
## Report the running game's high-level multiplayer state: peer id, server/client
## role, connected peers, transport status. Works offline too (reports single-player).
func _get_multiplayer_status(_args: Dictionary) -> Dictionary:
	var mp := multiplayer
	if mp == null:
		return {"ok": false, "error": "No MultiplayerAPI available"}
	var peer = mp.multiplayer_peer
	var has_peer: bool = peer != null and not (peer is OfflineMultiplayerPeer)
	var info := {
		"unique_id": mp.get_unique_id(),
		"is_server": mp.is_server(),
		"has_active_peer": has_peer,
	}
	if has_peer:
		var status_names := ["disconnected", "connecting", "connected"]
		var st := int(peer.get_connection_status())
		info["connection_status"] = status_names[st] if st >= 0 and st < status_names.size() else str(st)
		info["connected_peers"] = mp.get_peers()
		info["peer_class"] = peer.get_class()
	else:
		info["note"] = "No active multiplayer peer — the game is running offline / single-player."
	return {"ok": true, "multiplayer": info}

## Call an @rpc method on a node via rpc()/rpc_id(). peer_id 0 (default) broadcasts;
## a specific id targets one peer. Returns the RPC dispatch error code (OK = 0).
func _call_rpc_runtime(args: Dictionary) -> Dictionary:
	var node_path := str(args.get("node_path", "")).strip_edges()
	var method := str(args.get("method", "")).strip_edges()
	if node_path.is_empty() or method.is_empty():
		return {"ok": false, "error": "node_path and method are required"}
	var node := _resolve_runtime_node(node_path)
	if not node:
		return {"ok": false, "error": "Node not found: " + node_path}
	if not node.has_method(method):
		return {"ok": false, "error": "Node '%s' (%s) has no method '%s'" % [node_path, node.get_class(), method]}
	var call_args: Array = []
	var raw = args.get("args", [])
	if raw is Array:
		for a in raw:
			call_args.append(_parse_tween_value(a))
	var peer_id := int(args.get("peer_id", 0))
	var err
	if peer_id != 0:
		err = node.callv("rpc_id", [peer_id, StringName(method)] + call_args)
	else:
		err = node.callv("rpc", [StringName(method)] + call_args)
	# The tool ran; rpc_error carries the RPC's own result code (0 = OK, else e.g.
	# ERR_UNCONFIGURED 13 if the method has no @rpc annotation). Non-OK is not a
	# tool failure, so ok stays true and the payload survives.
	return {"ok": true, "node_path": node_path, "method": method, "peer_id": peer_id,
		"rpc_error": int(err), "rpc_ok": int(err) == OK,
		"note": "rpc dispatched; actual delivery depends on the multiplayer setup (offline it runs locally if you are the authority)."}


# =============================================================================
# await_signal_runtime — wait (with timeout) for a signal in the running game
# =============================================================================
## Resolves when the named signal fires on the node, or when timeout_ms elapses.
## Lets an agent assert event-driven behaviour ("did the player emit 'died'?").
## The helper class accepts up to 8 optional args so it matches signals of any
## common arity without knowing it in advance.
class _SignalAwait extends RefCounted:
	var runtime: Object
	var rid: String
	func fire(_a = null, _b = null, _c = null, _d = null, _e = null, _f = null, _g = null, _h = null) -> void:
		runtime._resolve_await(rid, {"signal_fired": true, "timed_out": false})

var _awaits: Dictionary = {}  # rid -> true while pending (guards double-resolve)

func _start_await_signal(rid: String, args: Dictionary) -> void:
	var node_path := str(args.get("node_path", "")).strip_edges()
	var signal_name := str(args.get("signal", "")).strip_edges()
	var timeout_ms := clampi(int(args.get("timeout_ms", 3000)), 1, 60000)
	if node_path.is_empty() or signal_name.is_empty():
		_send_async_result(rid, false, {"error": "node_path and signal are required"})
		return
	var node := _resolve_runtime_node(node_path)
	if not node:
		_send_async_result(rid, false, {"error": "Node not found: " + node_path})
		return
	if not node.has_signal(signal_name):
		_send_async_result(rid, false, {"error": "Node '%s' (%s) has no signal '%s'" % [node_path, node.get_class(), signal_name]})
		return
	var handle := _SignalAwait.new()
	handle.runtime = self
	handle.rid = rid
	_awaits[rid] = handle  # keep the handle alive until resolved (the Callable alone may not)
	node.connect(signal_name, handle.fire, CONNECT_ONE_SHOT)
	var timer := get_tree().create_timer(timeout_ms / 1000.0)
	timer.timeout.connect(func(): _resolve_await(rid, {"signal_fired": false, "timed_out": true}))

## Send an await result exactly once (first of signal / timeout wins).
func _resolve_await(rid: String, payload: Dictionary) -> void:
	if not _awaits.has(rid):
		return
	_awaits.erase(rid)
	_send_async_result(rid, true, payload)


# =============================================================================
# take_screenshot
# =============================================================================
func _take_screenshot(args: Dictionary) -> Dictionary:
	var save_to: String = str(args.get("save_to", "")).strip_edges()
	var return_base64: bool = bool(args.get("return_base64", false))

	var viewport := get_viewport()
	if viewport == null:
		return {"ok": false, "error": "No viewport available"}
	var img: Image = viewport.get_texture().get_image()
	if img == null:
		return {"ok": false, "error": "Viewport returned no image"}

	var resource_path := ""
	if save_to.is_empty():
		_ensure_cache_dir()
		resource_path = "%sscreenshot_%d.png" % [CACHE_SCREENSHOT_DIR, Time.get_ticks_msec()]
	else:
		var guarded := PathGuard.sanitize(save_to)
		if not guarded[&"ok"]:
			return {"ok": false, "error": guarded[&"error"]}
		resource_path = guarded[&"path"]

	var abs_path := ProjectSettings.globalize_path(resource_path)
	var dir := abs_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var err := img.save_png(abs_path)
	if err != OK:
		return {"ok": false, "error": "save_png failed: %d (%s) at %s" % [err, error_string(err), abs_path]}

	var out := {
		"ok": true,
		"resource_path": resource_path,
		"absolute_path": abs_path,
		"width": img.get_width(),
		"height": img.get_height(),
	}
	if return_base64:
		out["base64_png"] = Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(abs_path))
	return out


# =============================================================================
# send_input
# =============================================================================
func _send_input(args: Dictionary) -> Dictionary:
	# Untyped + validated: a stringified 'event' that failed JSON parse would
	# hard-crash a typed `Dictionary` local (aborting dispatch, hanging the call).
	var event_desc = args.get("event", {})
	if not event_desc is Dictionary or event_desc.is_empty():
		return {"ok": false, "error": "Missing or invalid 'event' dictionary"}
	var event := _build_input_event(event_desc)
	if event == null:
		return {"ok": false, "error": "Could not construct InputEvent from: %s" % str(event_desc)}
	_dispatch_synthetic_input(event)
	return {
		"ok": true,
		"dispatched": event.get_class(),
		"event": event_desc,
	}

## Count of synthetic events dispatched but not yet seen back through _input()
## below. Godot does not tag an InputEvent with where it came from, so this is
## the only way to tell an expected synthetic event apart from real hardware
## input landing at the same time.
var _synthetic_pending := 0

## The one place every synthetic InputEvent goes through — send_input,
## replay_input_sequence, click_control_runtime all call this instead of
## Input.parse_input_event() directly, so _input() below has one counter to
## check rather than one per call site.
func _dispatch_synthetic_input(event: InputEvent) -> void:
	_synthetic_pending += 1
	Input.parse_input_event(event)

func _build_input_event(desc: Dictionary) -> InputEvent:
	var t: String = str(desc.get("type", ""))
	match t:
		"key":
			var k := InputEventKey.new()
			k.pressed = bool(desc.get("pressed", true))
			if desc.has("keycode"):
				k.keycode = int(desc["keycode"])
			if desc.has("physical_keycode"):
				k.physical_keycode = int(desc["physical_keycode"])
			if desc.has("key"):
				var keystr := str(desc["key"]).to_upper()
				k.physical_keycode = OS.find_keycode_from_string(keystr)
			if desc.has("shift"): k.shift_pressed = bool(desc["shift"])
			if desc.has("ctrl"): k.ctrl_pressed = bool(desc["ctrl"])
			if desc.has("alt"): k.alt_pressed = bool(desc["alt"])
			if desc.has("meta"): k.meta_pressed = bool(desc["meta"])
			return k
		"mouse_button":
			var mb := InputEventMouseButton.new()
			mb.pressed = bool(desc.get("pressed", true))
			mb.button_index = int(desc.get("button_index", MOUSE_BUTTON_LEFT))
			if desc.has("position"):
				mb.position = _to_vec2(desc["position"])
				mb.global_position = mb.position
			if desc.has("double_click"):
				mb.double_click = bool(desc["double_click"])
			return mb
		"mouse_motion":
			var mm := InputEventMouseMotion.new()
			if desc.has("position"):
				mm.position = _to_vec2(desc["position"])
				mm.global_position = mm.position
			if desc.has("relative"):
				mm.relative = _to_vec2(desc["relative"])
			return mm
		"action":
			var act := InputEventAction.new()
			act.action = str(desc.get("action", ""))
			act.pressed = bool(desc.get("pressed", true))
			act.strength = float(desc.get("strength", 1.0 if act.pressed else 0.0))
			return act
		"joypad_button":
			var jb := InputEventJoypadButton.new()
			jb.device = int(desc.get("device", 0))
			jb.button_index = int(desc.get("button_index", 0))
			jb.pressed = bool(desc.get("pressed", true))
			jb.pressure = float(desc.get("pressure", 1.0 if jb.pressed else 0.0))
			return jb
		"joypad_motion":
			var jm := InputEventJoypadMotion.new()
			jm.device = int(desc.get("device", 0))
			jm.axis = int(desc.get("axis", 0))
			jm.axis_value = float(desc.get("axis_value", 0.0))
			return jm
		"screen_touch":
			var st := InputEventScreenTouch.new()
			st.index = int(desc.get("index", 0))
			st.pressed = bool(desc.get("pressed", true))
			if desc.has("position"):
				st.position = _to_vec2(desc["position"])
			return st
		"screen_drag":
			var sd := InputEventScreenDrag.new()
			sd.index = int(desc.get("index", 0))
			if desc.has("position"):
				sd.position = _to_vec2(desc["position"])
			if desc.has("relative"):
				sd.relative = _to_vec2(desc["relative"])
			if desc.has("velocity"):
				sd.velocity = _to_vec2(desc["velocity"])
			return sd
		_:
			return null


func _to_vec2(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	if v is Dictionary:
		return Vector2(float(v.get("x", 0)), float(v.get("y", 0)))
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO


# =============================================================================
# monitor_properties — sample node properties per frame over N frames
# =============================================================================
## Records a time-series of one or more properties on a live node, one sample
## per _process frame for `frames` frames. Lets an agent verify motion/physics/
## interpolation (e.g. "did velocity ramp then settle?") without screenshots.
## Property paths support get_indexed() sub-paths, e.g. "position:x".
##
## `setup_code`, if given, is an optional game_eval-style snippet (same `tree`/
## `node` scope) run once, synchronously, before the first sample — in the same
## call that starts the sampling job. This closes the gap that made sub-second
## events unobservable: without it, triggering an event needs its own game_eval
## call, and by the time the following monitor_properties call lands the event
## (a 0.74s jump arc, a 0.12s input buffer) is already over. With setup_code the
## trigger and the first sample happen back to back, no round trip in between.
func _start_monitor(rid: String, args: Dictionary) -> void:
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	if node_path.is_empty():
		_send_async_result(rid, false, {"error": "Missing 'node_path'"})
		return
	var props_raw = args.get("properties", [])
	if not props_raw is Array or props_raw.is_empty():
		_send_async_result(rid, false, {"error": "Missing 'properties' (non-empty array of property paths)"})
		return
	var frames: int = clampi(int(args.get("frames", 60)), 1, 1200)

	var node := _resolve_runtime_node(node_path)
	if not node:
		_send_async_result(rid, false, {"error": "Node not found: " + node_path})
		return

	var props: Array = []
	for p in props_raw:
		props.append(str(p))

	var setup_code := str(args.get("setup_code", "")).strip_edges()
	var setup_result_serialized = null
	var had_setup := false
	if not setup_code.is_empty():
		var compiled := _compile_eval(setup_code)
		if not compiled.get("ok", false):
			_send_async_result(rid, false, compiled)
			return
		# Same caveat as game_eval: a RUNTIME error in setup_code cannot be caught
		# from GDScript here either (see 5.2 in notes/BACKLOG.md) — this only
		# removes the round-trip gap, it does not make the trigger snippet safe.
		var result = compiled["instance"].call("_mcp_eval", get_tree(), node)
		setup_result_serialized = _serialize(result)
		had_setup = true

	var job := {
		"rid": rid,
		"node": node,
		"node_path": node_path,
		"props": props,
		"frames_left": frames,
		"total_frames": frames,
		"samples": [],
	}
	if had_setup:
		job["setup_result"] = setup_result_serialized
	_monitor_jobs.append(job)

func _tick_monitors() -> void:
	if _monitor_jobs.is_empty():
		return
	var i := _monitor_jobs.size() - 1
	while i >= 0:
		var job: Dictionary = _monitor_jobs[i]
		var node = job["node"]
		if not is_instance_valid(node):
			_send_async_result(str(job["rid"]), false, {
				"error": "Monitored node was freed during sampling",
				"node_path": job["node_path"],
				"samples": job["samples"],
			})
			_monitor_jobs.remove_at(i)
			i -= 1
			continue

		var frame_idx: int = job["total_frames"] - job["frames_left"]
		var values: Dictionary = {}
		for prop: String in job["props"]:
			values[prop] = _serialize(node.get_indexed(NodePath(prop)))
		job["samples"].append({"frame": frame_idx, "t_msec": Time.get_ticks_msec(), "values": values})
		job["frames_left"] -= 1

		if job["frames_left"] <= 0:
			var out := {
				"node_path": job["node_path"],
				"frames": job["total_frames"],
				"samples": job["samples"],
				"message": "Sampled %d propert%s over %d frame(s) on %s" % [
					job["props"].size(), "y" if job["props"].size() == 1 else "ies",
					job["total_frames"], job["node_path"],
				],
			}
			if job.has("setup_result"):
				out["setup_result"] = job["setup_result"]
			_send_async_result(str(job["rid"]), true, out)
			_monitor_jobs.remove_at(i)
		i -= 1

## Send a tool_result for an async job (monitor_properties). `payload` must NOT
## carry an "ok" key (mirrors _handle_message, which erases it before sending).
func _send_async_result(rid: String, success: bool, payload: Dictionary) -> void:
	_send({
		"type": "tool_result",
		"id": rid,
		"success": success,
		# On failure too — same reason as the synchronous path, and it matters
		# more here: a failing async job carries the work it DID manage. When a
		# monitored node is freed mid-sampling, monitor_properties reports the
		# samples it collected up to that frame, and those were being dropped
		# along with everything else that was not the error string.
		"result": payload,
		"error": str(payload.get("error", "")) if not success else "",
	})

# =============================================================================
# replay_input_sequence — deterministic timed input playback for playtests
# =============================================================================
## Feed a scripted sequence of input events into the running game at specific
## frames, so an agent can reproduce a playthrough deterministically and then
## assert on the result (via monitor_properties / serialize_runtime_tree). Each
## sequence item is {at_frame:int, event:<same shape as send_input>}. Frame-based
## (not wall-clock) so it's reproducible regardless of machine speed.
func _start_replay(rid: String, args: Dictionary) -> void:
	var seq = args.get("sequence", [])
	if not seq is Array or seq.is_empty():
		_send_async_result(rid, false, {"error": "Missing 'sequence' (non-empty array of {at_frame, event})"})
		return
	var events: Array = []
	var max_frame := 0
	for item in seq:
		if not item is Dictionary:
			_send_async_result(rid, false, {"error": "Each sequence item must be an object {at_frame, event}"})
			return
		var frame := maxi(0, int(item.get("at_frame", 0)))
		var evt := _build_input_event(item.get("event", {}))
		if evt == null:
			_send_async_result(rid, false, {"error": "Bad 'event' in sequence item at_frame %d" % frame})
			return
		events.append({"frame": frame, "evt": evt})
		max_frame = maxi(max_frame, frame)
	var settle := clampi(int(args.get("settle_frames", 10)), 0, 1200)
	_replay_jobs.append({"rid": rid, "events": events, "frame": 0, "end_frame": max_frame + settle, "pushed": 0})

func _tick_replays() -> void:
	if _replay_jobs.is_empty():
		return
	var i := _replay_jobs.size() - 1
	while i >= 0:
		var job: Dictionary = _replay_jobs[i]
		var f: int = job["frame"]
		for e in job["events"]:
			if int(e["frame"]) == f:
				_dispatch_synthetic_input(e["evt"])
				job["pushed"] += 1
		job["frame"] += 1
		if job["frame"] > int(job["end_frame"]):
			_send_async_result(str(job["rid"]), true, {
				"events_played": job["pushed"],
				"frames": job["frame"],
				"message": "Replayed %d input event(s) over %d frame(s)" % [job["pushed"], job["frame"]],
			})
			_replay_jobs.remove_at(i)
		i -= 1

# =============================================================================
# input recording — capture a play session into a replay_input_sequence payload
# =============================================================================
var _recording := false
var _recorded: Array = []
var _record_start_frame := 0
var _record_mouse_motion := false

## Fires for every input event, real or synthetic — Godot does not tag origin,
## so this one handler does both jobs that need to see every event: recording
## (below, unchanged) and telling real input apart from `_dispatch_synthetic_
## input`'s own dispatch (see notes/BACKLOG.md §5.6 — a real mouse click landed
## as an attack, blocked jumping, and read as a tool bug for a long time before
## the real cause was found). Every unexpected event is pushed through the same
## unsolicited activity channel _tick_scene_awareness uses, not just logged for
## a poll to maybe notice — the "louder warning" that entry asked for.
func _input(event: InputEvent) -> void:
	if _synthetic_pending > 0:
		_synthetic_pending -= 1
	else:
		push_runtime_log("warn", "Real input reached the game during an automated run: %s. If the editor (or game) window has focus, real clicks/keys land on the game and can contaminate a test — see notes/BACKLOG.md §5.6." % event)
		_push_activity("real_input_detected", {"event": str(event)})

	if not _recording:
		return
	if event is InputEventMouseMotion and not _record_mouse_motion:
		return
	var desc := _serialize_input_event(event)
	if desc.is_empty():
		return
	_recorded.append({"at_frame": Engine.get_process_frames() - _record_start_frame, "event": desc})

func _start_input_recording(args: Dictionary) -> Dictionary:
	_recording = true
	_recorded = []
	_record_start_frame = Engine.get_process_frames()
	_record_mouse_motion = bool(args.get("include_mouse_motion", false))
	set_process_input(true)
	return {"ok": true, "message": "Recording input%s. Play the game, then call stop_input_recording." % ("" if _record_mouse_motion else " (mouse motion skipped)")}

func _stop_input_recording(_args: Dictionary) -> Dictionary:
	_recording = false
	return {"ok": true, "count": _recorded.size(), "sequence": _recorded,
		"message": "Recorded %d input event(s). Pass 'sequence' straight to replay_input_sequence to reproduce it." % _recorded.size()}

## Reverse of _build_input_event: InputEvent -> the desc dict replay/send_input use.
func _serialize_input_event(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		return {"type": "key", "pressed": e.pressed, "keycode": e.keycode,
			"physical_keycode": e.physical_keycode, "shift": e.shift_pressed,
			"ctrl": e.ctrl_pressed, "alt": e.alt_pressed, "meta": e.meta_pressed}
	if e is InputEventMouseButton:
		return {"type": "mouse_button", "pressed": e.pressed, "button_index": e.button_index,
			"position": {"x": e.position.x, "y": e.position.y}, "double_click": e.double_click}
	if e is InputEventMouseMotion:
		return {"type": "mouse_motion", "position": {"x": e.position.x, "y": e.position.y},
			"relative": {"x": e.relative.x, "y": e.relative.y}}
	if e is InputEventJoypadButton:
		return {"type": "joypad_button", "device": e.device, "button_index": e.button_index, "pressed": e.pressed}
	if e is InputEventJoypadMotion:
		return {"type": "joypad_motion", "device": e.device, "axis": e.axis, "axis_value": e.axis_value}
	if e is InputEventScreenTouch:
		return {"type": "screen_touch", "index": e.index, "pressed": e.pressed,
			"position": {"x": e.position.x, "y": e.position.y}}
	if e is InputEventScreenDrag:
		return {"type": "screen_drag", "index": e.index,
			"position": {"x": e.position.x, "y": e.position.y}, "relative": {"x": e.relative.x, "y": e.relative.y}}
	return {}


# =============================================================================
# query_runtime_node — inspect a live node in the running scene tree
# =============================================================================
func _query_runtime_node(args: Dictionary) -> Dictionary:
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	if node_path.is_empty():
		return {"ok": false, "error": "Missing 'node_path' (e.g. /root/Main/Player or relative path from current_scene)"}
	# Untyped guard: a stringified 'properties' that failed JSON parse would
	# hard-crash a typed `Array` local. _parse_bool_arg handles bools that
	# arrive as the string "false" (bool("false") is truthy).
	var properties_raw = args.get("properties", [])
	var properties: Array = properties_raw if properties_raw is Array else []
	var include_children: bool = _parse_bool_arg(args.get("include_children", false))
	var include_groups: bool = _parse_bool_arg(args.get("include_groups", true))

	var tree := get_tree()
	if tree == null:
		return {"ok": false, "error": "SceneTree unavailable"}

	var node: Node = null
	if node_path.begins_with("/"):
		node = tree.root.get_node_or_null(NodePath(node_path))
	else:
		var current := tree.current_scene
		if current:
			node = current.get_node_or_null(NodePath(node_path))
		if node == null:
			node = tree.root.get_node_or_null(NodePath(node_path))

	if node == null:
		return {"ok": false, "error": "Node not found: %s" % node_path}

	var info := {
		"ok": true,
		"name": str(node.name),
		"class": node.get_class(),
		"path": str(node.get_path()),
		"valid": true,
	}
	if include_groups:
		info["groups"] = node.get_groups()

	if properties.is_empty():
		# Default subset that's almost always interesting
		properties = ["position", "global_position", "rotation", "scale", "visible", "modulate"]
	var prop_values := {}
	var missing_props: Array = []
	for pname_v in properties:
		var pname := str(pname_v)
		# Include null-valued props too: a null slot (e.g. an unassigned resource)
		# is real state, distinct from a property that doesn't exist. _serialize
		# maps null → null.
		#
		# But node.get() also returns null for a property that isn't there, so a
		# bare null is ambiguous: "this Sprite2D has no texture" and "you asked
		# for a property this class doesn't have" looked identical, and a typo in
		# the request read as a legitimate null. Report the ones that don't exist
		# separately so the caller can tell the difference.
		if not (pname in node):
			missing_props.append(pname)
			continue
		prop_values[pname] = _serialize(node.get(pname))
	info["properties"] = prop_values
	if not missing_props.is_empty():
		info["missing_properties"] = missing_props

	if include_children:
		var kids: Array = []
		for c in node.get_children():
			kids.append({"name": str(c.name), "class": c.get_class()})
		info["children"] = kids

	return info


func _serialize(v: Variant) -> Variant:
	match typeof(v):
		TYPE_VECTOR2: return {"type": "Vector2", "x": v.x, "y": v.y}
		TYPE_VECTOR3: return {"type": "Vector3", "x": v.x, "y": v.y, "z": v.z}
		TYPE_COLOR: return {"type": "Color", "r": v.r, "g": v.g, "b": v.b, "a": v.a}
		TYPE_OBJECT:
			# A null Variant is TYPE_NIL, not TYPE_OBJECT, so it never lands here —
			# it falls through to the default below, which returns null as-is.
			return "<%s>" % v.get_class() if v.has_method("get_class") else "<Object>"
		_: return v


# =============================================================================
# get_runtime_log — recent runtime log lines pushed via push_runtime_log()
# =============================================================================
func _get_runtime_log(args: Dictionary) -> Dictionary:
	var limit: int = clampi(int(args.get("limit", 200)), 1, LOG_RING_CAPACITY)
	var since_ms: int = int(args.get("since_ms", 0))
	var level: String = str(args.get("level", "")).strip_edges().to_lower()
	var filtered: Array = []
	for entry in _log_ring:
		if entry.get("ts_ms", 0) < since_ms:
			continue
		if not level.is_empty() and str(entry.get("level", "")).to_lower() != level:
			continue
		filtered.append(entry)
	if filtered.size() > limit:
		filtered = filtered.slice(filtered.size() - limit, filtered.size())
	return {
		"ok": true,
		"entries": filtered,
		"count": filtered.size(),
		"started_at_ms": _started_at_msec,
		"now_ms": Time.get_ticks_msec(),
		"hint": "For full engine output (prints from your scripts) the editor's get_console_log already includes the running game's stdout.",
	}


# Public: user scripts can call MCPRuntime.push_runtime_log("info", "msg") to
# surface custom diagnostics in the agent's get_runtime_log results.
func push_runtime_log(level: String, text: String) -> void:
	if _log_ring.size() >= LOG_RING_CAPACITY:
		_log_ring.pop_front()
	_log_ring.append({
		"ts_ms": Time.get_ticks_msec(),
		"level": level,
		"text": text,
	})


# =============================================================================
# Runtime awareness — push what changed in the running game, unsolicited
# =============================================================================
## Notice when the running game swaps its scene. Compared by object identity
## rather than path so that reloading the same scene still counts as a change:
## every node the agent resolved is gone either way.
func _tick_scene_awareness() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var current := tree.current_scene
	if current == _last_scene:
		return
	# The first scene seen is the game starting, not a change. Distinguished
	# because the two mean different things to an agent: one invalidates node
	# paths it already holds, the other is just "there is a game now".
	var first := _last_scene == null
	_last_scene = current
	_push_activity(
		"game_started" if first else "game_scene_changed",
		current.scene_file_path if current else ""
	)


func _push_activity(type: String, detail) -> void:
	_activity_seq += 1
	_send({
		"type": "editor_activity",
		"event": {
			"id": _activity_seq,
			"t_ms": Time.get_ticks_msec(),
			"type": type,
			"detail": detail,
			"source": "runtime",
		},
	})


# =============================================================================
# list_signal_connections — runtime-side
# =============================================================================
func _list_signal_connections(args: Dictionary) -> Dictionary:
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	if node_path.is_empty():
		return {"ok": false, "error": "Missing 'node_path'"}

	var tree := get_tree()
	if tree == null:
		return {"ok": false, "error": "SceneTree unavailable"}

	var node: Node = null
	if node_path.begins_with("/"):
		node = tree.root.get_node_or_null(NodePath(node_path))
	else:
		var current := tree.current_scene
		if current:
			node = current.get_node_or_null(NodePath(node_path))

	if node == null:
		return {"ok": false, "error": "Node not found: %s" % node_path}

	var outgoing: Array = []
	for sig in node.get_signal_list():
		var sig_name := str(sig["name"])
		for conn in node.get_signal_connection_list(sig_name):
			var callable: Callable = conn["callable"]
			var dst = callable.get_object()
			outgoing.append({
				"signal": sig_name,
				"to_object": str(dst.get_path()) if dst is Node else "<%s>" % (dst.get_class() if dst else "null"),
				"method": callable.get_method(),
				"flags": int(conn.get("flags", 0)),
			})

	return {
		"ok": true,
		"source": "runtime",
		"node_path": node_path,
		"outgoing": outgoing,
		"outgoing_count": outgoing.size(),
	}


# =============================================================================
# connect_signal_runtime / disconnect_signal_runtime
# =============================================================================
func _connect_signal_runtime(args: Dictionary) -> Dictionary:
	var from_path: String = str(args.get("from_node_path", "")).strip_edges()
	var signal_name: String = str(args.get("signal", "")).strip_edges()
	var to_path: String = str(args.get("to_node_path", "")).strip_edges()
	var method: String = str(args.get("method", "")).strip_edges()

	if from_path.is_empty() or signal_name.is_empty() or to_path.is_empty() or method.is_empty():
		return {"ok": false, "error": "from_node_path, signal, to_node_path, and method are all required"}

	var src := _resolve_runtime_node(from_path)
	var dst := _resolve_runtime_node(to_path)
	if not src:
		return {"ok": false, "error": "from_node_path not found: " + from_path}
	if not dst:
		return {"ok": false, "error": "to_node_path not found: " + to_path}
	if not src.has_signal(signal_name):
		return {"ok": false, "error": "Signal '%s' not found on %s" % [signal_name, src.get_class()]}
	if not dst.has_method(method):
		return {"ok": false, "error": "Method '%s' not found on %s" % [method, dst.get_class()]}

	var callable := Callable(dst, method)
	if src.is_connected(signal_name, callable):
		return {"ok": true, "already_connected": true, "message": "Connection already exists; no change."}

	var err := src.connect(signal_name, callable)
	if err != OK:
		return {"ok": false, "error": "connect() returned %d (%s)" % [err, error_string(err)]}

	return {"ok": true, "from_node_path": from_path, "signal": signal_name,
		"to_node_path": to_path, "method": method,
		"message": "Connected %s.%s -> %s.%s (runtime-only, not persisted)" % [from_path, signal_name, to_path, method]}


func _disconnect_signal_runtime(args: Dictionary) -> Dictionary:
	var from_path: String = str(args.get("from_node_path", "")).strip_edges()
	var signal_name: String = str(args.get("signal", "")).strip_edges()
	var to_path: String = str(args.get("to_node_path", "")).strip_edges()
	var method: String = str(args.get("method", "")).strip_edges()

	if from_path.is_empty() or signal_name.is_empty() or to_path.is_empty() or method.is_empty():
		return {"ok": false, "error": "from_node_path, signal, to_node_path, and method are all required"}

	var src := _resolve_runtime_node(from_path)
	var dst := _resolve_runtime_node(to_path)
	if not src:
		return {"ok": false, "error": "from_node_path not found: " + from_path}
	if not dst:
		return {"ok": false, "error": "to_node_path not found: " + to_path}

	var callable := Callable(dst, method)
	if not src.is_connected(signal_name, callable):
		return {"ok": true, "message": "Not connected; no change."}

	src.disconnect(signal_name, callable)
	return {"ok": true, "from_node_path": from_path, "signal": signal_name,
		"to_node_path": to_path, "method": method, "message": "Disconnected."}


# =============================================================================
# tween_property_runtime
# =============================================================================
func _tween_property_runtime(args: Dictionary) -> Dictionary:
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var property_name: String = str(args.get("property", "")).strip_edges()
	var final_value = args.get("final_value")
	var duration: float = float(args.get("duration", 1.0))

	if node_path.is_empty() or property_name.is_empty() or final_value == null:
		return {"ok": false, "error": "node_path, property, and final_value are all required"}

	var node := _resolve_runtime_node(node_path)
	if not node:
		return {"ok": false, "error": "Node not found: " + node_path}
	if not (property_name in node):
		return {"ok": false, "error": "Node '%s' (%s) has no property '%s'" % [node_path, node.get_class(), property_name]}

	var tween := node.create_tween()
	tween.tween_property(node, property_name, _parse_tween_value(final_value), duration)

	return {"ok": true, "node_path": node_path, "property": property_name, "duration": duration,
		"message": "Started tween on '%s.%s' (%.2fs)" % [node_path, property_name, duration]}

func _parse_tween_value(v: Variant) -> Variant:
	# The runtime WebSocket bridge doesn't go through tool_executor.gd's
	# stringification-repair heuristic, so dict-shaped args (like final_value)
	# can arrive here as a raw JSON string instead of a Dictionary.
	if v is String:
		var s: String = v.strip_edges()
		if s.begins_with("{") and s.ends_with("}"):
			var parsed = JSON.parse_string(s)
			if parsed != null:
				v = parsed
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("x") and d.has("y") and d.has("z"):
			return Vector3(float(d.get("x", 0)), float(d.get("y", 0)), float(d.get("z", 0)))
		if d.has("x") and d.has("y"):
			return Vector2(float(d.get("x", 0)), float(d.get("y", 0)))
		if d.has("r") and d.has("g") and d.has("b"):
			return Color(float(d.get("r", 1)), float(d.get("g", 1)), float(d.get("b", 1)), float(d.get("a", 1)))
	return v


# =============================================================================
# play_animation_runtime
# =============================================================================
func _play_animation_runtime(args: Dictionary) -> Dictionary:
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var animation_name: String = str(args.get("animation_name", "")).strip_edges()

	if node_path.is_empty() or animation_name.is_empty():
		return {"ok": false, "error": "node_path and animation_name are required"}

	var node := _resolve_runtime_node(node_path)
	if not node:
		return {"ok": false, "error": "Node not found: " + node_path}
	if not (node is AnimationPlayer):
		return {"ok": false, "error": "Node '%s' (%s) is not an AnimationPlayer" % [node_path, node.get_class()]}

	if not node.has_animation(animation_name):
		return {"ok": false, "error": "Animation '%s' not found on '%s'" % [animation_name, node_path]}

	node.play(animation_name)
	return {"ok": true, "node_path": node_path, "animation_name": animation_name,
		"message": "Playing '%s' on '%s'" % [animation_name, node_path]}


# =============================================================================
# dump_control_tree — list visible Control nodes with global rects, so an
# agent can "see" a UI layout without a screenshot.
# =============================================================================
func _dump_control_tree(args: Dictionary) -> Dictionary:
	var root_path: String = str(args.get("root_path", "")).strip_edges()
	var only_visible := _parse_bool_arg(args.get("only_visible", true))

	var tree := get_tree()
	if tree == null:
		return {"ok": false, "error": "SceneTree unavailable"}

	var root: Node
	if root_path.is_empty():
		root = tree.current_scene if tree.current_scene else tree.root
	else:
		root = _resolve_runtime_node(root_path)
	if root == null:
		return {"ok": false, "error": "Node not found: %s" % root_path}

	var controls: Array = []
	_collect_controls(root, controls, only_visible)
	return {"ok": true, "root_path": str(root.get_path()), "controls": controls, "count": controls.size()}


func _collect_controls(node: Node, out: Array, only_visible: bool) -> void:
	if node is Control:
		var c: Control = node
		if not only_visible or c.is_visible_in_tree():
			var r := c.get_global_rect()
			out.append({
				"name": str(c.name),
				"class": c.get_class(),
				"path": str(c.get_path()),
				"rect": {"x": r.position.x, "y": r.position.y, "width": r.size.x, "height": r.size.y},
				"visible": c.visible,
				"focus_mode": c.focus_mode,
				"mouse_filter": c.mouse_filter,
			})
	for child in node.get_children():
		_collect_controls(child, out, only_visible)


# =============================================================================
# click_control_runtime — click a Control by node_path (resolves its global
# rect center) instead of requiring the caller to compute screen pixels.
# =============================================================================
func _click_control_runtime(args: Dictionary) -> Dictionary:
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	var text: String = str(args.get("text", "")).strip_edges()
	var button_index: int = int(args.get("button_index", MOUSE_BUTTON_LEFT))

	if node_path.is_empty() and text.is_empty():
		return {"ok": false, "error": "Provide 'node_path' or 'text'"}

	# Clicking by visible label is what a human tester does, and the agent often
	# knows the button's caption but not its path in the Control tree.
	var node: Node = null
	if not node_path.is_empty():
		node = _resolve_runtime_node(node_path)
		if not node:
			return {"ok": false, "error": "Node not found: " + node_path}
	else:
		var matches := _find_controls_by_text(text, bool(args.get("exact", false)), true)
		if matches.is_empty():
			return {"ok": false, "error": "No visible Control with text '%s'. Use dump_control_tree to see what is on screen." % text}
		if matches.size() > 1:
			var paths: Array = []
			for m in matches:
				paths.append(m["path"])
			return {"ok": false, "error": "Text '%s' matches %d controls: %s. Pass 'node_path' to disambiguate, or exact:true." % [text, matches.size(), str(paths)]}
		node = matches[0]["node"]
		node_path = str(matches[0]["path"])

	if not (node is Control):
		return {"ok": false, "error": "Node '%s' (%s) is not a Control" % [node_path, node.get_class()]}

	var control: Control = node
	if not control.is_visible_in_tree():
		return {"ok": false, "error": "Control '%s' is not visible in tree" % node_path}

	var center := control.get_global_rect().get_center()

	var down := InputEventMouseButton.new()
	down.button_index = button_index
	down.pressed = true
	down.position = center
	down.global_position = center
	_dispatch_synthetic_input(down)

	var up := InputEventMouseButton.new()
	up.button_index = button_index
	up.pressed = false
	up.position = center
	up.global_position = center
	_dispatch_synthetic_input(up)

	return {"ok": true, "node_path": node_path, "clicked_at": {"x": center.x, "y": center.y},
		"message": "Clicked '%s' at global (%.1f, %.1f)" % [node_path, center.x, center.y]}


# =============================================================================
# assert_screen_text — is this text actually on screen right now?
# =============================================================================
## The end of most UI assertions: after clicking through a flow, did the label
## the player is supposed to see appear? Reads the live Control tree rather than
## pixels, so it works headless and needs no OCR.
func _assert_screen_text(args: Dictionary) -> Dictionary:
	var text: String = str(args.get("text", "")).strip_edges()
	if text.is_empty():
		return {"ok": false, "error": "Missing 'text'"}
	var should_exist: bool = bool(args.get("should_exist", true))
	var exact: bool = bool(args.get("exact", false))
	var visible_only: bool = bool(args.get("visible_only", true))

	var matches := _find_controls_by_text(text, exact, visible_only)
	var where: Array = []
	for m in matches:
		where.append({"path": m["path"], "class": str(m["node"].get_class()), "text": m["text"]})

	var found := not matches.is_empty()
	var passed := found == should_exist
	return {
		"ok": true,
		"passed": passed,
		"found": found,
		"text": text,
		"should_exist": should_exist,
		"match_count": matches.size(),
		"matches": where,
		"message": "'%s' %s on screen (expected %s)" % [
			text, "is" if found else "is NOT", "present" if should_exist else "absent"],
	}

## Controls whose text/label contains (or equals) `needle`. Covers the common
## text-bearing properties; a Control that paints its own text has none of them
## and cannot be found this way.
func _find_controls_by_text(needle: String, exact: bool, visible_only: bool) -> Array:
	var out: Array = []
	var root := get_tree().root
	if root == null:
		return out
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.append(c)
		if not (node is Control):
			continue
		var control: Control = node
		if visible_only and not control.is_visible_in_tree():
			continue
		for prop in ["text", "tooltip_text", "placeholder_text"]:
			if not (prop in control):
				continue
			var value := str(control.get(prop))
			if value.is_empty():
				continue
			var hit := (value == needle) if exact else value.containsn(needle)
			if hit:
				out.append({"node": control, "path": str(control.get_path()), "text": value})
				break
	return out


# =============================================================================
# get_focused_control — read which Control (if any) currently owns keyboard
# focus in the game's viewport.
# =============================================================================
func _get_focused_control(args: Dictionary) -> Dictionary:
	var viewport := get_viewport()
	if viewport == null:
		return {"ok": false, "error": "No viewport available"}
	var focused := viewport.gui_get_focus_owner()
	if focused == null:
		return {"ok": true, "focused": false, "node_path": ""}
	return {"ok": true, "focused": true, "node_path": str(focused.get_path()), "class": focused.get_class()}


# Same JSON-string-stringification risk documented for _parse_tween_value:
# the runtime WebSocket bridge doesn't go through tool_executor.gd's
# boolean-repair heuristic, so an untyped bool arg can arrive as the raw
# string "false" (which bool() would treat as truthy, since it's non-empty).
func _parse_bool_arg(v: Variant) -> bool:
	if v is String:
		return v.strip_edges().to_lower() != "false"
	return bool(v)


# =============================================================================
func _ensure_cache_dir() -> void:
	var abs := ProjectSettings.globalize_path(CACHE_SCREENSHOT_DIR)
	if not DirAccess.dir_exists_absolute(abs):
		DirAccess.make_dir_recursive_absolute(abs)


func _send(msg: Dictionary) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		# Same reason as the editor client: a raw control character anywhere in
		# the payload makes the message unparseable at the far end, and the call
		# hangs to its timeout with the answer already computed. game_eval and
		# get_runtime_log both carry whatever the game printed.
		_socket.send_text(JSON.stringify(WireText.clean_tree(msg)))
