@tool
extends SceneToolBase
class_name ShaderTools
## Shader resource tools for MCP.
## Handles: create_shader, read_shader, edit_shader,
##          assign_shader_material, set_shader_param, get_shader_params


## Locate the material slot to use for a node, mirroring set_material_3d's
## CanvasItem (2D) vs MeshInstance3D/GeometryInstance3D (3D) decision.
## Returns {&"ok": true, &"material": Material_or_null, &"setter": Callable,
##          &"prop": StringName_or_empty, &"surface": int}
## or {&"ok": false, &"error": String}.
##
## `prop`/`surface` describe the same write as `setter` in a form the undo
## helpers can record: a plain property, or the indexed surface-override method.
## `setter` stays for callers that only need the effect.
func _resolve_material_slot(target: Node, surface_index: int) -> Dictionary:
	if target is CanvasItem:
		return {
			&"ok": true,
			&"material": target.get(&"material"),
			&"prop": &"material",
			&"surface": -1,
			&"setter": func(mat: Material): target.set(&"material", mat)
		}
	if target is MeshInstance3D and surface_index >= 0:
		return {
			&"ok": true,
			&"material": target.get_surface_override_material(surface_index),
			&"prop": &"",
			&"surface": surface_index,
			&"setter": func(mat: Material): target.set_surface_override_material(surface_index, mat)
		}
	if target is GeometryInstance3D:
		return {
			&"ok": true,
			&"material": target.get(&"material_override"),
			&"prop": &"material_override",
			&"surface": -1,
			&"setter": func(mat: Material): target.set(&"material_override", mat)
		}
	return {&"ok": false, &"error": "Node '%s' (%s) does not support materials" % [target.name, target.get_class()]}

# =============================================================================
# create_shader
# =============================================================================
const _TEMPLATES: Dictionary = {
	"canvas_item": "shader_type canvas_item;\n\nvoid fragment() {\n\t// COLOR = texture(TEXTURE, UV);\n}\n",
	"spatial": "shader_type spatial;\n\nvoid fragment() {\n\t// ALBEDO = vec3(1.0);\n}\n",
	"particles": "shader_type particles;\n\nvoid start() {\n}\n\nvoid process() {\n}\n",
	"sky": "shader_type sky;\n\nvoid sky() {\n}\n",
	"fog": "shader_type fog;\n\nvoid fog() {\n}\n",
}

func create_shader(args: Dictionary) -> Dictionary:
	var shader_path: String = _ensure_res_path(str(args.get(&"shader_path", "")))
	var shader_type: String = str(args.get(&"shader_type", "canvas_item"))
	var code = args.get(&"code")

	if shader_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'shader_path'"}
	if PathGuard.is_bad(shader_path):
		return PathGuard.error_for(shader_path, "shader_path")
	if not _TEMPLATES.has(shader_type):
		return {&"ok": false, &"error": "Invalid 'shader_type': %s. Use one of: %s" % [shader_type, ", ".join(_TEMPLATES.keys())]}

	var shader := Shader.new()
	if code != null and not str(code).is_empty():
		shader.set_code(str(code))
	else:
		shader.set_code(_TEMPLATES[shader_type])

	var save_result := ResourceSaver.save(shader, shader_path)
	if save_result != OK:
		return {&"ok": false, &"error": "Failed to save shader: " + str(save_result)}

	_refresh_filesystem()

	return {&"ok": true, &"shader_path": shader_path, &"shader_type": shader_type,
		&"message": "Created shader at " + shader_path}

# =============================================================================
# read_shader
# =============================================================================
func read_shader(args: Dictionary) -> Dictionary:
	var shader_path: String = _ensure_res_path(str(args.get(&"shader_path", "")))

	if shader_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'shader_path'"}
	if not FileAccess.file_exists(shader_path):
		return {&"ok": false, &"error": "Shader does not exist: " + shader_path}

	var shader := load(shader_path) as Shader
	if not shader:
		return {&"ok": false, &"error": "Failed to load Shader: " + shader_path}

	return {&"ok": true, &"shader_path": shader_path, &"code": shader.get_code(), &"mode": shader.get_mode()}

# =============================================================================
# edit_shader - Apply a small surgical code edit (mirrors edit_script's
# snippet_replace, but keeps only the plain match / error cases).
# =============================================================================
func edit_shader(args: Dictionary) -> Dictionary:
	var shader_path: String = _ensure_res_path(str(args.get(&"shader_path", "")))
	var old_code_snippet: String = str(args.get(&"old_code_snippet", ""))
	var new_code_snippet: String = str(args.get(&"new_code_snippet", ""))

	if shader_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'shader_path'"}
	if old_code_snippet.is_empty():
		return {&"ok": false, &"error": "Missing 'old_code_snippet'"}
	if not FileAccess.file_exists(shader_path):
		return {&"ok": false, &"error": "Shader does not exist: " + shader_path}

	var shader := load(shader_path) as Shader
	if not shader:
		return {&"ok": false, &"error": "Failed to load Shader: " + shader_path}

	var content := shader.get_code()
	var pos := content.find(old_code_snippet)
	if pos == -1:
		return {&"ok": false, &"error": "Could not find old_code_snippet in shader. Make sure it matches the shader code exactly."}

	var second_pos := content.find(old_code_snippet, pos + 1)
	if second_pos != -1:
		return {&"ok": false, &"error": "old_code_snippet appears multiple times. Provide a larger, unique snippet."}

	var new_content := content.substr(0, pos) + new_code_snippet + content.substr(pos + old_code_snippet.length())
	shader.set_code(new_content)

	var save_result := ResourceSaver.save(shader, shader_path)
	if save_result != OK:
		return {&"ok": false, &"error": "Failed to save shader: " + str(save_result)}

	_refresh_filesystem()

	return {&"ok": true, &"shader_path": shader_path, &"message": "Applied edit to " + shader_path}

# =============================================================================
# assign_shader_material
# =============================================================================
func assign_shader_material(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var shader_path: String = _ensure_res_path(str(args.get(&"shader_path", "")))
	var surface_index: int = int(args.get(&"surface_index", -1))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if shader_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'shader_path'"}
	if not FileAccess.file_exists(shader_path):
		return {&"ok": false, &"error": "Shader does not exist: " + shader_path}

	var shader := load(shader_path) as Shader
	if not shader:
		return {&"ok": false, &"error": "Failed to load Shader: " + shader_path}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var target := _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err

	var slot := _resolve_material_slot(target, surface_index)
	if not slot[&"ok"]:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": slot[&"error"]}

	var mat := ShaderMaterial.new()
	mat.set_shader(shader)

	var ctx := _begin_edit(is_live, "MCP: assign shader to %s" % node_path, root)
	var prev_material = slot[&"material"]
	var surface: int = int(slot[&"surface"])
	if surface >= 0:
		target.set_surface_override_material(surface, mat)
		_edit_record(ctx, target, &"set_surface_override_material", [surface, mat],
			&"set_surface_override_material", [surface, prev_material])
	else:
		_edit_set(ctx, target, StringName(slot[&"prop"]), mat)
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path, &"shader_path": shader_path,
		&"message": "Assigned ShaderMaterial (%s) to '%s'" % [shader_path, node_path]}

# =============================================================================
# set_shader_param
# =============================================================================
func set_shader_param(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var param_name: String = str(args.get(&"param_name", ""))
	var value = args.get(&"value")

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if param_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'param_name'"}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var target := _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err

	var slot := _resolve_material_slot(target, int(args.get(&"surface_index", -1)))
	if not slot[&"ok"]:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": slot[&"error"]}

	var material: ShaderMaterial = slot[&"material"] as ShaderMaterial
	if not material or not material.get_shader():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' has no ShaderMaterial with a shader assigned" % node_path}

	# Parsed against the type the SHADER declares, not guessed from the value's
	# shape. Untyped, "#ff0000" stayed a String, set_shader_parameter dropped it
	# without a word, and the read-back showed the uniform's default — the call
	# answering ok the whole time.
	var declared_type := _uniform_type(material.get_shader(), param_name)
	var parsed = VariantCodec.parse_typed_value(value, declared_type)
	var prev_value = material.get_shader_parameter(StringName(param_name))
	var ctx := _begin_edit(is_live, "MCP: set shader param '%s'" % param_name, root)
	material.set_shader_parameter(StringName(param_name), parsed)
	_edit_record(ctx, material, &"set_shader_parameter", [StringName(param_name), parsed],
		&"set_shader_parameter", [StringName(param_name), prev_value])
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	# Read it back. A uniform the shader does not declare accepts the write and
	# holds nothing; one given the wrong type keeps its default. Both look like
	# success from here otherwise.
	var landed = material.get_shader_parameter(StringName(param_name))
	var out := {&"ok": true, &"scene_path": scene_path, &"node_path": node_path, &"param_name": param_name,
		&"value": VariantCodec.serialize_value(landed),
		&"message": "Set shader param '%s' on '%s'" % [param_name, node_path]}
	if declared_type == -1:
		out[&"warning"] = "The shader declares no uniform named '%s', so nothing reads this value. Call get_shader_params for the ones it does declare." % param_name
	elif not _values_match(landed, parsed):
		out[&"warning"] = "Asked for %s, the material holds %s." % [str(parsed), str(landed)]
	return out

## The Variant type a shader declares for one uniform, or -1 when it has none.
func _uniform_type(shader: Shader, param_name: String) -> int:
	if shader == null:
		return -1
	for uniform in shader.get_shader_uniform_list(true):
		if str(uniform.get(&"name", "")) == param_name:
			return int(uniform.get(&"type", -1))
	return -1

# =============================================================================
# get_shader_params
# =============================================================================
func get_shader_params(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var target := _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err

	var slot := _resolve_material_slot(target, int(args.get(&"surface_index", -1)))
	if not slot[&"ok"]:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": slot[&"error"]}

	var material: ShaderMaterial = slot[&"material"] as ShaderMaterial
	if not material or not material.get_shader():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' has no ShaderMaterial with a shader assigned" % node_path}

	var params: Array = []
	for uniform in material.get_shader().get_shader_uniform_list(false):
		var uniform_name: String = str(uniform.get(&"name", ""))
		var uniform_value = material.get_shader_parameter(uniform_name)
		params.append({
			&"name": uniform_name,
			&"type": uniform.get(&"type", TYPE_NIL),
			&"value": VariantCodec.serialize_value(uniform_value)
		})

	_discard_scene(root, is_live)

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path, &"params": params}
