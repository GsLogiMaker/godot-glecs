@tool
extends Node
class_name MCPClient
const WireText = preload("res://addons/godot_mcp/utils/wire_text.gd")
## WebSocket client for communication with the MCP server.
## Handles connection, reconnection, and message routing.

signal connected
signal disconnected
signal tool_requested(request_id: String, tool_name: String, args: Dictionary)
signal client_count_changed(count: int)
signal runtime_status_changed(connected: bool)
## Emitted when the server refuses this editor outright and reconnecting is
## pointless (currently: the server is bound to a different project).
signal fatal_error(reason: String)

const DEFAULT_PORT := 6505
const PORT_SETTING := "godot_mcp/network/port"
const SECRET_SETTING := "godot_mcp/network/secret"
## Mirrors CLOSE_WRONG_PROJECT in mcp-server/src/godot-bridge.ts. Distinct from
## 4000/4001 (a slot is already taken), which ARE worth retrying.
const CLOSE_WRONG_PROJECT := 4002
## Mirrors CLOSE_BAD_SECRET. Also a configuration error, not a race — retrying
## with the same wrong secret will fail identically forever.
const CLOSE_BAD_SECRET := 4003
const RECONNECT_DELAY := 2.0
const MAX_RECONNECT_DELAY := 10.0
const MAX_PACKETS_PER_FRAME := 32

var socket: WebSocketPeer = WebSocketPeer.new()
var server_url: String = ""
var _is_connected := false
var _reconnect_timer: Timer
var _current_reconnect_delay := RECONNECT_DELAY
var _should_reconnect := true
var _project_path: String
var _initialized := false
var _runtime_connected: bool = false

## Resolve the port, in precedence order: GODOT_MCP_PORT env var, then the
## `godot_mcp/network/port` project setting, then 6505.
##
## The env var wins so a headless/CI editor can be pointed somewhere else
## without editing (and dirtying) project.godot. The project setting is the
## normal path for a developer running two projects at once — set a different
## port per project and start each server with a matching GODOT_MCP_PORT.
static func resolve_port() -> int:
	var from_env := OS.get_environment("GODOT_MCP_PORT")
	if not from_env.is_empty() and from_env.is_valid_int():
		var env_port := from_env.to_int()
		if env_port > 0 and env_port < 65536:
			return env_port
		push_warning("[MCP] Ignoring out-of-range GODOT_MCP_PORT=%s" % from_env)

	if ProjectSettings.has_setting(PORT_SETTING):
		var from_setting: int = int(ProjectSettings.get_setting(PORT_SETTING))
		if from_setting > 0 and from_setting < 65536:
			return from_setting
		push_warning("[MCP] Ignoring out-of-range %s=%d" % [PORT_SETTING, from_setting])

	return DEFAULT_PORT

static func default_url() -> String:
	return "ws://127.0.0.1:%d" % resolve_port()

## Resolve the optional handshake secret: GODOT_MCP_SECRET env var, then the
## `godot_mcp/network/secret` project setting, else empty (no secret sent).
##
## The bridge already refuses any connection that sends an `Origin` header,
## which is what stops a web page from driving the editor — a WebSocket from a
## browser is not blocked by the same-origin policy, and loopback binding does
## not help there. This secret covers the case that check cannot: another
## process on this machine opening a plain WebSocket and claiming to be Godot.
##
## Prefer the env var if the value is sensitive: the project setting lives in
## project.godot, which is usually committed.
static func resolve_secret() -> String:
	var from_env := OS.get_environment("GODOT_MCP_SECRET")
	if not from_env.is_empty():
		return from_env
	if ProjectSettings.has_setting(SECRET_SETTING):
		return str(ProjectSettings.get_setting(SECRET_SETTING))
	return ""

func _ready() -> void:
	_project_path = ProjectSettings.globalize_path("res://")
	if server_url.is_empty():
		server_url = default_url()

	# Create reconnect timer
	_reconnect_timer = Timer.new()
	_reconnect_timer.one_shot = true
	_reconnect_timer.timeout.connect(_on_reconnect_timer)
	add_child(_reconnect_timer)
	_initialized = true

func _process(_delta: float) -> void:
	if not _initialized:
		return
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		_check_fatal_close()
		if _is_connected:
			_handle_disconnect()
		elif _should_reconnect and not _reconnect_timer.time_left > 0:
			_schedule_reconnect()
		return

	socket.poll()

	match socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _is_connected:
				_handle_connect()
			var packets_processed := 0
			while socket.get_available_packet_count() > 0 and packets_processed < MAX_PACKETS_PER_FRAME:
				_handle_message(socket.get_packet().get_string_from_utf8())
				packets_processed += 1

		WebSocketPeer.STATE_CLOSING:
			pass  # Wait for close

		WebSocketPeer.STATE_CLOSED:
			if _is_connected:
				_handle_disconnect()

func connect_to_server(url: String = "") -> void:
	server_url = url if not url.is_empty() else default_url()
	_should_reconnect = true
	_current_reconnect_delay = RECONNECT_DELAY
	_attempt_connection()

func disconnect_from_server() -> void:
	_should_reconnect = false
	if _reconnect_timer:
		_reconnect_timer.stop()
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.close()
	_is_connected = false

func _attempt_connection() -> void:
	if socket and socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close()

	socket = WebSocketPeer.new()
	socket.outbound_buffer_size = 4 * 1024 * 1024  # 4 MB
	socket.inbound_buffer_size  = 1 * 1024 * 1024   # 1 MB
	_is_connected = false

	print("[MCP] Connecting to ", server_url, "...")
	var err := socket.connect_to_url(server_url)
	if err != OK:
		push_error("[MCP] Failed to connect: ", err)
		_schedule_reconnect()

func _handle_connect() -> void:
	_is_connected = true
	_current_reconnect_delay = RECONNECT_DELAY  # Reset backoff
	print("[MCP] Connected to server")

	# Send godot_ready message with project info. role=editor distinguishes
	# this connection from the runtime helper that may also connect.
	var hello := {
		&"type": &"godot_ready",
		&"role": &"editor",
		&"project_path": _project_path,
		# The server compares this with its own version. A server newer than the
		# addon advertises tools whose GDScript handler does not exist yet, and
		# the failure surfaces as "Unknown tool" or a silently missing argument
		# rather than as "you did not reinstall the addon" — which is exactly
		# what the release notes have been asking users to remember to do.
		&"addon_version": addon_version(),
	}
	# Only sent when configured on this side; a server with no secret set ignores
	# it, so setting it here alone cannot lock the editor out.
	var secret := resolve_secret()
	if not secret.is_empty():
		hello[&"secret"] = secret
	_send_message(hello)

	connected.emit()

## Stop retrying when the server told us we're the wrong project.
##
## Reconnecting is right for a server that isn't up yet, but a project mismatch
## is a configuration error: retrying every 2s just buries the reason in noise
## and leaves the status indicator saying "connecting" forever. Say it once,
## loudly, and stop.
func _check_fatal_close() -> void:
	if not _should_reconnect:
		return
	var code := socket.get_close_code()
	if code != CLOSE_WRONG_PROJECT and code != CLOSE_BAD_SECRET:
		return
	_should_reconnect = false
	if _reconnect_timer:
		_reconnect_timer.stop()
	if code == CLOSE_WRONG_PROJECT:
		push_error("[MCP] Server refused this project: %s" % socket.get_close_reason())
		push_error("[MCP] This editor has '%s' open. Point the server at this project (GODOT_MCP_PROJECT), or give each project its own port via '%s'." % [_project_path, PORT_SETTING])
	else:
		push_error("[MCP] Server refused the handshake secret: %s" % socket.get_close_reason())
		push_error("[MCP] The server was started with GODOT_MCP_SECRET set. Set the same value here via the GODOT_MCP_SECRET environment variable or the '%s' project setting." % SECRET_SETTING)
	fatal_error.emit(socket.get_close_reason())

func _handle_disconnect() -> void:
	_is_connected = false
	print("[MCP] Disconnected from server")
	disconnected.emit()

	if _should_reconnect:
		_schedule_reconnect()

func _schedule_reconnect() -> void:
	if not _reconnect_timer:
		return
	print("[MCP] Reconnecting in ", _current_reconnect_delay, " seconds...")
	_reconnect_timer.start(_current_reconnect_delay)
	# Exponential backoff
	_current_reconnect_delay = min(_current_reconnect_delay * 2, MAX_RECONNECT_DELAY)

func _on_reconnect_timer() -> void:
	_attempt_connection()

func _handle_message(json_string: String) -> void:
	var message = JSON.parse_string(json_string)
	if message == null or not message is Dictionary:
		push_error("[MCP] Failed to parse message (or not a JSON object): ", json_string)
		return

	var msg_type: String = message.get(&"type", "")
	match msg_type:
		"ping":
			_send_message({&"type": &"pong"})
		"tool_invoke":
			var request_id: String = message.get(&"id", "")
			var tool_name: String = message.get(&"tool", "")
			var args: Dictionary = message.get(&"args", {})
			print("[MCP] Tool request: ", tool_name, " (", request_id, ")")
			tool_requested.emit(request_id, tool_name, args)
		"client_status":
			var count: int = int(message.get(&"count", 0))
			client_count_changed.emit(count)
		"runtime_status":
			var rconn: bool = bool(message.get(&"connected", false))
			if rconn != _runtime_connected:
				_runtime_connected = rconn
				runtime_status_changed.emit(rconn)
		_:
			print("[MCP] Unknown message type: ", msg_type)

func send_tool_result(request_id: String, success: bool, result = null, error: String = "") -> void:
	var response := {
		&"type": &"tool_result",
		&"id": request_id,
		&"success": success,
	}

	# Always include the structured result dict when we have one, even on
	# failure. This lets tools ship extra context fields (open_in_editor,
	# is_active, clamped, requested_ms, etc.) alongside the top-level error
	# message instead of losing them on the wire.
	if result != null:
		response[&"result"] = result
	if not success:
		response[&"error"] = error

	_send_message(response)
	print("[MCP] Sent result for ", request_id, " (success=", success, ")")

## Push one editor-activity event to the server, unsolicited.
##
## The server used to poll get_editor_activity on a timer while a client was
## subscribed to the activity resource. This replaces that: the editor already
## knows the instant something happens, so it says so. Dropped silently when the
## socket is not open — activity is best-effort, and a queue of stale events
## delivered on reconnect would be worse than the gap.
func send_editor_activity(event: Dictionary) -> void:
	_send_message({&"type": &"editor_activity", &"event": event})

func _send_message(message: Dictionary) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		# Cleaned here rather than in each tool: JSON.stringify leaves C0 control
		# characters raw, and one of them makes the whole message unparseable at
		# the far end. The server drops it and the call hangs to its timeout with
		# the answer already computed. See WireText.
		socket.send_text(JSON.stringify(WireText.clean_tree(message)))

func is_connected_to_server() -> bool:
	return _is_connected

func is_runtime_connected() -> bool:
	return _runtime_connected

## Version from plugin.cfg, so it cannot drift from what the editor loaded.
static func addon_version() -> String:
	var cfg := ConfigFile.new()
	if cfg.load("res://addons/godot_mcp/plugin.cfg") != OK:
		return ""
	return str(cfg.get_value("plugin", "version", ""))
