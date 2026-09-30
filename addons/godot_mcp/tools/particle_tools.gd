@tool
extends SceneToolBase
class_name ParticleTools
## GPU particle tools for MCP.
## Handles: create_particles, set_particle_material, set_particle_color_gradient,
##          apply_particle_preset, get_particle_info


func _is_particles_node(node: Node) -> bool:
	return node.is_class("GPUParticles2D") or node.is_class("GPUParticles3D")

## Parses a direction argument as Vector3 (ParticleProcessMaterial.direction is
## always Vector3, even for 2D particles). Falls back to Vector3(x, y, 0) if a
## 2D {x,y} dict is given without a z component.
func _parse_direction(value: Variant) -> Vector3:
	var parsed = _parse_value(value)
	if parsed is Vector3:
		return parsed
	if parsed is Vector2:
		return Vector3(parsed.x, parsed.y, 0.0)
	return Vector3(1, 0, 0)

# =============================================================================
# create_particles
# =============================================================================
func create_particles(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var parent_path: String = str(args.get(&"parent_path", "."))
	var dimension: String = str(args.get(&"dimension", "2D"))
	var node_name: String = str(args.get(&"node_name", ""))
	var amount: int = int(args.get(&"amount", 8))
	var lifetime: float = float(args.get(&"lifetime", 1.0))
	var one_shot: bool = bool(args.get(&"one_shot", false))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if dimension not in ["2D", "3D"]:
		return {&"ok": false, &"error": "Invalid 'dimension': %s. Use '2D' or '3D'." % dimension}

	var node_type: String = "GPUParticles2D" if dimension == "2D" else "GPUParticles3D"
	if node_name.strip_edges().is_empty():
		node_name = node_type

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

	var particles: Node = ClassDB.instantiate(node_type)
	if not particles:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Failed to create node of type: " + node_type}
	particles.name = node_name
	particles.set(&"amount", amount)
	particles.set(&"lifetime", lifetime)
	particles.set(&"one_shot", one_shot)

	# Undo entry opened here, after the validations above: an action left open
	# by an early return would sit unclosed on the editor's undo stack.
	var ctx := _begin_edit(is_live, "MCP: add %s" % particles.name, root)
	_edit_add_child(ctx, parent, particles, root)
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_name": particles.name, &"node_type": node_type,
		&"message": "Added %s (%s) to '%s'" % [particles.name, node_type, parent_path]}

# =============================================================================
# set_particle_material
# =============================================================================
func set_particle_material(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var direction = args.get(&"direction")
	var spread = args.get(&"spread")
	var initial_velocity_min = args.get(&"initial_velocity_min")
	var initial_velocity_max = args.get(&"initial_velocity_max")
	var gravity = args.get(&"gravity")

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
	if not _is_particles_node(target):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) is not a GPUParticles2D/3D" % [node_path, target.get_class()]}

	# Validate everything BEFORE mutating anything. On a live (open) scene,
	# _discard_scene is a no-op — target is the actual node the editor is
	# displaying, not a copy — so a mutation applied here is not rolled back
	# by an error returned further down. Parse/validate first, assign last.
	var parsed_gravity = null
	if gravity != null:
		parsed_gravity = _parse_typed_value(gravity, TYPE_VECTOR3) if gravity is Array else _parse_value(gravity)
		if not (parsed_gravity is Vector3):
			_discard_scene(root, is_live)
			return {&"ok": false, &"error": "'gravity' must be a {x,y,z} Vector3"}

	var ctx := _begin_edit(is_live, "MCP: set particle material on %s" % node_path, root)
	var material: ParticleProcessMaterial = target.get(&"process_material") as ParticleProcessMaterial
	if not material:
		material = ParticleProcessMaterial.new()
		_edit_set(ctx, target, &"process_material", material)

	if direction != null:
		_edit_set(ctx, material, &"direction", _parse_direction(direction))
	if spread != null:
		_edit_set(ctx, material, &"spread", float(spread))
	if initial_velocity_min != null:
		_edit_set(ctx, material, &"initial_velocity_min", float(initial_velocity_min))
	if initial_velocity_max != null:
		_edit_set(ctx, material, &"initial_velocity_max", float(initial_velocity_max))
	if parsed_gravity != null:
		_edit_set(ctx, material, &"gravity", parsed_gravity)
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"message": "Updated particle process material on '%s'" % node_path}

# =============================================================================
# set_particle_color_gradient
# =============================================================================
func set_particle_color_gradient(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var stops: Array = args.get(&"stops", [])

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if stops.is_empty():
		return {&"ok": false, &"error": "Missing 'stops' (array of {offset, color})"}

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
	if not _is_particles_node(target):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) is not a GPUParticles2D/3D" % [node_path, target.get_class()]}

	var gradient := Gradient.new()
	var offsets: PackedFloat32Array = []
	var colors: PackedColorArray = []
	for stop in stops:
		if not stop is Dictionary or not stop.has(&"offset") or not stop.has(&"color"):
			_discard_scene(root, is_live)
			return {&"ok": false, &"error": "Each stop must be {offset: float, color: {r,g,b,a}}"}
		var parsed_color = _parse_typed_value(stop[&"color"], TYPE_COLOR)
		if not (parsed_color is Color):
			_discard_scene(root, is_live)
			return {&"ok": false, &"error": "Stop 'color' must be a Color: \"#ff0000\" or {\"r\":1,\"g\":1,\"b\":1,\"a\":1}"}
		offsets.append(float(stop[&"offset"]))
		colors.append(parsed_color)
	gradient.offsets = offsets
	gradient.colors = colors

	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient

	var ctx := _begin_edit(is_live, "MCP: set particle gradient on %s" % node_path, root)
	var material: ParticleProcessMaterial = target.get(&"process_material") as ParticleProcessMaterial
	if not material:
		material = ParticleProcessMaterial.new()
		_edit_set(ctx, target, &"process_material", material)
	_edit_set(ctx, material, &"color_ramp", gradient_texture)
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"stop_count": stops.size(),
		&"message": "Set color gradient (%d stops) on '%s'" % [stops.size(), node_path]}

# =============================================================================
# apply_particle_preset
# =============================================================================
func apply_particle_preset(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var preset: String = str(args.get(&"preset", ""))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if preset not in ["fire", "smoke", "rain", "snow", "sparks"]:
		return {&"ok": false, &"error": "Invalid 'preset': %s. Use fire, smoke, rain, snow, or sparks." % preset}

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
	if not _is_particles_node(target):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) is not a GPUParticles2D/3D" % [node_path, target.get_class()]}

	# Preset name is validated above, so opening the batch here is safe.
	var ctx := _begin_edit(is_live, "MCP: apply '%s' particle preset" % preset, root)
	var material := ParticleProcessMaterial.new()

	match preset:
		"fire":
			_edit_set(ctx, target, &"amount", 32)
			_edit_set(ctx, target, &"lifetime", 0.8)
			material.direction = Vector3(0, -1, 0)
			material.spread = 20.0
			material.initial_velocity_min = 40.0
			material.initial_velocity_max = 80.0
			material.gravity = Vector3(0, -20, 0)
			material.scale_min = 0.5
			material.scale_max = 1.2
			material.color = Color(1.0, 0.5, 0.1, 1.0)
		"smoke":
			_edit_set(ctx, target, &"amount", 16)
			_edit_set(ctx, target, &"lifetime", 2.0)
			material.direction = Vector3(0, -1, 0)
			material.spread = 15.0
			material.initial_velocity_min = 10.0
			material.initial_velocity_max = 25.0
			material.gravity = Vector3(0, -5, 0)
			material.scale_min = 1.0
			material.scale_max = 2.5
			material.color = Color(0.5, 0.5, 0.5, 0.6)
		"rain":
			_edit_set(ctx, target, &"amount", 64)
			_edit_set(ctx, target, &"lifetime", 1.5)
			material.direction = Vector3(0, 1, 0)
			material.spread = 2.0
			material.initial_velocity_min = 200.0
			material.initial_velocity_max = 250.0
			material.gravity = Vector3(0, 400, 0)
			material.scale_min = 0.3
			material.scale_max = 0.5
			material.color = Color(0.6, 0.7, 1.0, 0.7)
		"snow":
			_edit_set(ctx, target, &"amount", 48)
			_edit_set(ctx, target, &"lifetime", 3.0)
			material.direction = Vector3(0, 1, 0)
			material.spread = 30.0
			material.initial_velocity_min = 20.0
			material.initial_velocity_max = 40.0
			material.gravity = Vector3(0, 20, 0)
			material.scale_min = 0.3
			material.scale_max = 0.8
			material.color = Color(1.0, 1.0, 1.0, 0.9)
		"sparks":
			_edit_set(ctx, target, &"amount", 24)
			_edit_set(ctx, target, &"lifetime", 0.5)
			material.direction = Vector3(0, -1, 0)
			material.spread = 180.0
			material.initial_velocity_min = 100.0
			material.initial_velocity_max = 200.0
			material.gravity = Vector3(0, 300, 0)
			material.scale_min = 0.1
			material.scale_max = 0.3
			material.color = Color(1.0, 0.9, 0.3, 1.0)

	_edit_set(ctx, target, &"process_material", material)
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path, &"preset": preset,
		&"message": "Applied '%s' preset to '%s'" % [preset, node_path]}

# =============================================================================
# get_particle_info
# =============================================================================
func get_particle_info(args: Dictionary) -> Dictionary:
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
	if not _is_particles_node(target):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) is not a GPUParticles2D/3D" % [node_path, target.get_class()]}

	var info: Dictionary = {
		&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"node_type": target.get_class(),
		&"amount": int(target.get(&"amount")),
		&"lifetime": float(target.get(&"lifetime")),
		&"one_shot": bool(target.get(&"one_shot")),
		&"emitting": bool(target.get(&"emitting")),
	}

	var material: ParticleProcessMaterial = target.get(&"process_material") as ParticleProcessMaterial
	if material:
		info[&"direction"] = VariantCodec.serialize_value(material.direction)
		info[&"spread"] = material.spread
		info[&"initial_velocity_min"] = material.initial_velocity_min
		info[&"initial_velocity_max"] = material.initial_velocity_max
		info[&"gravity"] = VariantCodec.serialize_value(material.gravity)
		info[&"has_color_ramp"] = material.color_ramp != null

	_discard_scene(root, is_live)
	return info
