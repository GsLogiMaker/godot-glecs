@tool
extends Node
class_name ProjectTools
## Project configuration and debug tools for MCP.
## Handles: get_project_settings, list_settings, update_project_settings,
##          get_input_map, configure_input_map, get_collision_layers,
##          get_node_properties, setup_autoload,
##          get_console_log, get_errors, clear_console_log,
##          open_in_godot, scene_tree_dump, get_uid,
##          get_editor_selection, select_nodes, clear_editor_selection,
##          get_performance_monitors, get_editor_performance,
##          create_resource, remove_autoload

const VariantCodec = preload("res://addons/godot_mcp/utils/variant_codec.gd")
const MCPPaths = preload("res://addons/godot_mcp/utils/paths.gd")
const PathGuard = preload("res://addons/godot_mcp/utils/path_guard.gd")

var _editor_plugin: EditorPlugin = null

# Background export jobs, keyed by job_id. A headless export can take minutes
# (cold shader compile), far past the MCP request timeout, so export_project runs
# it on a Thread and returns immediately; get_export_status polls the result.
# Guarded by a Mutex because the worker Thread and the polling call touch it.
var _export_jobs: Dictionary = {}
var _export_mutex := Mutex.new()

# PIDs of headless multiplayer test peers spawned via spawn_headless_peers.
var _spawned_peers: Array = []

# Reference to the MCPClient in the addon. Set by the plugin so we can ask
# the TS server (via the editor WebSocket connection) whether the runtime
# helper is currently connected.
var _mcp_client: Object = null

func set_mcp_client(client: Object) -> void:
	_mcp_client = client

# Track the moment the editor most recently launched a scene so we can report
# uptime and detect "started but immediately crashed" cases.
var _last_run_scene_started_at_ms: int = 0
var _last_run_scene_target: String = ""
## PID of a game launched with attach_debugger=false, so stop_scene can end it.
## EditorInterface knows nothing about that process — it is not "playing" as far
## as the editor is concerned.
var _detached_pid: int = -1

## Where the detached game's pid outlives this editor session.
##
## restart_editor (and any crash) resets _detached_pid to -1 while the game it
## named keeps running: run_scene then starts a second one, stop_scene can no
## longer reach the first, and every runtime tool talks to whichever helper
## connected — usually the orphan. Writing the pid down makes the next session
## able to adopt it.
const _DETACHED_PID_FILE := "user://mcp_detached_pid.txt"

# Cached reference to the editor Output panel's RichTextLabel.
var _editor_log_rtl: RichTextLabel = null

# Cached reference to the Debugger > Errors tab's Tree widget.
var _debugger_error_tree: Tree = null

# Character offset for clear_console_log.
var _clear_char_offset: int = 0

func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin

# =============================================================================
# get_project_settings
# =============================================================================
func get_project_settings(args: Dictionary) -> Dictionary:
	var include_render: bool = bool(args.get(&"include_render", true))
	var include_physics: bool = bool(args.get(&"include_physics", true))

	var out: Dictionary = {}
	out[&"main_scene"] = str(ProjectSettings.get_setting("application/run/main_scene", ""))

	# Window size
	var width = ProjectSettings.get_setting("display/window/size/viewport_width", null)
	var height = ProjectSettings.get_setting("display/window/size/viewport_height", null)
	if width != null: out[&"window_width"] = int(width)
	if height != null: out[&"window_height"] = int(height)

	# Stretch
	var stretch_mode = ProjectSettings.get_setting("display/window/stretch/mode", null)
	var stretch_aspect = ProjectSettings.get_setting("display/window/stretch/aspect", null)
	if stretch_mode != null: out[&"stretch_mode"] = str(stretch_mode)
	if stretch_aspect != null: out[&"stretch_aspect"] = str(stretch_aspect)

	if include_physics:
		var pps = ProjectSettings.get_setting("physics/common/physics_ticks_per_second", null)
		if pps != null: out[&"physics_ticks_per_second"] = int(pps)

	if include_render:
		var method = ProjectSettings.get_setting("rendering/renderer/rendering_method", null)
		if method != null: out[&"rendering_method"] = str(method)
		var vsync = ProjectSettings.get_setting("display/window/vsync/vsync_mode", null)
		if vsync != null: out[&"vsync"] = str(vsync)

	return {&"ok": true, &"settings": out}

# =============================================================================
# list_settings
# =============================================================================
func list_settings(args: Dictionary) -> Dictionary:
	var category: String = str(args.get(&"category", ""))
	# Substring filter on setting paths — cheap way to find a setting without dumping
	# a whole category (e.g. filter="vsync" across display/*).
	var filter: String = str(args.get(&"filter", "")).strip_edges().to_lower()

	var properties: Array = ProjectSettings.get_property_list()

	if category.strip_edges().is_empty():
		# With a filter but no category, search matching settings across ALL categories.
		if not filter.is_empty():
			var matches: Array = []
			for prop: Dictionary in properties:
				var pn: String = prop[&"name"]
				if pn.is_empty() or pn.begins_with("_") or not pn.to_lower().contains(filter):
					continue
				matches.append({&"path": pn, &"type": _type_to_string(prop[&"type"]),
					&"value": _serialize_value(ProjectSettings.get_setting(pn))})
			return {&"ok": true, &"filter": filter, &"settings": matches, &"count": matches.size()}
		var categories: Dictionary = {}
		for prop: Dictionary in properties:
			var prop_name: String = prop[&"name"]
			if prop_name.is_empty() or prop_name.begins_with("_"):
				continue
			var slash_idx := prop_name.find("/")
			if slash_idx == -1:
				continue
			var cat: String = prop_name.substr(0, slash_idx)
			categories[cat] = categories.get(cat, 0) + 1
		return {&"ok": true, &"categories": categories,
			&"hint": "Pass a category name to list its settings, or a filter to search across all."}

	var settings: Array = []
	for prop: Dictionary in properties:
		var prop_name: String = prop[&"name"]
		if not prop_name.begins_with(category + "/"):
			continue
		if prop_name.begins_with("_"):
			continue
		if not filter.is_empty() and not prop_name.to_lower().contains(filter):
			continue

		var info: Dictionary = {
			&"path": prop_name,
			&"type": _type_to_string(prop[&"type"]),
			&"value": _serialize_value(ProjectSettings.get_setting(prop_name))
		}

		var hint: int = prop.get(&"hint", 0)
		var hint_string: String = str(prop.get(&"hint_string", ""))
		if hint == PROPERTY_HINT_ENUM and not hint_string.is_empty():
			info[&"enum_values"] = hint_string
		elif hint == PROPERTY_HINT_RANGE and not hint_string.is_empty():
			info[&"range"] = hint_string

		settings.append(info)

	return {&"ok": true, &"category": category, &"settings": settings, &"count": settings.size()}

# =============================================================================
# update_project_settings
# =============================================================================
func update_project_settings(args: Dictionary) -> Dictionary:
	var settings = args.get(&"settings", {})
	if not settings is Dictionary or settings.is_empty():
		return {&"ok": false, &"error": "Missing or empty 'settings' dictionary. Use list_settings to discover available setting paths."}

	var warnings: Array = []
	var rename_info: Dictionary = {}

	# Detect a config-name change BEFORE we apply it. Godot rebinds user://
	# whenever application/config/name changes, but does not create the new
	# folder on disk. The first FileAccess.WRITE into user:// then silently
	# fails. We pre-create the folder and warn the caller.
	if settings.has("application/config/name"):
		var old_name := str(ProjectSettings.get_setting("application/config/name", ""))
		var new_name := str(settings["application/config/name"])
		if old_name != new_name:
			rename_info = {
				&"setting": "application/config/name",
				&"old": old_name,
				&"new": new_name,
				&"warning": "Renaming the project changes the user:// path. Existing user:// files (saved games, settings, generated assets cached in user://) will appear to disappear because user:// now points at a different folder. The new folder will be auto-created."
			}
			warnings.append(rename_info)

	var updated: Array = []
	for key: String in settings:
		if key.begins_with("input/"):
			var existing = ProjectSettings.get_setting(key, {&"deadzone": 0.5, &"events": []})
			var merged: Dictionary = {&"deadzone": 0.5, &"events": []}
			if existing is Dictionary:
				merged = existing.duplicate()
			if settings[key] is Dictionary:
				merged.merge(settings[key], true)
			ProjectSettings.set_setting(key, merged)
		else:
			ProjectSettings.set_setting(key, settings[key])
		updated.append(key)

	_save_and_refresh_settings()

	# After the save, the new application/config/name takes effect. Make sure
	# user:// resolves to a real folder so subsequent tool calls don't fail.
	if not rename_info.is_empty():
		var ok := MCPPaths.ensure_user_dir()
		rename_info[&"new_user_path"] = MCPPaths.absolute_for("user://")
		rename_info[&"new_user_path_created"] = ok

	var out: Dictionary = {&"ok": true, &"updated": updated, &"count": updated.size()}
	if not warnings.is_empty():
		out[&"warnings"] = warnings
	return out

# =============================================================================
# set_main_scene — set application/run/main_scene (the scene F5 / a no-arg run uses)
# =============================================================================
## A validated shortcut for the most common project-settings edit: which scene runs
## by default. update_project_settings can do it too, but this checks the scene
## actually exists and is a .tscn first, and is discoverable by name (a repeated
## community request for AI-driven Godot workflows).
func set_main_scene(args: Dictionary) -> Dictionary:
	var scene_path: String = str(args.get(&"scene_path", ""))
	if scene_path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	var guarded := PathGuard.sanitize(scene_path)
	if not guarded[&"ok"]:
		return {&"ok": false, &"error": guarded[&"error"]}
	scene_path = str(guarded[&"path"])
	if not scene_path.ends_with(".tscn"):
		return {&"ok": false, &"error": "Main scene must be a .tscn file, got: " + scene_path}
	if not FileAccess.file_exists(scene_path):
		return {&"ok": false, &"error": "Scene does not exist: " + scene_path}

	var previous := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	ProjectSettings.set_setting("application/run/main_scene", scene_path)
	_save_and_refresh_settings()

	return {&"ok": true, &"main_scene": scene_path, &"previous": previous,
		&"message": "Main scene set to %s (was %s)" % [scene_path, previous if not previous.is_empty() else "(none)"]}

# =============================================================================
# get_input_map
# =============================================================================
func get_input_map(args: Dictionary) -> Dictionary:
	var include_deadzones: bool = bool(args.get(&"include_deadzones", true))
	var include_builtin: bool = bool(args.get(&"include_builtin", false))

	# Merge action names from both sources:
	# - InputMap.get_actions() covers built-ins (ui_*, spatial_editor/*, etc.)
	# - ProjectSettings input/* keys cover project-defined actions
	# The editor InputMap only knows about built-ins + actions added via InputMap.add_action()
	# during the current session; project.godot actions are NOT automatically loaded into it.
	var all_actions: Dictionary = {}
	for action: StringName in InputMap.get_actions():
		all_actions[str(action)] = true
	for prop: Dictionary in ProjectSettings.get_property_list():
		var pname: String = prop[&"name"]
		if pname.begins_with("input/"):
			all_actions[pname.substr(6)] = true

	var sorted_names: Array = all_actions.keys()
	sorted_names.sort()

	var result: Dictionary = {}
	var builtin_skipped := 0
	for action_name: String in sorted_names:
		var ps_key: String = "input/" + action_name
		# The editor's InputMap carries every action the EDITOR uses — the whole
		# ui_* set plus spatial_editor/* and friends. Measured on a project with
		# one action of its own, they were 14,137 of the 14,300 characters this
		# returned, on every call.
		#
		# Filtered by namespace rather than by ProjectSettings: the engine
		# registers its ui_* defaults as project settings too, so has_setting()
		# is true for them and cannot tell them apart. ui_* and anything with a
		# "/" are the engine's reserved namespaces; what is left is what the
		# game author wrote.
		if not include_builtin and (action_name.begins_with("ui_") or "/" in action_name):
			builtin_skipped += 1
			continue
		var events: Array = []
		var deadzone: float = 0.5

		if ProjectSettings.has_setting(ps_key):
			# Project-defined or overridden action — ProjectSettings is the source of truth.
			# The editor InputMap may have a stale or default deadzone for these.
			var ps_data = ProjectSettings.get_setting(ps_key, {})
			if ps_data is Dictionary:
				deadzone = float(ps_data.get(&"deadzone", 0.5))
				for e in ps_data.get(&"events", []):
					if not e is InputEvent:
						continue
					events.append(_describe_input_event(e))
		elif InputMap.has_action(action_name):
			# Pure built-in with no project override — read from InputMap directly.
			deadzone = InputMap.action_get_deadzone(action_name)
			for e: InputEvent in InputMap.action_get_events(action_name):
				events.append(_describe_input_event(e))

		var action_data := {&"events": events}
		if include_deadzones:
			action_data[&"deadzone"] = deadzone
		result[action_name] = action_data

	var out := {&"ok": true, &"actions": result, &"count": result.size()}
	if builtin_skipped > 0:
		out[&"builtin_skipped"] = builtin_skipped
		out[&"note"] = "%d engine/editor action(s) (ui_*, spatial_editor/*, ...) omitted — they are not defined by this project. Pass include_builtin: true for the full map." % builtin_skipped
	return out

func _describe_input_event(e: InputEvent) -> Dictionary:
	var item := {&"type": e.get_class()}
	if e is InputEventKey:
		var keycode = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		item[&"keycode"] = keycode
		item[&"key_label"] = OS.get_keycode_string(keycode) if keycode != 0 else ""
	elif e is InputEventMouseButton:
		item[&"button_index"] = e.button_index
	elif e is InputEventJoypadButton:
		item[&"button_index"] = e.button_index
	elif e is InputEventJoypadMotion:
		item[&"axis"] = e.axis
		item[&"axis_value"] = e.axis_value
	return item

# =============================================================================
# configure_input_map
# =============================================================================
func configure_input_map(args: Dictionary) -> Dictionary:
	var action: String = str(args.get(&"action", ""))
	var operation: String = str(args.get(&"operation", ""))

	if action.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'action' name"}
	if operation.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'operation'. Use: add, remove, set"}

	match operation:
		"add":
			return _input_map_add(action, args)
		"remove":
			return _input_map_remove(action)
		"set":
			return _input_map_set(action, args)
		_:
			return {&"ok": false, &"error": "Unknown operation: %s. Use: add, remove, set" % operation}

func _input_map_add(action: String, args: Dictionary) -> Dictionary:
	var deadzone: float = float(args.get(&"deadzone", 0.5))
	var events_data: Array = args.get(&"events", [])

	var created := false
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)
		created = true
	else:
		InputMap.action_set_deadzone(action, deadzone)

	var added_events: Array = []
	var event_errors: Array = []
	for event_desc in events_data:
		if not event_desc is Dictionary:
			continue
		var result: Dictionary = _create_input_event(event_desc)
		if result.has(&"error"):
			event_errors.append(result[&"error"])
			continue
		InputMap.action_add_event(action, result[&"event"])
		added_events.append(_describe_event(result[&"event"]))

	_persist_action(action)
	_save_and_refresh_settings()
	_try_refresh_input_map_ui()

	var msg := "Action '%s' %s" % [action, "created" if created else "updated"]
	if added_events.size() > 0:
		msg += " with %d event(s)" % added_events.size()

	var out: Dictionary = {&"ok": true, &"message": msg, &"events_added": added_events}
	if event_errors.size() > 0:
		out[&"event_errors"] = event_errors
	return out

func _input_map_remove(action: String) -> Dictionary:
	if not InputMap.has_action(action):
		return {&"ok": false, &"error": "Action not found: " + action}

	InputMap.erase_action(action)
	if ProjectSettings.has_setting("input/" + action):
		ProjectSettings.clear("input/" + action)
	_save_and_refresh_settings()
	_try_refresh_input_map_ui()

	return {&"ok": true, &"message": "Removed action: " + action}

func _input_map_set(action: String, args: Dictionary) -> Dictionary:
	var deadzone: float = float(args.get(&"deadzone", 0.5))
	var events_data: Array = args.get(&"events", [])

	if InputMap.has_action(action):
		InputMap.erase_action(action)

	InputMap.add_action(action, deadzone)

	var added_events: Array = []
	var event_errors: Array = []
	for event_desc in events_data:
		if not event_desc is Dictionary:
			continue
		var result: Dictionary = _create_input_event(event_desc)
		if result.has(&"error"):
			event_errors.append(result[&"error"])
			continue
		InputMap.action_add_event(action, result[&"event"])
		added_events.append(_describe_event(result[&"event"]))

	_persist_action(action)
	_save_and_refresh_settings()
	_try_refresh_input_map_ui()

	# Every event rejected means the action exists and is bound to nothing: the
	# game reads it as never pressed, and answering ok let that pass for a
	# working binding. Some events through is a partial success and stays ok.
	if added_events.is_empty() and not event_errors.is_empty():
		return {
			&"ok": false,
			&"error": "Action '%s' was created but none of its %d event(s) could be built, so it is bound to nothing and will never fire." % [action, event_errors.size()],
			&"event_errors": event_errors,
		}

	var out: Dictionary = {&"ok": true, &"message": "Set action '%s' with %d event(s)" % [action, added_events.size()], &"events": added_events}
	if event_errors.size() > 0:
		out[&"event_errors"] = event_errors
	return out

func _create_input_event(desc: Dictionary) -> Dictionary:
	var type: String = str(desc.get(&"type", ""))

	match type:
		"key":
			var event := InputEventKey.new()
			# get_input_map REPORTS events as {"type":"InputEventKey","keycode":83},
			# so handing one straight back was the obvious move and the only
			# accepted form was the key NAME — the tool did not take its own
			# output. Both work now.
			if desc.has(&"keycode"):
				var numeric := int(desc.get(&"keycode", 0))
				if numeric == 0:
					return {&"error": "Invalid 'keycode' for key event (0 is not a key)"}
				event.physical_keycode = numeric
				return {&"event": event}
			var key_string: String = str(desc.get(&"key", ""))
			if key_string.is_empty():
				return {&"error": "Missing 'key' for key event — a key name like \"Space\" or \"A\", or a numeric 'keycode'"}
			var keycode := OS.find_keycode_from_string(key_string)
			if keycode == 0:
				return {&"error": "Unknown key: " + key_string}
			event.physical_keycode = keycode
			return {&"event": event}

		"mouse_button":
			var button_index: int = int(desc.get(&"button_index", 0))
			if button_index <= 0:
				return {&"error": "Invalid 'button_index' for mouse_button (must be >= 1: 1=left, 2=right, 3=middle)"}
			var event := InputEventMouseButton.new()
			event.button_index = button_index
			return {&"event": event}

		"joypad_button":
			var button_index: int = int(desc.get(&"button_index", -1))
			if button_index < 0:
				return {&"error": "Missing or invalid 'button_index' for joypad_button"}
			var event := InputEventJoypadButton.new()
			event.button_index = button_index
			return {&"event": event}

		"joypad_motion":
			var axis: int = int(desc.get(&"axis", -1))
			if axis < 0:
				return {&"error": "Missing or invalid 'axis' for joypad_motion"}
			var axis_value: float = float(desc.get(&"axis_value", 0.0))
			var event := InputEventJoypadMotion.new()
			event.axis = axis
			event.axis_value = axis_value
			return {&"event": event}

		_:
			return {&"error": "Unknown event type: '%s'. Use: key, mouse_button, joypad_button, joypad_motion" % type}

func _save_and_refresh_settings() -> void:
	ProjectSettings.save()
	ProjectSettings.notify_property_list_changed()

# =============================================================================
# sync_localization
# =============================================================================
## Godot imports a translation CSV into one .translation per locale, but each of
## those still has to be registered under internationalization/locale/translations
## by hand — miss one and that language silently never loads. This reads the CSV,
## reports the gaps in it, and registers whatever the importer produced.
func sync_localization(args: Dictionary) -> Dictionary:
	var csv_arg: String = str(args.get(&"csv_path", "")).strip_edges()
	var dry_run: bool = bool(args.get(&"dry_run", false))

	if csv_arg.is_empty():
		return {&"ok": false, &"error": "Missing 'csv_path' (the translation CSV, e.g. res://i18n/strings.csv)"}
	var guarded := PathGuard.sanitize(csv_arg)
	if not guarded[&"ok"]:
		return {&"ok": false, &"error": guarded[&"error"]}
	var csv_path: String = guarded[&"path"]
	if not FileAccess.file_exists(csv_path):
		return {&"ok": false, &"error": "CSV not found: " + csv_path}

	var f := FileAccess.open(csv_path, FileAccess.READ)
	if f == null:
		return {&"ok": false, &"error": "Could not read " + csv_path}
	# get_csv_line handles quoted fields and embedded commas.
	var header := f.get_csv_line()
	if header.size() < 2:
		f.close()
		return {&"ok": false, &"error": "CSV header needs a key column plus at least one locale column, e.g. keys,en,es"}

	var locales: Array = []
	for i in range(1, header.size()):
		var loc := str(header[i]).strip_edges()
		if not loc.is_empty():
			locales.append(loc)

	var key_count := 0
	var missing: Dictionary = {}       # locale -> [keys with an empty cell]
	var duplicate_keys: Array = []
	var seen_keys: Dictionary = {}
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() == 0 or str(row[0]).strip_edges().is_empty():
			continue
		var key := str(row[0]).strip_edges()
		key_count += 1
		if seen_keys.has(key):
			if not duplicate_keys.has(key):
				duplicate_keys.append(key)
		seen_keys[key] = true
		for i in range(1, header.size()):
			var loc := str(header[i]).strip_edges()
			if loc.is_empty():
				continue
			var cell := str(row[i]).strip_edges() if i < row.size() else ""
			if cell.is_empty():
				if not missing.has(loc):
					missing[loc] = []
				missing[loc].append(key)
	f.close()

	# The importer writes <basename>.<locale>.translation next to the CSV.
	var base := csv_path.get_basename()
	var found: Array = []
	var not_imported: Array = []
	for loc in locales:
		var t_path := "%s.%s.translation" % [base, loc]
		if FileAccess.file_exists(t_path) or ResourceLoader.exists(t_path):
			found.append(t_path)
		else:
			not_imported.append(loc)

	var registered: Array = ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray())
	var current: Array = Array(registered)
	var added: Array = []
	for t_path in found:
		if not current.has(t_path):
			current.append(t_path)
			added.append(t_path)

	if not added.is_empty() and not dry_run:
		ProjectSettings.set_setting("internationalization/locale/translations", PackedStringArray(current))
		_save_and_refresh_settings()

	var result := {
		&"ok": true,
		&"csv_path": csv_path,
		&"locales": locales,
		&"key_count": key_count,
		&"translations_found": found,
		&"registered": [] if dry_run else added,
		&"would_register": added if dry_run else [],
		&"already_registered": found.size() - added.size(),
		&"dry_run": dry_run,
		&"missing_translations": missing,
		&"missing_count": missing.size(),
	}
	if not duplicate_keys.is_empty():
		result[&"duplicate_keys"] = duplicate_keys
	if not not_imported.is_empty():
		# No .translation means Godot has not imported the CSV yet: it only runs
		# the importer on a filesystem scan, so a freshly-written CSV needs one.
		result[&"not_imported"] = not_imported
		result[&"hint"] = "Godot has not generated a .translation for these locales yet. Call rescan_filesystem, wait a moment, then run sync_localization again."
	return result

func _try_refresh_input_map_ui() -> void:
	if not _editor_plugin:
		return
	var base := _editor_plugin.get_editor_interface().get_base_control()
	var pse := _find_node_by_class(base, "ProjectSettingsEditor")
	if not pse:
		return
	if pse.has_method("_update_action_map_editor"):
		pse.call("_update_action_map_editor")
	else:
		push_warning("[Godot MCP] Input map changed and saved, but the editor UI could not refresh. Reopen Project Settings to see changes.")

func _persist_action(action: String) -> void:
	if not InputMap.has_action(action):
		return
	var deadzone: float = InputMap.action_get_deadzone(action)
	var events: Array = InputMap.action_get_events(action)
	ProjectSettings.set_setting("input/" + action, {
		"deadzone": deadzone,
		"events": events
	})

func _describe_event(event: InputEvent) -> String:
	if event is InputEventKey:
		var keycode: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		var label: String = OS.get_keycode_string(keycode) if keycode != 0 else "Unknown"
		return "Key: " + label
	elif event is InputEventMouseButton:
		return "Mouse Button: " + str(event.button_index)
	elif event is InputEventJoypadButton:
		return "Joypad Button: " + str(event.button_index)
	elif event is InputEventJoypadMotion:
		return "Joypad Axis: %d (%.1f)" % [event.axis, event.axis_value]
	return event.get_class()

# =============================================================================
# get_collision_layers
# =============================================================================
func get_collision_layers(_args: Dictionary) -> Dictionary:
	var layers_2d: Array = _collect_layers("layer_names/2d_physics")
	var layers_3d: Array = _collect_layers("layer_names/3d_physics")
	return {&"ok": true, &"layers_2d": layers_2d, &"layers_3d": layers_3d}

func _collect_layers(prefix: String) -> Array:
	var out: Array = []
	for i: int in range(1, 33):
		var key := "%s/layer_%d" % [prefix, i]
		var layer_name := str(ProjectSettings.get_setting(key, ""))
		if not layer_name.is_empty():
			out.append({&"index": i, &"name": layer_name})
	return out

# =============================================================================
# get_node_properties
# =============================================================================
const _SKIP_PROPS: Dictionary = {
	"script": true, "owner": true, "scene_file_path": true, "unique_name_in_owner": true,
}

const ENUM_HINTS = {
	"anchors_preset": "0:Top Left,1:Top Right,2:Bottom Right,3:Bottom Left,4:Center Left,5:Center Top,6:Center Right,7:Center Bottom,8:Center,9:Left Wide,10:Top Wide,11:Right Wide,12:Bottom Wide,13:VCenter Wide,14:HCenter Wide,15:Full Rect",
	"grow_horizontal": "0:Begin,1:End,2:Both",
	"grow_vertical": "0:Begin,1:End,2:Both",
	"horizontal_alignment": "0:Left,1:Center,2:Right,3:Fill",
	"vertical_alignment": "0:Top,1:Center,2:Bottom,3:Fill"
}

func get_node_properties(args: Dictionary) -> Dictionary:
	var node_type: String = str(args.get(&"node_type", ""))
	if node_type.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'node_type'"}
	if not ClassDB.class_exists(node_type):
		return {&"ok": false, &"error": "Unknown node type: " + node_type}

	var temp = ClassDB.instantiate(node_type)
	if not temp:
		return {&"ok": false, &"error": "Cannot instantiate: " + node_type}

	var properties: Array = []
	for prop: Dictionary in temp.get_property_list():
		var prop_name: String = prop[&"name"]
		if prop_name.begins_with("_"):
			continue
		if _SKIP_PROPS.has(prop_name):
			continue
		if not (prop.get(&"usage", 0) & PROPERTY_USAGE_EDITOR):
			continue

		var info := {
			&"name": prop_name,
			&"type": _type_to_string(prop[&"type"]),
			&"default": _serialize_value(temp.get(prop_name))
		}

		# Enum hints
		if prop.has(&"hint") and prop[&"hint"] == PROPERTY_HINT_ENUM and prop.has(&"hint_string"):
			info[&"enum_values"] = prop[&"hint_string"]
		if prop_name in ENUM_HINTS:
			info[&"enum_values"] = ENUM_HINTS[prop_name]

		properties.append(info)

	temp.queue_free()

	# Inheritance chain
	var chain: Array = []
	var cls: String = node_type
	while cls != "":
		chain.append(cls)
		cls = ClassDB.get_parent_class(cls)

	return {&"ok": true, &"node_type": node_type, &"inheritance_chain": chain,
		&"property_count": properties.size(), &"properties": properties}

func _type_to_string(type_id: int) -> String:
	match type_id:
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "String"
		TYPE_VECTOR2: return "Vector2"
		TYPE_VECTOR3: return "Vector3"
		TYPE_VECTOR2I: return "Vector2i"
		TYPE_VECTOR3I: return "Vector3i"
		TYPE_COLOR: return "Color"
		TYPE_RECT2: return "Rect2"
		TYPE_QUATERNION: return "Quaternion"
		TYPE_AABB: return "AABB"
		TYPE_BASIS: return "Basis"
		TYPE_TRANSFORM3D: return "Transform3D"
		TYPE_OBJECT: return "Resource"
		TYPE_ARRAY: return "Array"
		TYPE_DICTIONARY: return "Dictionary"
		_: return "Variant"

func _serialize_value(value: Variant) -> Variant:
	return VariantCodec.serialize_value(value)

# =============================================================================
# setup_autoload
# =============================================================================
func setup_autoload(args: Dictionary) -> Dictionary:
	var operation: String = str(args.get(&"operation", ""))

	if operation.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'operation'. Use: add, remove, list"}

	match operation:
		"list":
			return _autoload_list()
		"add":
			return _autoload_add(args)
		"remove":
			return _autoload_remove(args)
		_:
			return {&"ok": false, &"error": "Unknown operation: %s. Use: add, remove, list" % operation}

func _autoload_list() -> Dictionary:
	var autoloads: Array = []
	for prop: Dictionary in ProjectSettings.get_property_list():
		var prop_name: String = prop[&"name"]
		if not prop_name.begins_with("autoload/"):
			continue
		var al_name: String = prop_name.substr(9)
		var al_path: String = str(ProjectSettings.get_setting(prop_name, ""))
		var enabled: bool = al_path.begins_with("*")
		if enabled:
			al_path = al_path.substr(1)
		autoloads.append({&"name": al_name, &"path": al_path, &"enabled": enabled})
	return {&"ok": true, &"autoloads": autoloads, &"count": autoloads.size()}

func _autoload_add(args: Dictionary) -> Dictionary:
	var autoload_name: String = str(args.get(&"name", ""))
	var path: String = str(args.get(&"path", ""))

	if autoload_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'name'"}
	if path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'path' for add operation"}

	var guarded := PathGuard.sanitize(path)
	if not guarded[&"ok"]:
		return {&"ok": false, &"error": guarded[&"error"]}
	path = guarded[&"path"]
	if not FileAccess.file_exists(path):
		return {&"ok": false, &"error": "File not found: " + path}

	var setting_key := "autoload/" + autoload_name
	ProjectSettings.set_setting(setting_key, "*" + path)
	_save_and_refresh_settings()

	return {&"ok": true, &"message": "Registered autoload: %s -> %s" % [autoload_name, path]}

func _autoload_remove(args: Dictionary) -> Dictionary:
	var autoload_name: String = str(args.get(&"name", ""))

	if autoload_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'name'"}

	var setting_key := "autoload/" + autoload_name
	if not ProjectSettings.has_setting(setting_key):
		return {&"ok": false, &"error": "Autoload not found: " + autoload_name}

	ProjectSettings.clear(setting_key)
	_save_and_refresh_settings()

	return {&"ok": true, &"message": "Unregistered autoload: " + autoload_name}

# =============================================================================
# Editor Output Panel access
# =============================================================================
# We read directly from the editor's internal EditorLog RichTextLabel.
# This is real-time and matches exactly what the user sees in the Output panel.
# =============================================================================

func _get_editor_log_rtl() -> RichTextLabel:
	"""Find (and cache) the RichTextLabel inside the editor's Output panel."""
	if is_instance_valid(_editor_log_rtl):
		return _editor_log_rtl
	if not _editor_plugin:
		return null
	var base := _editor_plugin.get_editor_interface().get_base_control()
	var editor_log := _find_node_by_class(base, "EditorLog")
	if editor_log:
		_editor_log_rtl = _find_child_rtl(editor_log)
	return _editor_log_rtl

func _find_node_by_class(root: Node, cls_name: String) -> Node:
	if root.get_class() == cls_name:
		return root
	for child: Node in root.get_children():
		var found := _find_node_by_class(child, cls_name)
		if found:
			return found
	return null

func _find_child_rtl(node: Node) -> RichTextLabel:
	for child: Node in node.get_children():
		if child is RichTextLabel:
			return child
		var found := _find_child_rtl(child)
		if found:
			return found
	return null

func _read_output_panel_lines() -> Array:
	"""Return all non-empty lines from the editor Output panel (after clear offset)."""
	var rtl := _get_editor_log_rtl()
	if not rtl:
		return []
	var full_text: String = rtl.get_parsed_text()
	if _clear_char_offset > 0 and _clear_char_offset < full_text.length():
		full_text = full_text.substr(_clear_char_offset)
	elif _clear_char_offset >= full_text.length():
		return []
	var lines: Array = []
	for line: String in full_text.split("\n"):
		if not line.strip_edges().is_empty():
			lines.append(line)
	return lines

# =============================================================================
# get_console_log
# =============================================================================
func get_console_log(args: Dictionary) -> Dictionary:
	var max_lines: int = int(args.get(&"max_lines", 50))
	var filter: String = str(args.get(&"filter", "")).strip_edges().to_lower()

	var rtl := _get_editor_log_rtl()
	if not rtl:
		return {&"ok": false,
			&"error": "Could not access the Godot editor Output panel. Make sure the MCP plugin is enabled and running inside the Godot editor."}

	var all_lines := _read_output_panel_lines()
	if not filter.is_empty():
		var matched: Array = []
		for l in all_lines:
			if str(l).to_lower().contains(filter):
				matched.append(l)
		all_lines = matched
	var start := maxi(0, all_lines.size() - max_lines)
	var lines := all_lines.slice(start)
	# Return only the joined text (dropped the duplicate `lines` array that carried the
	# same content twice — a pointless doubling of the payload).
	return {&"ok": true, &"line_count": lines.size(), &"content": "\n".join(lines)}

# =============================================================================
# get_errors
# =============================================================================
const _ERROR_PREFIXES: PackedStringArray = [
	"ERROR:", "SCRIPT ERROR:", "USER ERROR:",
	"WARNING:", "USER WARNING:", "SCRIPT WARNING:",
	"Parse Error:", "Invalid",
]

func get_errors(args: Dictionary) -> Dictionary:
	var max_errors: int = int(args.get(&"max_errors", 50))
	var include_warnings: bool = bool(args.get(&"include_warnings", true))

	var all_errors: Array = []

	# Source 1: Output panel
	var rtl := _get_editor_log_rtl()
	if rtl:
		var all_lines := _read_output_panel_lines()
		for i: int in range(all_lines.size()):
			var line: String = all_lines[i].strip_edges()
			if line.is_empty():
				continue

			var is_error := false
			var severity := "error"
			for prefix: String in _ERROR_PREFIXES:
				if line.begins_with(prefix):
					is_error = true
					if "WARNING" in prefix:
						severity = "warning"
					break

			if not is_error and line.begins_with("at: ") and "res://" in line:
				if all_errors.size() > 0:
					var prev: Dictionary = all_errors[all_errors.size() - 1]
					var loc := _extract_file_line(line)
					if not loc.is_empty():
						prev[&"file"] = loc.get(&"file", "")
						prev[&"line"] = loc.get(&"line", 0)
				continue

			if not is_error:
				continue
			if severity == "warning" and not include_warnings:
				continue

			var error_info := {&"message": line, &"severity": severity, &"source": &"output"}
			var loc := _extract_file_line(line)
			if not loc.is_empty():
				error_info[&"file"] = loc.get(&"file", "")
				error_info[&"line"] = loc.get(&"line", 0)
			all_errors.append(error_info)

	# Source 2: Debugger > Errors tab
	var dbg_errors := _read_debugger_errors(include_warnings)
	all_errors.append_array(dbg_errors)

	var start := maxi(0, all_errors.size() - max_errors)
	var errors := all_errors.slice(start)
	var out := {&"ok": true, &"errors": errors, &"error_count": errors.size(),
		&"summary": "%d error(s) found" % errors.size()}
	# Say what the Debugger > Errors read actually saw whenever it contributed
	# nothing. "0 errors" and "could not find the panel" are different answers
	# and used to look identical from the outside (issue #4).
	if dbg_errors.is_empty():
		out[&"debugger_panel"] = _error_tree_diag if not _error_tree_diag.is_empty() else {
			&"matched_by": "not searched (no editor plugin)",
		}
	return out

func _extract_file_line(text: String) -> Dictionary:
	var idx := text.find("res://")
	if idx == -1:
		return {}
	var rest := text.substr(idx)
	var colon_idx := rest.find(":", 6)
	if colon_idx == -1:
		return {&"file": rest.strip_edges()}
	var file_path := rest.substr(0, colon_idx)
	var after_colon := rest.substr(colon_idx + 1)
	var line_str := ""
	for c in after_colon:
		if c.is_valid_int():
			line_str += c
		else:
			break
	if not line_str.is_empty():
		return {&"file": file_path, &"line": int(line_str)}
	return {&"file": file_path}

## Error vs warning for one row of the Debugger > Errors tree.
##
## Read from the meta Godot stamps on the row, never from its text: that panel is
## TRANSLATED, so matching on the word "warning" only ever worked in an English
## editor. Everywhere else every warning was reported as an error and
## include_warnings=false filtered nothing. `_is_warning` / `_is_error` are set in
## script_editor_debugger.cpp and read back by Godot the same way, identically on
## 4.5 and 4.7.
func _severity_for_error_item(item: TreeItem, message: String) -> String:
	if item.has_meta(&"_is_warning"):
		return "warning"
	if item.has_meta(&"_is_error"):
		return "error"
	# No meta: not a row Godot built as an error entry. Fall back to the text so
	# an unfamiliar build degrades to the old behaviour instead of calling
	# everything an error.
	return "warning" if "warning" in message.to_lower() else "error"


func _read_debugger_errors(include_warnings: bool) -> Array:
	var tree := _get_debugger_error_tree()
	if not tree:
		return []
	var root := tree.get_root()
	if not root:
		return []

	var errors: Array = []
	var item := root.get_first_child()
	while item:
		var col_count := tree.columns
		var parts: Array = []
		for col: int in range(col_count):
			var text: String = item.get_text(col)
			if not text.strip_edges().is_empty():
				parts.append(text)
		var message: String = " | ".join(parts) if not parts.is_empty() else ""

		if message.strip_edges().is_empty():
			item = item.get_next()
			continue

		var severity := _severity_for_error_item(item, message)

		if severity == "warning" and not include_warnings:
			item = item.get_next()
			continue

		var error_info := {&"message": message, &"severity": severity, &"source": &"debugger"}

		var loc := _extract_file_line(message)
		if not loc.is_empty():
			error_info[&"file"] = loc.get(&"file", "")
			error_info[&"line"] = loc.get(&"line", 0)

		var stack_trace: Array = []
		var child_item := item.get_first_child()
		while child_item:
			var trace_parts: Array = []
			for col: int in range(col_count):
				var t: String = child_item.get_text(col)
				if not t.strip_edges().is_empty():
					trace_parts.append(t)
			if not trace_parts.is_empty():
				stack_trace.append(" | ".join(trace_parts))
			child_item = child_item.get_next()
		if not stack_trace.is_empty():
			error_info[&"stack_trace"] = stack_trace

		errors.append(error_info)
		item = item.get_next()

	return errors

## How many debugger trees the last lookup saw, and which one it took. Reported
## in get_errors' payload so a "returns 0" report answers itself instead of
## needing a session to reproduce (issue #4).
var _error_tree_diag: Dictionary = {}

## Find the Debugger > Errors tree.
##
## Identified by CONTENT, not by node name. The old version walked up from each
## Tree looking for "Error" in an ancestor's name and, failing that, took
## `candidates[0]` — whichever Tree happened to come first under the debugger,
## which could be the profiler's, the monitors' or the stack list. It then
## cached that choice permanently, so one wrong pick meant `error_count: 0`
## forever with a panel full of errors. Godot stamps `_is_error` / `_is_warning`
## on the rows it builds in this panel (script_editor_debugger.cpp), which is
## the same meta `_severity_for_error_item` already trusts for severity — so a
## tree holding rows with that meta IS the errors tree, in any editor language
## and any dock layout.
##
## There can also be more than one ScriptEditorDebugger: Godot makes one per
## debug session tab, so the first one found may be a stale tab while the
## errors are in another.
func _get_debugger_error_tree() -> Tree:
	# Re-validate rather than trust the cache: a cached tree can be freed with
	# its tab, and one cached while empty may not be the errors tree at all.
	if is_instance_valid(_debugger_error_tree) and _tree_error_rows(_debugger_error_tree) > 0:
		return _debugger_error_tree
	if not _editor_plugin:
		return null
	var base := _editor_plugin.get_editor_interface().get_base_control()

	var debuggers: Array[Node] = []
	_collect_by_class(base, "ScriptEditorDebugger", debuggers)
	var candidates: Array[Tree] = []
	for debugger in debuggers:
		_collect_trees(debugger, candidates)

	var best: Tree = null
	var best_rows := 0
	for tree: Tree in candidates:
		var rows := _tree_error_rows(tree)
		if rows > best_rows:
			best = tree
			best_rows = rows

	_error_tree_diag = {
		&"debugger_nodes": debuggers.size(),
		&"trees_examined": candidates.size(),
		&"rows_in_chosen_tree": best_rows,
		&"matched_by": "error/warning row meta" if best != null else "nothing matched",
	}

	# No tree has error rows: either nothing has errored yet, or the panel was
	# cleared. Both mean "no errors", and answering that is correct — guessing a
	# tree is what produced the wrong answer before.
	if best == null:
		_debugger_error_tree = null
		return null

	_debugger_error_tree = best
	return _debugger_error_tree

## Number of top-level rows Godot built as an error/warning entry. Zero for any
## other Tree in the debugger, which is what makes this a reliable identifier.
func _tree_error_rows(tree: Tree) -> int:
	var root := tree.get_root()
	if root == null:
		return 0
	var n := 0
	var item := root.get_first_child()
	while item:
		if item.has_meta(&"_is_error") or item.has_meta(&"_is_warning"):
			n += 1
		item = item.get_next()
	return n

func _collect_by_class(node: Node, cls_name: String, out: Array[Node]) -> void:
	if node.get_class() == cls_name:
		out.append(node)
	for child: Node in node.get_children():
		_collect_by_class(child, cls_name, out)

func _collect_trees(node: Node, out: Array[Tree]) -> void:
	if node is Tree:
		out.append(node as Tree)
	for child: Node in node.get_children():
		_collect_trees(child, out)

# =============================================================================
# clear_console_log
# =============================================================================
func clear_console_log(_args: Dictionary) -> Dictionary:
	var rtl := _get_editor_log_rtl()
	if not rtl:
		return {&"ok": false,
			&"error": "Could not access the Godot editor Output panel. Make sure the MCP plugin is enabled and running inside the Godot editor."}

	# Actually clear the editor Output panel
	rtl.clear()
	_clear_char_offset = 0
	return {&"ok": true,
		&"message": "Console log cleared."}

# =============================================================================
# open_in_godot
# =============================================================================
func open_in_godot(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	var line: int = int(args.get(&"line", 0))

	if path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'path'"}

	var guarded := PathGuard.sanitize(path)
	if not guarded[&"ok"]:
		return {&"ok": false, &"error": guarded[&"error"]}
	path = guarded[&"path"]

	if not _editor_plugin:
		return {&"ok": false, &"error": "Editor plugin not available"}

	var ei = _editor_plugin.get_editor_interface()

	if path.ends_with(".gd") or path.ends_with(".shader"):
		var script = load(path)
		if script:
			ei.edit_resource(script)
			if line > 0:
				ei.get_script_editor().goto_line(line - 1)
		else:
			return {&"ok": false, &"error": "Could not load: " + path}
	elif path.ends_with(".tscn") or path.ends_with(".scn"):
		ei.open_scene_from_path(path)
	else:
		var res = load(path)
		if res:
			ei.edit_resource(res)

	return {&"ok": true, &"message": "Opened %s%s" % [path, " at line %d" % line if line > 0 else ""]}

# =============================================================================
# scene_tree_dump
# =============================================================================
func scene_tree_dump(args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return {&"ok": false, &"error": "Editor plugin not available"}

	var ei = _editor_plugin.get_editor_interface()
	var edited_scene = ei.get_edited_scene_root()

	if not edited_scene:
		return {&"ok": true, &"tree": "(no scene open)", &"message": "No scene is currently open in the editor"}

	# max_depth caps how deep the dump goes so a big scene doesn't return a huge
	# payload; a depth-limited branch reports its descendant count instead. -1 =
	# unlimited (default, unchanged behavior).
	var max_depth := int(args.get(&"max_depth", -1))
	var tree_text := _dump_node(edited_scene, 0, max_depth)

	return {&"ok": true, &"tree": tree_text, &"scene_path": edited_scene.scene_file_path,
		&"max_depth": max_depth}

func _dump_node(node: Node, depth: int, max_depth: int = -1) -> String:
	var indent := "  ".repeat(depth)
	var line := "%s%s (%s)" % [indent, node.name, node.get_class()]

	var script = node.get_script()
	if script:
		line += " [%s]" % script.resource_path.get_file()

	var children := node.get_children()
	if children.is_empty():
		return line

	if max_depth >= 0 and depth >= max_depth:
		return line + "  (+%d descendant node(s), depth-limited)" % _count_descendants(node)

	var parts: PackedStringArray = [line]
	for child: Node in children:
		parts.append(_dump_node(child, depth + 1, max_depth))
	return "\n".join(parts)

func _count_descendants(node: Node) -> int:
	var n := node.get_child_count()
	for child: Node in node.get_children():
		n += _count_descendants(child)
	return n

## Launch N headless Godot instances of `scene` as multiplayer CLIENT peers (they
## get user args `--no-mcp --mp-client` so they connect to the server running in the
## current run_scene game without grabbing the MCP runtime socket). Lets an agent
## drive a real networking test: run the server scene, spawn peers, then check
## get_multiplayer_status / await peer_connected on the server. See
## examples/multiplayer/mp_sample.gd for the server/client role convention the spawned
## scene is expected to follow (host by default; connect as client on --mp-client).
func spawn_headless_peers(args: Dictionary) -> Dictionary:
	var count: int = clampi(int(args.get(&"count", 1)), 1, 8)
	var scene: String = str(args.get(&"scene", "")).strip_edges()
	if scene.is_empty():
		return {&"ok": false, &"error": "Missing 'scene' (res:// path the peers run as clients)"}
	var guarded := PathGuard.sanitize(scene)
	if not guarded[&"ok"]:
		return {&"ok": false, &"error": guarded[&"error"]}
	scene = str(guarded[&"path"])
	if not FileAccess.file_exists(scene):
		return {&"ok": false, &"error": "Scene not found: " + scene}

	var godot := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	var extra: Array = args.get(&"client_args", ["--mp-client"])
	var pids: Array = []
	for i in count:
		var argv := PackedStringArray(["--headless", "--path", proj, scene, "--", "--no-mcp"])
		for a in extra:
			argv.append(str(a))
		var pid := OS.create_process(godot, argv)
		if pid > 0:
			pids.append(pid)
	_spawned_peers.append_array(pids)
	return {&"ok": true, &"spawned": pids.size(), &"pids": pids, &"scene": scene,
		&"message": "Spawned %d headless client peer(s). They connect to the server in the current scene — check get_multiplayer_status (connected_peers) or await peer_connected. Call stop_headless_peers when done." % pids.size()}

## Kill every peer previously spawned by spawn_headless_peers.
func stop_headless_peers(_args: Dictionary) -> Dictionary:
	var killed := 0
	for pid in _spawned_peers:
		if OS.is_process_running(pid):
			OS.kill(pid)
			killed += 1
	var total := _spawned_peers.size()
	_spawned_peers.clear()
	return {&"ok": true, &"killed": killed, &"tracked": total}

## Poll what the DEVELOPER has been doing in the editor — selection changes, scene
## open/close, script focus, filesystem changes — so the agent can react to the human
## working alongside it (bidirectional awareness). Pass since_id from the previous
## call's latest_id to get only new events. Note: events include the agent's OWN edits
## too (a filesystem/selection change fired by a tool call looks the same); correlate
## with your own actions if you need to isolate the human's.
func get_editor_activity(args: Dictionary) -> Dictionary:
	if not _editor_plugin or not _editor_plugin.has_method("get_editor_activity"):
		return {&"ok": false, &"error": "Editor plugin not available (awareness runs inside the editor)."}
	var since_id: int = int(args.get(&"since_id", 0))
	var limit: int = clampi(int(args.get(&"limit", 50)), 1, 200)
	var source_filter: String = str(args.get(&"source", "")).strip_edges().to_lower()
	var r: Dictionary = _editor_plugin.get_editor_activity(since_id, limit, source_filter)
	r[&"ok"] = true
	return r

# =============================================================================
# run_scene / stop_scene / is_playing
# =============================================================================

## Launch a scene in the editor. With block_until_started=true (default true)
## the call waits until the editor's play state flips on, so the agent can
## reliably call get_errors/get_runtime_log/take_screenshot immediately after.
## Set wait_for_runtime=true to additionally block until the MCPRuntime
## autoload connects back; required for take_screenshot / send_input to work
## right away.
## Pause without freezing the editor. Falls back to a blocking delay only where
## there is no SceneTree to yield to (headless tests), which is also the only
## place where freezing costs nothing.
func _yield_ms(ms: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		await tree.create_timer(ms / 1000.0, false, false, true).timeout
	else:
		OS.delay_msec(ms)


## Marker consumed once by MCPRuntime._ready() in the spawned game process. Has
## to be a file rather than an argument to play_custom_scene()/play_main_scene()
## (neither takes one) — writing it just before Play launches the process and
## reading it in the first autoload's _ready() is what makes debug_collisions
## land before the scene exists, which is the one point SceneTree.debug_
## collisions_hint is documented to reliably apply from (see notes/BACKLOG.md
## §5.4 — flipping it mid-session is not reliable).
const _DEBUG_COLLISIONS_MARKER := "res://addons/godot_mcp/cache/.debug_collisions"

func run_scene(args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return {&"ok": false, &"error": "Editor plugin not available"}
	var ei := _editor_plugin.get_editor_interface()
	var scene: String = str(args.get(&"scene", ""))
	var block_until_started: bool = bool(args.get(&"block_until_started", true))
	var wait_for_runtime: bool = bool(args.get(&"wait_for_runtime", false))
	var debug_collisions: bool = bool(args.get(&"debug_collisions", false))
	# Detached: run the game as its own process instead of through the editor's
	# Play. The editor's Play always attaches the remote debugger, and a
	# debugger-attached process HALTS on any GDScript runtime error — including
	# one inside a game_eval snippet — which reads to the bridge as a dead
	# connection and costs a stop/run cycle per typo (notes/BACKLOG.md 5.2).
	# Measured detached: the same bad snippet answers in 107ms and the next call
	# still works.
	var attach_debugger: bool = bool(args.get(&"attach_debugger", true))
	if debug_collisions:
		DirAccess.make_dir_recursive_absolute(_DEBUG_COLLISIONS_MARKER.get_base_dir())
		var f := FileAccess.open(_DEBUG_COLLISIONS_MARKER, FileAccess.WRITE)
		if f:
			f.store_string("1")
	elif FileAccess.file_exists(_DEBUG_COLLISIONS_MARKER):
		DirAccess.remove_absolute(_DEBUG_COLLISIONS_MARKER)
	# A cap, not an expected wait. The "~11-20s" this comment used to quote was
	# measured while a bug made every call run its full timeout; re-measured
	# 2026-09-03 on the same machine and project, MCPRuntime connects in
	# **1.6-1.7s**, attached or detached, across repeated runs. The default
	# stays at 20s because it costs nothing when the connection is fast and
	# still covers a cold-cache import on a big project — but an agent should
	# expect ~2s, not a stall. If wait_for_runtime does report false, poll
	# get_runtime_status shortly after: the connection is very likely about to
	# land rather than broken.
	var startup_timeout_ms: int = int(args.get(&"startup_timeout_ms", 20000))

	_recover_detached_pid()
	if ei.is_playing_scene():
		return {&"ok": false, &"error": "A scene is already running. Call stop_scene first."}
	if _detached_pid != -1 and _process_alive(_detached_pid):
		return {&"ok": false, &"error": "A detached game (pid %d) is already running. Call stop_scene first." % _detached_pid}

	if not attach_debugger:
		return await _run_scene_detached(scene, wait_for_runtime, startup_timeout_ms, debug_collisions)

	# Determine which scene file will run, so we can compute /root/<RootName>
	# for the agent's downstream query_runtime_node calls.
	var resolved_scene_path: String = ""
	if scene == "current":
		var edited := ei.get_edited_scene_root()
		resolved_scene_path = edited.scene_file_path if edited else ""
		ei.play_current_scene()
		_last_run_scene_target = "current"
	elif not scene.is_empty():
		var guarded := PathGuard.sanitize(scene)
		if not guarded[&"ok"]:
			return {&"ok": false, &"error": guarded[&"error"]}
		scene = guarded[&"path"]
		if not FileAccess.file_exists(scene):
			return {&"ok": false, &"error": "Scene file not found: %s" % scene}
		resolved_scene_path = scene
		ei.play_custom_scene(scene)
		_last_run_scene_target = scene
	else:
		resolved_scene_path = str(ProjectSettings.get_setting("application/run/main_scene", ""))
		ei.play_main_scene()
		_last_run_scene_target = "main"

	_last_run_scene_started_at_ms = Time.get_ticks_msec()
	var root_node_name: String = _peek_scene_root_name(resolved_scene_path)
	var runtime_root: String = "/root/%s" % root_node_name if not root_node_name.is_empty() else ""

	var started: bool = ei.is_playing_scene()
	var runtime_connected: bool = _runtime_is_connected()
	var poll_started_ms: int = 0
	var poll_runtime_ms: int = 0

	# Both loops yield to the SceneTree rather than OS.delay_msec — the same
	# hazard `wait` documents, and for a second reason that made it worse here:
	# the conditions below (is_playing_scene, and the runtime-connected flag the
	# client sets when the server tells it) are BOTH updated by the main loop.
	# Blocking it meant they could never become true, so every call ran the full
	# startup_timeout_ms, the WebSocket pump stopped for that whole stretch, and
	# the server's ping watchdog terminated the editor socket — run_scene
	# reported "Godot disconnected" for a game that had launched perfectly.
	if block_until_started and not started:
		var t0 := Time.get_ticks_msec()
		while not started and (Time.get_ticks_msec() - t0) < startup_timeout_ms:
			await _yield_ms(50)
			started = ei.is_playing_scene()
		poll_started_ms = Time.get_ticks_msec() - t0

	if wait_for_runtime and started and not runtime_connected:
		var t1 := Time.get_ticks_msec()
		while not runtime_connected and (Time.get_ticks_msec() - t1) < startup_timeout_ms:
			await _yield_ms(100)
			runtime_connected = _runtime_is_connected()
		poll_runtime_ms = Time.get_ticks_msec() - t1

	var out := {
		&"ok": true,
		&"message": "Scene launched" + (" (%s)" % scene if not scene.is_empty() else " (main scene)"),
		&"started": started,
		&"runtime_connected": runtime_connected,
		&"wait_for_started_ms": poll_started_ms,
		&"wait_for_runtime_ms": poll_runtime_ms,
		&"scene_path": resolved_scene_path,
		&"runtime_root": runtime_root,
		&"hint": "" if started else "Editor did not flip to playing state within startup_timeout_ms. See launch_errors below (also get_console_log for more).",
	}
	# When the launch failed to start, surface WHY inline instead of making the
	# agent do a second get_errors call (a repeated community pain: #106).
	if not started:
		var errs = get_errors({&"max_errors": 10, &"include_warnings": false})
		out[&"launch_errors"] = errs.get(&"errors", [])
	return out

## Read the root node name out of a .tscn without instantiating it. Returns an
## empty string if the file can't be loaded (autoload-only / corrupt / .scn).
func _peek_scene_root_name(scene_path: String) -> String:
	if scene_path.is_empty() or not FileAccess.file_exists(scene_path):
		return ""
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return ""
	var st := packed.get_state()
	if st.get_node_count() == 0:
		return ""
	return str(st.get_node_name(0))

func stop_scene(_args: Dictionary) -> Dictionary:
	# The detached case comes FIRST, before the editor-plugin guard: ending a
	# process we started ourselves needs no editor, and requiring one made a
	# detached game unstoppable in exactly the situations where it is most
	# likely to be left running.
	#
	# A detached game is not "playing" as far as the editor is concerned, so it
	# has to be ended by pid or it outlives the session in the background.
	_recover_detached_pid()
	if _detached_pid != -1:
		var pid := _detached_pid
		_forget_detached_pid()
		if _process_alive(pid):
			_kill_pid(pid)
			return {&"ok": true, &"detached": true, &"pid": pid, &"message": "Detached game (pid %d) stopped." % pid}
		return {&"ok": true, &"detached": true, &"pid": pid, &"message": "Detached game (pid %d) had already exited." % pid}

	if not _editor_plugin:
		return {&"ok": false, &"error": "Editor plugin not available"}
	var ei := _editor_plugin.get_editor_interface()
	if not ei.is_playing_scene():
		return {&"ok": true, &"message": "No scene is currently running"}
	ei.stop_playing_scene()
	return {&"ok": true, &"message": "Scene stopped"}


## Launch the game as a separate process, with no debugger attached.
##
## What this buys, and what it costs, both measured rather than assumed:
##   + a runtime error inside game_eval comes back as a result instead of
##     halting the process and timing the call out (5.2)
##   + the editor is not driving the game, so its UI stays out of the way
##   - no editor debugger: the debug_* tools have nothing to attach to, and the
##     Debugger > Errors panel stays empty, so get_errors loses its runtime
##     source. get_runtime_log and get_console_log still work.
##   - is_playing() reports false: the editor genuinely is not playing anything.
func _run_scene_detached(scene: String, wait_for_runtime: bool, startup_timeout_ms: int, debug_collisions: bool) -> Dictionary:
	var target := scene
	if target.is_empty() or target == "current":
		var ei := _editor_plugin.get_editor_interface()
		if target == "current":
			var edited := ei.get_edited_scene_root()
			target = edited.scene_file_path if edited else ""
		if target.is_empty():
			target = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if target.is_empty():
		return {&"ok": false, &"error": "No scene to run: pass 'scene', open one, or set a main scene."}

	if debug_collisions:
		DirAccess.make_dir_recursive_absolute(_DEBUG_COLLISIONS_MARKER.get_base_dir())
		var f := FileAccess.open(_DEBUG_COLLISIONS_MARKER, FileAccess.WRITE)
		if f:
			f.store_string("1")

	var exe := OS.get_executable_path()
	var project_dir := ProjectSettings.globalize_path("res://")
	var pid := OS.create_process(exe, ["--path", project_dir, target])
	if pid <= 0:
		return {&"ok": false, &"error": "Could not start a detached Godot process (create_process returned %d)." % pid}

	_remember_detached_pid(pid)
	_last_run_scene_target = target
	_last_run_scene_started_at_ms = Time.get_ticks_msec()

	var runtime_connected := _runtime_is_connected()
	var waited_ms := 0
	if wait_for_runtime and not runtime_connected:
		var t0 := Time.get_ticks_msec()
		while not runtime_connected and (Time.get_ticks_msec() - t0) < startup_timeout_ms:
			await _yield_ms(100)
			runtime_connected = _runtime_is_connected()
		waited_ms = Time.get_ticks_msec() - t0

	var root_node_name: String = _peek_scene_root_name(target)
	return {
		&"ok": true,
		&"detached": true,
		&"pid": pid,
		&"started": true,
		&"scene_path": target,
		&"runtime_connected": runtime_connected,
		&"wait_for_runtime_ms": waited_ms,
		&"runtime_root": "/root/%s" % root_node_name if not root_node_name.is_empty() else "",
		&"message": "Started detached (pid %d), no debugger attached. game_eval survives a runtime error here; in exchange the debug_* tools and the Debugger > Errors source of get_errors are unavailable, and is_playing() reports false. stop_scene ends it." % pid,
	}

## Backward-compatible thin wrapper around get_runtime_status. Keep using this
## if you only need the boolean. For richer info (uptime, runtime helper status,
## last launched scene), prefer get_runtime_status.
func is_playing(_args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return {&"ok": false, &"error": "Editor plugin not available"}
	var ei := _editor_plugin.get_editor_interface()
	var playing := ei.is_playing_scene()
	var scene_path := ei.get_playing_scene() if playing else ""
	return {&"ok": true, &"playing": playing, &"scene": scene_path}

## Is this pid still alive, including one this process did not spawn?
##
## OS.is_process_running only knows the handles create_process opened in THIS
## process, so a game adopted from a previous editor session always reads as
## dead — which is precisely the case the pid file exists to cover. Fall back to
## asking the OS directly.
func _process_alive(pid: int) -> bool:
	if pid <= 0:
		return false
	if OS.is_process_running(pid):
		return true
	var out: Array = []
	if OS.get_name() == "Windows":
		OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/NH", "/FO", "CSV"], out, true)
		return out.size() > 0 and ("\"%d\"" % pid) in str(out[0])
	return OS.execute("kill", ["-0", str(pid)], out, true) == 0

## Kill by pid, including one this process did not spawn (see _process_alive).
func _kill_pid(pid: int) -> void:
	if OS.kill(pid) == OK:
		return
	var out: Array = []
	if OS.get_name() == "Windows":
		OS.execute("taskkill", ["/PID", str(pid), "/F"], out, true)
	else:
		OS.execute("kill", ["-9", str(pid)], out, true)

func _remember_detached_pid(pid: int) -> void:
	_detached_pid = pid
	var f := FileAccess.open(_DETACHED_PID_FILE, FileAccess.WRITE)
	if f:
		f.store_string(str(pid))
		f.close()

func _forget_detached_pid() -> void:
	_detached_pid = -1
	if FileAccess.file_exists(_DETACHED_PID_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_DETACHED_PID_FILE))

## Adopt a detached game left running by a previous editor session.
func _recover_detached_pid() -> void:
	if _detached_pid != -1 or not FileAccess.file_exists(_DETACHED_PID_FILE):
		return
	var f := FileAccess.open(_DETACHED_PID_FILE, FileAccess.READ)
	if not f:
		return
	var pid := int(f.get_as_text().strip_edges())
	f.close()
	if _process_alive(pid):
		_detached_pid = pid
	else:
		_forget_detached_pid()

## Combined editor-side and runtime-side status snapshot.
func get_runtime_status(_args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return {&"ok": false, &"error": "Editor plugin not available"}
	var ei := _editor_plugin.get_editor_interface()
	var playing := ei.is_playing_scene()
	# A detached game is not "playing" as far as the editor is concerned, but it
	# is running and the helper is talking to us — reporting uptime 0 for it made
	# the field useless exactly where it is most wanted.
	_recover_detached_pid()
	var detached_running := _detached_pid != -1 and _process_alive(_detached_pid)
	var uptime_ms := 0
	if (playing or detached_running) and _last_run_scene_started_at_ms > 0:
		uptime_ms = Time.get_ticks_msec() - _last_run_scene_started_at_ms

	return {
		&"ok": true,
		&"playing": playing,
		&"detached_pid": _detached_pid if detached_running else null,
		&"playing_scene": ei.get_playing_scene() if playing else "",
		&"last_launched": _last_run_scene_target,
		&"uptime_ms": uptime_ms,
		&"runtime_helper_connected": _runtime_is_connected(),
	}

# =============================================================================
# Editor-side wait. Runtime tools (take_screenshot, send_input,
# query_runtime_node, get_runtime_log, list_signal_connections with
# source="runtime") are routed by the TS MCP server directly to the
# MCPRuntime autoload running inside the user's game and never reach this
# editor-side dispatcher.
# =============================================================================
func _runtime_is_connected() -> bool:
	if _mcp_client == null:
		return false
	if _mcp_client.has_method("is_runtime_connected"):
		return _mcp_client.is_runtime_connected()
	return false

## Hard cap for `wait`. Must stay comfortably below the TS server's per-request
## timeout (30000ms) so the tool always has time to round-trip the result
## back before the transport gives up. We also never want to freeze the editor
## for a long time, so 20s is already on the generous side.
const _WAIT_MAX_MS: int = 20000

func wait(args: Dictionary) -> Dictionary:
	# Accept either ms (int) or seconds (float). If both are provided, ms wins.
	# Values above _WAIT_MAX_MS are clamped (not rejected) so the agent can
	# pass generous timeouts without tripping an error.
	#
	# IMPORTANT: we yield to the scene tree via `create_timer().timeout` INSTEAD
	# of `OS.delay_msec`, because the latter freezes the editor's main thread,
	# which in turn freezes the WebSocket pump, causes the TS server to hit
	# its 30s request timeout, and leaves the socket in a broken state when
	# Godot tries to write the response.
	var ms_raw: float = 0.0
	var had_input: bool = false
	if args.has(&"ms") and typeof(args.get(&"ms")) != TYPE_NIL:
		ms_raw = float(args.get(&"ms", 0))
		had_input = true
	elif args.has(&"seconds") and typeof(args.get(&"seconds")) != TYPE_NIL:
		ms_raw = float(args.get(&"seconds", 0.0)) * 1000.0
		had_input = true

	if not had_input or ms_raw <= 0.0:
		return {&"ok": false, &"error": "Missing or non-positive duration. Pass ms (int) or seconds (float)."}

	var requested_ms: int = int(round(ms_raw))
	var ms: int = clampi(requested_ms, 1, _WAIT_MAX_MS)
	var clamped: bool = requested_ms > _WAIT_MAX_MS

	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		await tree.create_timer(ms / 1000.0, false, false, true).timeout
	else:
		# Fallback (headless / no SceneTree). Still safer than a long blocking
		# delay because `ms` is already clamped to _WAIT_MAX_MS.
		OS.delay_msec(ms)

	var out: Dictionary = {&"ok": true, &"waited_ms": ms}
	if clamped:
		out[&"clamped"] = true
		out[&"requested_ms"] = requested_ms
		out[&"note"] = "Requested duration exceeded the %dms cap; waited %dms. Keep waits short; for long operations use get_runtime_status polling instead." % [_WAIT_MAX_MS, ms]
	return out

# =============================================================================
# rescan_filesystem
# =============================================================================

func rescan_filesystem(_args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return {&"ok": false, &"error": "No editor plugin available"}
	var efs := _editor_plugin.get_editor_interface().get_resource_filesystem()
	if efs.is_scanning():
		return {&"ok": false, &"error": "A filesystem scan is already in progress. Wait and retry."}
	efs.scan()
	return {&"ok": true, &"message": "Filesystem rescan triggered."}

# =============================================================================
# render_scene_preview
# =============================================================================

## Render a scene to a PNG without running the game.
##
## The gap: `take_screenshot` needs a running game, so the only way to LOOK at a
## scene was to launch it — a couple of seconds, a runtime connection, and a
## scene left running if you forget to stop it. Checking whether a level's
## platforms line up should not cost that. Building one, every visual mistake
## (grass strips three times too tall, a hitbox in the wrong place) was found by
## launching the game or not at all.
##
## Renders offscreen in a SubViewport, so the editor's own layout, grid and
## gizmos are not in the shot and nothing about the editor state changes.
## 2D only — a 3D scene needs a camera decision this cannot make for you.
func render_scene_preview(args: Dictionary) -> Dictionary:
	var raw_scene: String = str(args.get(&"scene_path", ""))
	if raw_scene.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	# PathGuard, not SceneToolBase's _ensure_res_path: this file extends Node, so
	# it does not inherit the scene helpers.
	var guarded_scene := PathGuard.sanitize(raw_scene)
	if not guarded_scene[&"ok"]:
		return {&"ok": false, &"error": guarded_scene[&"error"]}
	var scene_path: String = str(guarded_scene[&"path"])
	if not FileAccess.file_exists(scene_path):
		return {&"ok": false, &"error": "Scene not found: " + scene_path}

	var width: int = clampi(int(args.get(&"width", 1152)), 64, 4096)
	var height: int = clampi(int(args.get(&"height", 648)), 64, 4096)
	var save_to: String = str(args.get(&"save_to", ""))
	if save_to.strip_edges().is_empty():
		save_to = "res://addons/godot_mcp/cache/previews/%s.png" % scene_path.get_file().get_basename()
	var guarded_out := PathGuard.sanitize(save_to)
	if not guarded_out[&"ok"]:
		return {&"ok": false, &"error": "'save_to' rejected: " + str(guarded_out[&"error"])}
	save_to = str(guarded_out[&"path"])

	var packed := load(scene_path) as PackedScene
	if packed == null:
		return {&"ok": false, &"error": "Could not load as a scene: " + scene_path}
	var instance := packed.instantiate()
	if instance == null:
		return {&"ok": false, &"error": "Scene failed to instantiate: " + scene_path}

	var viewport := SubViewport.new()
	viewport.size = Vector2i(width, height)
	viewport.transparent_bg = bool(args.get(&"transparent", false))
	# ALWAYS, not the default ONCE: the render has to survive the frames we wait,
	# and a one-shot update would have cleared before the texture is read.
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(instance)

	# Any tree will do — rendering needs frames, not an editor. Falling back to
	# the main loop's root keeps this runnable (and testable) headless instead of
	# refusing without a plugin.
	var host: Node = _editor_plugin
	if host == null and is_inside_tree():
		# This node's own tree, which is the reliable handle — Engine's main loop
		# is not always castable to a SceneTree depending on how the tool was
		# reached.
		host = get_tree().root
	if host == null:
		instance.free()
		viewport.free()
		return {&"ok": false, &"error": "No scene tree available to render into"}
	host.add_child(viewport)

	# Frame the content instead of trusting it to sit at the origin — a level's
	# nodes are wherever the designer put them, often thousands of pixels out.
	var bounds := _content_bounds(instance)
	var camera := Camera2D.new()
	if bounds.has_area():
		camera.position = bounds.get_center()
		var margin: float = 1.08
		var zoom_factor: float = minf(
			float(width) / (bounds.size.x * margin),
			float(height) / (bounds.size.y * margin))
		# Never zoom IN past 1:1 — a magnified pixel-art scene reads as blurry
		# and hides exactly the alignment problems this is for.
		camera.zoom = Vector2.ONE * minf(zoom_factor, 1.0)
	viewport.add_child(camera)
	camera.make_current()

	# Set before the scene ever draws a frame in this tree — the exact point
	# SceneTree.debug_collisions_hint is documented to reliably apply from (see
	# notes/BACKLOG.md §5.4). Reliable here in a way it is not for a live
	# run_scene: this instance was only just added to the tree, so there is no
	# "already drawn" frame to have missed. Restored after, since `host`'s tree
	# is long-lived (the editor's own, most of the time) and this must not leave
	# collision outlines on for anything else sharing it.
	var show_collision: bool = bool(args.get(&"show_collision", false))
	var tree := host.get_tree()
	var prev_debug_collisions := tree.debug_collisions_hint
	if show_collision:
		tree.debug_collisions_hint = true

	# Two frames: one to build the render target, one to draw into it.
	await tree.process_frame
	await tree.process_frame

	var image := viewport.get_texture().get_image()
	if show_collision:
		tree.debug_collisions_hint = prev_debug_collisions
	host.remove_child(viewport)
	viewport.queue_free()

	if image == null:
		return {&"ok": false, &"error": "Viewport produced no image"}

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_to.get_base_dir()))
	var err := image.save_png(save_to)
	if err != OK:
		return {&"ok": false, &"error": "Could not write %s (err %d)" % [save_to, err]}
	# So the new PNG shows up in the editor's filesystem dock and can be loaded.
	if _editor_plugin:
		_editor_plugin.get_editor_interface().get_resource_filesystem().scan()

	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"resource_path": save_to,
		&"absolute_path": ProjectSettings.globalize_path(save_to),
		&"width": image.get_width(),
		&"height": image.get_height(),
		&"content_bounds": {&"x": bounds.position.x, &"y": bounds.position.y,
			&"width": bounds.size.x, &"height": bounds.size.y},
		&"zoom": camera.zoom.x,
		&"message": "Rendered %s to %s (no game launched)" % [scene_path, save_to],
	}

## World-space rectangle covering the scene's visible 2D content. Empty Rect2
## when nothing measurable was found, which the caller treats as "do not frame".
func _content_bounds(root: Node) -> Rect2:
	var bounds := Rect2()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)

		var rect := _node_rect(node)
		if rect == null:
			continue
		if first:
			bounds = rect
			first = false
		else:
			bounds = bounds.merge(rect)
	return bounds

## The world-space rect of one node, or null when it has no measurable extent.
## Covers the node types that actually carry a level's silhouette; anything else
## contributes nothing rather than guessing.
func _node_rect(node: Node) -> Variant:
	if node is Control:
		var c := node as Control
		if not c.is_visible_in_tree():
			return null
		return c.get_global_rect()
	if node is Sprite2D:
		var s := node as Sprite2D
		if s.texture == null or not s.is_visible_in_tree():
			return null
		var size := s.texture.get_size()
		size.x /= maxf(1.0, float(s.hframes))
		size.y /= maxf(1.0, float(s.vframes))
		var local := Rect2(-size * 0.5 if s.centered else Vector2.ZERO, size)
		return s.get_global_transform() * local
	if node is CollisionShape2D:
		var cs := node as CollisionShape2D
		if cs.shape == null:
			return null
		return cs.get_global_transform() * cs.shape.get_rect()
	# A bare Node2D is deliberately NOT counted. It has no extent, and folding its
	# origin into the bounds drags the frame toward wherever the scene root sits:
	# a level whose content lives at x=2000 framed from 0 renders mostly empty
	# space. Only things with a real silhouette decide the framing.
	return null

# =============================================================================
# restart_editor
# =============================================================================

## Restart the Godot editor, optionally saving first.
##
## Exists because a rescan is not always enough. Two things a running editor
## will not pick up on its own:
##   - an AUTOLOAD added during the session. Until it restarts, every script
##     referencing that singleton fails to compile, and — worse — a node whose
##     script failed to compile silently loses its exported properties, so
##     create_scene reports ok and writes defaults.
##   - a brand-new `class_name`, which the same failure mode follows.
## Both cost real time to diagnose, because nothing reports them as errors.
## Before this tool the only way out was killing the process from a shell.
##
## The connection drops with the editor and comes back a few seconds after it
## reopens — poll get_godot_status until connected, the same as a manual restart.
func restart_editor(args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return {&"ok": false, &"error": "No editor plugin available"}
	var save_first: bool = bool(args.get(&"save", true))

	var interface := _editor_plugin.get_editor_interface()
	if save_first:
		# Scenes first, then project settings: restart_editor(true) saves open
		# scenes but NOT ProjectSettings, and a setting changed through these
		# tools this session would otherwise be lost by the very restart meant to
		# make it take effect.
		interface.save_all_scenes()
		ProjectSettings.save()

	# Deferred so this call can return before the editor goes down — otherwise
	# the response never reaches the agent and the restart looks like a crash.
	interface.call_deferred(&"restart_editor", save_first)
	return {
		&"ok": true,
		&"saved": save_first,
		&"message": "Editor is restarting. The bridge will disconnect; poll get_godot_status until it reports connected again (usually 20-40s).",
	}

# =============================================================================
# classdb_query
# =============================================================================

const _WELL_KNOWN_VIRTUALS: Array[String] = [
	"_ready", "_process", "_physics_process", "_input", "_unhandled_input",
	"_unhandled_key_input", "_enter_tree", "_exit_tree", "_draw",
	"_gui_input", "_init", "_notification",
]

func classdb_query(args: Dictionary) -> Dictionary:
	var class_name_str: String = str(args.get(&"class_name", ""))
	if class_name_str.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'class_name'"}
	if not ClassDB.class_exists(class_name_str):
		return {&"ok": false, &"error": "Class '%s' does not exist in ClassDB" % class_name_str}

	var query: String = str(args.get(&"query", "all"))
	var include_virtual: bool = args.get(&"include_virtual", true)
	# Substring filter on member names — cuts the output hard on big classes when you
	# only need to check whether a specific method/property/signal exists.
	var filter: String = str(args.get(&"filter", "")).strip_edges().to_lower()
	var result: Dictionary = {&"ok": true, &"class": class_name_str}
	if not filter.is_empty():
		result[&"filter"] = filter

	result[&"parent_class"] = ClassDB.get_parent_class(class_name_str)

	if query == "all" or query == "properties":
		var props: Array = []
		for prop: Dictionary in ClassDB.class_get_property_list(class_name_str, true):
			if int(prop.get(&"usage", 0)) & PROPERTY_USAGE_EDITOR:
				if not filter.is_empty() and not str(prop[&"name"]).to_lower().contains(filter):
					continue
				props.append({&"name": prop[&"name"], &"type": type_string(int(prop[&"type"]))})
		result[&"properties"] = props

	if query == "all" or query == "methods":
		var methods: Array = []
		for method: Dictionary in ClassDB.class_get_method_list(class_name_str, true):
			var mname: String = method.get(&"name", "")
			if mname.begins_with("_"):
				if not include_virtual:
					continue
				if mname not in _WELL_KNOWN_VIRTUALS:
					continue
			if not filter.is_empty() and not mname.to_lower().contains(filter):
				continue
			var method_args: Array = []
			for arg: Dictionary in method.get(&"args", []):
				method_args.append({&"name": arg[&"name"], &"type": type_string(int(arg[&"type"]))})
			methods.append({&"name": mname, &"args": method_args,
				&"return_type": type_string(int(method.get(&"return", {}).get(&"type", 0)))})
		result[&"methods"] = methods

	if query == "all" or query == "signals":
		var signals_list: Array = []
		for sig: Dictionary in ClassDB.class_get_signal_list(class_name_str, true):
			if not filter.is_empty() and not str(sig[&"name"]).to_lower().contains(filter):
				continue
			var sig_args: Array = []
			for arg: Dictionary in sig.get(&"args", []):
				sig_args.append({&"name": arg[&"name"], &"type": type_string(int(arg[&"type"]))})
			signals_list.append({&"name": sig[&"name"], &"args": sig_args})
		result[&"signals"] = signals_list

	return result

# =============================================================================
# get_uid - resolve a resource's UID (Godot 4.4+ res:// unique IDs)
# =============================================================================
func get_uid(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	if path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'path'"}
	var guarded := PathGuard.sanitize(path)
	if not guarded[&"ok"]:
		return {&"ok": false, &"error": guarded[&"error"]}
	path = guarded[&"path"]

	if not FileAccess.file_exists(path):
		return {&"ok": false, &"error": "File not found: " + path}

	var id: int = ResourceLoader.get_resource_uid(path)
	if id == ResourceUID.INVALID_ID:
		return {&"ok": false, &"error": "No UID assigned to " + path + " (not imported yet, or UIDs unsupported for this file type)"}

	return {&"ok": true, &"path": path, &"uid": ResourceUID.id_to_text(id)}

# =============================================================================
# remove_autoload - counterpart to setup_autoload's "remove" operation
# =============================================================================
func remove_autoload(args: Dictionary) -> Dictionary:
	return _autoload_remove(args)

# =============================================================================
# get_editor_selection / select_nodes / clear_editor_selection
# =============================================================================
func get_editor_selection(_args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return {&"ok": false, &"error": "Editor selection tools require a live editor session"}

	var ei := _editor_plugin.get_editor_interface()
	var edited_scene := ei.get_edited_scene_root()
	var selected: Array = []
	for node: Node in ei.get_selection().get_selected_nodes():
		var node_path: String = str(edited_scene.get_path_to(node)) if edited_scene and edited_scene.is_ancestor_of(node) else str(node.get_path())
		selected.append({&"node_path": node_path, &"node_type": node.get_class()})

	return {&"ok": true, &"selected": selected, &"count": selected.size()}

func select_nodes(args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return {&"ok": false, &"error": "Editor selection tools require a live editor session"}

	var scene_path: String = str(args.get(&"scene_path", ""))
	var node_paths: Array = args.get(&"node_paths", [])

	if scene_path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	var guarded := PathGuard.sanitize(scene_path)
	if not guarded[&"ok"]:
		return {&"ok": false, &"error": guarded[&"error"]}
	scene_path = guarded[&"path"]

	var ei := _editor_plugin.get_editor_interface()
	var edited_scene := ei.get_edited_scene_root()
	if not edited_scene or edited_scene.scene_file_path != scene_path:
		return {&"ok": false, &"error": "'scene_path' does not match the currently open edited scene (%s)" % (edited_scene.scene_file_path if edited_scene else "none open")}

	var selection := ei.get_selection()
	selection.clear()

	var selected: Array = []
	var not_found: Array = []
	for node_path in node_paths:
		var node := edited_scene.get_node_or_null(str(node_path))
		if not node:
			not_found.append(str(node_path))
			continue
		selection.add_node(node)
		selected.append(str(node_path))

	var out: Dictionary = {&"ok": true, &"selected": selected, &"count": selected.size()}
	if not not_found.is_empty():
		out[&"not_found"] = not_found
	return out

func clear_editor_selection(_args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return {&"ok": false, &"error": "Editor selection tools require a live editor session"}

	_editor_plugin.get_editor_interface().get_selection().clear()
	return {&"ok": true, &"message": "Editor selection cleared"}

# =============================================================================
# close_scene_tab
# =============================================================================
## Closes a scene tab in the editor. EditorInterface.close_scene() only
## closes the currently-focused tab, so if scene_path isn't the active one
## we focus it first via open_scene_from_path().
func close_scene_tab(args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return {&"ok": false, &"error": "Editor selection tools require a live editor session"}

	var scene_path: String = str(args.get(&"scene_path", ""))
	var force: bool = bool(args.get(&"force", false))

	if scene_path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	var guarded := PathGuard.sanitize(scene_path)
	if not guarded[&"ok"]:
		return {&"ok": false, &"error": guarded[&"error"]}
	scene_path = guarded[&"path"]

	var ei := _editor_plugin.get_editor_interface()
	if scene_path not in ei.get_open_scenes():
		return {&"ok": false, &"error": "Scene is not open in the editor: " + scene_path}
	# get_unsaved_scenes() is 4.6+. On 4.5 — the version this addon advertises as
	# its minimum — calling it aborts the handler mid-way, and the tool returns
	# nothing at all. Without it there is no way to ask which scenes are dirty,
	# so the safe reading is "assume it might be": require force explicitly
	# rather than closing a tab that could be holding unsaved work.
	if ei.has_method(&"get_unsaved_scenes"):
		if scene_path in ei.get_unsaved_scenes() and not force:
			return {&"ok": false, &"error": "Scene has unsaved changes: %s. Save it first, or pass force=true to discard changes." % scene_path}
	elif not force:
		return {&"ok": false, &"error": "This Godot version (%s) cannot report which scenes have unsaved changes, so closing a tab might discard the developer's work. Save the scene first, or pass force=true to close it anyway." % Engine.get_version_info().get("string", "unknown")}

	var edited_scene := ei.get_edited_scene_root()
	if not edited_scene or edited_scene.scene_file_path != scene_path:
		ei.open_scene_from_path(scene_path)

	# Not `:=` — close_scene() returns void on Godot 4.3 and an Error later, so an
	# inferred type fails to compile on the version this addon advertises.
	var err = ei.close_scene()
	if err != null and int(err) != OK:
		return {&"ok": false, &"error": "Failed to close scene tab: " + str(err)}

	return {&"ok": true, &"scene_path": scene_path, &"message": "Closed scene tab: " + scene_path}

# =============================================================================
# get_performance_monitors / get_editor_performance
# =============================================================================
func get_performance_monitors(_args: Dictionary) -> Dictionary:
	return {
		&"ok": true,
		&"fps": Performance.get_monitor(Performance.TIME_FPS),
		&"process_time": Performance.get_monitor(Performance.TIME_PROCESS),
		&"physics_process_time": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),
		&"memory_static": Performance.get_monitor(Performance.MEMORY_STATIC),
		&"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
		&"object_node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		&"render_total_draw_calls_in_frame": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		&"physics_2d_active_objects": Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
		&"physics_3d_active_objects": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
	}

func get_editor_performance(_args: Dictionary) -> Dictionary:
	return {
		&"ok": true,
		&"fps": Performance.get_monitor(Performance.TIME_FPS),
		&"memory_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0),
	}

# =============================================================================
# create_resource
# =============================================================================
func create_resource(args: Dictionary) -> Dictionary:
	var resource_path: String = str(args.get(&"resource_path", ""))
	var resource_type: String = str(args.get(&"resource_type", ""))

	if resource_path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'resource_path'"}
	var guarded := PathGuard.sanitize(resource_path)
	if not guarded[&"ok"]:
		return {&"ok": false, &"error": guarded[&"error"]}
	resource_path = guarded[&"path"]
	if resource_type.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'resource_type'"}
	if not ClassDB.class_exists(resource_type):
		return {&"ok": false, &"error": "Unknown resource type: " + resource_type}

	var instance = ClassDB.instantiate(resource_type)
	if not instance:
		return {&"ok": false, &"error": "Cannot instantiate: " + resource_type}
	if not (instance is Resource):
		if instance is Node:
			instance.free()
		elif instance is RefCounted:
			pass
		else:
			instance.free()
		return {&"ok": false, &"error": "'%s' is not a Resource (it's a %s)" % [resource_type, instance.get_class()]}

	var save_result := ResourceSaver.save(instance, resource_path)
	if save_result != OK:
		return {&"ok": false, &"error": "Failed to save resource: " + str(save_result)}

	return {&"ok": true, &"resource_path": resource_path, &"resource_type": resource_type,
		&"message": "Created %s resource at %s" % [resource_type, resource_path]}

# =============================================================================
# list_export_presets / get_export_info / export_project
# =============================================================================
const _EXPORT_PRESETS_PATH := "res://export_presets.cfg"

func list_export_presets(_args: Dictionary) -> Dictionary:
	var cfg := ConfigFile.new()
	var err := cfg.load(_EXPORT_PRESETS_PATH)
	if err != OK:
		return {&"ok": true, &"presets": [], &"count": 0,
			&"message": "No export_presets.cfg found — no presets configured yet."}

	var presets: Array = []
	for section: String in cfg.get_sections():
		if not section.begins_with("preset.") or section.contains(".options"):
			continue
		var index: int = int(section.substr(7))
		presets.append({
			&"index": index,
			&"name": cfg.get_value(section, "name", ""),
			&"platform": cfg.get_value(section, "platform", ""),
			&"runnable": cfg.get_value(section, "runnable", false),
			&"export_path": cfg.get_value(section, "export_path", ""),
		})

	return {&"ok": true, &"presets": presets, &"count": presets.size()}

func get_export_info(args: Dictionary) -> Dictionary:
	var preset_index: int = int(args.get(&"preset_index", -1))
	if preset_index < 0:
		return {&"ok": false, &"error": "Missing or invalid 'preset_index'"}

	var cfg := ConfigFile.new()
	var err := cfg.load(_EXPORT_PRESETS_PATH)
	if err != OK:
		return {&"ok": false, &"error": "No export_presets.cfg found"}

	var section := "preset.%d" % preset_index
	if not cfg.has_section(section):
		return {&"ok": false, &"error": "Preset index %d not found" % preset_index}

	var preset_data: Dictionary = {}
	for key: String in cfg.get_section_keys(section):
		preset_data[key] = cfg.get_value(section, key)

	var options_section := "preset.%d.options" % preset_index
	var options: Dictionary = {}
	if cfg.has_section(options_section):
		for key: String in cfg.get_section_keys(options_section):
			options[key] = cfg.get_value(options_section, key)

	return {&"ok": true, &"preset_index": preset_index, &"preset": preset_data, &"options": options}

## Real headless export via a "shadow workspace": the project is cloned to a temp
## dir and a separate `godot --headless --export-*` subprocess builds it there. We do
## NOT export the live project dir directly — the in-editor export API blocks the main
## thread and deadlocks the Vulkan shader compiler, and exporting the open dir risks a
## Windows sharing-violation and corrupts global_script_class_cache.cfg. The clone keeps
## the import cache so it doesn't reimport from scratch. See RESEARCH_SUMMARY.md §3.
func export_project(args: Dictionary) -> Dictionary:
	var preset_index: int = int(args.get(&"preset_index", -1))
	var preset_name: String = str(args.get(&"preset_name", "")).strip_edges()
	var output_path: String = str(args.get(&"output_path", "")).strip_edges()
	var debug: bool = bool(args.get(&"debug", false))

	if output_path.is_empty():
		return {&"ok": false, &"error": "Missing 'output_path' (where to write the exported build, e.g. res://build/game.exe or an absolute path)"}

	var cfg := ConfigFile.new()
	if cfg.load(_EXPORT_PRESETS_PATH) != OK:
		return {&"ok": false, &"error": "No export_presets.cfg found. Create an export preset first in the editor (Project > Export), then retry with its name or index."}

	# The --export CLI arg is the preset NAME, so resolve index → name if needed.
	if preset_name.is_empty():
		if preset_index < 0:
			return {&"ok": false, &"error": "Provide 'preset_name' or 'preset_index'"}
		var section := "preset.%d" % preset_index
		if not cfg.has_section(section):
			return {&"ok": false, &"error": "Preset index %d not found" % preset_index}
		preset_name = str(cfg.get_value(section, "name", ""))
	if preset_name.is_empty():
		# Say what there IS. "Could not resolve a preset name" leaves the caller
		# guessing at strings when the answer is a list the file already holds.
		var known: Array = []
		for sect in cfg.get_sections():
			if sect.begins_with("preset.") and not sect.ends_with(".options"):
				known.append(str(cfg.get_value(sect, "name", sect)))
		return {&"ok": false, &"error": "Could not resolve a preset name. Presets in export_presets.cfg: %s" % (", ".join(known) if not known.is_empty() else "(none)")}

	# Flush unsaved editor state so the clone reflects the current project.
	if _editor_plugin:
		_editor_plugin.get_editor_interface().save_all_scenes()

	# Resolve the artifact to an absolute path OUTSIDE the temp clone (so no copy-back).
	var artifact_abs := output_path
	if output_path.begins_with("res://"):
		var guarded := PathGuard.sanitize(output_path)
		if not guarded[&"ok"]:
			return {&"ok": false, &"error": "output_path escapes the project sandbox"}
		artifact_abs = ProjectSettings.globalize_path(str(guarded[&"path"]))
	var art_dir := artifact_abs.get_base_dir()
	if not DirAccess.dir_exists_absolute(art_dir):
		DirAccess.make_dir_recursive_absolute(art_dir)

	var src_dir := ProjectSettings.globalize_path("res://")
	# OS.get_temp_dir() is Godot 4.5+; user:// is writable everywhere and is the
	# right home for a scratch clone anyway (it is per-project and not exported).
	var temp_root := ProjectSettings.globalize_path("user://")
	var temp_dir := temp_root.path_join("godot_shadow_ws_%d" % Time.get_ticks_msec())
	var clone_err := _clone_project_dir(src_dir, temp_dir)
	if not clone_err.is_empty():
		_rm_dir_recursive(temp_dir)
		return {&"ok": false, &"error": "Shadow-workspace clone failed: " + clone_err}

	# Run the export on a Thread and return immediately — a cold headless build
	# recompiles shaders and can take minutes, past the MCP request timeout.
	var job_id := "export_%d" % Time.get_ticks_msec()
	_export_mutex.lock()
	_export_jobs[job_id] = {
		"status": "running", "preset": preset_name, "artifact": artifact_abs,
		"output_path": output_path, "debug": debug,
	}
	_export_mutex.unlock()

	var thread := Thread.new()
	thread.start(_run_export_thread.bind(job_id, temp_dir, preset_name, artifact_abs, debug))
	_export_mutex.lock()
	_export_jobs[job_id]["thread"] = thread
	_export_mutex.unlock()

	return {&"ok": true, &"status": "started", &"job_id": job_id, &"preset": preset_name,
		&"output_path": output_path, &"artifact": artifact_abs, &"debug": debug,
		&"message": "Export started in the background (a cold headless build can take minutes). Poll get_export_status with job_id \"%s\"." % job_id}

## Worker: blocks on the headless export subprocess, cleans up the shadow
## workspace, and records the result in the job. Runs on its own Thread.
func _run_export_thread(job_id: String, temp_dir: String, preset_name: String, artifact_abs: String, debug: bool) -> void:
	var mode_flag := "--export-debug" if debug else "--export-release"
	var out_lines: Array = []
	var argv := ["--path", temp_dir, "--headless", mode_flag, preset_name, artifact_abs, "--quit"]
	var exit_code := OS.execute(OS.get_executable_path(), argv, out_lines, true, false)
	_rm_dir_recursive(temp_dir)
	var log_text := _sanitize_log_text("\n".join(out_lines).strip_edges())
	var written := FileAccess.file_exists(artifact_abs)
	_export_mutex.lock()
	if _export_jobs.has(job_id):
		var job: Dictionary = _export_jobs[job_id]
		job["status"] = "done" if (exit_code == 0 and written) else "failed"
		job["exit_code"] = exit_code
		job["artifact_written"] = written
		job["log"] = _tail_text(_condense_export_log(log_text), 4000)
		_export_jobs[job_id] = job
	_export_mutex.unlock()

## Poll a background export started by export_project.
func get_export_status(args: Dictionary) -> Dictionary:
	var job_id := str(args.get(&"job_id", "")).strip_edges()
	if job_id.is_empty():
		return {&"ok": false, &"error": "Missing 'job_id' (returned by export_project)"}

	_export_mutex.lock()
	if not _export_jobs.has(job_id):
		_export_mutex.unlock()
		return {&"ok": false, &"error": "Unknown job_id: " + job_id}
	var job: Dictionary = _export_jobs[job_id]
	var status := str(job.get("status"))
	var thread = job.get("thread")
	var preset = job.get("preset")
	var artifact = job.get("artifact")
	var exit_code = job.get("exit_code")
	var written = job.get("artifact_written", false)
	var log_text = job.get("log", "")
	_export_mutex.unlock()

	# Reap the finished thread so it doesn't warn on shutdown.
	if status != "running" and thread is Thread and thread.is_started():
		thread.wait_to_finish()
		_export_mutex.lock()
		if _export_jobs.has(job_id):
			_export_jobs[job_id].erase("thread")
		_export_mutex.unlock()

	var result := {&"ok": true, &"job_id": job_id, &"status": status,
		&"preset": preset, &"artifact": artifact}
	if status == "running":
		result[&"message"] = "Export still running…"
	else:
		result[&"exit_code"] = exit_code
		result[&"artifact_written"] = written
		result[&"log"] = log_text
		if status == "done":
			result[&"message"] = "Export finished: " + str(artifact)
		else:
			result[&"error_detail"] = "Export failed (exit %s). Check 'log' — the usual cause is missing export templates (Project > Export > Manage Export Templates)." % str(exit_code)
	return result

## Clone the project into a shadow workspace. Keeps the import cache so the headless
## export doesn't reimport everything; skips VCS and editor-only caches.
func _clone_project_dir(src: String, dst: String) -> String:
	if DirAccess.open(src) == null:
		return "cannot open source: " + src
	if DirAccess.make_dir_recursive_absolute(dst) != OK:
		return "cannot create temp dir: " + dst
	return _copy_tree(src, dst, "")

func _copy_tree(src_root: String, dst_root: String, rel: String) -> String:
	var cur := src_root.path_join(rel) if rel != "" else src_root
	var da := DirAccess.open(cur)
	if da == null:
		return ""
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name != "." and name != "..":
			var child_rel := rel.path_join(name) if rel != "" else name
			if not _clone_should_skip(child_rel):
				var d := dst_root.path_join(child_rel)
				if da.current_is_dir():
					DirAccess.make_dir_recursive_absolute(d)
					var e := _copy_tree(src_root, dst_root, child_rel)
					if not e.is_empty():
						da.list_dir_end()
						return e
				else:
					DirAccess.copy_absolute(src_root.path_join(child_rel), d)
		name = da.get_next()
	da.list_dir_end()
	return ""

## Skip .git and the editor-only / regenerable parts of .godot; keep .godot/imported
## and the class cache so the export doesn't reimport from scratch.
func _clone_should_skip(rel: String) -> bool:
	rel = rel.replace("\\", "/")
	if rel == ".git" or rel.begins_with(".git/"):
		return true
	if rel == ".godot/editor" or rel.begins_with(".godot/editor/"):
		return true
	if rel == ".godot/shader_cache" or rel.begins_with(".godot/shader_cache/"):
		return true
	return false

func _rm_dir_recursive(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := path.path_join(name)
			if da.current_is_dir():
				_rm_dir_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		name = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)

## Strips control characters (keeping newline/tab) from captured subprocess
## output before it goes into a tool_result. A headless export's stdout can
## carry raw control bytes (progress-bar carriage returns, terminal color
## codes) that JSON.stringify() on the Godot side doesn't escape the same way
## standard JSON.parse() on the receiving end expects — silently corrupting
## the tool_result message so the caller times out instead of getting the
## real (already-successful) status. Confirmed by reproduction: the export
## thread finishes and the Node bridge logs the parse failure and drops the
## message, so the request just sits until its own client-side timeout fires.
func _sanitize_log_text(s: String) -> String:
	# Drop the WHOLE colour sequence, escape byte and all. Removing only the
	# control character left the rest behind as literal text, so a log line came
	# back reading "[90m[1msavepack[22m | ..." — noise no terminal will ever
	# render, permanently baked into the payload and paid for in context.
	var ansi := RegEx.new()
	ansi.compile("\\x1b\\[[0-9;]*[A-Za-z]|\\[[0-9;]+m")
	var stripped := ansi.sub(s, "", true)
	var out := ""
	for i in range(stripped.length()):
		var c: int = stripped.unicode_at(i)
		if c == 9 or c == 10 or (c >= 32 and c != 127):
			out += stripped[i]
	return out

## The export log minus its per-file progress, which is most of it and says
## nothing: a successful export spent 40 of its 45 lines naming each packed
## file. Anything that looks like a problem is kept whatever it says.
func _condense_export_log(s: String) -> String:
	var kept: PackedStringArray = []
	var dropped := 0
	for line in s.split("
"):
		var text := String(line)
		var lower := text.to_lower()
		var noisy := "savepack" in lower or "storing file" in lower or "almacenando archivo" in lower
		var interesting := "error" in lower or "warning" in lower or "fail" in lower
		if noisy and not interesting:
			dropped += 1
			continue
		kept.append(text)
	var out := "
".join(kept)
	if dropped > 0:
		out += "
(%d per-file progress line(s) omitted)" % dropped
	return out

func _tail_text(s: String, n: int) -> String:
	if s.length() <= n:
		return s
	return "...(truncated)...\n" + s.substr(s.length() - n)

# =============================================================================
# undo_last / redo_last
# =============================================================================
## Step the editor's undo history, the same stack Ctrl+Z drives.
##
## Every mutating tool that touches an open scene registers an entry there, so
## this lets the agent take back its own last edit without the developer having
## to reach for the keyboard — and makes the undo coverage testable, which it
## otherwise isn't from outside the editor.
##
## Note this is the GLOBAL editor history: if the developer did something after
## the agent did, undo takes THEIR action back first. The returned action name is
## what actually got undone, so check it rather than assuming.
func undo_last(args: Dictionary) -> Dictionary:
	return _step_history(int(args.get(&"steps", 1)), true)

func redo_last(args: Dictionary) -> Dictionary:
	return _step_history(int(args.get(&"steps", 1)), false)

func _step_history(steps: int, undo: bool) -> Dictionary:
	if not _editor_plugin:
		return {&"ok": false, &"error": "Editor plugin unavailable (is the godot_mcp plugin enabled?)"}
	if steps < 1:
		return {&"ok": false, &"error": "'steps' must be >= 1"}

	var manager := _editor_plugin.get_undo_redo()
	if not manager:
		return {&"ok": false, &"error": "Undo history unavailable"}

	# EditorUndoRedoManager only RECORDS actions — undo()/redo() live on the
	# plain UndoRedo behind a history. Scene edits go to the edited scene's own
	# history, not the global one, so resolve the id from the scene root and
	# fall back to global when no scene is open.
	var history_id := EditorUndoRedoManager.GLOBAL_HISTORY
	var edited := _editor_plugin.get_editor_interface().get_edited_scene_root()
	if edited:
		history_id = manager.get_object_history_id(edited)
	var ur: UndoRedo = manager.get_history_undo_redo(history_id)
	if not ur:
		return {&"ok": false, &"error": "Undo history unavailable"}

	var verb := "undo" if undo else "redo"
	var done: Array = []
	for i in range(steps):
		# Read the label BEFORE stepping: afterwards it names the neighbouring
		# entry, not the one that just moved.
		var label: String = ur.get_current_action_name()
		if undo:
			if not ur.has_undo():
				break
			ur.undo()
		else:
			if not ur.has_redo():
				break
			ur.redo()
		done.append(label if not label.is_empty() else "(unnamed)")

	if done.is_empty():
		return {
			&"ok": true, &"undone": [], &"steps_applied": 0,
			&"message": "Nothing left to %s" % verb,
		}

	return {
		&"ok": true,
		&"steps_applied": done.size(),
		&"actions": done,
		&"message": "Stepped %d %s action(s): %s" % [done.size(), verb, ", ".join(done)],
	}

# =============================================================================
# save_scene
# =============================================================================
## Persist a scene that is open in the editor.
##
## Every mutating tool edits the LIVE tree when its target scene is open, so the
## developer's unsaved work is never clobbered — but nothing wrote those edits
## out. An agent that edited an open scene and then ran the game tested the
## file as it was BEFORE the edit, and the only way through was to close the tab
## (discarding the edit) and redo it with the scene closed.
##
## That is the build-and-verify loop this project exists for, and it needed a
## human to press Ctrl+S in the middle of it.
func save_scene(args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return {&"ok": false, &"error": "save_scene requires a live editor session"}

	var scene_path: String = str(args.get(&"scene_path", ""))
	var ei := _editor_plugin.get_editor_interface()
	var open_scenes := ei.get_open_scenes()

	# No argument means "the scene the developer is looking at".
	if scene_path.strip_edges().is_empty():
		var current := ei.get_edited_scene_root()
		if not current or current.scene_file_path.is_empty():
			return {&"ok": false, &"error": "No scene is currently open in the editor. Pass 'scene_path', or edit a scene first."}
		scene_path = current.scene_file_path
	else:
		var guarded := PathGuard.sanitize(scene_path)
		if not guarded[&"ok"]:
			return {&"ok": false, &"error": guarded[&"error"]}
		scene_path = guarded[&"path"]
		if scene_path not in open_scenes:
			return {
				&"ok": false,
				&"error": "Scene is not open in the editor: %s. Only an OPEN scene has unsaved state to write — a closed scene is already on disk, since tools edit it there directly." % scene_path,
				&"open_scenes": open_scenes,
			}

	# save_scene() writes whichever scene is currently being edited, so the tab
	# has to be the right one first. Switching is cheap and does not discard
	# anything: the other tabs keep their own unsaved state.
	var previous := ei.get_edited_scene_root()
	var previous_path := previous.scene_file_path if previous else ""
	var switched := previous_path != scene_path
	if switched:
		ei.open_scene_from_path(scene_path)

	var before_md5 := FileAccess.get_md5(scene_path)

	var err = ei.save_scene()
	if err != null and int(err) != OK:
		return {&"ok": false, &"error": "Failed to save scene: %s (error %s)" % [scene_path, str(err)]}

	# Restore whichever tab the developer had focused, so saving on their behalf
	# does not move them somewhere else.
	if switched and not previous_path.is_empty():
		ei.open_scene_from_path(previous_path)

	var after_md5 := FileAccess.get_md5(scene_path)
	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"changed": before_md5 != after_md5,
		&"message": "Saved %s%s" % [scene_path, "" if before_md5 != after_md5 else " (already up to date)"],
	}
