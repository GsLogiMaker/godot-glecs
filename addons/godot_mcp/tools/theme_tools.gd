@tool
extends Node
class_name ThemeTools
## Theme resource tools for MCP.
## Handles: create_theme, set_theme_color, set_theme_constant, set_theme_font_size,
##          set_theme_stylebox, get_theme_info
## All tools operate on a standalone Theme resource (.tres) on disk.

const VariantCodec = preload("res://addons/godot_mcp/utils/variant_codec.gd")
const PathGuard = preload("res://addons/godot_mcp/utils/path_guard.gd")

var _editor_plugin: EditorPlugin = null

func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin

## Sanitizes a res://-relative path and blocks traversal outside the project
## (e.g. "../../../Windows/System32"). On rejection returns a path that can
## never resolve to a real file, so every downstream FileAccess/load() call
## fails closed with a clear "does not exist"/"invalid" error instead of
## silently escaping the project sandbox. See MERGE_NOTES.md for why this
## exists — a plain "res://" prefix check does NOT stop "../" traversal.
func _ensure_res_path(path: String) -> String:
	var guarded := PathGuard.sanitize(path)
	if not guarded[&"ok"]:
		if path.strip_edges().is_empty():
			return PathGuard.MISSING
		push_warning("[MCP] Rejected path outside project sandbox: %s (%s)" % [path, guarded[&"error"]])
		return PathGuard.REJECTED
	return guarded[&"path"]

func _refresh_filesystem() -> void:
	if _editor_plugin:
		_editor_plugin.get_editor_interface().get_resource_filesystem().scan()

func _load_theme(theme_path: String) -> Array:
	"""Returns [theme_or_null, error_dict]."""
	if PathGuard.is_bad(theme_path):
		return [null, PathGuard.error_for(theme_path, "theme_path")]
	if not FileAccess.file_exists(theme_path):
		return [null, {&"ok": false, &"error": "Theme resource does not exist: " + theme_path}]
	var theme := load(theme_path) as Theme
	if not theme:
		return [null, {&"ok": false, &"error": "Failed to load Theme resource: " + theme_path}]
	return [theme, {}]

func _save_theme(theme: Theme, theme_path: String) -> Dictionary:
	if PathGuard.is_bad(theme_path):
		return PathGuard.error_for(theme_path, "theme_path")
	var save_result := ResourceSaver.save(theme, theme_path)
	if save_result != OK:
		return {&"ok": false, &"error": "Failed to save theme: " + str(save_result)}
	_refresh_filesystem()
	return {}

# =============================================================================
# create_theme
# =============================================================================
func create_theme(args: Dictionary) -> Dictionary:
	var theme_path: String = _ensure_res_path(str(args.get(&"theme_path", "")))

	if theme_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'theme_path'"}
	if PathGuard.is_bad(theme_path):
		return PathGuard.error_for(theme_path, "theme_path")
	if FileAccess.file_exists(theme_path):
		return {&"ok": false, &"error": "File already exists: " + theme_path}

	var theme := Theme.new()
	var save_result := ResourceSaver.save(theme, theme_path)
	if save_result != OK:
		return {&"ok": false, &"error": "Failed to save theme: " + str(save_result)}
	_refresh_filesystem()

	return {&"ok": true, &"theme_path": theme_path, &"message": "Created Theme resource at " + theme_path}

# =============================================================================
# set_theme_color
# =============================================================================
func set_theme_color(args: Dictionary) -> Dictionary:
	var theme_path: String = _ensure_res_path(str(args.get(&"theme_path", "")))
	var control_type: String = str(args.get(&"control_type", ""))
	var color_name: String = str(args.get(&"color_name", ""))
	var color = args.get(&"color")

	if theme_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'theme_path'"}
	if control_type.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'control_type' (e.g. 'Label', 'Button')"}
	if color_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'color_name' (e.g. 'font_color')"}
	if color == null:
		return {&"ok": false, &"error": "Missing 'color'"}

	var result := _load_theme(theme_path)
	if not result[1].is_empty():
		return result[1]
	var theme: Theme = result[0]

	var parsed = VariantCodec.parse_typed_value(color, TYPE_COLOR)
	if not (parsed is Color):
		return {&"ok": false, &"error": "'color' must be a Color: \"#ff0000\" or {\"r\":1,\"g\":1,\"b\":1,\"a\":1}"}

	theme.set_color(StringName(color_name), StringName(control_type), parsed)

	var err := _save_theme(theme, theme_path)
	if not err.is_empty():
		return err

	return {&"ok": true, &"theme_path": theme_path, &"control_type": control_type, &"color_name": color_name,
		&"message": "Set color '%s' on '%s' in %s" % [color_name, control_type, theme_path]}

# =============================================================================
# set_theme_constant
# =============================================================================
func set_theme_constant(args: Dictionary) -> Dictionary:
	var theme_path: String = _ensure_res_path(str(args.get(&"theme_path", "")))
	var control_type: String = str(args.get(&"control_type", ""))
	var constant_name: String = str(args.get(&"constant_name", ""))

	if theme_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'theme_path'"}
	if control_type.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'control_type'"}
	if constant_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'constant_name' (e.g. 'separation')"}
	if not args.has(&"value"):
		return {&"ok": false, &"error": "Missing 'value'"}

	var result := _load_theme(theme_path)
	if not result[1].is_empty():
		return result[1]
	var theme: Theme = result[0]

	var value: int = int(args.get(&"value"))
	theme.set_constant(StringName(constant_name), StringName(control_type), value)

	var err := _save_theme(theme, theme_path)
	if not err.is_empty():
		return err

	return {&"ok": true, &"theme_path": theme_path, &"control_type": control_type,
		&"constant_name": constant_name, &"value": value,
		&"message": "Set constant '%s' on '%s' in %s" % [constant_name, control_type, theme_path]}

# =============================================================================
# set_theme_font_size
# =============================================================================
func set_theme_font_size(args: Dictionary) -> Dictionary:
	var theme_path: String = _ensure_res_path(str(args.get(&"theme_path", "")))
	var control_type: String = str(args.get(&"control_type", ""))
	var font_size_name: String = str(args.get(&"font_size_name", "font_size"))

	if theme_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'theme_path'"}
	if control_type.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'control_type'"}
	if not args.has(&"value"):
		return {&"ok": false, &"error": "Missing 'value'"}

	var result := _load_theme(theme_path)
	if not result[1].is_empty():
		return result[1]
	var theme: Theme = result[0]

	var value: int = int(args.get(&"value"))
	theme.set_font_size(StringName(font_size_name), StringName(control_type), value)

	var err := _save_theme(theme, theme_path)
	if not err.is_empty():
		return err

	return {&"ok": true, &"theme_path": theme_path, &"control_type": control_type,
		&"font_size_name": font_size_name, &"value": value,
		&"message": "Set font size '%s' on '%s' in %s" % [font_size_name, control_type, theme_path]}

# =============================================================================
# set_theme_stylebox
# =============================================================================
## Builds a StyleBoxFlat from a friendly dict and assigns it as a theme stylebox override.
func _build_styleboxflat(style: Dictionary) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if style.has(&"bg_color"):
		var c = VariantCodec.parse_value(style[&"bg_color"])
		if c is Color:
			sb.bg_color = c
	if style.has(&"border_width"):
		var w := int(style[&"border_width"])
		sb.set(&"border_width_left", w)
		sb.set(&"border_width_right", w)
		sb.set(&"border_width_top", w)
		sb.set(&"border_width_bottom", w)
	if style.has(&"border_color"):
		var c = VariantCodec.parse_value(style[&"border_color"])
		if c is Color:
			sb.border_color = c
	if style.has(&"corner_radius"):
		var r := int(style[&"corner_radius"])
		sb.set(&"corner_radius_top_left", r)
		sb.set(&"corner_radius_top_right", r)
		sb.set(&"corner_radius_bottom_left", r)
		sb.set(&"corner_radius_bottom_right", r)
	if style.has(&"content_margin"):
		var m := float(style[&"content_margin"])
		sb.set(&"content_margin_left", m)
		sb.set(&"content_margin_right", m)
		sb.set(&"content_margin_top", m)
		sb.set(&"content_margin_bottom", m)
	return sb

func set_theme_stylebox(args: Dictionary) -> Dictionary:
	var theme_path: String = _ensure_res_path(str(args.get(&"theme_path", "")))
	var control_type: String = str(args.get(&"control_type", ""))
	var stylebox_name: String = str(args.get(&"stylebox_name", ""))
	var style: Dictionary = args.get(&"style", {})

	if theme_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'theme_path'"}
	if control_type.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'control_type'"}
	if stylebox_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'stylebox_name' (e.g. 'panel', 'normal')"}
	if style.is_empty():
		return {&"ok": false, &"error": "Missing 'style' (e.g. {\"bg_color\":{...},\"corner_radius\":4})"}

	var result := _load_theme(theme_path)
	if not result[1].is_empty():
		return result[1]
	var theme: Theme = result[0]

	var sb := _build_styleboxflat(style)
	theme.set_stylebox(StringName(stylebox_name), StringName(control_type), sb)

	var err := _save_theme(theme, theme_path)
	if not err.is_empty():
		return err

	return {&"ok": true, &"theme_path": theme_path, &"control_type": control_type,
		&"stylebox_name": stylebox_name,
		&"message": "Set stylebox '%s' on '%s' in %s" % [stylebox_name, control_type, theme_path]}

# =============================================================================
# get_theme_info
# =============================================================================
func get_theme_info(args: Dictionary) -> Dictionary:
	var theme_path: String = _ensure_res_path(str(args.get(&"theme_path", "")))

	if theme_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'theme_path'"}

	var result := _load_theme(theme_path)
	if not result[1].is_empty():
		return result[1]
	var theme: Theme = result[0]

	var types: Array = []
	for type_name: StringName in theme.get_type_list():
		var colors: Array = []
		for c: StringName in theme.get_color_list(type_name):
			colors.append({&"name": str(c), &"value": VariantCodec.serialize_value(theme.get_color(c, type_name))})
		var constants: Array = []
		for c: StringName in theme.get_constant_list(type_name):
			constants.append({&"name": str(c), &"value": theme.get_constant(c, type_name)})
		var font_sizes: Array = []
		for c: StringName in theme.get_font_size_list(type_name):
			font_sizes.append({&"name": str(c), &"value": theme.get_font_size(c, type_name)})
		var styleboxes: Array = []
		for c: StringName in theme.get_stylebox_list(type_name):
			styleboxes.append({&"name": str(c), &"class": theme.get_stylebox(c, type_name).get_class()})

		if colors.is_empty() and constants.is_empty() and font_sizes.is_empty() and styleboxes.is_empty():
			continue

		types.append({
			&"control_type": str(type_name),
			&"colors": colors, &"constants": constants,
			&"font_sizes": font_sizes, &"styleboxes": styleboxes,
		})

	return {&"ok": true, &"theme_path": theme_path, &"types": types}
