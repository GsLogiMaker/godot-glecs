@tool
extends SceneToolBase
class_name AudioTools
## Audio operation tools for MCP.
## Handles: add_audio_player, add_audio_bus, get_audio_bus_layout


const _PLAYER_TYPES := {
	"2D": "AudioStreamPlayer2D",
	"3D": "AudioStreamPlayer3D",
	"": "AudioStreamPlayer",
}

# =============================================================================
# add_audio_player
# =============================================================================
func add_audio_player(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var parent_path: String = str(args.get(&"parent_path", "."))
	var node_name: String = str(args.get(&"node_name", "AudioStreamPlayer"))
	# Case-folded: the schema says "2D", and callers write "2d" about as often.
	var player_type: String = str(args.get(&"player_type", "")).to_upper()
	var stream_path: String = str(args.get(&"stream_path", ""))
	var bus: String = str(args.get(&"bus", ""))
	var autoplay: bool = bool(args.get(&"autoplay", false))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if not _PLAYER_TYPES.has(player_type):
		return {&"ok": false, &"error": "Invalid 'player_type': %s. Use '', '2D', or '3D'." % player_type}

	var node_type: String = _PLAYER_TYPES[player_type]

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var parent = _find_node(root, parent_path)
	if not parent:
		var err := _node_not_found(root, parent_path, "Parent node")
		_discard_scene(root, is_live)
		return err

	var player: Node = ClassDB.instantiate(node_type)
	if not player:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Failed to create node of type: " + node_type}
	player.name = node_name

	if not stream_path.is_empty():
		var guarded_stream_path: String = _ensure_res_path(stream_path)
		if PathGuard.is_bad(guarded_stream_path):
			player.free()
			_discard_scene(root, is_live)
			return {&"ok": false, &"error": "Stream path escapes the project sandbox (rejected): " + stream_path}
		var stream = load(guarded_stream_path)
		if not stream or not (stream is AudioStream):
			player.free()
			_discard_scene(root, is_live)
			return {&"ok": false, &"error": "Failed to load audio stream (or not an AudioStream): " + stream_path}
		player.set(&"stream", stream)

	if not bus.is_empty():
		player.set(&"bus", bus)
	player.set(&"autoplay", autoplay)

	# Undo entry opened here, after the validations above: an action left open
	# by an early return would sit unclosed on the editor's undo stack.
	var ctx := _begin_edit(is_live, "MCP: add %s" % player.name, root)
	_edit_add_child(ctx, parent, player, root)
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_name": player.name, &"node_type": node_type,
		&"message": "Added %s (%s) to '%s'" % [player.name, node_type, parent_path]}

# =============================================================================
# add_audio_bus
# =============================================================================
func add_audio_bus(args: Dictionary) -> Dictionary:
	var bus_name: String = str(args.get(&"bus_name", ""))
	var send_to: String = str(args.get(&"send_to", "Master"))
	var volume_db: float = float(args.get(&"volume_db", 0.0))
	var mute: bool = bool(args.get(&"mute", false))
	var at_position: int = int(args.get(&"at_position", -1))

	if bus_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'bus_name'"}
	if AudioServer.get_bus_index(bus_name) != -1:
		return {&"ok": false, &"error": "Audio bus already exists: " + bus_name}
	if AudioServer.get_bus_index(send_to) == -1:
		return {&"ok": false, &"error": "'send_to' bus does not exist: " + send_to}

	var index: int = at_position if at_position >= 0 else AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, send_to)
	AudioServer.set_bus_volume_db(index, volume_db)
	AudioServer.set_bus_mute(index, mute)

	# Persist the layout to the project's default bus layout resource, or the
	# change is lost on editor restart.
	var layout_path: String = str(ProjectSettings.get_setting("audio/buses/default_bus_layout", "res://default_bus_layout.tres"))
	var layout := AudioServer.generate_bus_layout()
	var save_err := ResourceSaver.save(layout, layout_path)
	if save_err != OK:
		return {&"ok": false, &"error": "Bus created at runtime but failed to save layout to %s: %s" % [layout_path, str(save_err)]}

	return {&"ok": true, &"bus_name": bus_name, &"index": index, &"send_to": send_to,
		&"volume_db": volume_db, &"mute": mute, &"layout_path": layout_path,
		&"message": "Added audio bus '%s' (sending to '%s')" % [bus_name, send_to]}

# =============================================================================
# get_audio_bus_layout
# =============================================================================
func get_audio_bus_layout(args: Dictionary) -> Dictionary:
	var buses: Array = []
	for i in range(AudioServer.bus_count):
		buses.append({
			&"index": i,
			&"name": AudioServer.get_bus_name(i),
			&"volume_db": AudioServer.get_bus_volume_db(i),
			&"mute": AudioServer.is_bus_mute(i),
			&"solo": AudioServer.is_bus_solo(i),
			&"send": AudioServer.get_bus_send(i),
		})

	return {&"ok": true, &"buses": buses, &"bus_count": buses.size()}
