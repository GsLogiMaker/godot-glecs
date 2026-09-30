@tool
extends Node
class_name BatchTools
## Batch/refactor/analysis tools for MCP.
## Handles: find_nodes_by_type, batch_set_property, get_scene_dependencies,
##          rename_symbol_project_wide

const VariantCodec = preload("res://addons/godot_mcp/utils/variant_codec.gd")
const PathGuard = preload("res://addons/godot_mcp/utils/path_guard.gd")

const _SKIP_EXTENSIONS := {".import": true, ".uid": true, ".translation": true}
const MAX_TRAVERSAL_DEPTH := 24

var _editor_plugin: EditorPlugin = null

func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin

# =============================================================================
# Shared helpers (mirrors scene_tools.gd)
# =============================================================================
func _refresh_and_reload(scene_path: String) -> void:
	if _editor_plugin:
		_editor_plugin.get_editor_interface().get_resource_filesystem().scan()
		var ei = _editor_plugin.get_editor_interface()
		var edited = ei.get_edited_scene_root()
		if edited and edited.scene_file_path == scene_path:
			ei.reload_scene_from_path(scene_path)

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

func _load_scene(scene_path: String) -> Array:
	"""Returns [scene_root, error_dict]. If error_dict is not empty, scene_root is null."""
	if PathGuard.is_bad(scene_path):
		return [null, PathGuard.error_for(scene_path, "scene_path")]
	if not FileAccess.file_exists(scene_path):
		return [null, {&"ok": false, &"error": "Scene does not exist: " + scene_path}]

	var packed = load(scene_path) as PackedScene
	if not packed:
		return [null, {&"ok": false, &"error": "Failed to load scene: " + scene_path}]

	var root = _instantiate_packed_scene_for_edit(packed)
	if not root:
		return [null, {&"ok": false, &"error": "Failed to instantiate scene: " + scene_path + ". It loaded as a PackedScene but produced no node — usually a scene whose root script fails to compile."}]

	return [root, {}]

func _instantiate_packed_scene_for_edit(packed: PackedScene) -> Node:
	if not packed:
		return null
	if not Engine.is_editor_hint():
		return packed.instantiate()
	var state = packed.get_state()
	if state and state.get_base_scene_state() != null:
		return packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN_INHERITED)
	return packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)

func _save_scene(scene_root: Node, scene_path: String) -> Dictionary:
	"""Pack and save a scene. Returns error dict or empty on success."""
	if PathGuard.is_bad(scene_path):
		scene_root.queue_free()
		return PathGuard.error_for(scene_path, "scene_path")
	var packed = PackedScene.new()
	var pack_result = packed.pack(scene_root)
	if pack_result != OK:
		scene_root.queue_free()
		return {&"ok": false, &"error": "Failed to pack scene: " + str(pack_result)}

	var save_result = ResourceSaver.save(packed, scene_path)
	scene_root.queue_free()

	if save_result != OK:
		return {&"ok": false, &"error": "Failed to save scene: " + str(save_result)}

	_refresh_and_reload(scene_path)
	return {}

func _find_node(scene_root: Node, node_path: String) -> Node:
	if node_path == "." or node_path.is_empty():
		return scene_root
	return scene_root.get_node_or_null(node_path)

# =============================================================================
# find_nodes_by_type
# =============================================================================
func find_nodes_by_type(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_type: String = str(args.get(&"node_type", ""))
	var exact_match: bool = bool(args.get(&"exact_match", false))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if node_type.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'node_type'"}

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]
	var root: Node = result[0]

	var matches: Array = []
	_find_nodes_by_type_recursive(root, root, node_type, exact_match, matches)
	root.queue_free()

	return {&"ok": true, &"scene_path": scene_path, &"node_type": node_type,
		&"matches": matches, &"count": matches.size()}

func _find_nodes_by_type_recursive(node: Node, root: Node, node_type: String, exact_match: bool, out: Array) -> void:
	var matches_type := (node.get_class() == node_type) if exact_match else node.is_class(node_type)
	if matches_type:
		var path_str: String = "." if node == root else str(root.get_path_to(node))
		out.append({&"node_path": path_str, &"node_name": node.name, &"node_type": node.get_class()})
	for child in node.get_children():
		_find_nodes_by_type_recursive(child, root, node_type, exact_match, out)

# =============================================================================
# batch_set_property
# =============================================================================
func batch_set_property(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_paths: Array = args.get(&"node_paths", [])
	var property_name: String = str(args.get(&"property_name", ""))
	var value = args.get(&"value")

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if node_paths.is_empty():
		return {&"ok": false, &"error": "Missing 'node_paths' (non-empty array)"}
	if property_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'property_name'"}
	if not args.has(&"value"):
		return {&"ok": false, &"error": "Missing 'value'"}

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]
	var root: Node = result[0]

	var parsed_value = VariantCodec.parse_value(value)
	var applied: Array = []
	var failed: Array = []

	for np in node_paths:
		var node_path := str(np)
		var target := _find_node(root, node_path)
		if not target:
			# Named in the message too: a batch answer is read as a list of
			# strings, and "Node not found" repeated four times says nothing
			# about which four.
			failed.append({&"node_path": node_path, &"error": "Node not found: " + node_path})
			continue
		if not (property_name in target):
			failed.append({&"node_path": node_path, &"error": "No property '%s' on %s" % [property_name, target.get_class()]})
			continue
		var old_value = target.get(property_name)
		target.set(property_name, parsed_value)
		applied.append({&"node_path": node_path, &"old": VariantCodec.serialize_value(old_value), &"new": VariantCodec.serialize_value(parsed_value)})

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"property_name": property_name,
		&"applied": applied, &"failed": failed,
		&"message": "Applied %d/%d, %d failed" % [applied.size(), node_paths.size(), failed.size()]}

# =============================================================================
# get_scene_dependencies
# =============================================================================
func get_scene_dependencies(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if not FileAccess.file_exists(scene_path):
		return {&"ok": false, &"error": "Scene does not exist: " + scene_path}

	var deps := ResourceLoader.get_dependencies(scene_path)
	var dependencies: Array = []
	for dep: String in deps:
		# get_dependencies() entries look like "<uid_or_path>::<type_hint>" or
		# just a path; split on "::" defensively.
		var parts := dep.split("::")
		var dep_path: String = parts[0]
		dependencies.append({&"path": dep_path, &"type_hint": parts[1] if parts.size() > 1 else ""})

	return {&"ok": true, &"scene_path": scene_path,
		&"dependencies": dependencies, &"count": dependencies.size()}

# =============================================================================
# rename_symbol_project_wide
# =============================================================================
## Word-boundary regex rename across .gd files (and optionally .tscn method
## references). Defaults to dry_run=true — the community's own complaint
## about automated renames is false positives, so previewing matches before
## touching anything is the safe default, not an afterthought.
const _IDENTIFIER_RE := "^[A-Za-z_][A-Za-z0-9_]*$"

func rename_symbol_project_wide(args: Dictionary) -> Dictionary:
	var old_name: String = str(args.get(&"old_name", ""))
	var new_name: String = str(args.get(&"new_name", ""))
	var dry_run: bool = bool(args.get(&"dry_run", true))
	var include_scenes: bool = bool(args.get(&"include_scenes", false))
	var root_path: String = _ensure_res_path(str(args.get(&"root", "res://")))

	if old_name.strip_edges().is_empty() or new_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'old_name' or 'new_name'"}
	if PathGuard.is_bad(root_path):
		return PathGuard.error_for(root_path, "root")

	var ident_check := RegEx.new()
	ident_check.compile(_IDENTIFIER_RE)
	if not ident_check.search(old_name) or not ident_check.search(new_name):
		return {&"ok": false, &"error": "'old_name'/'new_name' must be valid identifiers ([A-Za-z_][A-Za-z0-9_]*)"}

	var regex := RegEx.new()
	regex.compile("\\b" + old_name + "\\b")

	var extensions: Array = [".gd"]
	if include_scenes:
		extensions.append(".tscn")

	var files: PackedStringArray = []
	_collect_files_recursive(root_path, extensions, files)

	var file_results: Array = []
	var total_matches := 0

	for file_path: String in files:
		var f := FileAccess.open(file_path, FileAccess.READ)
		if not f:
			continue
		var content := f.get_as_text()
		f.close()

		var matches := regex.search_all(content)
		if matches.is_empty():
			continue

		var lines := content.split("\n")
		var line_hits: Array = []
		for i in range(lines.size()):
			if regex.search(lines[i]):
				line_hits.append({&"line": i + 1, &"content": lines[i].strip_edges()})

		total_matches += matches.size()
		file_results.append({&"file": file_path, &"match_count": matches.size(), &"lines": line_hits})

		if not dry_run:
			var new_content := regex.sub(content, new_name, true)
			var wf := FileAccess.open(file_path, FileAccess.WRITE)
			if not wf:
				return {&"ok": false, &"error": "Failed to write file: " + file_path}
			wf.store_string(new_content)
			wf.close()

	if not dry_run and _editor_plugin:
		_editor_plugin.get_editor_interface().get_resource_filesystem().scan()

	return {&"ok": true, &"old_name": old_name, &"new_name": new_name,
		&"dry_run": dry_run, &"files": file_results,
		&"file_count": file_results.size(), &"total_matches": total_matches,
		&"message": ("Preview: %d matches in %d files. Call again with dry_run=false to apply." % [total_matches, file_results.size()]) if dry_run
			else ("Renamed %d matches in %d files." % [total_matches, file_results.size()])}

func _collect_files_recursive(path: String, extensions: Array, out: PackedStringArray, depth: int = 0) -> void:
	if depth >= MAX_TRAVERSAL_DEPTH:
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full_path := path.path_join(name)
		if dir.current_is_dir():
			_collect_files_recursive(full_path, extensions, out, depth + 1)
		else:
			var ext := "." + name.get_extension().to_lower()
			if extensions.has(ext) and not _SKIP_EXTENSIONS.has(ext):
				out.append(full_path)
		name = dir.get_next()
