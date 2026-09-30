@tool
extends SceneToolBase
class_name PhysicsTools
## Physics setup tools for MCP.
## Handles: add_raycast, setup_collision, set_physics_layers, get_collision_info
## Scene load/save/find + path guarding are inherited from SceneToolBase.

# =============================================================================
# add_raycast
# =============================================================================
func add_raycast(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var parent_path: String = str(args.get(&"parent_path", "."))
	var node_name: String = str(args.get(&"node_name", ""))
	var dimension: String = str(args.get(&"dimension", ""))
	var target_position = args.get(&"target_position")
	var enabled: bool = bool(args.get(&"enabled", true))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if not dimension.is_empty() and dimension not in ["2D", "3D"]:
		return {&"ok": false, &"error": "Invalid 'dimension': %s. Use '2D' or '3D'." % dimension}

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

	if dimension.is_empty():
		dimension = _dimension_of(parent)
		if dimension.is_empty():
			dimension = "2D"

	var node_type: String = "RayCast2D" if dimension == "2D" else "RayCast3D"
	if node_name.strip_edges().is_empty():
		node_name = node_type

	var raycast: Node = ClassDB.instantiate(node_type)
	if not raycast:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Failed to create node of type: " + node_type}
	raycast.name = node_name
	raycast.set(&"enabled", enabled)

	if target_position != null:
		# Typed, not bare: _parse_value leaves [0, 20] an Array, so the array form
		# that set_node_properties and tilemap coords both accept was refused here.
		var parsed = VariantCodec.parse_typed_value(
			target_position, TYPE_VECTOR2 if dimension == "2D" else TYPE_VECTOR3
		) if target_position is Array else _parse_value(target_position)
		if dimension == "2D":
			if not (parsed is Vector2):
				raycast.free()
				_discard_scene(root, is_live)
				return {&"ok": false, &"error": "'target_position' must be a {x,y} Vector2 for RayCast2D"}
			raycast.set(&"target_position", parsed)
		else:
			if not (parsed is Vector3):
				raycast.free()
				_discard_scene(root, is_live)
				return {&"ok": false, &"error": "'target_position' must be a {x,y,z} Vector3 for RayCast3D"}
			raycast.set(&"target_position", parsed)

	# Opened only here, after every validation that can bail out: an action left
	# open by an early return would sit unclosed on the editor's undo stack.
	# Configuring the node above needs no undo entries — it isn't in the tree
	# yet, and undoing the attach takes the whole node with it.
	var ctx := _begin_edit(is_live, "MCP: add %s" % node_name, root)
	_edit_add_child(ctx, parent, raycast, root)
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_name": raycast.name, &"node_type": node_type,
		&"message": "Added %s (%s) to '%s'" % [raycast.name, node_type, parent_path]}

# =============================================================================
# setup_collision
# =============================================================================
const _PHYSICS_BASE_CLASSES: PackedStringArray = [
	"CharacterBody2D", "CharacterBody3D", "RigidBody2D", "RigidBody3D",
	"StaticBody2D", "StaticBody3D", "Area2D", "Area3D",
]

func setup_collision(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var shape_type: String = str(args.get(&"shape_type", ""))
	var size = args.get(&"size")
	var node_name: String = str(args.get(&"node_name", "CollisionShape"))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if shape_type.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'shape_type'. Use 'rectangle', 'circle' or 'capsule' for 2D nodes, 'box', 'sphere' or 'capsule' for 3D nodes."}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var target = _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err

	var is_physics_node := false
	for base_class: String in _PHYSICS_BASE_CLASSES:
		if target.is_class(base_class):
			is_physics_node = true
			break
	if not is_physics_node:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) is not a physics body/area (%s)" % [node_path, target.get_class(), ", ".join(_PHYSICS_BASE_CLASSES)]}

	var is_3d: bool = target.is_class("CharacterBody3D") or target.is_class("RigidBody3D") \
		or target.is_class("StaticBody3D") or target.is_class("Area3D")

	var shape: Shape2D = null
	var shape3d: Shape3D = null

	if is_3d:
		match shape_type:
			"box":
				var box := BoxShape3D.new()
				box.size = _parse_typed_value(size, TYPE_VECTOR3) if size is Array else (_parse_value(size) if size != null else Vector3(1, 1, 1))
				shape3d = box
			"sphere":
				var sphere := SphereShape3D.new()
				sphere.radius = float(size) if size != null else 0.5
				shape3d = sphere
			"capsule":
				var capsule3d := CapsuleShape3D.new()
				var capsule_size3d: Vector2 = VariantCodec.parse_typed_value(size, TYPE_VECTOR2) if size != null else Vector2(0.5, 2.0)
				capsule3d.radius = capsule_size3d.x
				capsule3d.height = capsule_size3d.y
				shape3d = capsule3d
			_:
				_discard_scene(root, is_live)
				return {&"ok": false, &"error": "Invalid 'shape_type' for a 3D node: %s. Use 'box', 'sphere' or 'capsule'." % shape_type}
	else:
		match shape_type:
			"rectangle":
				var rect := RectangleShape2D.new()
				rect.size = _parse_typed_value(size, TYPE_VECTOR2) if size is Array else (_parse_value(size) if size != null else Vector2(32, 32))
				shape = rect
			"circle":
				var circle := CircleShape2D.new()
				circle.radius = float(size) if size != null else 16.0
				shape = circle
			"capsule":
				# The default body shape for a 2D platformer character, and the
				# tool used to answer it with "use rectangle or circle".
				var capsule := CapsuleShape2D.new()
				var capsule_size: Vector2 = VariantCodec.parse_typed_value(size, TYPE_VECTOR2) if size != null else Vector2(16, 32)
				capsule.radius = capsule_size.x
				capsule.height = capsule_size.y
				shape = capsule
			_:
				_discard_scene(root, is_live)
				return {&"ok": false, &"error": "Invalid 'shape_type' for a 2D node: %s. Use 'rectangle', 'circle' or 'capsule'." % shape_type}

	var collision_node_type: String = "CollisionShape3D" if is_3d else "CollisionShape2D"

	# Fill an existing EMPTY collision shape rather than adding a second one.
	#
	# create_scene happily accepts a CollisionShape2D with no shape resource, and
	# Godot only complains at runtime. Adding a sibling then left the useless
	# empty node in place, still warning, next to a working one — two nodes where
	# the developer asked for one working shape.
	var collision_node: Node = null
	var reused := false
	for child in target.get_children():
		if child.get_class() == collision_node_type and child.get(&"shape") == null:
			collision_node = child
			reused = true
			break

	if collision_node == null:
		collision_node = ClassDB.instantiate(collision_node_type)
		collision_node.name = node_name
	collision_node.set(&"shape", shape3d if is_3d else shape)

	# Where the shape sits relative to the body's origin.
	#
	# Default: sit the shape ON the origin instead of centring it there. For a
	# 2D character that is what you almost always want — the origin becomes the
	# feet, so `position` places the character on the ground and a sprite offset
	# is measured from the same point. Centring it (the old behaviour) buries a
	# body half-way into the floor, which is exactly how an orc ended up
	# hovering above the ground in the test project while the hand-made player
	# collision next to it was offset by hand.
	#
	# Pass an explicit `offset` to override, or `offset: {x: 0, y: 0}` for the
	# old centred behaviour.
	var offset = args.get(&"offset")
	if offset != null:
		collision_node.set(&"position", _parse_typed_value(offset, TYPE_VECTOR3 if is_3d else TYPE_VECTOR2) if offset is Array else _parse_value(offset))
	elif not is_3d and target.is_class("CollisionObject2D"):
		var half: float = 0.0
		if shape is RectangleShape2D:
			half = (shape as RectangleShape2D).size.y * 0.5
		elif shape is CircleShape2D:
			half = (shape as CircleShape2D).radius
		if half > 0.0:
			collision_node.set(&"position", Vector2(0.0, -half))

	var ctx := _begin_edit(is_live, "MCP: set up collision on %s" % target.name, root)
	if not reused:
		_edit_add_child(ctx, target, collision_node, root)
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"collision_node_name": collision_node.name, &"collision_node_type": collision_node_type,
		&"shape_type": shape_type,
		&"reused_existing_node": reused,
		&"message": "%s %s (%s shape) on '%s'" % ["Filled in existing" if reused else "Added", collision_node.name, shape_type, node_path]}

# =============================================================================
# set_physics_layers
# =============================================================================
## Converts a list of 1-based layer indices (1..32) into a 32-bit mask.
## Returns [mask: int, error: String]; error non-empty if any entry isn't a
## valid index — presets have no associated node, so there's no dimension to
## resolve a layer NAME against (unlike set_physics_layers). Silently treating
## an unresolvable name as 0 would save a preset with collision fully
## disabled and no indication why, so this fails loud instead.
func _layers_to_mask(layers: Array) -> Array:
	var mask := 0
	for l in layers:
		if l is String and not (l as String).is_valid_int():
			return [0, "Unknown layer '%s': collision presets take indices (1..32), not names — layer names need a node to resolve a 2D/3D dimension against (use set_physics_layers for that)." % l]
		var idx := int(l)
		if idx < 1 or idx > 32:
			return [0, "Layer index out of range (1..32): %s" % str(l)]
		mask |= 1 << (idx - 1)
	return [mask, ""]

# Resolve an array of layer tokens (index 1..32 or a name from Project Settings)
# into a bitmask. Returns [mask: int, error: String]; error non-empty on any
# unknown name or out-of-range index (fail loud rather than silently drop a bit).
func _resolve_layers(tokens: Array, dim: String) -> Array:
	var mask := 0
	for t in tokens:
		if t is String and not (t as String).is_valid_int():
			if dim.is_empty():
				return [0, "Node has no physics dimension; layer names need a CollisionObject2D/3D"]
			var bit := _layer_name_to_bit(t, dim)
			if bit < 0:
				return [0, "Unknown %s_physics layer name '%s'. Defined names: %s" % [dim, t, str(_defined_layer_names(dim))]]
			mask |= 1 << bit
		else:
			var idx := int(t)
			if idx < 1 or idx > 32:
				return [0, "Layer index out of range (1..32): %s" % str(t)]
			mask |= 1 << (idx - 1)
	return [mask, ""]

# 0-based bit for a named physics layer, -1 if no layer carries that name.
func _layer_name_to_bit(layer_name: String, dim: String) -> int:
	var wanted := layer_name.strip_edges().to_lower()
	for i in range(32):
		var key := "layer_names/%s_physics/layer_%d" % [dim, i + 1]
		if ProjectSettings.has_setting(key):
			if str(ProjectSettings.get_setting(key)).strip_edges().to_lower() == wanted:
				return i
	return -1

func _defined_layer_names(dim: String) -> Array:
	var names: Array = []
	for i in range(32):
		var key := "layer_names/%s_physics/layer_%d" % [dim, i + 1]
		if ProjectSettings.has_setting(key):
			var v := str(ProjectSettings.get_setting(key)).strip_edges()
			if not v.is_empty():
				names.append("%d:%s" % [i + 1, v])
	return names

func set_physics_layers(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var collision_layer = args.get(&"collision_layer")
	var collision_mask = args.get(&"collision_mask")

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if collision_layer == null and collision_mask == null:
		return {&"ok": false, &"error": "Provide at least one of 'collision_layer' or 'collision_mask'"}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var target = _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err
	if not (&"collision_layer" in target and &"collision_mask" in target):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) has no collision_layer/collision_mask properties" % [node_path, target.get_class()]}

	# Arrays may hold layer indices (1..32) or layer NAMES defined in Project
	# Settings (layer_names/{2d,3d}_physics/layer_N). Names are resolved against
	# the dimension implied by the node's class. A raw (non-array) int stays a
	# raw bitmask, unchanged from before.
	var dim := "2d" if target is CollisionObject2D else ("3d" if target is CollisionObject3D else "")

	# Resolve BOTH masks before applying EITHER. On an open scene _discard_scene
	# is a no-op (target is the editor's live node, not a copy), so applying the
	# layer and only then discovering the mask is invalid would leave the layer
	# permanently applied while this call reports total failure.
	var layer_value: int = 0
	var has_layer := collision_layer != null
	if has_layer:
		if collision_layer is Array:
			var r := _resolve_layers(collision_layer, dim)
			if not r[1].is_empty():
				_discard_scene(root, is_live)
				return {&"ok": false, &"error": r[1]}
			layer_value = r[0]
		else:
			layer_value = int(collision_layer)

	var mask_value: int = 0
	var has_mask := collision_mask != null
	if has_mask:
		if collision_mask is Array:
			var r := _resolve_layers(collision_mask, dim)
			if not r[1].is_empty():
				_discard_scene(root, is_live)
				return {&"ok": false, &"error": r[1]}
			mask_value = r[0]
		else:
			mask_value = int(collision_mask)

	# Both values are resolved above before anything is written: a bad mask name
	# must not leave the layer applied, since on a live scene there is nothing to
	# roll back to.
	var ctx := _begin_edit(is_live, "MCP: set physics layers on %s" % node_path, root)
	if has_layer:
		_edit_set(ctx, target, &"collision_layer", layer_value)
	if has_mask:
		_edit_set(ctx, target, &"collision_mask", mask_value)
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"message": "Updated physics layers on '%s'" % node_path}

# =============================================================================
# get_collision_info
# =============================================================================
func _mask_to_layers(mask: int) -> Array:
	var layers: Array = []
	for i in range(32):
		if mask & (1 << i):
			layers.append(i + 1)
	return layers

func get_collision_info(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var target = _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err
	if not (&"collision_layer" in target and &"collision_mask" in target):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) has no collision_layer/collision_mask properties" % [node_path, target.get_class()]}

	var layer_mask: int = int(target.get(&"collision_layer"))
	var mask_mask: int = int(target.get(&"collision_mask"))

	var shapes: Array = []
	for child in target.get_children():
		if child is CollisionShape2D or child is CollisionShape3D:
			var shape_res = child.get(&"shape")
			shapes.append({
				&"node_name": child.name,
				&"node_type": child.get_class(),
				&"shape_type": shape_res.get_class() if shape_res else "",
				&"disabled": bool(child.get(&"disabled")),
			})

	_discard_scene(root, is_live)

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"node_type": target.get_class(),
		&"collision_layer": layer_mask, &"collision_layer_bits": _mask_to_layers(layer_mask),
		&"collision_mask": mask_mask, &"collision_mask_bits": _mask_to_layers(mask_mask),
		&"collision_shapes": shapes}

# =============================================================================
# set_collision_preset / get_collision_presets / apply_collision_preset
# =============================================================================
## Named layer/mask combos ("Player", "Enemy", "Hazard") persisted per-project
## in ProjectSettings, so they're reusable across nodes without re-toggling
## bits every time. Not a native Godot concept — this project owns it fully.
const _PRESET_SETTING_PREFIX := "mcp_presets/collision/"

func set_collision_preset(args: Dictionary) -> Dictionary:
	var preset_name: String = str(args.get(&"name", "")).strip_edges()
	var collision_layer = args.get(&"collision_layer")
	var collision_mask = args.get(&"collision_mask")

	if preset_name.is_empty():
		return {&"ok": false, &"error": "Missing 'name'"}
	if collision_layer == null and collision_mask == null:
		return {&"ok": false, &"error": "Provide at least one of 'collision_layer' or 'collision_mask'"}

	var layer_mask := 0
	if collision_layer is Array:
		var r := _layers_to_mask(collision_layer)
		if not r[1].is_empty():
			return {&"ok": false, &"error": r[1]}
		layer_mask = r[0]
	elif collision_layer != null:
		layer_mask = int(collision_layer)

	var mask_mask := 0
	if collision_mask is Array:
		var r := _layers_to_mask(collision_mask)
		if not r[1].is_empty():
			return {&"ok": false, &"error": r[1]}
		mask_mask = r[0]
	elif collision_mask != null:
		mask_mask = int(collision_mask)

	var setting_key := _PRESET_SETTING_PREFIX + preset_name
	ProjectSettings.set_setting(setting_key, {&"collision_layer": layer_mask, &"collision_mask": mask_mask})
	ProjectSettings.save()

	return {&"ok": true, &"name": preset_name,
		&"collision_layer": layer_mask, &"collision_layer_bits": _mask_to_layers(layer_mask),
		&"collision_mask": mask_mask, &"collision_mask_bits": _mask_to_layers(mask_mask),
		&"message": "Saved collision preset '%s'" % preset_name}

func get_collision_presets(_args: Dictionary) -> Dictionary:
	var presets: Array = []
	for prop: Dictionary in ProjectSettings.get_property_list():
		var prop_name: String = prop[&"name"]
		if not prop_name.begins_with(_PRESET_SETTING_PREFIX):
			continue
		var preset_name: String = prop_name.substr(_PRESET_SETTING_PREFIX.length())
		var data: Dictionary = ProjectSettings.get_setting(prop_name, {})
		var layer_mask: int = int(data.get(&"collision_layer", 0))
		var mask_mask: int = int(data.get(&"collision_mask", 0))
		presets.append({
			&"name": preset_name,
			&"collision_layer": layer_mask, &"collision_layer_bits": _mask_to_layers(layer_mask),
			&"collision_mask": mask_mask, &"collision_mask_bits": _mask_to_layers(mask_mask),
		})
	return {&"ok": true, &"presets": presets, &"count": presets.size()}

func apply_collision_preset(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var preset_name: String = str(args.get(&"name", "")).strip_edges()

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if preset_name.is_empty():
		return {&"ok": false, &"error": "Missing 'name'"}

	var setting_key := _PRESET_SETTING_PREFIX + preset_name
	if not ProjectSettings.has_setting(setting_key):
		return {&"ok": false, &"error": "Collision preset not found: '%s'. Use get_collision_presets to list defined presets." % preset_name}
	var data: Dictionary = ProjectSettings.get_setting(setting_key, {})

	return set_physics_layers({
		&"scene_path": scene_path, &"node_path": node_path,
		&"collision_layer": int(data.get(&"collision_layer", 0)),
		&"collision_mask": int(data.get(&"collision_mask", 0)),
	})
