@tool
extends EditorPlugin
## Godot MCP Plugin
## Connects to the godot-mcp-bridge via WebSocket and executes tools.

const MCPClientScript = preload("res://addons/godot_mcp/mcp_client.gd")
const ToolExecutorScript = preload("res://addons/godot_mcp/tool_executor.gd")

const MCP_RUNTIME_AUTOLOAD_NAME := "MCPRuntime"
const MCP_RUNTIME_AUTOLOAD_PATH := "res://addons/godot_mcp/runtime/mcp_runtime.gd"

var _mcp_client: Node  # MCPClient
var _tool_executor: Node  # ToolExecutor
var _status_label: Label

func _enter_tree() -> void:
	print("[Godot MCP] Plugin loading...")

	_declare_port_setting()

	# Create MCP client
	_mcp_client = MCPClientScript.new()
	_mcp_client.name = "MCPClient"
	add_child(_mcp_client)

	# Create tool executor
	_tool_executor = ToolExecutorScript.new()
	_tool_executor.name = "ToolExecutor"
	add_child(_tool_executor)  # _ready() runs here, creating child tools
	_tool_executor.set_editor_plugin(self)  # Now _visualizer_tools exists
	if _tool_executor.has_method("set_mcp_client"):
		_tool_executor.set_mcp_client(_mcp_client)

	# Connect signals
	_mcp_client.connected.connect(_on_connected)
	_mcp_client.disconnected.connect(_on_disconnected)
	_mcp_client.tool_requested.connect(_on_tool_requested)
	_mcp_client.client_count_changed.connect(_on_client_count_changed)
	_mcp_client.runtime_status_changed.connect(_on_runtime_status_changed)
	_mcp_client.fatal_error.connect(_on_fatal_error)

	# Add status indicator to editor
	_setup_status_indicator()

	# Watch the dev's own editor activity so the agent can see what the human is
	# doing (bidirectional awareness — the AI works alongside the dev, not blind).
	_connect_awareness_signals()
	# Push each human action to the server as it happens, rather than having the
	# server poll for them on a timer.
	_activity.human_activity.connect(_on_human_activity)
	# A running game's crash is only visible on this side, over the debugger
	# channel — the game itself cannot report its own death.
	_debugger_watch = McpDebuggerWatchScript.new()
	_debugger_watch.game_event.connect(_on_debugger_game_event)
	add_debugger_plugin(_debugger_watch)

	# Start connection
	_mcp_client.connect_to_server()

	print("[Godot MCP] Plugin loaded - connecting to MCP server...")

## Make the port visible and editable in Project Settings.
##
## Only declares the property so it shows up with a sane default and type hint —
## it is deliberately NOT saved to project.godot unless the user changes it, so
## enabling the plugin doesn't dirty the project file. MCPClient.resolve_port()
## falls back to the same default when the setting is absent.
func _declare_port_setting() -> void:
	var key := MCPClientScript.PORT_SETTING
	if not ProjectSettings.has_setting(key):
		ProjectSettings.set_setting(key, MCPClientScript.DEFAULT_PORT)
	ProjectSettings.set_initial_value(key, MCPClientScript.DEFAULT_PORT)
	ProjectSettings.add_property_info({
		"name": key,
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "1024,65535,1",
	})
	# Set a different port here (and matching GODOT_MCP_PORT on the server) to
	# run two projects side by side. The env var overrides this.
	ProjectSettings.set_as_basic(key, true)

func _enable_plugin() -> void:
	# _enable_plugin() runs once when the user toggles the plugin ON in
	# Project > Project Settings > Plugins. _enter_tree() runs every time
	# the editor opens. We register the runtime autoload here so we don't
	# touch the user's project.godot on every editor restart.
	_register_runtime_autoload()

func _disable_plugin() -> void:
	_unregister_runtime_autoload()

func _exit_tree() -> void:
	print("[Godot MCP] Plugin unloading...")

	if _mcp_client:
		_mcp_client.disconnect_from_server()
		_mcp_client.queue_free()

	if _tool_executor:
		_tool_executor.queue_free()

	if _status_label:
		remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, _status_label)
		_status_label.queue_free()

	if _debugger_watch:
		remove_debugger_plugin(_debugger_watch)
		_debugger_watch = null

	print("[Godot MCP] Plugin unloaded")

func _register_runtime_autoload() -> void:
	if not FileAccess.file_exists(MCP_RUNTIME_AUTOLOAD_PATH):
		push_warning("[Godot MCP] Runtime autoload script missing: %s" % MCP_RUNTIME_AUTOLOAD_PATH)
		return
	# add_autoload_singleton is idempotent for the same name+path.
	add_autoload_singleton(MCP_RUNTIME_AUTOLOAD_NAME, MCP_RUNTIME_AUTOLOAD_PATH)
	print("[Godot MCP] Registered autoload '%s' -> %s" % [MCP_RUNTIME_AUTOLOAD_NAME, MCP_RUNTIME_AUTOLOAD_PATH])

func _unregister_runtime_autoload() -> void:
	# Only remove if the autoload is ours; don't stomp a user's same-named
	# autoload pointing somewhere else.
	var key := "autoload/" + MCP_RUNTIME_AUTOLOAD_NAME
	if not ProjectSettings.has_setting(key):
		return
	var current_path := str(ProjectSettings.get_setting(key, ""))
	if current_path.lstrip("*") != MCP_RUNTIME_AUTOLOAD_PATH:
		print("[Godot MCP] Autoload '%s' points to %s; leaving it alone." % [MCP_RUNTIME_AUTOLOAD_NAME, current_path])
		return
	remove_autoload_singleton(MCP_RUNTIME_AUTOLOAD_NAME)
	print("[Godot MCP] Unregistered autoload '%s'" % MCP_RUNTIME_AUTOLOAD_NAME)

func _on_runtime_status_changed(connected: bool) -> void:
	if not _status_label:
		return
	if connected:
		var current := _status_label.text
		if current.find(" + Runtime") < 0:
			_status_label.text = current + " + Runtime"
	else:
		_status_label.text = _status_label.text.replace(" + Runtime", "")

func _setup_status_indicator() -> void:
	"""Add a small status label to the editor toolbar."""
	_status_label = Label.new()
	_status_label.text = "MCP: Connecting..."
	_status_label.add_theme_color_override("font_color", Color.YELLOW)
	_status_label.add_theme_font_size_override("font_size", 20)
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, _status_label)

func _on_connected() -> void:
	print("[Godot MCP] Connected to MCP server")
	if _status_label:
		_status_label.text = "MCP: No Agent"
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.0))  # orange

func _on_disconnected() -> void:
	print("[Godot MCP] Disconnected from MCP server")
	if _status_label:
		_status_label.text = "MCP: Disconnected"
		_status_label.add_theme_color_override("font_color", Color.RED)

func _on_fatal_error(reason: String) -> void:
	# Distinct from "Disconnected": that one is retrying, this one has given up.
	# The label is the only place a user who isn't reading the Output panel will
	# notice, so it has to say the difference.
	print("[Godot MCP] Refused by server, not retrying: ", reason)
	if _status_label:
		_status_label.text = "MCP: Wrong project"
		_status_label.tooltip_text = reason
		_status_label.add_theme_color_override("font_color", Color.RED)

func _on_client_count_changed(count: int) -> void:
	if not _status_label:
		return
	if count > 0:
		_status_label.text = "MCP: Agent Active" if count == 1 else "MCP: Agents (%d)" % count
		_status_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		_status_label.text = "MCP: No Agent"
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.0))  # orange

# =============================================================================
# Editor-activity awareness — record what the DEV does in the editor so the agent
# can poll it (get_editor_activity) and pair-program instead of working blind.
# =============================================================================
# The buffering/tagging/digest rules live in McpActivityLog so they can be tested
# headless (an EditorPlugin cannot be instantiated outside the editor).
const McpActivityLogScript = preload("res://addons/godot_mcp/utils/activity_log.gd")
var _activity := McpActivityLogScript.new()
const McpDebuggerWatchScript = preload("res://addons/godot_mcp/utils/debugger_watch.gd")
var _debugger_watch: EditorDebuggerPlugin = null

func _connect_awareness_signals() -> void:
	# EditorPlugin's own scene lifecycle signals.
	if not scene_changed.is_connected(_on_awareness_scene_changed):
		scene_changed.connect(_on_awareness_scene_changed)
	if not scene_closed.is_connected(_on_awareness_scene_closed):
		scene_closed.connect(_on_awareness_scene_closed)

	var ei := get_editor_interface()
	var sel := ei.get_selection()
	if sel and not sel.selection_changed.is_connected(_on_awareness_selection):
		sel.selection_changed.connect(_on_awareness_selection)
	var se := ei.get_script_editor()
	if se and se.has_signal("editor_script_changed") and not se.editor_script_changed.is_connected(_on_awareness_script):
		se.editor_script_changed.connect(_on_awareness_script)
	var fs := ei.get_resource_filesystem()
	if fs and not fs.filesystem_changed.is_connected(_on_awareness_fs):
		fs.filesystem_changed.connect(_on_awareness_fs)

	# Save / import / undo / focus events. These are what tell the agent the dev
	# committed a change, pulled in new art, or undid something — the cases where
	# blindly continuing from a stale read is most likely to be wrong.
	if not scene_saved.is_connected(_on_awareness_scene_saved):
		scene_saved.connect(_on_awareness_scene_saved)
	if not resource_saved.is_connected(_on_awareness_resource_saved):
		resource_saved.connect(_on_awareness_resource_saved)
	if not main_screen_changed.is_connected(_on_awareness_main_screen):
		main_screen_changed.connect(_on_awareness_main_screen)
	if not project_settings_changed.is_connected(_on_awareness_project_settings):
		project_settings_changed.connect(_on_awareness_project_settings)
	if fs and not fs.resources_reimported.is_connected(_on_awareness_reimported):
		fs.resources_reimported.connect(_on_awareness_reimported)
	var ur := get_undo_redo()
	if ur and not ur.version_changed.is_connected(_on_awareness_undo_redo):
		ur.version_changed.connect(_on_awareness_undo_redo)

func _record_activity(type: String, detail) -> void:
	_activity.record(type, detail)

func _on_human_activity(event: Dictionary) -> void:
	if _mcp_client:
		_mcp_client.send_editor_activity(event)

## The debugger's view of the running game. Recorded with the agent window
## deliberately bypassed: the game crashing is worth telling the agent about
## even when the agent is the one who just launched it.
func _on_debugger_game_event(type: String, detail) -> void:
	var event := {
		&"id": 0, &"t_ms": Time.get_ticks_msec(),
		&"type": type, &"detail": detail, &"source": &"runtime",
	}
	if _mcp_client:
		_mcp_client.send_editor_activity(event)

## Read editor-activity events after `since_id` (0 = everything buffered), newest
## last. `source_filter` of "human"/"agent" narrows to just that origin. Returns the
## events plus the current latest id so a poller can advance its cursor: call again
## with since_id = latest_id to get only what's new.
func get_editor_activity(since_id: int, limit: int, source_filter: String = "") -> Dictionary:
	return _activity.query(since_id, limit, source_filter)

func _on_awareness_scene_changed(root: Node) -> void:
	_record_activity("scene_opened", root.scene_file_path if root else "")

func _on_awareness_scene_closed(path: String) -> void:
	_record_activity("scene_closed", path)

func _on_awareness_selection() -> void:
	var names: Array = []
	for n in get_editor_interface().get_selection().get_selected_nodes():
		names.append(str(n.name))
	_record_activity("selection", names)

func _on_awareness_script(script) -> void:
	_record_activity("script_focus", script.resource_path if script else "")

func _on_awareness_fs() -> void:
	_record_activity("filesystem_changed", "")

func _on_awareness_scene_saved(filepath: String) -> void:
	_record_activity("scene_saved", filepath)

func _on_awareness_resource_saved(resource: Resource) -> void:
	_record_activity("resource_saved", resource.resource_path if resource else "")

func _on_awareness_main_screen(screen_name: String) -> void:
	_record_activity("main_screen", screen_name)

func _on_awareness_project_settings() -> void:
	_record_activity("project_settings_changed", "")

func _on_awareness_reimported(resources: PackedStringArray) -> void:
	_record_activity("resources_reimported", Array(resources))

## version_changed fires on undo, redo AND on every committed action, so the
## detail carries the current action name to tell them apart at a glance.
func _on_awareness_undo_redo() -> void:
	var ur := get_undo_redo()
	_record_activity("undo_redo", ur.get_current_action_name() if ur else "")

func _on_tool_requested(request_id: String, tool_name: String, args: Dictionary) -> void:
	"""Handle incoming tool request from MCP server.

	execute_tool is a coroutine (at least one tool — `wait` — uses `await`),
	so we MUST await it here. For non-coroutine tools the await returns
	immediately with the Dictionary, so there is no overhead for the common
	case."""
	print("[Godot MCP] Executing tool: ", tool_name)

	# Mark editor activity fired during this tool call (and for a short grace period
	# after, to catch deferred editor signals) as agent-caused, so get_editor_activity
	# can tell the agent's own edits apart from the human's.
	_activity.begin_agent_call()
	var result: Dictionary = await _tool_executor.execute_tool(tool_name, args)
	_activity.end_agent_call()

	var success: bool = result.get(&"ok", false)
	# We keep the full dict and ship it as `result` regardless of success so
	# structured failure details (open_in_editor, where, clamped, …) survive
	# the round-trip to the agent. The top-level `error` string is kept on
	# failure for clients that only read that field.
	# Piggyback anything the DEVELOPER did since the last tool call. Polling
	# get_editor_activity only works if the agent remembers to poll; attaching a
	# short digest means it finds out the human moved something, saved, or hit
	# undo without having to ask — which is the whole point of the awareness
	# buffer. Kept tiny and omitted entirely when nothing human happened.
	var digest := _activity.human_digest()
	if not digest.is_empty():
		result[&"_editor_activity"] = digest

	if success:
		result.erase(&"ok")
		_mcp_client.send_tool_result(request_id, true, result)
	else:
		var error: String = result.get(&"error", "Unknown error")
		_mcp_client.send_tool_result(request_id, false, result, error)

