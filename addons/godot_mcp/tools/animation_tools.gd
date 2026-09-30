@tool
extends SceneToolBase
class_name AnimationTools
## Animation operation tools for MCP.
## Handles: list_animations, create_animation, add_animation_track,
##          set_animation_keyframe, get_animation_info, remove_animation
## All tools operate on an AnimationPlayer node inside a scene file, reading
## and writing its default AnimationLibrary ("" / AnimationMixer::ANIM_LIB_DEFAULT).


const _DEFAULT_LIB := ""


## Validate that the target node exists and is an AnimationPlayer. Returns
## [node_or_null, error_string].
func _get_animation_player(root: Node, node_path: String) -> Array:
	var target = _find_node(root, node_path)
	if not target:
		return [null, "Node not found: " + node_path]
	if not (target is AnimationPlayer):
		return [null, "Node '%s' is %s, expected AnimationPlayer" % [node_path, target.get_class()]]
	return [target, ""]

## Get (or lazily create) the default AnimationLibrary on an AnimationPlayer.
func _get_or_create_default_library(player: AnimationPlayer) -> AnimationLibrary:
	if player.has_animation_library(_DEFAULT_LIB):
		return player.get_animation_library(_DEFAULT_LIB)
	var lib := AnimationLibrary.new()
	player.add_animation_library(_DEFAULT_LIB, lib)
	return lib

const _TRACK_TYPES := {
	"value": Animation.TYPE_VALUE,
	"position": Animation.TYPE_POSITION_3D,
	"rotation": Animation.TYPE_ROTATION_3D,
	"method": Animation.TYPE_METHOD,
}

# =============================================================================
# list_animations
# =============================================================================
func list_animations(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var player_result := _get_animation_player(root, node_path)
	if not player_result[1].is_empty():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": player_result[1]}
	var player: AnimationPlayer = player_result[0]

	var animations: Array = []
	for anim_name: StringName in player.get_animation_list():
		var anim := player.get_animation(anim_name)
		animations.append({
			&"name": str(anim_name),
			&"length": anim.length,
			&"loop": anim.loop_mode != Animation.LOOP_NONE,
			&"track_count": anim.get_track_count(),
		})

	_discard_scene(root, is_live)

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"animations": animations, &"animation_count": animations.size()}

# =============================================================================
# create_animation
# =============================================================================
func create_animation(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var animation_name: String = str(args.get(&"animation_name", ""))
	var length: float = float(args.get(&"length", 1.0))
	var loop: bool = bool(args.get(&"loop", false))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if animation_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'animation_name'"}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var player_result := _get_animation_player(root, node_path)
	if not player_result[1].is_empty():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": player_result[1]}
	var player: AnimationPlayer = player_result[0]

	var lib := _get_or_create_default_library(player)
	if lib.has_animation(animation_name):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Animation already exists: " + animation_name}

	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var ctx := _begin_edit(is_live, "MCP: create animation '%s'" % animation_name, root)
	lib.add_animation(animation_name, anim)
	_edit_record(ctx, lib, &"add_animation", [animation_name, anim],
		&"remove_animation", [animation_name])
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"animation_name": animation_name, &"length": length, &"loop": loop,
		&"message": "Created animation '%s' on '%s'" % [animation_name, node_path]}

# =============================================================================
# add_animation_track
# =============================================================================
func add_animation_track(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var animation_name: String = str(args.get(&"animation_name", ""))
	var track_type: String = str(args.get(&"track_type", ""))
	var track_node_path: String = str(args.get(&"track_node_path", ""))
	var property_name: String = str(args.get(&"property", ""))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if animation_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'animation_name'"}
	if not _TRACK_TYPES.has(track_type):
		return {&"ok": false, &"error": "Invalid 'track_type': %s. Use one of: %s" % [track_type, ", ".join(_TRACK_TYPES.keys())]}
	if track_node_path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'track_node_path'"}
	if track_type == "value" and property_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'property' (required for track_type 'value')"}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var player_result := _get_animation_player(root, node_path)
	if not player_result[1].is_empty():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": player_result[1]}
	var player: AnimationPlayer = player_result[0]

	var lib := _get_or_create_default_library(player)
	if not lib.has_animation(animation_name):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Animation not found: " + animation_name}
	var anim := lib.get_animation(animation_name)

	var np: NodePath
	if track_type == "value":
		np = NodePath(str(track_node_path) + ":" + property_name)
	else:
		np = NodePath(track_node_path)

	var ctx := _begin_edit(is_live, "MCP: add %s track" % track_type, root)
	var track_idx := anim.add_track(_TRACK_TYPES[track_type])
	anim.track_set_path(track_idx, np)
	# add_track appends, so the inverse is removing the index it landed on.
	_edit_record(ctx, anim, &"add_track", [_TRACK_TYPES[track_type]],
		&"remove_track", [track_idx])
	_edit_record(ctx, anim, &"track_set_path", [track_idx, np],
		&"track_set_path", [track_idx, np])
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	var order_warning := _sprite_track_order_warning(anim)

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"animation_name": animation_name, &"track_index": track_idx,
		&"track_type": track_type, &"track_path": str(np),
		&"message": "Added %s track '%s' to '%s'" % [track_type, str(np), animation_name],
		"warning": order_warning if order_warning != "" else null}

# =============================================================================
# set_animation_keyframe
# =============================================================================
## Parse a keyframe value against the DECLARED type of the property its track
## drives, rather than guessing from the value's shape.
##
## Without the hint, `"res://.../IDLE.png"` on a `Sprite:texture` track is stored
## as a String; at runtime the assignment silently fails and the sprite goes
## blank. Same class as add_node dropping a texture, in a different tool — found
## by animating a real character and watching the keyframe hold a path instead of
## a Texture2D. Falls back to untyped parsing whenever the track's target cannot
## be resolved, so an unusual track never becomes an error.
func _parse_keyframe_value(root: Node, anim: Animation, track_index: int, value):
	if anim.track_get_type(track_index) != Animation.TYPE_VALUE:
		return VariantCodec.parse_value(value)

	var track_path: NodePath = anim.track_get_path(track_index)
	var prop: String = str(track_path.get_concatenated_subnames())
	if prop.is_empty():
		return VariantCodec.parse_value(value)

	var target: Node = root.get_node_or_null(NodePath(track_path.get_concatenated_names()))
	if target == null:
		return VariantCodec.parse_value(value)

	# Sub-paths like "position:x" drive a component, not the property itself.
	var hint: int = int(_property_type_map(target).get(prop, -1))
	return VariantCodec.parse_typed_value(value, hint)


func set_animation_keyframe(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var animation_name: String = str(args.get(&"animation_name", ""))
	var track_index: int = int(args.get(&"track_index", -1))
	var time: float = float(args.get(&"time", 0.0))
	var value = args.get(&"value")

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if animation_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'animation_name'"}
	if track_index < 0:
		return {&"ok": false, &"error": "Missing or invalid 'track_index'"}
	if value == null:
		return {&"ok": false, &"error": "Missing 'value'"}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var player_result := _get_animation_player(root, node_path)
	if not player_result[1].is_empty():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": player_result[1]}
	var player: AnimationPlayer = player_result[0]

	var lib := _get_or_create_default_library(player)
	if not lib.has_animation(animation_name):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Animation not found: " + animation_name}
	var anim := lib.get_animation(animation_name)

	if track_index >= anim.get_track_count():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Track index %d out of range (animation has %d tracks)" % [track_index, anim.get_track_count()]}

	var track_type := anim.track_get_type(track_index)
	var parsed_value = _parse_keyframe_value(root, anim, track_index, value)

	var key_index: int
	if track_type == Animation.TYPE_METHOD:
		if typeof(parsed_value) != TYPE_DICTIONARY or not parsed_value.has(&"method"):
			_discard_scene(root, is_live)
			return {&"ok": false, &"error": "For a method track, 'value' must be {\"method\": \"name\", \"args\": [...]}"}
		key_index = anim.track_insert_key(track_index, time, {
			&"method": str(parsed_value[&"method"]),
			&"args": parsed_value.get(&"args", []),
		})
	else:
		key_index = anim.track_insert_key(track_index, time, parsed_value)

	if key_index < 0:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Failed to insert keyframe: value type doesn't match track type %d (position/rotation tracks require Vector3/Quaternion — for 2D nodes use track_type 'value' with property 'position'/'rotation' instead)" % track_type}

	# Registered after the insert because the key index isn't known until the
	# engine places it by time — and the failure above must not leave an action
	# open on the undo stack.
	var ctx := _begin_edit(is_live, "MCP: keyframe at %ss" % time, root)
	_edit_record(ctx, anim, &"track_insert_key", [track_index, time, anim.track_get_key_value(track_index, key_index)],
		&"track_remove_key", [track_index, key_index])
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"animation_name": animation_name, &"track_index": track_index,
		&"key_index": key_index, &"time": time,
		&"message": "Inserted keyframe at t=%s on track %d of '%s'" % [str(time), track_index, animation_name]}

# =============================================================================
# get_animation_info
# =============================================================================
func get_animation_info(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var animation_name: String = str(args.get(&"animation_name", ""))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if animation_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'animation_name'"}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var player_result := _get_animation_player(root, node_path)
	if not player_result[1].is_empty():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": player_result[1]}
	var player: AnimationPlayer = player_result[0]

	var lib := _get_or_create_default_library(player)
	if not lib.has_animation(animation_name):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Animation not found: " + animation_name}
	var anim := lib.get_animation(animation_name)

	var tracks: Array = []
	for i in range(anim.get_track_count()):
		var keys: Array = []
		for k in range(anim.track_get_key_count(i)):
			keys.append({
				&"time": anim.track_get_key_time(i, k),
				&"value": VariantCodec.serialize_value(anim.track_get_key_value(i, k)),
			})
		tracks.append({
			&"index": i,
			&"type": anim.track_get_type(i),
			&"path": str(anim.track_get_path(i)),
			&"keys": keys,
		})

	_discard_scene(root, is_live)

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"animation_name": animation_name, &"length": anim.length,
		&"loop": anim.loop_mode != Animation.LOOP_NONE,
		&"tracks": tracks, &"track_count": tracks.size()}

# =============================================================================
# remove_animation
# =============================================================================
func remove_animation(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var animation_name: String = str(args.get(&"animation_name", ""))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if animation_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'animation_name'"}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var player_result := _get_animation_player(root, node_path)
	if not player_result[1].is_empty():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": player_result[1]}
	var player: AnimationPlayer = player_result[0]

	var lib := _get_or_create_default_library(player)
	if not lib.has_animation(animation_name):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Animation not found: " + animation_name}

	# Grab the resource before dropping it, or undo has nothing to put back.
	var removed_anim := lib.get_animation(animation_name)
	var ctx := _begin_edit(is_live, "MCP: remove animation '%s'" % animation_name, root)
	lib.remove_animation(animation_name)
	_edit_record(ctx, lib, &"remove_animation", [animation_name],
		&"add_animation", [animation_name, removed_anim])
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"animation_name": animation_name,
		&"message": "Removed animation '%s' from '%s'" % [animation_name, node_path]}


## An AnimationPlayer applies value tracks in INDEX order, so a `frame` track
## that sorts before the `hframes`/`vframes` track for the same sprite sets a
## frame index against whatever sheet layout the PREVIOUS animation left behind.
## Godot then logs "Index p_frame = N is out of bounds" on every frame, and the
## animation that is actually wrong is not the one playing.
##
## Godot exposes no way to reorder tracks, so this reports the hazard instead of
## silently producing it — the fix is to rebuild the animation in the right
## order, which is what the caller needs to be told.
func _sprite_track_order_warning(anim: Animation) -> String:
	var frame_at: Dictionary = {}
	var layout_at: Dictionary = {}
	for i in range(anim.get_track_count()):
		var path := str(anim.track_get_path(i))
		var parts := path.split(":")
		if parts.size() != 2:
			continue
		var node_part := parts[0]
		var prop := parts[1]
		if prop == "frame":
			if not frame_at.has(node_part):
				frame_at[node_part] = i
		elif prop == "hframes" or prop == "vframes":
			if not layout_at.has(node_part):
				layout_at[node_part] = i

	for node_part in frame_at:
		if layout_at.has(node_part) and int(frame_at[node_part]) < int(layout_at[node_part]):
			return ("Track order hazard on '%s': the 'frame' track (index %d) comes BEFORE 'hframes'/'vframes' (index %d). "
				+ "An AnimationPlayer applies value tracks in index order, so frame is set against the previous animation's "
				+ "sheet layout and Godot logs 'Index p_frame is out of bounds' every frame. Tracks cannot be reordered — "
				+ "remove_animation and rebuild it with the layout tracks first.") % [node_part, int(frame_at[node_part]), int(layout_at[node_part])]
	return ""

# =============================================================================
# create_sprite_animation / create_sprite_frames
# =============================================================================
# Building one animated character used to take ~40 calls: a track and a keyframe
# per frame, times every animation. It worked, but the natural unit is "this
# sheet, this many frames, this fps" — and getting it wrong is silent. The
# `frame` track must come AFTER `hframes`/`vframes` or Godot sets a frame index
# against the previous animation's sheet layout and logs
# "Index p_frame is out of bounds" on every frame; see add_animation_track's
# order warning, which exists because that is easy to do by hand.
#
# These build the tracks in the safe order by construction.

## Normalise a frame spec into a list of sheet indices.
## Accepts a count (0..n-1) or an explicit list, so a run cycle that uses frames
## 4..9 of a shared sheet is expressible.
func _frame_indices(frames, hframes: int, vframes: int) -> Array:
	var total := maxi(1, hframes) * maxi(1, vframes)
	var out: Array = []
	if frames is Array:
		for f in frames:
			out.append(int(f))
	elif frames != null:
		for i in range(int(frames)):
			out.append(i)
	else:
		for i in range(total):
			out.append(i)
	return out

func create_sprite_animation(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var sprite_path: String = str(args.get(&"sprite_path", ""))
	var animation_name: String = str(args.get(&"animation_name", ""))
	var texture_path: String = str(args.get(&"texture", ""))
	var hframes: int = int(args.get(&"hframes", 1))
	var vframes: int = int(args.get(&"vframes", 1))
	var fps: float = float(args.get(&"fps", 10.0))
	var loop: bool = bool(args.get(&"loop", true))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if animation_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'animation_name'"}
	if sprite_path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'sprite_path' (the Sprite2D node the animation drives, relative to the AnimationPlayer's scene root)"}
	if hframes < 1 or vframes < 1:
		return {&"ok": false, &"error": "'hframes' and 'vframes' must be >= 1 (got %d x %d)" % [hframes, vframes]}
	if fps <= 0.0:
		return {&"ok": false, &"error": "'fps' must be > 0 (got %s)" % str(fps)}

	var indices := _frame_indices(args.get(&"frames"), hframes, vframes)
	if indices.is_empty():
		return {&"ok": false, &"error": "No frames requested"}
	var max_index := hframes * vframes - 1
	for i in indices:
		if int(i) < 0 or int(i) > max_index:
			return {&"ok": false, &"error": "Frame index %d is outside this sheet: %dx%d has frames 0..%d. Godot logs 'Index p_frame is out of bounds' every frame when this happens at runtime." % [int(i), hframes, vframes, max_index]}

	var texture: Texture2D = null
	if not texture_path.strip_edges().is_empty():
		var guarded := _ensure_res_path(texture_path)
		if PathGuard.is_bad(guarded):
			return {&"ok": false, &"error": "'texture' path escapes the project sandbox: " + texture_path}
		if not FileAccess.file_exists(guarded):
			return {&"ok": false, &"error": "Texture not found: " + guarded}
		texture = load(guarded) as Texture2D
		if texture == null:
			# A file that exists but will not load as a Texture2D is almost always
			# an image the editor has not imported yet — load() resolves the
			# IMPORTED resource, not the raw file. Say so, because "not a
			# Texture2D" about a .png the caller can see on disk is baffling.
			return {&"ok": false, &"error": "Could not load '%s' as a Texture2D. If it is an image that was just created, the editor has not imported it yet — call rescan_filesystem and retry. Otherwise the file is not an image resource." % guarded}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var player_result := _get_animation_player(root, node_path)
	if not player_result[1].is_empty():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": player_result[1]}
	var player: AnimationPlayer = player_result[0]

	var sprite := _find_node(root, sprite_path)
	if not sprite:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Sprite node not found: " + sprite_path}
	if not (sprite is Sprite2D):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' is %s, expected Sprite2D. For an AnimatedSprite2D use create_sprite_frames instead." % [sprite_path, sprite.get_class()]}

	var lib := _get_or_create_default_library(player)
	if lib.has_animation(animation_name):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Animation already exists: %s. remove_animation first — tracks cannot be reordered, so rebuilding is the only way to change frame order." % animation_name}

	var anim := Animation.new()
	anim.length = indices.size() / fps
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE

	var ctx := _begin_edit(is_live, "MCP: sprite animation '%s'" % animation_name, root)

	# ORDER MATTERS. An AnimationPlayer applies value tracks by index, so the
	# sheet layout has to be set before the frame index that indexes into it.
	var tracks: Array = []
	if texture != null:
		tracks.append(["texture", texture])
	tracks.append(["hframes", hframes])
	if vframes > 1:
		tracks.append(["vframes", vframes])

	for spec in tracks:
		var t := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(t, NodePath("%s:%s" % [sprite_path, spec[0]]))
		# A constant track: these describe the sheet, they are not interpolated.
		anim.value_track_set_update_mode(t, Animation.UPDATE_DISCRETE)
		anim.track_insert_key(t, 0.0, spec[1])

	var frame_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(frame_track, NodePath("%s:frame" % sprite_path))
	anim.value_track_set_update_mode(frame_track, Animation.UPDATE_DISCRETE)
	for i in range(indices.size()):
		anim.track_insert_key(frame_track, i / fps, int(indices[i]))

	lib.add_animation(animation_name, anim)
	_edit_record(ctx, lib, &"add_animation", [animation_name, anim],
		&"remove_animation", [animation_name])
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {
		&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"animation_name": animation_name,
		&"frame_count": indices.size(),
		&"length": anim.length,
		&"track_count": anim.get_track_count(),
		&"loop": loop,
		&"message": "Built '%s': %d frames at %s fps (%.2fs) on '%s'" % [animation_name, indices.size(), str(fps), anim.length, sprite_path],
	}

## Build a SpriteFrames resource — what an AnimatedSprite2D needs, and what most
## Godot tutorials tell you to use. There was previously no way to make one at
## all, which meant the AnimatedSprite2D route was simply unavailable.
func create_sprite_frames(args: Dictionary) -> Dictionary:
	var res_path: String = _ensure_res_path(str(args.get(&"path", "")))
	if PathGuard.is_bad(res_path) or res_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing or rejected 'path' (where to save the .tres, e.g. res://player_frames.tres)"}
	if not res_path.ends_with(".tres") and not res_path.ends_with(".res"):
		return {&"ok": false, &"error": "'path' must end in .tres or .res (got %s)" % res_path}

	var anims = args.get(&"animations", [])
	if not (anims is Array) or (anims as Array).is_empty():
		return {&"ok": false, &"error": "Missing 'animations': an array of {name, texture, hframes, vframes?, frames?, fps?, loop?}"}

	var frames_res := SpriteFrames.new()
	# SpriteFrames always ships with a "default" animation; drop it unless the
	# caller actually asked for one, or every resource carries an empty extra.
	var wants_default := false
	var built: Array = []

	for spec_v in anims:
		if not (spec_v is Dictionary):
			return {&"ok": false, &"error": "Each entry in 'animations' must be an object with at least {name, texture}"}
		var spec: Dictionary = spec_v
		var name: String = str(spec.get("name", ""))
		if name.strip_edges().is_empty():
			return {&"ok": false, &"error": "An animation is missing 'name'"}
		if name == "default":
			wants_default = true

		# A missing key read as an empty path and came back "texture not found: ",
		# which reads as a bad path rather than an absent argument. The
		# unknown-argument guard cannot see inside array items, so this is the
		# only place that can say it.
		var raw_texture := str(spec.get("texture", ""))
		if raw_texture.strip_edges().is_empty():
			return {&"ok": false, &"error": "Animation '%s' has no 'texture'. Each entry takes {name, texture, hframes?, vframes?, frames?, fps?, loop?}; the keys present were: %s." % [name, ", ".join(PackedStringArray(spec.keys()))]}
		var tex_path: String = _ensure_res_path(raw_texture)
		if PathGuard.is_bad(tex_path) or not FileAccess.file_exists(tex_path):
			return {&"ok": false, &"error": "Animation '%s': texture not found: %s" % [name, raw_texture]}
		var sheet := load(tex_path) as Texture2D
		if sheet == null:
			return {&"ok": false, &"error": "Animation '%s': could not load '%s' as a Texture2D. A just-created image is not importable until the editor rescans — call rescan_filesystem and retry." % [name, tex_path]}

		var hf: int = int(spec.get("hframes", 1))
		var vf: int = int(spec.get("vframes", 1))
		if hf < 1 or vf < 1:
			return {&"ok": false, &"error": "Animation '%s': hframes/vframes must be >= 1" % name}
		var fps: float = float(spec.get("fps", 10.0))
		if fps <= 0.0:
			return {&"ok": false, &"error": "Animation '%s': fps must be > 0" % name}

		var indices := _frame_indices(spec.get("frames"), hf, vf)
		var max_index := hf * vf - 1
		for i in indices:
			if int(i) < 0 or int(i) > max_index:
				return {&"ok": false, &"error": "Animation '%s': frame %d is outside a %dx%d sheet (0..%d)" % [name, int(i), hf, vf, max_index]}

		if not frames_res.has_animation(name):
			frames_res.add_animation(name)
		frames_res.set_animation_speed(name, fps)
		frames_res.set_animation_loop(name, bool(spec.get("loop", true)))

		# Slice the sheet into AtlasTextures — one per frame, sharing the source
		# image rather than duplicating it.
		var fw := sheet.get_width() / hf
		var fh := sheet.get_height() / vf
		for idx_v in indices:
			var idx := int(idx_v)
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(float((idx % hf) * fw), float((idx / hf) * fh), float(fw), float(fh))
			frames_res.add_frame(name, atlas)

		built.append({&"name": name, &"frames": indices.size(), &"fps": fps,
			&"frame_size": {&"x": fw, &"y": fh}})

	if not wants_default and frames_res.has_animation("default"):
		frames_res.remove_animation("default")

	var save_err := ResourceSaver.save(frames_res, res_path)
	if save_err != OK:
		return {&"ok": false, &"error": "Failed to save SpriteFrames to %s (error %d)" % [res_path, save_err]}
	_refresh_filesystem()

	return {
		&"ok": true, &"path": res_path,
		&"animations": built, &"animation_count": built.size(),
		&"message": "Wrote %s with %d animation(s). Assign it to an AnimatedSprite2D's 'sprite_frames' property." % [res_path, built.size()],
	}
