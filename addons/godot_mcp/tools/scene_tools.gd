@tool
extends SceneToolBase
class_name SceneTools
## Scene operation tools for MCP.
## Handles: create_scene, read_scene, add_node, instance_scene, remove_node,
##          modify_node_property, rename_node, move_node, attach_script, detach_script,
##          set_collision_shape, set_sprite_texture, set_mesh, set_material,
##          get_node_spatial_info, measure_node_distance, snap_node_to_grid


# Untyped on purpose: typed Dictionary syntax is Godot 4.4+, and the addon
# advertises 4.3+. CI pins the claimed minimum so this stays honest.
const _SKIP_PROPS: Dictionary = {
	"script": true, "owner": true,
	"unique_name_in_owner": true, "editor_description": true,
}


# =============================================================================
# Shared helpers
# =============================================================================
func _reload_scene_in_editor(scene_path: String) -> void:
	if not _editor_plugin:
		return
	var ei = _editor_plugin.get_editor_interface()
	var edited = ei.get_edited_scene_root()
	if edited and edited.scene_file_path == scene_path:
		ei.reload_scene_from_path(scene_path)

## If `scene_path` is the scene currently open+focused in the editor, return its
## LIVE root node (the tree that holds the user's unsaved edits). Otherwise null.
## Mutating this live tree via the EditorUndoRedoManager (see _get_undo_redo) is
## undo-safe and does NOT clobber unsaved editor changes — unlike the disk
## load→save→reload path, which overwrites whatever the user hadn't saved yet.
func _edited_root_if_open(scene_path: String) -> Node:
	if not _editor_plugin:
		return null
	var edited = _editor_plugin.get_editor_interface().get_edited_scene_root()
	if edited and edited.scene_file_path == scene_path:
		return edited
	return null

func _get_undo_redo() -> EditorUndoRedoManager:
	if not _editor_plugin:
		return null
	return _editor_plugin.get_undo_redo()

## Type-safe equality for set() readback validation. GDScript raises
## "Invalid operands 'int' and 'String'" on a cross-type `!=`, which happens
## when a value arrives as a string (e.g. "1" for an int property) and the
## readback is a different type. Guard the cross-type case and fall back to a
## stringwise compare (also treats int 1 == float 1.0 as equal).
## setup_collision's vocabulary mapped to the class names this tool wants, so a
## caller that used the sibling tool's spelling gets told which word to use
## instead of a bare rejection. 2D wins ties: these tools are used on 2D scenes
## far more often, and the message names the tool the alias came from.
const _SHAPE_ALIASES := {
	"rectangle": "RectangleShape2D",
	"circle": "CircleShape2D",
	"capsule": "CapsuleShape2D",
	"box": "BoxShape3D",
	"sphere": "SphereShape3D",
}

# =============================================================================
# create_scene
# =============================================================================
func create_scene(args: Dictionary) -> Dictionary:
	_clear_warnings()
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var root_node_name: String = str(args.get(&"root_node_name", "Node"))
	var root_node_type: String = str(args.get(&"root_node_type", ""))
	var nodes: Array = args.get(&"nodes", [])
	var attach_script_path: String = str(args.get(&"attach_script", ""))
	var dry_run: bool = bool(args.get(&"dry_run", false))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path' parameter"}
	if root_node_type.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'root_node_type' parameter"}
	if not scene_path.ends_with(".tscn"):
		scene_path += ".tscn"
	if FileAccess.file_exists(scene_path):
		return {&"ok": false, &"error": "Scene already exists: " + scene_path}
	if not ClassDB.class_exists(root_node_type):
		return {&"ok": false, &"error": "Invalid root node type: " + root_node_type}

	# Ensure parent directory
	var dir_path := scene_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var root: Node = ClassDB.instantiate(root_node_type) as Node
	if not root:
		return {&"ok": false, &"error": "Failed to create root node of type: " + root_node_type}
	root.name = root_node_name

	if not attach_script_path.is_empty():
		attach_script_path = _ensure_res_path(attach_script_path)
		if PathGuard.is_bad(attach_script_path):
			root.queue_free()
			return {&"ok": false, &"error": "attach_script escapes the project sandbox"}
		var script_res = load(attach_script_path)
		if script_res:
			root.set_script(script_res)
		else:
			root.queue_free()
			return {&"ok": false, &"error": "Failed to load script: " + attach_script_path}

	var node_count := 0
	for node_data: Variant in nodes:
		if typeof(node_data) != TYPE_DICTIONARY:
			root.queue_free()
			return {&"ok": false, &"error": "Every entry in 'nodes' must be a Dictionary; got %s" % type_string(typeof(node_data))}
		var created_pair := _create_node_recursive(node_data, root, root)
		if created_pair[1] != "":
			root.queue_free()
			return {&"ok": false, &"error": "create_scene: %s" % String(created_pair[1])}
		if created_pair[0] != null:
			node_count += _count_nodes(created_pair[0])

	if dry_run:
		root.queue_free()
		return {&"ok": true, &"dry_run": true, &"path": scene_path, &"root_type": root_node_type,
			&"child_count": node_count,
			&"message": "Preview: would create scene at %s with %d node(s). Call again with dry_run=false to save." % [scene_path, node_count + 1]}

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return _with_warnings({&"ok": true, &"path": scene_path, &"root_type": root_node_type, &"child_count": node_count,
		&"message": "Scene created at " + scene_path})

## Known child-spec keys. Anything else is a typo (common agent mistake: using
## parent_path, class, kind, etc. in a child block). We reject unknown keys so
## the bug surfaces loudly rather than defaulting to a generic Node.
const _CHILD_SPEC_KEYS: PackedStringArray = [
	"name", "node_name", "type", "node_type", "script",
	"properties", "children", "groups",
]

## Recursively create a child node. Returns [Node_or_null, error_string].
## Accepts EITHER {name, type} OR {node_name, node_type} so the child spec can
## use the same key names as add_node's top-level arguments. Unknown keys
## trigger an error so malformed specs are caught instead of silently
## producing a generic Node with the wrong name.
func _create_node_recursive(data: Dictionary, parent: Node, owner: Node) -> Array:
	# Validate keys first so typos fail loudly instead of silently.
	for key in data.keys():
		var key_str: String = str(key)
		if not _CHILD_SPEC_KEYS.has(key_str):
			return [null, "Unknown child spec key '%s'. Valid keys: %s" % [key_str, ", ".join(_CHILD_SPEC_KEYS)]]

	var n_name: String = str(data.get(&"node_name", data.get(&"name", "")))
	var n_type: String = str(data.get(&"node_type", data.get(&"type", "")))
	var n_script: String = str(data.get(&"script", ""))
	var props: Dictionary = data.get(&"properties", {})
	var children: Array = data.get(&"children", [])
	var groups: Array = data.get(&"groups", [])

	if n_type.is_empty():
		return [null, "Child spec missing 'node_type' (or 'type')"]
	if not ClassDB.class_exists(n_type):
		return [null, "Unknown node type in child spec: %s" % n_type]
	var node: Node = ClassDB.instantiate(n_type) as Node
	if not node:
		return [null, "Failed to instantiate node of type: %s" % n_type]

	if not n_name.is_empty():
		node.name = n_name

	# SCRIPT FIRST, then properties. The other order looks harmless and is not:
	# a node's exported properties do not exist until its script is attached, so
	# `{script: "health.gd", properties: {max_health: 400}}` silently dropped
	# max_health and the node kept the default. Found by building a game with
	# these tools and wondering why a boss had 100 HP instead of 400.
	if not n_script.is_empty():
		n_script = _ensure_res_path(n_script)
		if PathGuard.is_bad(n_script):
			node.free()
			return [null, "Child script for '%s' escapes the project sandbox" % n_name]
		var s = load(n_script)
		if s:
			node.set_script(s)
		else:
			node.free()
			return [null, "Failed to load script for child '%s': %s" % [n_name, n_script]]

	_note_unknown_properties(node, _set_node_properties(node, props))

	for g in groups:
		var gname := str(g)
		if not gname.is_empty():
			node.add_to_group(gname, true)

	parent.add_child(node, true)
	node.owner = owner

	for child_data: Variant in children:
		if typeof(child_data) != TYPE_DICTIONARY:
			return [null, "Every entry in 'children' must be a Dictionary; got %s" % type_string(typeof(child_data))]
		var sub := _create_node_recursive(child_data, node, owner)
		if sub[1] != "":
			return sub
	return [node, ""]

func _count_nodes(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children():
		count += _count_nodes(child)
	return count

# =============================================================================
# read_scene
# =============================================================================
func read_scene(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var include_properties: bool = args.get(&"include_properties", false)
	# Ask for exactly the properties you need. `include_properties` is all-or-
	# nothing over a fixed list of twelve, which is both too much (a tree dump
	# with modulate and mass on every node) and too little (nothing else is
	# reachable). For a 2D game the first question is usually "where is
	# everything", and answering it used to mean one call per node.
	# Untyped on purpose: `var x: Array = args.get(...)` throws when the caller
	# sends a string, which kills the handler before the check below can run and
	# returns an empty dict — a guard that cannot fire is worse than none.
	var wanted_props = args.get(&"properties", [])
	if not (wanted_props is Array):
		return {&"ok": false, &"error": "'properties' must be an array of property names, e.g. [\"position\", \"visible\"]"}
	# Cap recursion so a big scene doesn't return a giant tree; a depth-limited node
	# reports children_truncated instead of expanding. -1 = full (default, unchanged).
	var max_depth: int = int(args.get(&"max_depth", -1))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path' parameter"}

	# A read has to see the LIVE tree when the scene is open, or it reports the
	# last-saved state: an agent that edits and then reads back gets stale values
	# and cannot tell. _discard_scene is a no-op on the live root, so the frees
	# below stay correct on both paths.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]

	# Read one branch instead of the whole tree. max_depth makes a big scene
	# cheap by cutting it off at the top; this makes it cheap by starting
	# lower, which is the question an agent usually has ("what is under
	# Player?") and used to cost the entire scene to answer.
	var node_path: String = str(args.get(&"node_path", ".")).strip_edges()
	if node_path.is_empty():
		node_path = "."
	var subject: Node = root
	if node_path != ".":
		subject = _find_node(root, node_path)
		if subject == null:
			var err := _node_not_found(root, node_path)
			_discard_scene(root, is_live)
			return err

	var structure = _build_node_structure(subject, include_properties, node_path, max_depth, 0, wanted_props)
	_discard_scene(root, is_live)

	var out := {&"ok": true, &"scene_path": scene_path, &"max_depth": max_depth, &"root": structure}
	if node_path != ".":
		# Say what was read. Without this the answer looks like a whole scene
		# whose root happens to be a Sprite2D.
		out[&"read_from"] = node_path
	return out

func _build_node_structure(node: Node, include_props: bool, path: String = ".", max_depth: int = -1, depth: int = 0, wanted_props: Array = []) -> Dictionary:
	const PROPERTIES: PackedStringArray = ["position", "rotation", "scale", "size", "offset", "visible",
			"modulate", "z_index", "text", "collision_layer", "collision_mask", "mass"]
	var data := {&"name": str(node.name), &"type": node.get_class(), &"path": path, &"children": []}
	if not node.scene_file_path.is_empty() and path != ".":
		data[&"instance"] = node.scene_file_path
	var script = node.get_script()
	if script:
		data[&"script"] = script.resource_path

	if include_props or not wanted_props.is_empty():
		# An explicit list wins: it is a narrower question and answering it with
		# the twelve-property default would defeat the point.
		var names: Array = wanted_props if not wanted_props.is_empty() else Array(PROPERTIES)
		var props := {}
		var missing: Array = []
		for prop_name_v in names:
			var prop_name := str(prop_name_v)
			# `in` distinguishes "the node has no such property" from "it is set
			# to null" — asking for a typo used to look like a null value.
			if not (prop_name in node):
				if not wanted_props.is_empty():
					missing.append(prop_name)
				continue
			var val = node.get(prop_name)
			if val != null:
				props[prop_name] = _serialize_value(val)
		if not props.is_empty():
			data[&"properties"] = props
		if not missing.is_empty():
			data[&"missing_properties"] = missing

	if max_depth >= 0 and depth >= max_depth:
		var kids := node.get_child_count()
		if kids > 0:
			data[&"children_truncated"] = kids
		return data

	for child: Node in node.get_children():
		var child_path = child.name if path == "." else path + "/" + child.name
		data[&"children"].append(_build_node_structure(child, include_props, child_path, max_depth, depth + 1, wanted_props))
	return data

# =============================================================================
# add_node
# =============================================================================
func add_node(args: Dictionary) -> Dictionary:
	_clear_warnings()
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_name: String = str(args.get(&"node_name", ""))
	var node_type: String = str(args.get(&"node_type", "Node"))
	var parent_path: String = str(args.get(&"parent_path", "."))
	var properties: Dictionary = args.get(&"properties", {})
	var script_path: String = str(args.get(&"script", ""))
	var children: Array = args.get(&"children", [])
	var groups: Array = args.get(&"groups", [])
	var dry_run: bool = bool(args.get(&"dry_run", false))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if node_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'node_name'"}
	if not ClassDB.class_exists(node_type):
		return {&"ok": false, &"error": "Invalid node type: " + node_type}

	# If the scene is open in the editor, mutate the live tree (undoable, no
	# clobber of unsaved edits) instead of the disk load→save path below.
	var live_root := _edited_root_if_open(scene_path)
	if live_root != null and not dry_run:
		return _add_node_live(live_root, scene_path, node_name, node_type, parent_path, properties, script_path, children, groups)

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var parent = _find_node(root, parent_path)
	if not parent:
		var err := _node_not_found(root, parent_path, "Parent node")
		root.queue_free()
		return err

	var new_node: Node = ClassDB.instantiate(node_type) as Node
	if not new_node:
		root.queue_free()
		return {&"ok": false, &"error": "Failed to create node of type: " + node_type}

	new_node.name = node_name

	# Script before properties — an exported property does not exist until the
	# script is on the node. See _create_node_recursive for the incident.
	if not script_path.is_empty():
		script_path = _ensure_res_path(script_path)
		if PathGuard.is_bad(script_path):
			root.queue_free()
			return {&"ok": false, &"error": "script escapes the project sandbox"}
		var s := load(script_path)
		if s:
			new_node.set_script(s)
		else:
			root.queue_free()
			return {&"ok": false, &"error": "Failed to load script: " + script_path}

	_note_unknown_properties(new_node, _set_node_properties(new_node, properties))

	for g in groups:
		var gname := str(g)
		if not gname.is_empty():
			new_node.add_to_group(gname, true)

	parent.add_child(new_node, true)
	new_node.owner = root

	var added_descendants: int = 0
	for child_data: Variant in children:
		if typeof(child_data) != TYPE_DICTIONARY:
			root.queue_free()
			return {&"ok": false, &"error": "Every entry in 'children' must be a Dictionary; got %s" % type_string(typeof(child_data))}
		var created_pair := _create_node_recursive(child_data, new_node, root)
		if created_pair[1] != "":
			root.queue_free()
			return {&"ok": false, &"error": "add_node: %s" % String(created_pair[1])}
		if created_pair[0] != null:
			added_descendants += _count_nodes(created_pair[0])

	if dry_run:
		root.queue_free()
		return {&"ok": true, &"dry_run": true, &"scene_path": scene_path, &"node_name": new_node.name,
			&"node_type": node_type, &"descendants_added": added_descendants,
			&"message": "Preview: would add %s (%s)%s to scene. Call again with dry_run=false to save." % [new_node.name, node_type,
				(" with %d descendant(s)" % added_descendants) if added_descendants > 0 else ""]}

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return _with_warnings({&"ok": true, &"scene_path": scene_path, &"node_name": new_node.name, &"node_type": node_type,
		&"descendants_added": added_descendants,
		&"message": "Added %s (%s) to scene%s" % [new_node.name, node_type,
			(" with %d descendant(s)" % added_descendants) if added_descendants > 0 else ""]})

# =============================================================================
# remove_node
# =============================================================================
func remove_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", ""))
	var dry_run: bool = bool(args.get(&"dry_run", false))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if node_path.strip_edges().is_empty() or node_path == ".":
		return {&"ok": false, &"error": "Cannot remove root node"}

	var live_root := _edited_root_if_open(scene_path)
	if live_root != null and not dry_run:
		return _remove_node_live(live_root, scene_path, node_path)

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target = root.get_node_or_null(node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		root.queue_free()
		return err

	var n_name = target.name
	var n_type = target.get_class()
	var n_child_count = target.get_child_count()

	if dry_run:
		root.queue_free()
		return {&"ok": true, &"dry_run": true, &"scene_path": scene_path, &"node_path": node_path,
			&"would_remove": {&"name": n_name, &"type": n_type, &"child_count": n_child_count},
			&"message": "Preview: would remove %s (%s) with %d child node(s). Call again with dry_run=false to save." % [n_name, n_type, n_child_count]}

	target.get_parent().remove_child(target)
	target.queue_free()

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"removed_node": node_path,
		&"message": "Removed %s (%s)" % [n_name, n_type]}

# =============================================================================
# modify_node_property
# =============================================================================
## Thin wrapper around set_node_properties for the single-property case.
## Delegating (instead of duplicating the load/set/save logic here) is a
## deliberate fix: this function used to have its own copy of that logic,
## which silently failed to persist boolean `false` values (target.set()
## visibly succeeded in-memory but the .tscn save never captured it) despite
## being structurally identical to set_node_properties' version. Cause not
## fully root-caused; delegating sidesteps it entirely and removes the
## duplication.
func modify_node_property(args: Dictionary) -> Dictionary:
	var property_name: String = str(args.get(&"property_name", ""))
	var value = args.get(&"value")

	if str(args.get(&"scene_path", "")).strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if property_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'property_name'"}
	if not args.has(&"value"):
		return {&"ok": false, &"error": "Missing 'value'"}
	if property_name == "script":
		return {&"ok": false, &"error": "Use attach_script to set or change a node's script. modify_node_property only edits the .tscn on disk, leaving the editor's in-memory node without the script (which breaks connect_signal and other tools that validate against the live node)."}

	var dry_run: bool = bool(args.get(&"dry_run", false))
	var inner_properties: Dictionary = {}
	inner_properties[property_name] = value
	var batch_result := set_node_properties({
		&"scene_path": args.get(&"scene_path", ""),
		&"node_path": args.get(&"node_path", "."),
		&"properties": inner_properties,
		&"dry_run": dry_run,
	})

	if not batch_result.get(&"ok", false):
		return batch_result

	var failed: Array = batch_result.get(&"failed", [])
	if not failed.is_empty():
		return {&"ok": false, &"error": str(failed[0].get(&"reason", "Failed to set property"))}

	var applied: Array = batch_result.get(&"applied", [])
	var entry: Dictionary = applied[0] if not applied.is_empty() else {}

	var out := {&"ok": true, &"scene_path": batch_result.get(&"scene_path"), &"node_path": batch_result.get(&"node_path"),
		&"property_name": property_name, &"old_value": entry.get(&"old"), &"new_value": entry.get(&"new"),
		&"message": "Set %s.%s = %s" % [batch_result.get(&"node_path"), property_name, str(entry.get(&"new"))]}
	if dry_run:
		out[&"dry_run"] = true
		out[&"message"] = "Preview: would set %s.%s = %s. Call again with dry_run=false to save." % [batch_result.get(&"node_path"), property_name, str(entry.get(&"new"))]
	return out

# =============================================================================
# rename_node
# =============================================================================
func rename_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", ""))
	var new_name: String = str(args.get(&"new_name", ""))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if node_path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'node_path'"}
	if new_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'new_name'"}

	var live_root := _edited_root_if_open(scene_path)
	if live_root != null:
		return _rename_node_live(live_root, node_path, new_name)

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target = _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		root.queue_free()
		return err

	var old_name = target.name
	target.name = new_name

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {&"ok": true, &"old_name": str(old_name), &"new_name": new_name,
		&"message": "Renamed '%s' to '%s'" % [old_name, new_name]}

# =============================================================================
# move_node
# =============================================================================
func move_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", ""))
	var new_parent_path: String = str(args.get(&"new_parent_path", "."))
	var sibling_index: int = int(args.get(&"sibling_index", -1))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if node_path.strip_edges().is_empty() or node_path == ".":
		return {&"ok": false, &"error": "Cannot move root node"}

	var live_root := _edited_root_if_open(scene_path)
	if live_root != null:
		return _move_node_live(live_root, node_path, new_parent_path, sibling_index)

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target = root.get_node_or_null(node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		root.queue_free()
		return err

	var new_parent = _find_node(root, new_parent_path)
	if not new_parent:
		var err := _node_not_found(root, new_parent_path, "New parent")
		root.queue_free()
		return err

	# Clear the owner before reparenting so add_child doesn't warn about an owner
	# that isn't an ancestor of the new location yet; re-own the whole subtree after.
	target.owner = null
	target.get_parent().remove_child(target)
	new_parent.add_child(target)
	_set_owner_recursive(target, root)

	if sibling_index >= 0:
		new_parent.move_child(target, mini(sibling_index, new_parent.get_child_count() - 1))

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {&"ok": true, &"message": "Moved '%s' to '%s'" % [node_path, new_parent_path]}

# =============================================================================
# duplicate_node
# =============================================================================
func duplicate_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", ""))
	var new_name: String = str(args.get(&"new_name", ""))
	var dry_run: bool = bool(args.get(&"dry_run", false))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if node_path.strip_edges().is_empty() or node_path == ".":
		return {&"ok": false, &"error": "Cannot duplicate root node"}

	var live_root := _edited_root_if_open(scene_path)
	if live_root != null and not dry_run:
		return _duplicate_node_live(live_root, node_path, new_name)

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root: Node = result[0]
	var target = root.get_node_or_null(node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		root.queue_free()
		return err

	var parent = target.get_parent()
	if not parent:
		root.queue_free()
		return {&"ok": false, &"error": "Cannot duplicate - no parent"}

	if new_name.is_empty():
		var base_name = target.name
		var counter = 2
		new_name = base_name + str(counter)
		while parent.has_node(NodePath(new_name)):
			counter += 1
			new_name = base_name + str(counter)

	if dry_run:
		var src_name := str(target.name)
		var src_type := target.get_class()
		var src_children := target.get_child_count()
		root.queue_free()
		return {&"ok": true, &"dry_run": true, &"scene_path": scene_path, &"node_path": node_path,
			&"new_name": new_name,
			&"would_duplicate": {&"name": src_name, &"type": src_type, &"child_count": src_children},
			&"message": "Preview: would duplicate %s (%s) with %d child node(s) as '%s'. Call again with dry_run=false to save." % [node_path, src_type, src_children, new_name]}

	var duplicate = target.duplicate()
	duplicate.name = new_name
	parent.add_child(duplicate)
	
	_set_owner_recursive(duplicate, root)
	
	var original_index = target.get_index()
	parent.move_child(duplicate, original_index + 1)

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {&"ok": true, &"new_name": new_name,
		&"message": "Duplicated '%s' as '%s'" % [node_path, new_name]}


func _set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child: Node in node.get_children():
		_set_owner_recursive(child, owner)

# =============================================================================
# Live-scene structural edits (add/remove/rename/move/duplicate on the OPEN scene)
# =============================================================================
## When the target scene is the one open in the editor, structural edits must go
## through the live tree + EditorUndoRedoManager instead of the disk load→save
## path — otherwise the save silently clobbers the user's unsaved edits (same
## hazard the property path already fixed). These helpers are used as undo/redo
## methods so the whole subtree (owners included) round-trips correctly.

## add_child + owner-set the whole subtree so it persists in the saved scene.
func _attach_node_owned(parent: Node, node: Node, owner: Node) -> void:
	parent.add_child(node, true)
	_set_owner_recursive(node, owner)

## Same, but placed at a specific child index (undo of remove, redo of duplicate).
func _attach_node_at(parent: Node, node: Node, owner: Node, index: int) -> void:
	parent.add_child(node, true)
	_set_owner_recursive(node, owner)
	if index >= 0:
		parent.move_child(node, mini(index, parent.get_child_count() - 1))

## Reparent a node (works as both the do and the undo of a move).
func _reparent_node(node: Node, new_parent: Node, owner: Node, index: int) -> void:
	var cur := node.get_parent()
	if cur:
		cur.remove_child(node)
	new_parent.add_child(node, true)
	_set_owner_recursive(node, owner)
	if index >= 0:
		new_parent.move_child(node, mini(index, new_parent.get_child_count() - 1))

func _add_node_live(root: Node, scene_path: String, node_name: String, node_type: String, parent_path: String, properties: Dictionary, script_path: String, children: Array, groups: Array) -> Dictionary:
	var parent := _find_node(root, parent_path)
	if not parent:
		return _node_not_found(root, parent_path, "Parent node")
	var new_node: Node = ClassDB.instantiate(node_type) as Node
	if not new_node:
		return {&"ok": false, &"error": "Failed to create node of type: " + node_type}
	new_node.name = node_name
	# Script before properties — see _create_node_recursive.
	if not script_path.is_empty():
		var sp := _ensure_res_path(script_path)
		if PathGuard.is_bad(sp):
			new_node.free()
			return {&"ok": false, &"error": "script escapes the project sandbox"}
		var s = load(sp)
		if not s:
			new_node.free()
			return {&"ok": false, &"error": "Failed to load script: " + sp}
		new_node.set_script(s)
	_note_unknown_properties(new_node, _set_node_properties(new_node, properties))
	for g in groups:
		var gname := str(g)
		if not gname.is_empty():
			new_node.add_to_group(gname, true)
	var added_descendants := 0
	for child_data: Variant in children:
		if typeof(child_data) != TYPE_DICTIONARY:
			new_node.free()
			return {&"ok": false, &"error": "Every entry in 'children' must be a Dictionary; got %s" % type_string(typeof(child_data))}
		# owner is set by _attach_node_owned once new_node is in the tree
		var created_pair := _create_node_recursive(child_data, new_node, null)
		if created_pair[1] != "":
			new_node.free()
			return {&"ok": false, &"error": "add_node: %s" % String(created_pair[1])}
		if created_pair[0] != null:
			added_descendants += _count_nodes(created_pair[0])
	var ur := _get_undo_redo()
	if ur:
		# custom_context pins the action to the edited scene's history. Without it
		# EditorUndoRedoManager infers the history from the FIRST object it sees —
		# which here is `self`, a tool node living under the EditorPlugin, not in
		# the scene. The entry then lands in the global history where Ctrl+Z on
		# the scene never reaches it.
		ur.create_action("MCP: add %s" % node_name, UndoRedo.MERGE_DISABLE, root)
		ur.add_do_method(self, &"_attach_node_owned", parent, new_node, root)
		ur.add_do_reference(new_node)
		ur.add_undo_method(parent, &"remove_child", new_node)
		ur.commit_action()
	else:
		_attach_node_owned(parent, new_node, root)
	return {&"ok": true, &"scene_path": scene_path, &"node_name": new_node.name, &"node_type": node_type,
		&"descendants_added": added_descendants, &"live_editor_scene": true,
		&"message": "Added %s (%s) to open scene%s (undoable)" % [new_node.name, node_type,
			(" with %d descendant(s)" % added_descendants) if added_descendants > 0 else ""]}

func _remove_node_live(root: Node, scene_path: String, node_path: String) -> Dictionary:
	var target := root.get_node_or_null(node_path)
	if not target:
		return _node_not_found(root, node_path)
	if target == root:
		return {&"ok": false, &"error": "Cannot remove root node"}
	var parent := target.get_parent()
	var n_name = target.name
	var n_type := target.get_class()
	var index := target.get_index()
	var ur := _get_undo_redo()
	if ur:
		ur.create_action("MCP: remove %s" % n_name, UndoRedo.MERGE_DISABLE, root)
		ur.add_do_method(parent, &"remove_child", target)
		ur.add_undo_method(self, &"_attach_node_at", parent, target, root, index)
		ur.add_undo_reference(target)
		ur.commit_action()
	else:
		parent.remove_child(target)
		target.queue_free()
	return {&"ok": true, &"scene_path": scene_path, &"removed_node": node_path, &"live_editor_scene": true,
		&"message": "Removed %s (%s) from open scene (undoable)" % [n_name, n_type]}

func _rename_node_live(root: Node, node_path: String, new_name: String) -> Dictionary:
	var target := _find_node(root, node_path)
	if not target:
		return _node_not_found(root, node_path)
	var old_name = target.name
	var ur := _get_undo_redo()
	if ur:
		ur.create_action("MCP: rename %s" % old_name, UndoRedo.MERGE_DISABLE, root)
		ur.add_do_property(target, &"name", new_name)
		ur.add_undo_property(target, &"name", old_name)
		ur.commit_action()
	else:
		target.name = new_name
	return {&"ok": true, &"old_name": str(old_name), &"new_name": new_name, &"live_editor_scene": true,
		&"message": "Renamed '%s' to '%s' in open scene (undoable)" % [old_name, new_name]}

func _move_node_live(root: Node, node_path: String, new_parent_path: String, sibling_index: int) -> Dictionary:
	var target := root.get_node_or_null(node_path)
	if not target:
		return _node_not_found(root, node_path)
	if target == root:
		return {&"ok": false, &"error": "Cannot move root node"}
	var new_parent := _find_node(root, new_parent_path)
	if not new_parent:
		return _node_not_found(root, new_parent_path, "New parent")
	var old_parent := target.get_parent()
	var old_index := target.get_index()
	var ur := _get_undo_redo()
	if ur:
		ur.create_action("MCP: move %s" % target.name, UndoRedo.MERGE_DISABLE, root)
		ur.add_do_method(self, &"_reparent_node", target, new_parent, root, sibling_index)
		ur.add_undo_method(self, &"_reparent_node", target, old_parent, root, old_index)
		ur.commit_action()
	else:
		_reparent_node(target, new_parent, root, sibling_index)
	return {&"ok": true, &"live_editor_scene": true,
		&"message": "Moved '%s' to '%s' in open scene (undoable)" % [node_path, new_parent_path]}

func _duplicate_node_live(root: Node, node_path: String, new_name: String) -> Dictionary:
	var target := root.get_node_or_null(node_path)
	if not target:
		return _node_not_found(root, node_path)
	if target == root:
		return {&"ok": false, &"error": "Cannot duplicate root node"}
	var parent := target.get_parent()
	if not parent:
		return {&"ok": false, &"error": "Cannot duplicate - no parent"}
	if new_name.is_empty():
		var base_name = target.name
		var counter := 2
		new_name = base_name + str(counter)
		while parent.has_node(NodePath(new_name)):
			counter += 1
			new_name = base_name + str(counter)
	var dup := target.duplicate()
	dup.name = new_name
	var index := target.get_index() + 1
	var ur := _get_undo_redo()
	if ur:
		ur.create_action("MCP: duplicate %s" % target.name, UndoRedo.MERGE_DISABLE, root)
		ur.add_do_method(self, &"_attach_node_at", parent, dup, root, index)
		ur.add_do_reference(dup)
		ur.add_undo_method(parent, &"remove_child", dup)
		ur.commit_action()
	else:
		_attach_node_at(parent, dup, root, index)
	return {&"ok": true, &"new_name": new_name, &"live_editor_scene": true,
		&"message": "Duplicated '%s' as '%s' in open scene (undoable)" % [node_path, new_name]}


# =============================================================================
# batch_scene_edit — many edits to ONE scene with a single load + single save
# =============================================================================
## Apply a list of structural/property edits to one scene, loading it ONCE and
## saving ONCE — instead of the N load+save round-trips you'd get from N separate
## add_node/set_node_properties/... calls on a closed scene. For an OPEN scene the
## whole batch lands on the live tree and marks it dirty (no disk write at all).
## Ops run in order against the shared tree; `stop_on_error` discards the whole
## batch (nothing saved) on the first failure. Supported op types: add_node,
## set_properties, remove_node, rename_node, move_node.
func batch_scene_edit(args: Dictionary) -> Dictionary:
	_clear_warnings()
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var operations: Array = args.get(&"operations", [])
	var stop_on_error: bool = bool(args.get(&"stop_on_error", true))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if operations.is_empty():
		return {&"ok": false, &"error": "Missing 'operations' (non-empty array of {op, ...})"}

	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]

	# The whole batch is ONE undo entry: it is presented as a single atomic edit,
	# so Ctrl+Z should take all of it back, not unwind it op by op.
	var ctx := _begin_edit(is_live, "MCP: batch edit %s" % scene_path.get_file(), root)
	ctx[&"live"] = is_live

	var results: Array = []
	var applied := 0
	var all_ok := true
	for op_v in operations:
		if typeof(op_v) != TYPE_DICTIONARY:
			results.append({&"ok": false, &"error": "Each operation must be an object with an 'op' field"})
			all_ok = false
			if stop_on_error:
				_abort_edit(ctx, root, is_live)
				return {&"ok": false, &"error": "Operation %d is not an object; batch discarded" % results.size(), &"results": results}
			continue
		var r := _apply_op(root, op_v, ctx)
		results.append(r)
		if r.get(&"ok", false):
			applied += 1
		else:
			all_ok = false
			if stop_on_error:
				_abort_edit(ctx, root, is_live)
				return {&"ok": false, &"scene_path": scene_path,
					&"error": "Op %d (%s) failed: %s — batch discarded, nothing saved" % [results.size() - 1, str(op_v.get(&"op", "?")), str(r.get(&"error", ""))],
					&"results": results}

	_edit_commit(ctx)
	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return _with_warnings({&"ok": true, &"scene_path": scene_path, &"live_editor_scene": is_live,
		&"operations_run": results.size(), &"applied": applied, &"all_ok": all_ok,
		&"results": results,
		&"message": "Applied %d/%d edit(s) to %s with a single %s" % [applied, results.size(), scene_path, "live-tree update" if is_live else "load+save"]})

## Detach a node without freeing it. Paired with _attach_node_at as the undo of a
## batch remove; the node stays alive through the undo entry's reference.
func _detach_node(parent: Node, node: Node) -> void:
	if is_instance_valid(parent) and is_instance_valid(node) and node.get_parent() == parent:
		parent.remove_child(node)

## Apply one batch operation to an already-loaded scene root. Mutates in place, no
## load/save. Returns a per-op {ok, ...} result. Mirrors the standalone tools but
## without their own disk round-trip so batch_scene_edit can share one load+save.
func _apply_op(root: Node, op: Dictionary, ctx: Dictionary) -> Dictionary:
	var kind := str(op.get(&"op", ""))
	match kind:
		"add_node":
			var parent := _find_node(root, str(op.get(&"parent_path", ".")))
			if not parent:
				return {&"ok": false, &"op": kind, &"error": "Parent not found: " + str(op.get(&"parent_path", "."))}
			var node_type := str(op.get(&"node_type", "Node"))
			if not ClassDB.class_exists(node_type):
				return {&"ok": false, &"op": kind, &"error": "Invalid node_type: " + node_type}
			var n: Node = ClassDB.instantiate(node_type) as Node
			if not n:
				return {&"ok": false, &"op": kind, &"error": "Failed to create " + node_type}
			n.name = str(op.get(&"node_name", node_type))
			# Script before properties — see _create_node_recursive.
			var script_path := str(op.get(&"script", ""))
			if not script_path.is_empty():
				var sp := _ensure_res_path(script_path)
				var s = load(sp) if not PathGuard.is_bad(sp) else null
				if s:
					n.set_script(s)
				else:
					n.free()
					return {&"ok": false, &"op": kind, &"error": "Failed to load script: " + script_path}
			_note_unknown_properties(n, _set_node_properties(n, op.get(&"properties", {})))
			for g in op.get(&"groups", []):
				if not str(g).is_empty():
					n.add_to_group(str(g), true)
			_edit_add_child(ctx, parent, n, root)
			_set_owner_recursive(n, root)
			for child_data in op.get(&"children", []):
				if typeof(child_data) == TYPE_DICTIONARY:
					var made := _create_node_recursive(child_data, n, root)
					if made[1] != "":
						return {&"ok": false, &"op": kind, &"error": String(made[1])}
			return {&"ok": true, &"op": kind, &"node_name": n.name}
		"set_properties":
			var t := _find_node(root, str(op.get(&"node_path", ".")))
			if not t:
				return {&"ok": false, &"op": kind, &"error": "Node not found: " + str(op.get(&"node_path", "."))}
			_edit_set_many(ctx, t, op.get(&"properties", {}))
			return {&"ok": true, &"op": kind, &"node_path": str(op.get(&"node_path", "."))}
		"remove_node":
			var np := str(op.get(&"node_path", ""))
			if np.is_empty() or np == ".":
				return {&"ok": false, &"op": kind, &"error": "Cannot remove root"}
			var t2 := root.get_node_or_null(np)
			if not t2:
				return {&"ok": false, &"op": kind, &"error": "Node not found: " + np}
			var t2_parent := t2.get_parent()
			var t2_index := t2.get_index()
			t2_parent.remove_child(t2)
			# Undo has to be able to put it back, so the node cannot be freed on
			# the live path — the undo entry holds the only remaining reference.
			if bool(ctx.get(&"live", false)):
				_edit_record(ctx, self, &"_detach_node", [t2_parent, t2],
					&"_attach_node_at", [t2_parent, t2, root, t2_index])
				var ur_ref: EditorUndoRedoManager = ctx.get(&"ur")
				if ur_ref:
					ur_ref.add_undo_reference(t2)
			else:
				t2.queue_free()
			return {&"ok": true, &"op": kind, &"removed": np}
		"rename_node":
			var t3 := _find_node(root, str(op.get(&"node_path", "")))
			if not t3:
				return {&"ok": false, &"op": kind, &"error": "Node not found: " + str(op.get(&"node_path", ""))}
			var new_name := str(op.get(&"new_name", ""))
			if new_name.is_empty():
				return {&"ok": false, &"op": kind, &"error": "Missing new_name"}
			_edit_set(ctx, t3, &"name", new_name)
			return {&"ok": true, &"op": kind, &"new_name": new_name}
		"move_node":
			var t4 := root.get_node_or_null(str(op.get(&"node_path", "")))
			if not t4:
				return {&"ok": false, &"op": kind, &"error": "Node not found: " + str(op.get(&"node_path", ""))}
			var new_parent := _find_node(root, str(op.get(&"new_parent_path", ".")))
			if not new_parent:
				var np_err := _node_not_found(root, str(op.get(&"new_parent_path", ".")), "New parent")
				return {&"ok": false, &"op": kind, &"error": str(np_err.get(&"error", "New parent not found"))}
			var old_parent_b := t4.get_parent()
			var old_index_b := t4.get_index()
			_reparent_node(t4, new_parent, root, int(op.get(&"sibling_index", -1)))
			_edit_record(ctx, self, &"_reparent_node", [t4, new_parent, root, int(op.get(&"sibling_index", -1))],
				&"_reparent_node", [t4, old_parent_b, root, old_index_b])
			return {&"ok": true, &"op": kind, &"moved": str(op.get(&"node_path", ""))}
		_:
			return {&"ok": false, &"op": kind, &"error": "Unknown op '%s' (use add_node, set_properties, remove_node, rename_node, move_node)" % kind}


# =============================================================================
# set_anchor_preset
# =============================================================================
const _ANCHOR_PRESETS := {
	"top_left": Control.PRESET_TOP_LEFT,
	"top_right": Control.PRESET_TOP_RIGHT,
	"bottom_left": Control.PRESET_BOTTOM_LEFT,
	"bottom_right": Control.PRESET_BOTTOM_RIGHT,
	"center_left": Control.PRESET_CENTER_LEFT,
	"center_top": Control.PRESET_CENTER_TOP,
	"center_right": Control.PRESET_CENTER_RIGHT,
	"center_bottom": Control.PRESET_CENTER_BOTTOM,
	"center": Control.PRESET_CENTER,
	"top_wide": Control.PRESET_TOP_WIDE,
	"bottom_wide": Control.PRESET_BOTTOM_WIDE,
	"left_wide": Control.PRESET_LEFT_WIDE,
	"right_wide": Control.PRESET_RIGHT_WIDE,
	"vcenter_wide": Control.PRESET_VCENTER_WIDE,
	"hcenter_wide": Control.PRESET_HCENTER_WIDE,
	"full_rect": Control.PRESET_FULL_RECT,
}

func set_anchor_preset(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var preset_name: String = str(args.get(&"preset", "")).to_lower()
	var keep_offsets: bool = bool(args.get(&"keep_offsets", false))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if not _ANCHOR_PRESETS.has(preset_name):
		return {&"ok": false, &"error": "Invalid 'preset': %s. Valid presets: %s" % [preset_name, ", ".join(_ANCHOR_PRESETS.keys())]}

	# _acquire_scene, not _load_scene: on an OPEN scene, loading a disk copy and
	# saving it back discards the editor's unsaved state and the reload that
	# follows wipes the live tree with it.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var target = _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err
	if not (target is Control):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) is not a Control" % [node_path, target.get_class()]}

	var control: Control = target
	control.set_anchors_preset(_ANCHOR_PRESETS[preset_name], keep_offsets)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path, &"preset": preset_name,
		&"message": "Applied anchor preset '%s' to '%s'" % [preset_name, node_path]}


# =============================================================================
# reorder_node - simpler function just for changing sibling order
# =============================================================================
func reorder_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", ""))
	var new_index: int = int(args.get(&"new_index", -1))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if node_path.strip_edges().is_empty() or node_path == ".":
		return {&"ok": false, &"error": "Cannot reorder root node"}

	# _acquire_scene, not _load_scene: on an OPEN scene, loading a disk copy and
	# saving it back discards the editor's unsaved state and the reload that
	# follows wipes the live tree with it.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var target = root.get_node_or_null(node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err

	var parent = target.get_parent()
	if not parent:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Cannot reorder - no parent"}

	var old_index = target.get_index()
	var max_index = parent.get_child_count() - 1
	new_index = clampi(new_index, 0, max_index)
	
	if old_index == new_index:
		_discard_scene(root, is_live)
		return {&"ok": true, &"message": "No change needed"}

	parent.move_child(target, new_index)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"old_index": old_index, &"new_index": new_index,
		&"message": "Moved '%s' from index %d to %d" % [node_path, old_index, new_index]}


# =============================================================================
# attach_script
# =============================================================================
func attach_script(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var script_path: String = str(args.get(&"script_path", ""))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if script_path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'script_path'"}
	script_path = _ensure_res_path(script_path)
	if PathGuard.is_bad(script_path):
		return {&"ok": false, &"error": "script_path escapes the project sandbox"}

	# _acquire_scene, not _load_scene: when the target scene is OPEN, loading a
	# disk copy and saving it back throws away whatever is unsaved in the editor,
	# and the reload that follows wipes the live tree with it. Verified against a
	# real project — this call used to destroy an unsaved node outright.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]

	var target = _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err

	var script_res = load(script_path)
	if not script_res:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Failed to load script: " + script_path}

	var ctx := _begin_edit(is_live, "MCP: attach script to %s" % node_path, root)
	_edit_set(ctx, target, &"script", script_res)
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"live_editor_scene": is_live,
		&"message": "Attached %s to node '%s'" % [script_path, node_path]}

# =============================================================================
# detach_script
# =============================================================================
func detach_script(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}

	# _acquire_scene, not _load_scene: on an OPEN scene, loading a disk copy and
	# saving it back discards the editor's unsaved state and the reload that
	# follows wipes the live tree with it.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var target = _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err

	target.set_script(null)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"message": "Detached script from node '%s'" % node_path}

# =============================================================================
# set_collision_shape
# =============================================================================
func set_collision_shape(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var shape_type: String = str(args.get(&"shape_type", ""))
	var shape_params: Dictionary = args.get(&"shape_params", {})

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if shape_type.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'shape_type'"}
	if not ClassDB.class_exists(shape_type):
		# Two tools in this repo take a `shape_type` and accept different
		# vocabularies: setup_collision wants "rectangle"/"circle"/"box"/"sphere",
		# this one wants the Godot class name. Passing the other spelling used to
		# give a bare "Invalid shape type: rectangle" with no hint that a
		# different word was expected, let alone which.
		var suggestion := _SHAPE_ALIASES.get(shape_type.to_lower(), "")
		var msg := "Invalid 'shape_type': '%s'. This tool takes a Godot class name" % shape_type
		if suggestion != "":
			msg += " — did you mean '%s'? ('%s' is setup_collision's spelling.)" % [suggestion, shape_type]
		msg += " Common 2D: RectangleShape2D, CircleShape2D, CapsuleShape2D. Common 3D: BoxShape3D, SphereShape3D, CapsuleShape3D."
		return {&"ok": false, &"error": msg}

	# _acquire_scene, not _load_scene: on an OPEN scene, loading a disk copy and
	# saving it back discards the editor's unsaved state and the reload that
	# follows wipes the live tree with it.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var target = _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err
	if not (&"shape" in target):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) has no 'shape' property — point node_path at a CollisionShape2D/3D" % [node_path, target.get_class()]}

	var shape = ClassDB.instantiate(shape_type)
	if not shape:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Failed to create shape: " + shape_type}

	if shape_params.has(&"radius"):
		shape.set("radius", float(shape_params[&"radius"]))
	if shape_params.has(&"height"):
		shape.set("height", float(shape_params[&"height"]))
	if shape_params.has(&"size"):
		shape.set("size", _parse_value(shape_params[&"size"]))

	target.set("shape", shape)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"message": "Set %s on node '%s'" % [shape_type, node_path]}

# =============================================================================
# set_sprite_texture
# =============================================================================
func set_sprite_texture(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var texture_type: String = str(args.get(&"texture_type", ""))
	var texture_params: Dictionary = args.get(&"texture_params", {})

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if texture_type.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'texture_type'"}

	# _acquire_scene, not _load_scene: on an OPEN scene, loading a disk copy and
	# saving it back discards the editor's unsaved state and the reload that
	# follows wipes the live tree with it.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var target = _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err
	if not (&"texture" in target):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) has no 'texture' property" % [node_path, target.get_class()]}

	var texture: Texture2D = null

	match texture_type:
		# Canonical name for "load whatever texture is at this path".
		# "ImageTexture" is kept as a deprecated alias for backward compat.
		"FromPath", "ImageTexture":
			var tex_path: String = str(texture_params.get(&"path", ""))
			if tex_path.is_empty():
				_discard_scene(root, is_live)
				return {&"ok": false, &"error": "Missing 'path' in texture_params for %s" % texture_type}
			tex_path = _ensure_res_path(tex_path)
			if PathGuard.is_bad(tex_path):
				_discard_scene(root, is_live)
				return {&"ok": false, &"error": "texture path escapes the project sandbox"}
			texture = load(tex_path)
			if not texture:
				_discard_scene(root, is_live)
				return {&"ok": false, &"error": "Failed to load texture: " + tex_path}

		# Real ImageTexture from raw image data on disk (use when you need
		# an in-memory ImageTexture rather than a CompressedTexture2D).
		"NewImageTexture":
			var src_path: String = str(texture_params.get(&"path", ""))
			if src_path.is_empty():
				_discard_scene(root, is_live)
				return {&"ok": false, &"error": "Missing 'path' in texture_params for NewImageTexture"}
			src_path = _ensure_res_path(src_path)
			if PathGuard.is_bad(src_path):
				_discard_scene(root, is_live)
				return {&"ok": false, &"error": "image path escapes the project sandbox"}
			var img := Image.new()
			var ierr := img.load(ProjectSettings.globalize_path(src_path))
			if ierr != OK:
				_discard_scene(root, is_live)
				return {&"ok": false, &"error": "Image.load failed for %s (err=%d %s)" % [src_path, ierr, error_string(ierr)]}
			texture = ImageTexture.create_from_image(img)

		"PlaceholderTexture2D":
			texture = PlaceholderTexture2D.new()
			var size_data = texture_params.get(&"size", {&"x": 64, &"y": 64})
			if typeof(size_data) == TYPE_DICTIONARY:
				texture.size = Vector2(size_data.get(&"x", 64), size_data.get(&"y", 64))

		"GradientTexture2D":
			texture = GradientTexture2D.new()
			texture.width = int(texture_params.get(&"width", 64))
			texture.height = int(texture_params.get(&"height", 64))

		"NoiseTexture2D":
			texture = NoiseTexture2D.new()
			texture.width = int(texture_params.get(&"width", 64))
			texture.height = int(texture_params.get(&"height", 64))

		_:
			_discard_scene(root, is_live)
			return {&"ok": false, &"error": "Unknown texture type: %s. Use one of: NewImageTexture (with texture_params.path), PlaceholderTexture2D, GradientTexture2D, NoiseTexture2D." % texture_type}

	target.set("texture", texture)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	# Report what the texture actually decodes to. For texture_type "FromPath"
	# (or its alias "ImageTexture"), Godot's importer typically returns a
	# CompressedTexture2D, NOT an ImageTexture — surfacing this here saves the
	# agent a round trip via get_resource_info.
	var resolved_class: String = texture.get_class() if texture else ""
	var tex_path: String = ""
	if texture_type in ["FromPath", "ImageTexture", "NewImageTexture"]:
		tex_path = str(texture_params.get(&"path", ""))

	return {
		&"ok": true,
		&"texture_type": texture_type,
		&"texture_class": resolved_class,
		&"texture_path": tex_path,
		&"width": texture.get_width() if texture else 0,
		&"height": texture.get_height() if texture else 0,
		&"message": "Set %s (%s) on node '%s'" % [texture_type, resolved_class, node_path],
	}

# =============================================================================
# instance_scene
# =============================================================================
func instance_scene(args: Dictionary) -> Dictionary:
	_clear_warnings()
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var instance_path: String = _ensure_res_path(str(args.get(&"instance_path", "")))
	var node_name: String = str(args.get(&"node_name", ""))
	var parent_path: String = str(args.get(&"parent_path", "."))
	var properties: Dictionary = args.get(&"properties", {})

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if instance_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'instance_path'"}
	if PathGuard.is_bad(instance_path):
		return {&"ok": false, &"error": "instance_path escapes the project sandbox"}

	if scene_path == instance_path:
		return {&"ok": false, &"error": "Cannot instance a scene inside itself (circular reference): " + instance_path}

	var instance_packed = load(instance_path) as PackedScene
	if not instance_packed:
		return {&"ok": false, &"error": "Failed to load scene: " + instance_path}

	# _acquire_scene, not _load_scene: on an OPEN scene, loading a disk copy and
	# saving it back discards the editor's unsaved state and the reload that
	# follows wipes the live tree with it.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var parent = _find_node(root, parent_path)
	if not parent:
		var err := _node_not_found(root, parent_path, "Parent node")
		_discard_scene(root, is_live)
		return err

	var instance = _instantiate_packed_scene_for_edit(instance_packed, true)
	if not instance:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Failed to instantiate scene: " + instance_path}

	if not node_name.strip_edges().is_empty():
		instance.name = node_name

	# No reordering needed here: an instanced scene arrives with its script
	# already attached, so its exported properties exist.
	_note_unknown_properties(instance, _set_node_properties(instance, properties))

	parent.add_child(instance, true)
	instance.owner = root

	var actual_name: String = instance.name

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return _with_warnings({&"ok": true, &"scene_path": scene_path, &"instance_path": instance_path,
		&"node_name": actual_name, &"node_type": instance.get_class(),
		&"message": "Instanced '%s' as '%s' in scene" % [instance_path, actual_name]})

# =============================================================================
# set_node_reference
# =============================================================================

## Point an exported property at another NODE in the same scene.
##
## The gap this fills: a property typed as a node — `@export var target: Area2D`,
## `@export var health: HealthComponent`, `@export var initial_state: State` —
## cannot be set through modify_node_property or set_node_properties. Those take
## a VALUE, and the value here is a live object, not something JSON can carry.
## Until this existed, the only way to wire one was dragging it in the inspector,
## which is not available to an agent — so a whole game's components had to be
## redesigned to discover each other at runtime instead of being wired in the
## scene. That is the tool bending the code, which is backwards.
##
## Handles both shapes automatically:
##   @export var x: SomeNode  → assigns the node object (Godot serialises the
##                              NodePath into the .tscn on save)
##   @export var x: NodePath  → assigns the path itself
func set_node_reference(args: Dictionary) -> Dictionary:
	_clear_warnings()
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var property: String = str(args.get(&"property", ""))
	var target_path: String = str(args.get(&"target_path", ""))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if property.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'property' (the exported property to point at a node)"}
	if target_path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'target_path' (the node to point it at, relative to the scene root)"}

	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]

	var node := _find_node(root, node_path)
	if not node:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err

	var target := _find_node(root, target_path)
	if not target:
		var err := _node_not_found(root, target_path, "Target node")
		_discard_scene(root, is_live)
		return err

	# The property has to actually exist, or this becomes the very silent-drop
	# bug it was written to avoid.
	var types := _property_type_map(node)
	if not types.has(property):
		_discard_scene(root, is_live)
		var known := PackedStringArray()
		for candidate in types:
			var t: int = int(types[candidate])
			if t == TYPE_OBJECT or t == TYPE_NODE_PATH:
				known.append(str(candidate))
		var hint := ""
		if known.size() > 0:
			hint = " Node-typed properties on this node: %s." % ", ".join(known)
		elif node.get_script() == null:
			hint = " The node has no script, so it has no exported node properties."
		else:
			hint = " Its script may not be compiled yet — try rescan_metadata or restart_editor."
		return {&"ok": false, &"error": "No property '%s' on '%s' (%s).%s" % [
			property, node_path, node.get_class(), hint]}

	var declared: int = int(types[property])
	var assigned: Variant = target
	if declared == TYPE_NODE_PATH:
		# Relative to the node holding the property, which is how Godot resolves
		# an exported NodePath — not relative to the scene root.
		assigned = node.get_path_to(target)
	node.set(property, assigned)

	# Read back rather than trust the set: assigning a node to a property typed
	# for a DIFFERENT node class silently does nothing, and that is exactly the
	# kind of failure this tool exists to stop reporting as success.
	var readback: Variant = node.get(property)
	var landed := false
	if declared == TYPE_NODE_PATH:
		landed = str(readback) == str(assigned)
	else:
		landed = readback == target
	if not landed:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Assignment did not take on '%s.%s'. The property is probably typed for a different node class than '%s' (%s)." % [
			node_path, property, target.name, target.get_class()]}

	var result := _finish_scene_edit(root, scene_path, is_live)
	if not result.is_empty() and result.get(&"ok", true) == false:
		return result

	return _with_warnings({
		&"ok": true,
		&"scene_path": scene_path,
		&"node_path": node_path,
		&"property": property,
		&"target_path": target_path,
		&"stored_as": "NodePath" if declared == TYPE_NODE_PATH else "node reference",
		&"live_editor_scene": is_live,
		&"message": "Pointed %s.%s at '%s'" % [node_path, property, target_path],
	})

# =============================================================================
# set_mesh
# =============================================================================
func set_mesh(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var mesh_type: String = str(args.get(&"mesh_type", ""))
	var mesh_params: Dictionary = args.get(&"mesh_params", {})

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if mesh_type.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'mesh_type'"}

	# _acquire_scene, not _load_scene: on an OPEN scene, loading a disk copy and
	# saving it back discards the editor's unsaved state and the reload that
	# follows wipes the live tree with it.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var target = _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err

	if not (target is MeshInstance3D):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' is %s, expected MeshInstance3D" % [node_path, target.get_class()]}

	var mesh: Mesh = null

	if mesh_type == "file":
		var file_path: String = str(mesh_params.get(&"path", ""))
		if file_path.is_empty():
			_discard_scene(root, is_live)
			return {&"ok": false, &"error": "Missing 'path' in mesh_params for file type"}
		file_path = _ensure_res_path(file_path)
		if PathGuard.is_bad(file_path):
			_discard_scene(root, is_live)
			return {&"ok": false, &"error": "mesh path escapes the project sandbox"}
		var loaded = load(file_path)
		if not loaded or not (loaded is Mesh):
			_discard_scene(root, is_live)
			return {&"ok": false, &"error": "Failed to load mesh resource (or not a Mesh): " + file_path}
		mesh = loaded
	else:
		# add_mesh_instance takes "box"/"sphere"/..., so a caller who built the
		# node with one of those writes the same word here. This took the Godot
		# class name only, and answered "Unknown mesh type: sphere" without
		# saying what it did want.
		var friendly := {
			"box": "BoxMesh", "sphere": "SphereMesh", "cylinder": "CylinderMesh",
			"plane": "PlaneMesh", "capsule": "CapsuleMesh", "torus": "TorusMesh",
			"quad": "QuadMesh", "prism": "PrismMesh",
		}
		if friendly.has(mesh_type.to_lower()):
			mesh_type = friendly[mesh_type.to_lower()]
		if not ClassDB.class_exists(mesh_type) or not ClassDB.is_parent_class(mesh_type, "Mesh"):
			_discard_scene(root, is_live)
			return {&"ok": false, &"error": "Unknown mesh type: %s. Use one of %s, a Mesh class name (BoxMesh, SphereMesh, ...), or \"file\" with mesh_params.path." % [mesh_type, ", ".join(PackedStringArray(friendly.keys()))]}
		if not ClassDB.can_instantiate(mesh_type):
			_discard_scene(root, is_live)
			return {&"ok": false, &"error": "Cannot instantiate mesh type: " + mesh_type}

		var instance = ClassDB.instantiate(mesh_type)
		if not (instance is PrimitiveMesh):
			if instance is Node:
				instance.queue_free()
			_discard_scene(root, is_live)
			return {&"ok": false, &"error": "'%s' is not a PrimitiveMesh type" % mesh_type}
		mesh = instance

		if mesh_params.has(&"radius"):
			mesh.set("radius", float(mesh_params[&"radius"]))
		if mesh_params.has(&"height"):
			mesh.set("height", float(mesh_params[&"height"]))
		if mesh_params.has(&"top_radius"):
			mesh.set("top_radius", float(mesh_params[&"top_radius"]))
		if mesh_params.has(&"bottom_radius"):
			mesh.set("bottom_radius", float(mesh_params[&"bottom_radius"]))
		if mesh_params.has(&"inner_radius"):
			mesh.set("inner_radius", float(mesh_params[&"inner_radius"]))
		if mesh_params.has(&"outer_radius"):
			mesh.set("outer_radius", float(mesh_params[&"outer_radius"]))
		if mesh_params.has(&"radial_segments"):
			mesh.set("radial_segments", int(mesh_params[&"radial_segments"]))
		if mesh_params.has(&"rings"):
			mesh.set("rings", int(mesh_params[&"rings"]))
		if mesh_params.has(&"left_to_right"):
			mesh.set("left_to_right", float(mesh_params[&"left_to_right"]))
		if mesh_params.has(&"subdivide_width"):
			mesh.set("subdivide_width", int(mesh_params[&"subdivide_width"]))
		if mesh_params.has(&"subdivide_height"):
			mesh.set("subdivide_height", int(mesh_params[&"subdivide_height"]))
		if mesh_params.has(&"subdivide_depth"):
			mesh.set("subdivide_depth", int(mesh_params[&"subdivide_depth"]))
		if mesh_params.has(&"text"):
			mesh.set("text", str(mesh_params[&"text"]))
		if mesh_params.has(&"font_size"):
			mesh.set("font_size", int(mesh_params[&"font_size"]))
		if mesh_params.has(&"depth"):
			mesh.set("depth", float(mesh_params[&"depth"]))
		if mesh_params.has(&"size"):
			mesh.set("size", _parse_value(mesh_params[&"size"]))

	target.set("mesh", mesh)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"message": "Set %s on node '%s'" % [mesh_type, node_path]}

# =============================================================================
# set_material
# =============================================================================
func set_material(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var material_type: String = str(args.get(&"material_type", ""))
	var material_params: Dictionary = args.get(&"material_params", {})
	var surface_index: int = int(args.get(&"surface_index", -1))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if material_type.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'material_type'"}

	# _acquire_scene, not _load_scene: on an OPEN scene, loading a disk copy and
	# saving it back discards the editor's unsaved state and the reload that
	# follows wipes the live tree with it.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var target = _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err

	var material: Material = null

	if material_type == "file":
		var file_path: String = str(material_params.get(&"path", ""))
		if file_path.is_empty():
			_discard_scene(root, is_live)
			return {&"ok": false, &"error": "Missing 'path' in material_params for file type"}
		file_path = _ensure_res_path(file_path)
		if PathGuard.is_bad(file_path):
			_discard_scene(root, is_live)
			return {&"ok": false, &"error": "material path escapes the project sandbox"}
		var loaded = load(file_path)
		if not loaded or not (loaded is Material):
			_discard_scene(root, is_live)
			return {&"ok": false, &"error": "Failed to load material (or not a Material): " + file_path}
		material = loaded

	elif material_type == "StandardMaterial3D":
		material = StandardMaterial3D.new()

		if material_params.has(&"albedo_color"):
			material.albedo_color = _parse_value(material_params[&"albedo_color"])
		if material_params.has(&"metallic"):
			material.metallic = float(material_params[&"metallic"])
		if material_params.has(&"roughness"):
			material.roughness = float(material_params[&"roughness"])
		if material_params.has(&"emission"):
			var parsed_emission = _parse_value(material_params[&"emission"])
			if parsed_emission is Color:
				material.emission = parsed_emission
				material.emission_enabled = true
		if material_params.has(&"emission_energy"):
			material.emission_energy_multiplier = float(material_params[&"emission_energy"])
		if material_params.has(&"transparency"):
			material.transparency = int(material_params[&"transparency"])

	else:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Unknown material type: '%s'. Use 'StandardMaterial3D' or 'file'." % material_type}

	var apply_mode: String
	if target is MeshInstance3D:
		if surface_index >= 0:
			target.set_surface_override_material(surface_index, material)
			apply_mode = "surface_override_material[%d]" % surface_index
		else:
			target.material_override = material
			apply_mode = "material_override"
	elif target is CSGPrimitive3D:
		target.set("material", material)
		apply_mode = "material"
	elif target is GeometryInstance3D:
		target.material_override = material
		apply_mode = "material_override"
	else:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) does not support material assignment" % [node_path, target.get_class()]}

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"message": "Set %s on node '%s' via %s" % [material_type, node_path, apply_mode]}

# =============================================================================
# get_node_spatial_info
# =============================================================================
func get_node_spatial_info(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var include_bounds: bool = bool(args.get(&"include_bounds", true))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}

	# A read has to see the LIVE tree when the scene is open, or it reports the
	# last-saved state: an agent that edits and then reads back gets stale values
	# and cannot tell. _discard_scene is a no-op on the live root, so the frees
	# below stay correct on both paths.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var target = _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err
	if not (target is Node3D):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) is not a Node3D" % [node_path, target.get_class()]}

	var target_3d: Node3D = target
	var local_transform: Transform3D = target_3d.transform
	var global_transform: Transform3D = _get_node3d_global_transform(target_3d)

	var info := {
		&"ok": true,
		&"scene_path": scene_path,
		&"node_path": node_path,
		&"node_name": target_3d.name,
		&"node_type": target_3d.get_class(),
		&"local_position": _serialize_value(local_transform.origin),
		&"global_position": _serialize_value(global_transform.origin),
		&"local_scale": _serialize_value(local_transform.basis.get_scale()),
		&"global_scale": _serialize_value(global_transform.basis.get_scale()),
		&"local_rotation_quaternion": _serialize_value(local_transform.basis.orthonormalized().get_rotation_quaternion()),
		&"global_rotation_quaternion": _serialize_value(global_transform.basis.orthonormalized().get_rotation_quaternion()),
	}

	if include_bounds:
		var subtree_bounds = _get_node_global_aabb(target_3d)
		if subtree_bounds is AABB:
			info[&"global_aabb"] = _serialize_value(subtree_bounds)
			info[&"global_aabb_center"] = _serialize_value(subtree_bounds.position + (subtree_bounds.size * 0.5))
			info[&"global_aabb_size"] = _serialize_value(subtree_bounds.size)
			info[&"has_bounds"] = true
		else:
			info[&"has_bounds"] = false

		if target_3d is VisualInstance3D:
			var visual_target: VisualInstance3D = target_3d
			var local_aabb: AABB = visual_target.get_aabb()
			info[&"local_aabb"] = _serialize_value(local_aabb)

	_discard_scene(root, is_live)
	return info

func _get_node3d_global_transform(node: Node3D) -> Transform3D:
	var current: Transform3D = node.transform
	if node.top_level:
		return current
	var parent := node.get_parent_node_3d()
	while parent:
		current = parent.transform * current
		parent = parent.get_parent_node_3d()
	return current

func _get_node_global_aabb(node: Node) -> Variant:
	var has_bounds := false
	var merged_bounds := AABB()

	if node is VisualInstance3D:
		var visual: VisualInstance3D = node
		var visual_transform := _get_node3d_global_transform(visual)
		merged_bounds = _transform_aabb(visual.get_aabb(), visual_transform)
		has_bounds = true

	for child: Node in node.get_children():
		var child_bounds = _get_node_global_aabb(child)
		if child_bounds is AABB:
			if has_bounds:
				merged_bounds = merged_bounds.merge(child_bounds)
			else:
				merged_bounds = child_bounds
				has_bounds = true

	return merged_bounds if has_bounds else null

func _transform_aabb(aabb: AABB, transform: Transform3D) -> AABB:
	var corners: Array[Vector3] = [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0, 0),
		aabb.position + Vector3(0, aabb.size.y, 0),
		aabb.position + Vector3(0, 0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0),
		aabb.position + Vector3(aabb.size.x, 0, aabb.size.z),
		aabb.position + Vector3(0, aabb.size.y, aabb.size.z),
		aabb.position + aabb.size,
	]

	var first: Vector3 = transform * corners[0]
	var min_corner := first
	var max_corner := first

	for i: int in range(1, corners.size()):
		var point: Vector3 = transform * corners[i]
		min_corner = Vector3(
			minf(min_corner.x, point.x),
			minf(min_corner.y, point.y),
			minf(min_corner.z, point.z)
		)
		max_corner = Vector3(
			maxf(max_corner.x, point.x),
			maxf(max_corner.y, point.y),
			maxf(max_corner.z, point.z)
		)

	return AABB(min_corner, max_corner - min_corner)

# =============================================================================
# measure_node_distance
# =============================================================================
func measure_node_distance(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var from_node_path: String = str(args.get(&"from_node_path", ""))
	var to_node_path: String = str(args.get(&"to_node_path", ""))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if from_node_path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'from_node_path'"}
	if to_node_path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'to_node_path'"}

	# A read has to see the LIVE tree when the scene is open, or it reports the
	# last-saved state: an agent that edits and then reads back gets stale values
	# and cannot tell. _discard_scene is a no-op on the live root, so the frees
	# below stay correct on both paths.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var from_node = _find_node(root, from_node_path)
	var to_node = _find_node(root, to_node_path)

	if not from_node:
		var err := _node_not_found(root, from_node_path)
		_discard_scene(root, is_live)
		return err
	if not to_node:
		var err := _node_not_found(root, to_node_path)
		_discard_scene(root, is_live)
		return err
	if not (from_node is Node3D):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) is not a Node3D" % [from_node_path, from_node.get_class()]}
	if not (to_node is Node3D):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) is not a Node3D" % [to_node_path, to_node.get_class()]}

	var from_position: Vector3 = _get_node3d_global_transform(from_node).origin
	var to_position: Vector3 = _get_node3d_global_transform(to_node).origin
	var delta: Vector3 = to_position - from_position

	_discard_scene(root, is_live)

	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"from_node_path": from_node_path,
		&"to_node_path": to_node_path,
		&"from_global_position": _serialize_value(from_position),
		&"to_global_position": _serialize_value(to_position),
		&"delta": _serialize_value(delta),
		&"distance": delta.length(),
		&"horizontal_distance": Vector2(delta.x, delta.z).length(),
	}

# =============================================================================
# snap_node_to_grid
# =============================================================================
func snap_node_to_grid(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var space: String = str(args.get(&"space", "global")).to_lower()
	var axes: PackedStringArray = _normalized_axes(args.get(&"axes", ["x", "y", "z"]))
	var grid_value = _grid_size_to_vector3(args.get(&"grid_size", 1.0))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if grid_value == null:
		return {&"ok": false, &"error": "Invalid 'grid_size'. Use a positive number or {x,y,z} object."}
	if axes.is_empty():
		return {&"ok": false, &"error": "Missing or invalid 'axes'. Use any of: x, y, z."}
	if space not in ["local", "global"]:
		return {&"ok": false, &"error": "Invalid 'space'. Use 'local' or 'global'."}

	# _acquire_scene, not _load_scene: on an OPEN scene, loading a disk copy and
	# saving it back discards the editor's unsaved state and the reload that
	# follows wipes the live tree with it.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var target = _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err
	if not (target is Node3D):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) is not a Node3D" % [node_path, target.get_class()]}

	var target_3d: Node3D = target
	var grid: Vector3 = grid_value
	var old_local_transform: Transform3D = target_3d.transform
	var old_global_transform: Transform3D = _get_node3d_global_transform(target_3d)

	if space == "local":
		var new_local_transform := old_local_transform
		new_local_transform.origin = _snap_position_to_grid(old_local_transform.origin, grid, axes)
		target_3d.transform = new_local_transform
	else:
		var new_global_transform := old_global_transform
		new_global_transform.origin = _snap_position_to_grid(old_global_transform.origin, grid, axes)
		_set_node3d_global_transform(target_3d, new_global_transform)

	var new_local_position: Vector3 = target_3d.transform.origin
	var new_global_position: Vector3 = _get_node3d_global_transform(target_3d).origin

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"node_path": node_path,
		&"space": space,
		&"axes": Array(axes),
		&"grid_size": _serialize_value(grid),
		&"old_local_position": _serialize_value(old_local_transform.origin),
		&"new_local_position": _serialize_value(new_local_position),
		&"old_global_position": _serialize_value(old_global_transform.origin),
		&"new_global_position": _serialize_value(new_global_position),
		&"message": "Snapped '%s' to %s grid" % [node_path, space]
	}

func _set_node3d_global_transform(node: Node3D, global_transform: Transform3D) -> void:
	if node.top_level:
		node.transform = global_transform
		return
	var parent := node.get_parent_node_3d()
	if parent:
		node.transform = _get_node3d_global_transform(parent).affine_inverse() * global_transform
	else:
		node.transform = global_transform

func _grid_size_to_vector3(grid_size: Variant) -> Variant:
	var parsed = _parse_value(grid_size)
	if parsed is Vector3:
		if parsed.x <= 0.0 or parsed.y <= 0.0 or parsed.z <= 0.0:
			return null
		return parsed
	if typeof(parsed) == TYPE_FLOAT or typeof(parsed) == TYPE_INT:
		var scalar: float = float(parsed)
		if scalar <= 0.0:
			return null
		return Vector3(scalar, scalar, scalar)
	return null

func _normalized_axes(axes_value: Variant) -> PackedStringArray:
	var normalized := PackedStringArray()
	if axes_value is Array:
		for axis_value in axes_value:
			var axis: String = str(axis_value).to_lower()
			if axis in ["x", "y", "z"] and axis not in normalized:
				normalized.append(axis)
	return normalized

func _snap_position_to_grid(position: Vector3, grid: Vector3, axes: PackedStringArray) -> Vector3:
	var snapped := position
	if "x" in axes:
		snapped.x = round(position.x / grid.x) * grid.x
	if "y" in axes:
		snapped.y = round(position.y / grid.y) * grid.y
	if "z" in axes:
		snapped.z = round(position.z / grid.z) * grid.z
	return snapped

# =============================================================================
# get_scene_hierarchy (for visualizer)
# =============================================================================
func get_scene_hierarchy(args: Dictionary) -> Dictionary:
	"""Get the full scene hierarchy with node information for the visualizer."""
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}

	# A read has to see the LIVE tree when the scene is open, or it reports the
	# last-saved state: an agent that edits and then reads back gets stale values
	# and cannot tell. _discard_scene is a no-op on the live root, so the frees
	# below stay correct on both paths.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var hierarchy = _build_hierarchy_recursive(root, ".")
	_discard_scene(root, is_live)

	return {&"ok": true, &"scene_path": scene_path, &"hierarchy": hierarchy}

func _build_hierarchy_recursive(node: Node, path: String) -> Dictionary:
	"""Build node hierarchy with all info needed for visualizer."""
	var data := {
		&"name": str(node.name),
		&"type": node.get_class(),
		&"path": path,
		&"children": [],
		&"child_count": node.get_child_count()
	}

	var script = node.get_script()
	if script:
		data[&"script"] = script.resource_path

	var parent = node.get_parent()
	if parent:
		data[&"index"] = node.get_index()

	for i: int in range(node.get_child_count()):
		var child = node.get_child(i)
		var child_path = child.name if path == "." else path + "/" + child.name
		data[&"children"].append(_build_hierarchy_recursive(child, child_path))

	return data

# =============================================================================
# get_scene_node_properties (dynamic property fetching)
# =============================================================================
func get_scene_node_properties(args: Dictionary) -> Dictionary:
	"""Get all properties of a specific node in a scene with their current values."""
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}

	# A read has to see the LIVE tree when the scene is open, or it reports the
	# last-saved state: an agent that edits and then reads back gets stale values
	# and cannot tell. _discard_scene is a no-op on the live root, so the frees
	# below stay correct on both paths.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var target = _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err

	var node_type = target.get_class()
	var properties: Array = []
	var categories: Dictionary = {}

	for prop: Dictionary in target.get_property_list():
		var prop_name: String = prop[&"name"]

		if prop_name.begins_with("_"):
			continue
		if _SKIP_PROPS.has(prop_name):
			continue

		var usage = prop.get(&"usage", 0)
		if not (usage & PROPERTY_USAGE_EDITOR):
			continue

		var current_value = target.get(prop_name)

		var prop_info := {
			&"name": prop_name,
			&"type": prop[&"type"],
			&"type_name": _type_id_to_name(prop[&"type"]),
			&"hint": prop.get(&"hint", 0),
			&"hint_string": prop.get(&"hint_string", ""),
			&"value": _serialize_value(current_value),
			&"usage": usage
		}

		var category = _get_property_category(target, prop_name)
		prop_info[&"category"] = category

		if not categories.has(category):
			categories[category] = []
		categories[category].append(prop_info)
		properties.append(prop_info)

	var chain: Array = []
	var cls: String = node_type
	while cls != "":
		chain.append(cls)
		cls = ClassDB.get_parent_class(cls)

	_discard_scene(root, is_live)

	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"node_path": node_path,
		&"node_type": node_type,
		&"node_name": target.name,
		&"inheritance_chain": chain,
		&"properties": properties,
		&"categories": categories,
		&"property_count": properties.size()
	}

func _type_id_to_name(type_id: int) -> String:
	"""Convert Godot type ID to human-readable name."""
	match type_id:
		TYPE_NIL: return "null"
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "String"
		TYPE_VECTOR2: return "Vector2"
		TYPE_VECTOR2I: return "Vector2i"
		TYPE_RECT2: return "Rect2"
		TYPE_RECT2I: return "Rect2i"
		TYPE_VECTOR3: return "Vector3"
		TYPE_VECTOR3I: return "Vector3i"
		TYPE_TRANSFORM2D: return "Transform2D"
		TYPE_VECTOR4: return "Vector4"
		TYPE_VECTOR4I: return "Vector4i"
		TYPE_PLANE: return "Plane"
		TYPE_QUATERNION: return "Quaternion"
		TYPE_AABB: return "AABB"
		TYPE_BASIS: return "Basis"
		TYPE_TRANSFORM3D: return "Transform3D"
		TYPE_PROJECTION: return "Projection"
		TYPE_COLOR: return "Color"
		TYPE_STRING_NAME: return "StringName"
		TYPE_NODE_PATH: return "NodePath"
		TYPE_RID: return "RID"
		TYPE_OBJECT: return "Object"
		TYPE_CALLABLE: return "Callable"
		TYPE_SIGNAL: return "Signal"
		TYPE_DICTIONARY: return "Dictionary"
		TYPE_ARRAY: return "Array"
		TYPE_PACKED_BYTE_ARRAY: return "PackedByteArray"
		TYPE_PACKED_INT32_ARRAY: return "PackedInt32Array"
		TYPE_PACKED_INT64_ARRAY: return "PackedInt64Array"
		TYPE_PACKED_FLOAT32_ARRAY: return "PackedFloat32Array"
		TYPE_PACKED_FLOAT64_ARRAY: return "PackedFloat64Array"
		TYPE_PACKED_STRING_ARRAY: return "PackedStringArray"
		TYPE_PACKED_VECTOR2_ARRAY: return "PackedVector2Array"
		TYPE_PACKED_VECTOR3_ARRAY: return "PackedVector3Array"
		TYPE_PACKED_COLOR_ARRAY: return "PackedColorArray"
		_: return "Variant"

func _get_property_category(node: Node, prop_name: String) -> String:
	"""Determine which class in the hierarchy defines this property."""
	var cls: String = node.get_class()
	while cls != "":
		var class_props = ClassDB.class_get_property_list(cls, true)
		for prop: Dictionary in class_props:
			if prop[&"name"] == prop_name:
				return cls
		cls = ClassDB.get_parent_class(cls)
	return node.get_class()

# =============================================================================
# set_scene_node_property (for visualizer inline editing)
# =============================================================================
func set_scene_node_property(args: Dictionary) -> Dictionary:
	"""Set a property on a node in a scene (supports complex types)."""
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var property_name: String = str(args.get(&"property_name", ""))
	var value = args.get(&"value")
	var value_type: int = int(args.get(&"value_type", -1))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if property_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'property_name'"}

	# _acquire_scene, not _load_scene: on an OPEN scene, loading a disk copy and
	# saving it back discards the editor's unsaved state and the reload that
	# follows wipes the live tree with it.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var target = _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err

	var parsed_value = _parse_typed_value(value, value_type)
	var old_value = target.get(property_name)

	target.set(property_name, parsed_value)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"node_path": node_path,
		&"property_name": property_name,
		&"old_value": _serialize_value(old_value),
		&"new_value": _serialize_value(parsed_value),
		&"message": "Set %s.%s" % [node_path, property_name]
	}

func _parse_typed_value(value, type_hint: int):
	return VariantCodec.parse_typed_value(value, type_hint)

# =============================================================================
# set_node_properties (bulk)
# =============================================================================
## Apply multiple properties to a node in a single load/save cycle.
## Non-atomic: properties that exist and validate are applied; the rest are
## reported as failures. The scene is only saved if at least one applied.
func set_node_properties(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var properties: Dictionary = args.get(&"properties", {})
	var dry_run: bool = bool(args.get(&"dry_run", false))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if properties.is_empty():
		return {&"ok": false, &"error": "Missing or empty 'properties' dictionary"}

	# If the target scene is the one open+focused in the editor, mutate its LIVE
	# tree through the EditorUndoRedoManager (undoable, marks dirty, preserves the
	# user's other unsaved edits) instead of the disk load→save→reload path, which
	# would clobber whatever the user hadn't saved yet.
	var live_root := _edited_root_if_open(scene_path)
	var is_live := live_root != null
	var root: Node
	if is_live:
		root = live_root
	else:
		var result := _load_scene(scene_path)
		if not result[1].is_empty():
			return result[1]
		root = result[0]

	var target := _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		if not is_live:
			root.queue_free()
		return err

	# Build the set of valid property names once, keeping each one's declared
	# type so values can be parsed against it (see _parse_value call below).
	var valid_props: Dictionary = {}
	for prop in target.get_property_list():
		valid_props[str(prop[&"name"])] = int(prop.get(&"type", TYPE_NIL))

	var applied: Array = []
	var failed: Array = []
	# Live path defers the actual writes so they commit as one undoable action.
	var pending: Array = []

	for prop_name_v in properties.keys():
		var prop_name := str(prop_name_v)
		var raw_value = properties[prop_name_v]

		if not valid_props.has(prop_name):
			failed.append({&"property": prop_name, &"reason": "no such property on " + target.get_class()})
			continue

		var old_value = target.get(prop_name)
		# Parse against the DECLARED type, not the value's shape: without the
		# hint `[100, 100]` for a Vector2 property stays an Array, set() quietly
		# no-ops, and the caller gets "type mismatch?" for a form other tools
		# here accept.
		var parsed = VariantCodec.parse_typed_value(raw_value, int(valid_props.get(prop_name, -1)))

		# A res:// path for an Object-typed property means "load this and assign
		# it". Every other tool here that takes a resource takes a path
		# (attach_script, set_sprite_texture, assign_shader_material), so an
		# agent writes one here too — and without this it silently no-ops,
		# because set() rejects a String for an Object property.
		if int(valid_props.get(prop_name, -1)) == TYPE_OBJECT and parsed is String:
			var res_path := str(parsed)
			if res_path.begins_with("res://"):
				if not ResourceLoader.exists(res_path):
					failed.append({&"property": prop_name, &"reason": "resource not found: " + res_path})
					continue
				var loaded := ResourceLoader.load(res_path)
				if loaded == null:
					failed.append({&"property": prop_name, &"reason": "could not load resource: " + res_path})
					continue
				parsed = loaded

		if old_value is Resource and not (parsed is Resource):
			failed.append({&"property": prop_name, &"reason": "expects a Resource (use set_resource_property or specialized tool)"})
			continue

		if is_live:
			pending.append({&"prop": prop_name, &"old": old_value, &"parsed": parsed})
			continue

		target.set(prop_name, parsed)
		# Godot's set() silently no-ops on a type mismatch (e.g. a String handed
		# to an int property): it returns nothing and the property keeps its old
		# value. Read back and confirm the value actually took before reporting
		# it as applied, so a mismatch surfaces as a failure instead of a lie.
		var after = target.get(prop_name)
		if not _values_match(after, parsed):
			failed.append({&"property": prop_name, &"reason": "set had no effect (type mismatch?)"})
			continue
		applied.append({
			&"property": prop_name,
			&"old": _serialize_value(old_value),
			&"new": _serialize_value(after),
		})

	# Preview: never mutate. (The live tree is never freed.)
	if dry_run:
		if is_live:
			for p in pending:
				applied.append({&"property": p[&"prop"], &"old": _serialize_value(p[&"old"]), &"new": _serialize_value(p[&"parsed"])})
		else:
			root.queue_free()
		return {
			&"ok": true,
			&"dry_run": true,
			&"scene_path": scene_path,
			&"node_path": node_path,
			&"applied": applied,
			&"failed": failed,
			&"message": "Preview: would apply %d/%d propert%s on %s. Call again with dry_run=false to save." % [
				applied.size(), applied.size() + failed.size(),
				"y" if (applied.size() + failed.size()) == 1 else "ies",
				node_path,
			],
		}

	if is_live and not pending.is_empty():
		var ur := _get_undo_redo()
		if ur:
			ur.create_action("MCP: set properties on %s" % node_path, UndoRedo.MERGE_DISABLE, root)
			for p in pending:
				ur.add_do_property(target, p[&"prop"], p[&"parsed"])
				ur.add_undo_property(target, p[&"prop"], p[&"old"])
			ur.commit_action()
		else:
			for p in pending:
				target.set(p[&"prop"], p[&"parsed"])
		# Read back each write to confirm it actually landed.
		for p in pending:
			var after = target.get(p[&"prop"])
			if not _values_match(after, p[&"parsed"]):
				failed.append({&"property": p[&"prop"], &"reason": "set had no effect (type mismatch?)"})
			else:
				applied.append({&"property": p[&"prop"], &"old": _serialize_value(p[&"old"]), &"new": _serialize_value(after)})

	if applied.is_empty():
		if not is_live:
			root.queue_free()
		return {
			&"ok": false,
			&"error": "No properties applied. See 'failed' for per-property reasons.",
			&"failed": failed,
		}

	if not is_live:
		var err := _save_scene(root, scene_path)
		if not err.is_empty():
			return err

	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"node_path": node_path,
		&"applied": applied,
		&"failed": failed,
		&"live_editor_scene": is_live,
		&"message": "Applied %d/%d propert%s on %s%s" % [
			applied.size(), applied.size() + failed.size(),
			"y" if (applied.size() + failed.size()) == 1 else "ies",
			node_path,
			" (live editor scene — undoable)" if is_live else "",
		],
	}

# =============================================================================
# Node groups (scene-file editing)
# =============================================================================
## Set the FULL group membership of a node. `mode` controls behavior:
##   "replace" (default) — node ends up in exactly the listed groups
##   "add"     — listed groups added; existing groups untouched
##   "remove"  — listed groups removed; others untouched
func set_node_groups(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var groups_arg: Array = args.get(&"groups", [])
	var mode: String = str(args.get(&"mode", "replace"))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}

	# See attach_script: _load_scene + _save_scene destroys unsaved editor state
	# when the scene is open.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]

	var target := _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err

	var requested: Array[String] = []
	for g in groups_arg:
		var s := str(g).strip_edges()
		if not s.is_empty():
			requested.append(s)

	if mode not in ["replace", "add", "remove"]:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Invalid 'mode': " + mode + ". Use 'replace', 'add', or 'remove'."}

	var current_groups := target.get_groups()
	var ctx := _begin_edit(is_live, "MCP: set groups on %s" % node_path, root)
	match mode:
		"replace":
			for g in current_groups:
				target.remove_from_group(g)
				_edit_record(ctx, target, &"remove_from_group", [g], &"add_to_group", [g, true])
			for g in requested:
				target.add_to_group(g, true)
				_edit_record(ctx, target, &"add_to_group", [g, true], &"remove_from_group", [g])
		"add":
			for g in requested:
				target.add_to_group(g, true)
				_edit_record(ctx, target, &"add_to_group", [g, true], &"remove_from_group", [g])
		"remove":
			for g in requested:
				target.remove_from_group(g)
				_edit_record(ctx, target, &"remove_from_group", [g], &"add_to_group", [g, true])
	_edit_commit(ctx)

	# Read back from the tree we just edited (live or disk copy) rather than
	# re-loading the file, which would report stale groups on an open scene.
	var resulting_groups: Array = target.get_groups()

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"node_path": node_path,
		&"mode": mode,
		&"groups": resulting_groups,
		&"message": "Node '%s' groups (%s): %s" % [node_path, mode, str(resulting_groups)],
	}

func get_node_groups(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}

	# A read has to see the LIVE tree when the scene is open, or it reports the
	# last-saved state: an agent that edits and then reads back gets stale values
	# and cannot tell. _discard_scene is a no-op on the live root, so the frees
	# below stay correct on both paths.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var target := _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err

	var groups := target.get_groups()
	_discard_scene(root, is_live)

	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"node_path": node_path,
		&"groups": groups,
	}

func find_nodes_in_group(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var group_name: String = str(args.get(&"group", ""))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if group_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'group'"}

	# A read has to see the LIVE tree when the scene is open, or it reports the
	# last-saved state: an agent that edits and then reads back gets stale values
	# and cannot tell. _discard_scene is a no-op on the live root, so the frees
	# below stay correct on both paths.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var matches: Array = []
	_collect_nodes_in_group(root, group_name, ".", matches)
	_discard_scene(root, is_live)

	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"group": group_name,
		&"matches": matches,
		&"count": matches.size(),
	}

func _collect_nodes_in_group(node: Node, group_name: String, path: String, matches: Array) -> void:
	if node.is_in_group(group_name):
		matches.append({&"path": path, &"name": str(node.name), &"type": node.get_class()})
	for child in node.get_children():
		var child_path = child.name if path == "." else path + "/" + child.name
		_collect_nodes_in_group(child, group_name, child_path, matches)

# =============================================================================
# Generic resource property tools
# =============================================================================
## Set a property on a node's existing Resource property (or on a sub-resource of one).
## Example uses: tweak a SphereShape3D radius without re-creating the shape;
## change a StandardMaterial3D albedo_color on an existing material.
##
## resource_path: dot/slash path from the node to the resource.
##   "shape"                       → the node's shape resource
##   "material/albedo_color_texture" → texture sub-resource of the node's material
func set_resource_property(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	# get_resource_info calls this same slot `resource_property`, which is the
	# accurate name — the value is a property on the node ("texture"), not a
	# path. Both are taken so the two tools can be used with one vocabulary.
	var resource_path: String = str(args.get(&"resource_path", args.get(&"resource_property", "")))
	var property_name: String = str(args.get(&"property_name", ""))
	var value = args.get(&"value")

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if property_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'property_name'"}

	# _acquire_scene, not _load_scene: on an OPEN scene, loading a disk copy and
	# saving it back discards the editor's unsaved state.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var target := _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err

	# Walk to the resource.
	var resource: Object = target
	if not resource_path.is_empty():
		for segment in resource_path.split("/", false):
			if resource == null:
				_discard_scene(root, is_live)
				return {&"ok": false, &"error": "Resource path broke at segment '%s' (got null)" % segment}
			resource = resource.get(segment)
		if resource == null:
			_discard_scene(root, is_live)
			return {&"ok": false, &"error": "Resource at '%s' is null on node '%s'" % [resource_path, node_path]}
		if not (resource is Resource):
			_discard_scene(root, is_live)
			return {&"ok": false, &"error": "'%s' is not a Resource (got %s)" % [resource_path, typeof(resource)]}

	var has_prop := false
	for p in resource.get_property_list():
		if str(p[&"name"]) == property_name:
			has_prop = true
			break
	if not has_prop:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Property '%s' not found on %s" % [property_name, resource.get_class()]}

	var old_value = resource.get(property_name)
	var parsed = _parse_value(value)
	resource.set(property_name, parsed)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"node_path": node_path,
		&"resource_path": resource_path,
		&"property_name": property_name,
		&"old_value": _serialize_value(old_value),
		&"new_value": _serialize_value(parsed),
		&"message": "Set %s.%s.%s" % [node_path, resource_path, property_name],
	}

## Save a Resource currently held by a node (or sub-resource) to its own .tres file
## so it can be shared by other scenes / referenced by path. After saving, the
## node's property is reassigned to the loaded-from-disk version so future edits
## via this tool persist to that file.
func save_resource_to_file(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var resource_path: String = str(args.get(&"resource_path", ""))
	var save_to: String = _ensure_res_path(str(args.get(&"save_to", "")))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if save_to.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'save_to'"}

	# If the scene is open, operate on the live tree and reattach via undo so we
	# don't clobber unsaved edits (the whole-.tscn rewrite of the disk path would).
	# Only the live root must never be queue_free'd — guard every cleanup with it.
	var live_root := _edited_root_if_open(scene_path)
	var is_live := live_root != null
	var root: Node
	if is_live:
		root = live_root
	else:
		var result := _load_scene(scene_path)
		if not result[1].is_empty():
			return result[1]
		root = result[0]

	var target := _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		if not is_live: root.queue_free()
		return err

	# Walk to the resource. Track parent for re-assignment.
	var parent_obj: Object = target
	var parent_prop: String = ""
	var resource: Object = target
	if resource_path.is_empty():
		if not is_live: root.queue_free()
		return {&"ok": false, &"error": "Missing 'resource_path' (e.g., 'shape', 'material', 'mesh')"}

	var segments := Array(resource_path.split("/", false))
	for i in range(segments.size()):
		var seg = str(segments[i])
		if i == segments.size() - 1:
			parent_obj = resource
			parent_prop = seg
		resource = resource.get(seg)
		if resource == null:
			if not is_live: root.queue_free()
			return {&"ok": false, &"error": "Resource walk broke at '%s'" % seg}

	if not (resource is Resource):
		if not is_live: root.queue_free()
		return {&"ok": false, &"error": "Target is not a Resource (got %s)" % typeof(resource)}

	# Ensure target dir exists.
	var dir := save_to.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var save_err := ResourceSaver.save(resource, save_to)
	if save_err != OK:
		if not is_live: root.queue_free()
		return {&"ok": false, &"error": "ResourceSaver.save failed: %s (%d)" % [error_string(save_err), save_err]}

	var loaded := load(save_to)
	if loaded == null:
		if not is_live: root.queue_free()
		return {&"ok": false, &"error": "Saved but failed to reload from %s" % save_to}

	if is_live:
		# Reattach the loaded-from-disk resource on the live node, undoably. No
		# whole-scene disk write — the editor's unsaved state is preserved.
		var ur := _get_undo_redo()
		if ur:
			ur.create_action("MCP: save resource on %s" % node_path, UndoRedo.MERGE_DISABLE, root)
			ur.add_do_property(parent_obj, parent_prop, loaded)
			ur.add_undo_property(parent_obj, parent_prop, resource)
			ur.commit_action()
		else:
			parent_obj.set(parent_prop, loaded)
	else:
		parent_obj.set(parent_prop, loaded)
		var serr := _save_scene(root, scene_path)
		if not serr.is_empty():
			return serr

	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"node_path": node_path,
		&"resource_path": resource_path,
		&"saved_to": save_to,
		&"resource_class": loaded.get_class(),
		&"live_editor_scene": is_live,
		&"message": "Saved %s to %s and reattached to node%s" % [loaded.get_class(), save_to,
			" (open scene — undoable)" if is_live else ""],
	}

# =============================================================================
# get_resource_info — generic resource introspection (any .tres/.res/.png/etc.)
# =============================================================================
## Inspect any resource on disk: type, dimensions for textures, vertex counts
## for meshes, key properties, and dependencies. Replaces ad-hoc image/PNG checks
## with a uniform tool that works for Resource, PackedScene, Texture2D, Mesh,
## AudioStream, Material, FontFile, Animation, Shader, etc.
func get_resource_info(args: Dictionary) -> Dictionary:
	# Two modes:
	#   1) path = "res://...resource"     → load from disk and inspect
	#   2) scene_path + node_path + resource_property → read a resource that
	#      lives ON a node inside a scene file (no need to save it as .tres
	#      first). Supports either or both of these arg shapes.
	# node_path is a relative path WITHIN the scene tree (e.g. "Ground/CollisionShape"),
	# never a res:// filesystem path — it must never go through PathGuard/_ensure_res_path.
	var path_raw: String = str(args.get(&"path", "")).strip_edges()
	var scene_path_raw: String = str(args.get(&"scene_path", "")).strip_edges()
	var node_path: String = str(args.get(&"node_path", ""))
	var resource_property: String = str(args.get(&"resource_property", ""))

	var res: Resource = null
	var info: Dictionary = {&"ok": true}
	var loaded_root: Node = null
	var scene_is_live := false
	var path: String = ""

	if not path_raw.is_empty():
		path = _ensure_res_path(path_raw)
		if not FileAccess.file_exists(path):
			return {&"ok": false, &"error": "File not found: " + path}
		res = load(path)
		if res == null:
			return {&"ok": false, &"error": "Failed to load resource: " + path}
		info[&"path"] = path
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			info[&"file_size_bytes"] = f.get_length()
			f.close()
	elif not scene_path_raw.is_empty() and not node_path.is_empty() and not resource_property.is_empty():
		var scene_path: String = _ensure_res_path(scene_path_raw)
		# Live tree when the scene is open, so a resource the agent just changed
		# reads back as it is now rather than as it was last saved.
		var sacq := _acquire_scene(scene_path)
		if not sacq[2].is_empty():
			return sacq[2]
		loaded_root = sacq[0]
		scene_is_live = sacq[1]
		var target := _find_node(loaded_root, node_path)
		if not target:
			var err := _node_not_found(loaded_root, node_path)
			_discard_scene(loaded_root, scene_is_live)
			return err
		var prop_value = target.get(resource_property)
		if prop_value == null or not (prop_value is Resource):
			_discard_scene(loaded_root, scene_is_live)
			return {&"ok": false, &"error": "Property '%s' on node '%s' is not a Resource (got %s)" % [resource_property, node_path, type_string(typeof(prop_value))]}
		res = prop_value
		info[&"scene_path"] = scene_path
		info[&"node_path"] = node_path
		info[&"resource_property"] = resource_property
	else:
		return {&"ok": false, &"error": "Provide either 'path' (resource on disk) or 'scene_path'+'node_path'+'resource_property' (resource attached to a node)."}

	info[&"class"] = res.get_class()
	info[&"resource_name"] = res.resource_name
	if res.resource_path:
		info[&"resource_path"] = res.resource_path

	# Type-specific extras.
	if res is Texture2D:
		var t: Texture2D = res
		info[&"width"] = t.get_width()
		info[&"height"] = t.get_height()
		info[&"has_alpha"] = t.has_alpha() if t.has_method("has_alpha") else null

	elif res is Mesh:
		var m: Mesh = res
		var surfaces: Array = []
		for i in range(m.get_surface_count()):
			var arr := m.surface_get_arrays(i)
			var verts: int = arr[Mesh.ARRAY_VERTEX].size() if arr and arr.size() > Mesh.ARRAY_VERTEX else 0
			surfaces.append({&"index": i, &"vertices": verts})
		info[&"surface_count"] = m.get_surface_count()
		info[&"surfaces"] = surfaces
		info[&"aabb"] = _serialize_value(m.get_aabb())

	elif res is AudioStream:
		var a: AudioStream = res
		info[&"length_seconds"] = a.get_length() if a.has_method("get_length") else null

	elif res is PackedScene:
		var ps: PackedScene = res
		var st := ps.get_state()
		info[&"node_count"] = st.get_node_count()

	elif res is Material:
		# Surface a few common Material properties.
		var keys := ["albedo_color", "metallic", "roughness", "emission", "shading_mode"]
		var mat_props := {}
		for k in keys:
			var v = res.get(k)
			if v != null:
				mat_props[k] = _serialize_value(v)
		info[&"properties"] = mat_props

	elif res is Animation:
		var anim: Animation = res
		info[&"length_seconds"] = anim.length
		info[&"track_count"] = anim.get_track_count()
		info[&"loop_mode"] = anim.loop_mode

	elif res is Shape2D or res is Shape3D:
		var keys2 := ["radius", "height", "size", "extents"]
		var sh_props := {}
		for k in keys2:
			var v = res.get(k)
			if v != null:
				sh_props[k] = _serialize_value(v)
		info[&"properties"] = sh_props

	# Dependencies (other resources this one references). Only meaningful for
	# resources actually on disk.
	var dep_path: String = path if not path.is_empty() else (res.resource_path if res else "")
	if not dep_path.is_empty():
		var deps := ResourceLoader.get_dependencies(dep_path)
		if deps.size() > 0:
			info[&"dependencies"] = Array(deps)

	if loaded_root:
		# Never free the editor's live root — _discard_scene is the guard.
		_discard_scene(loaded_root, scene_is_live)

	return info

# =============================================================================
# Signal connection tools (scene file source)
# =============================================================================
## List signal connections originating from a node in a scene file.
## For runtime queries on a live game, set source="runtime" (handled separately).
func list_signal_connections(args: Dictionary) -> Dictionary:
	var source: String = str(args.get(&"source", "scene_file"))
	if source != "scene_file":
		return {&"ok": false, &"error": "list_signal_connections source='%s' is handled by the runtime helper. Ensure your game is running and try again." % source}

	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var include_outgoing: bool = bool(args.get(&"include_outgoing", true))
	var include_incoming: bool = bool(args.get(&"include_incoming", true))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}

	# A read has to see the LIVE tree when the scene is open, or it reports the
	# last-saved state: an agent that edits and then reads back gets stale values
	# and cannot tell. _discard_scene is a no-op on the live root, so the frees
	# below stay correct on both paths.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var target := _find_node(root, node_path)
	if not target:
		var err := _node_not_found(root, node_path)
		_discard_scene(root, is_live)
		return err

	var outgoing: Array = []
	var incoming: Array = []

	if include_outgoing:
		for sig in target.get_signal_list():
			var sig_name := str(sig[&"name"])
			for conn in target.get_signal_connection_list(sig_name):
				outgoing.append(_serialize_connection(conn, root))

	if include_incoming:
		# Walk the whole scene and collect connections targeting our node.
		_collect_incoming(root, target, root, incoming)

	_discard_scene(root, is_live)

	return {
		&"ok": true,
		&"source": "scene_file",
		&"scene_path": scene_path,
		&"node_path": node_path,
		&"outgoing": outgoing,
		&"incoming": incoming,
		&"outgoing_count": outgoing.size(),
		&"incoming_count": incoming.size(),
	}

func _collect_incoming(node: Node, target: Node, root: Node, out: Array) -> void:
	for sig in node.get_signal_list():
		var sig_name := str(sig[&"name"])
		for conn in node.get_signal_connection_list(sig_name):
			var callable: Callable = conn[&"callable"]
			if callable.get_object() == target:
				out.append(_serialize_connection(conn, root))
	for child in node.get_children():
		_collect_incoming(child, target, root, out)

func _serialize_connection(conn: Dictionary, root: Node) -> Dictionary:
	var callable: Callable = conn[&"callable"]
	var sig: Signal = conn[&"signal"]
	var src_obj = sig.get_object()
	var src_node = src_obj if src_obj is Node else null
	var dst_node = callable.get_object() if callable.get_object() is Node else null
	return {
		&"signal": sig.get_name(),
		&"from_node": _node_path_str(src_node, root) if src_node else null,
		&"to_node": _node_path_str(dst_node, root) if dst_node else null,
		&"method": callable.get_method(),
		&"flags": int(conn.get(&"flags", 0)),
	}

func _node_path_str(node: Node, root: Node) -> String:
	if node == null:
		return ""
	if node == root:
		return "."
	return str(root.get_path_to(node))

## Add a signal connection between two nodes in a scene file.
func connect_signal(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var from_node: String = str(args.get(&"from_node", ""))
	var signal_name: String = str(args.get(&"signal", ""))
	var to_node: String = str(args.get(&"to_node", ""))
	var method: String = str(args.get(&"method", ""))
	var flags: int = int(args.get(&"flags", 0))
	# wire_signal writes the handler into the target's .gd before connecting, so
	# the cached live node may not report has_method yet. It sets this to bypass
	# the guard (the method is guaranteed present in the on-disk script).
	var skip_method_check: bool = bool(args.get(&"_skip_method_check", false))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if from_node.is_empty() or signal_name.is_empty() or to_node.is_empty() or method.is_empty():
		return {&"ok": false, &"error": "from_node, signal, to_node, and method are all required"}

	# _acquire_scene, not _load_scene: on an OPEN scene, loading a disk copy and
	# saving it back discards the editor's unsaved state and the reload that
	# follows wipes the live tree with it.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var src := _find_node(root, from_node)
	var dst := _find_node(root, to_node)
	if not src:
		var err := _node_not_found(root, from_node, "from_node")
		_discard_scene(root, is_live)
		return err
	if not dst:
		var err := _node_not_found(root, to_node, "to_node")
		_discard_scene(root, is_live)
		return err
	if not src.has_signal(signal_name):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Signal '%s' not found on %s" % [signal_name, src.get_class()]}
	if not skip_method_check and not dst.has_method(method):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Method '%s' not found on %s. Make sure the target script defines it (and that the script was attached via attach_script so the editor's live node sees it)." % [method, dst.get_class()]}

	var callable := Callable(dst, method)
	if src.is_connected(signal_name, callable):
		_discard_scene(root, is_live)
		return {&"ok": true, &"already_connected": true,
			&"message": "Connection already exists; no change."}

	# CRITICAL: connections must be made with CONNECT_PERSIST (flag 8) or
	# PackedScene.pack() will strip them when we save. Force it on so the
	# caller can't silently end up with a runtime-only connection that
	# vanishes on save.
	var persist_flags: int = flags | Object.CONNECT_PERSIST
	var err := src.connect(signal_name, callable, persist_flags)
	if err != OK:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "connect() returned %d (%s)" % [err, error_string(err)]}

	var serr := _finish_scene_edit(root, scene_path, is_live)
	if not serr.is_empty():
		return serr

	# Verify the connection actually landed, rather than claiming success after a
	# save silently dropped it (which happens when dst is not an owned descendant
	# of root).
	#
	# WHERE to look depends on the path taken. On a live scene nothing is written
	# to disk — the edit sits in the editor until the user saves — so re-reading
	# the .tscn would always report "not persisted" and turn a good connection
	# into a spurious error. Check the live tree instead; the CONNECT_PERSIST flag
	# above is what makes it survive the eventual save.
	var persisted := false
	if is_live:
		for c in src.get_signal_connection_list(signal_name):
			var cb: Callable = c.get("callable", Callable())
			if cb.get_object() == dst and str(cb.get_method()) == method:
				persisted = (int(c.get("flags", 0)) & Object.CONNECT_PERSIST) != 0
				break
	else:
		persisted = _signal_is_persisted(scene_path, from_node, signal_name, to_node, method)
	if not persisted:
		return {&"ok": false, &"error": "connect() succeeded at runtime but the connection did not persist into the .tscn. Ensure the target node is part of the scene (not an external autoload) and that the script is attached via attach_script."}

	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"from_node": from_node,
		&"signal": signal_name,
		&"to_node": to_node,
		&"method": method,
		&"flags": persist_flags,
		&"persisted": true,
		&"message": "Connected %s.%s -> %s.%s (written to .tscn)" % [from_node, signal_name, to_node, method],
	}

# =============================================================================
# wire_signal — connect a signal AND scaffold the typed handler in one call.
# Reads the emitter's signal argument types, writes a matching `func _on_x(...)`
# into the receiver's script (if absent), then persists the connection. Collapses
# the two-place edit (scene connection + handler stub) that connect_signal leaves
# to the caller, and matches the arg signature to the signal so the stub compiles.
# =============================================================================
func wire_signal(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var from_node: String = str(args.get(&"from_node", ""))
	var signal_name: String = str(args.get(&"signal", ""))
	var to_node: String = str(args.get(&"to_node", ""))
	var method: String = str(args.get(&"method", ""))
	var flags: int = int(args.get(&"flags", 0))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if from_node.is_empty() or signal_name.is_empty() or to_node.is_empty():
		return {&"ok": false, &"error": "from_node, signal, and to_node are required"}

	# Throwaway load to read the signal's arg types and the receiver's script path.
	# A read has to see the LIVE tree when the scene is open, or it reports the
	# last-saved state: an agent that edits and then reads back gets stale values
	# and cannot tell. _discard_scene is a no-op on the live root, so the frees
	# below stay correct on both paths.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var src := _find_node(root, from_node)
	var dst := _find_node(root, to_node)
	if not src:
		var err := _node_not_found(root, from_node, "from_node")
		_discard_scene(root, is_live)
		return err
	if not dst:
		var err := _node_not_found(root, to_node, "to_node")
		_discard_scene(root, is_live)
		return err
	if not src.has_signal(signal_name):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Signal '%s' not found on %s" % [signal_name, src.get_class()]}
	var scr := dst.get_script()
	if scr == null or str(scr.resource_path).is_empty():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "to_node '%s' has no attached script to hold the handler. Attach one first via attach_script." % to_node}
	var script_path: String = str(scr.resource_path)
	var params := _signal_params(src, signal_name)
	_discard_scene(root, is_live)

	if method.is_empty():
		method = "_on_%s_%s" % [str(from_node.get_file()).to_snake_case(), signal_name]

	# Insert the handler stub into the script if it isn't already declared.
	var f := FileAccess.open(script_path, FileAccess.READ)
	if f == null:
		return {&"ok": false, &"error": "Could not read script: " + script_path}
	var content := f.get_as_text()
	f.close()
	var stub_added := false
	var re := RegEx.new()
	re.compile("(?m)^func\\s+" + method + "\\s*\\(")
	if re.search(content) == null:
		var stub := "\n\nfunc %s(%s) -> void:\n\tpass # TODO: implement (wired from %s.%s)\n" % [method, params, from_node, signal_name]
		if not content.ends_with("\n"):
			content += "\n"
		content += stub
		var wf := FileAccess.open(script_path, FileAccess.WRITE)
		if wf == null:
			return {&"ok": false, &"error": "Could not write script: " + script_path}
		wf.store_string(content)
		wf.close()
		stub_added = true
		_refresh_filesystem()

	# Persist the connection via the existing path. Skip its has_method guard:
	# the method now exists in the on-disk script even if the cached live node
	# hasn't reloaded yet; the persisted connection is just a string in the .tscn.
	var conn := connect_signal({
		&"scene_path": scene_path, &"from_node": from_node, &"signal": signal_name,
		&"to_node": to_node, &"method": method, &"flags": flags,
		&"_skip_method_check": true,
	})
	conn[&"stub_added"] = stub_added
	conn[&"handler"] = method
	conn[&"handler_params"] = params
	conn[&"handler_script"] = script_path
	return conn

## Build a typed parameter list string for a signal from the emitter's signal
## list, e.g. "body: Node2D, amount: int". Empty string for a zero-arg signal.
func _signal_params(node: Object, signal_name: String) -> String:
	for s in node.get_signal_list():
		if str(s.get("name", "")) == signal_name:
			var parts: Array = []
			for a in s.get("args", []):
				var pname := str(a.get("name", "arg"))
				var tn := ""
				var cls := str(a.get("class_name", ""))
				if not cls.is_empty():
					tn = cls
				else:
					var t := int(a.get("type", TYPE_NIL))
					if t != TYPE_NIL:
						tn = type_string(t)
				parts.append(pname if tn.is_empty() else "%s: %s" % [pname, tn])
			return ", ".join(parts)
	return ""

# =============================================================================
# generate_onready_refs — scan a scene subtree and emit typed @onready vars for
# named children (%Name for unique-name nodes, else $RelativePath). Returns the
# block; with insert:true it splices it into the target node's script after the
# @tool/class_name/extends header, skipping vars already declared.
# =============================================================================
func generate_onready_refs(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var target_node: String = str(args.get(&"target_node", "."))
	var include_nested: bool = bool(args.get(&"include_nested", false))
	var do_insert: bool = bool(args.get(&"insert", false))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}

	# A read has to see the LIVE tree when the scene is open, or it reports the
	# last-saved state: an agent that edits and then reads back gets stale values
	# and cannot tell. _discard_scene is a no-op on the live root, so the frees
	# below stay correct on both paths.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var target := _find_node(root, target_node)
	if not target:
		var err := _node_not_found(root, target_node, "target_node")
		_discard_scene(root, is_live)
		return err

	var nodes: Array = []
	if include_nested:
		_collect_descendants(target, nodes)
	else:
		for c in target.get_children():
			nodes.append(c)

	var lines: Array = []
	var used_names: Dictionary = {}
	var skipped: Array = []
	for n in nodes:
		var vn := str(n.name).to_snake_case()
		if not _is_valid_ident(vn):
			skipped.append(str(n.name))
			continue
		if used_names.has(vn):
			skipped.append("%s (dup var %s)" % [str(n.name), vn])
			continue
		used_names[vn] = true
		var access := ("%" + str(n.name)) if n.unique_name_in_owner else ("$" + str(target.get_path_to(n)))
		lines.append("@onready var %s: %s = %s" % [vn, _node_type_name(n), access])

	var block := "\n".join(lines)
	var script_path := ""
	var scr := target.get_script()
	if scr != null:
		script_path = str(scr.resource_path)
	_discard_scene(root, is_live)

	var inserted := false
	var insert_note := ""
	if do_insert:
		if script_path.is_empty():
			insert_note = "target_node has no script; returned block only"
		else:
			var res := _insert_onready_block(script_path, lines)
			inserted = res[0]
			insert_note = res[1]

	return {
		&"ok": true, &"scene_path": scene_path, &"target_node": target_node,
		&"refs_count": lines.size(), &"block": block, &"skipped": skipped,
		&"script_path": script_path, &"inserted": inserted, &"insert_note": insert_note,
	}

func _collect_descendants(node: Node, out: Array) -> void:
	for c in node.get_children():
		out.append(c)
		_collect_descendants(c, out)

func _is_valid_ident(s: String) -> bool:
	if s.is_empty():
		return false
	var re := RegEx.new()
	re.compile("^[a-zA-Z_][a-zA-Z0-9_]*$")
	return re.search(s) != null

## Prefer the node's script global class_name, else the engine class.
func _node_type_name(n: Node) -> String:
	var scr := n.get_script()
	if scr is Script:
		var gn := str((scr as Script).get_global_name())
		if not gn.is_empty():
			return gn
	return n.get_class()

## Insert @onready lines after the script header, skipping already-declared vars.
## Returns [inserted: bool, note: String].
func _insert_onready_block(script_path: String, lines: Array) -> Array:
	var f := FileAccess.open(script_path, FileAccess.READ)
	if f == null:
		return [false, "could not read script"]
	var content := f.get_as_text()
	f.close()

	var fresh: Array = []
	for line in lines:
		var vn := _var_name_of(line)
		var re := RegEx.new()
		re.compile("(?m)^\\s*(@onready\\s+)?var\\s+" + vn + "\\b")
		if re.search(content) == null:
			fresh.append(line)
	if fresh.is_empty():
		return [false, "all vars already declared"]

	var src_lines := content.split("\n")
	var insert_at := 0
	for i in range(src_lines.size()):
		var t := str(src_lines[i]).strip_edges()
		if t.begins_with("@tool") or t.begins_with("class_name") or t.begins_with("extends"):
			insert_at = i + 1
	var block_lines: Array = [""]
	for line in fresh:
		block_lines.append(line)

	var merged: Array = []
	if insert_at <= 0:
		merged.append_array(block_lines)
	for i in range(src_lines.size()):
		merged.append(src_lines[i])
		if insert_at > 0 and i == insert_at - 1:
			merged.append_array(block_lines)

	var wf := FileAccess.open(script_path, FileAccess.WRITE)
	if wf == null:
		return [false, "could not write script"]
	wf.store_string("\n".join(merged))
	wf.close()
	_refresh_filesystem()
	return [true, "inserted %d refs after header" % fresh.size()]

func _var_name_of(onready_line: String) -> String:
	var re := RegEx.new()
	re.compile("var\\s+([a-zA-Z_][a-zA-Z0-9_]*)")
	var m := re.search(onready_line)
	return m.get_string(1) if m else ""

# =============================================================================
# scaffold_entity — the canonical player/enemy setup in one call: physics body
# root + CollisionShape2D/3D (with an actual shape resource, so the "node has no
# shape" warning never appears) + a sprite + an optional movement script.
# This is the sequence every Godot tutorial repeats by hand for each character.
# =============================================================================
const _BODY_DEFAULTS := {
	"CharacterBody2D": "2D", "RigidBody2D": "2D", "StaticBody2D": "2D", "Area2D": "2D",
	"CharacterBody3D": "3D", "RigidBody3D": "3D", "StaticBody3D": "3D", "Area3D": "3D",
}

func scaffold_entity(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var entity_name: String = str(args.get(&"entity_name", ""))
	var body_type: String = str(args.get(&"body_type", "CharacterBody2D"))
	var shape: String = str(args.get(&"collision_shape", "capsule"))
	var shape_params: Dictionary = args.get(&"shape_params", {})
	var sprite_type: String = str(args.get(&"sprite", "Sprite2D"))
	var texture: String = str(args.get(&"texture", ""))
	var script_path: String = str(args.get(&"script_path", ""))
	var movement: String = str(args.get(&"movement", "none"))
	var groups: Array = args.get(&"groups", [])

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if not _BODY_DEFAULTS.has(body_type):
		return {&"ok": false, &"error": "Unsupported body_type '%s'. Use one of: %s" % [body_type, ", ".join(_BODY_DEFAULTS.keys())]}
	if entity_name.strip_edges().is_empty():
		entity_name = str(scene_path.get_file().get_basename()).to_pascal_case()

	var dim: String = _BODY_DEFAULTS[body_type]
	if movement != "none" and dim == "3D":
		return {&"ok": false, &"error": "movement templates are 2D-only for now; pass movement:\"none\" for a 3D body"}
	if movement != "none" and body_type != "CharacterBody2D":
		return {&"ok": false, &"error": "movement templates require body_type CharacterBody2D (got %s)" % body_type}

	var created: Array = []
	var cs_type := "CollisionShape2D" if dim == "2D" else "CollisionShape3D"
	if sprite_type == "Sprite2D" and dim == "3D":
		sprite_type = "MeshInstance3D"

	var cr := create_scene({
		&"scene_path": scene_path, &"root_node_name": entity_name, &"root_node_type": body_type,
	})
	if not cr.get(&"ok", true):
		return cr
	created.append("%s (%s)" % [entity_name, body_type])

	var ar := add_node({&"scene_path": scene_path, &"parent_path": ".", &"node_type": cs_type, &"node_name": "CollisionShape"})
	if not ar.get(&"ok", true):
		return ar
	created.append("CollisionShape (%s)" % cs_type)

	# Give the collision node a real shape resource. Without this the body warns
	# and silently collides with nothing — the single most common scaffold bug.
	var shape_type := _shape_class_for(shape, dim)
	if shape_type.is_empty():
		return {&"ok": false, &"error": "Unsupported collision_shape '%s' for %s" % [shape, dim]}
	var sr := set_collision_shape({
		&"scene_path": scene_path, &"node_path": "CollisionShape",
		&"shape_type": shape_type, &"shape_params": shape_params,
	})
	if not sr.get(&"ok", true):
		return sr

	if sprite_type != "none":
		var sprops: Dictionary = {}
		if not texture.is_empty() and sprite_type in ["Sprite2D", "TextureRect"]:
			sprops["texture"] = texture
		var spr := add_node({
			&"scene_path": scene_path, &"parent_path": ".", &"node_type": sprite_type,
			&"node_name": "Sprite", &"properties": sprops,
		})
		if not spr.get(&"ok", true):
			return spr
		created.append("Sprite (%s)" % sprite_type)

	if not groups.is_empty():
		set_node_groups({&"scene_path": scene_path, &"node_path": ".", &"groups": groups})

	var script_written := ""
	if movement != "none" or not script_path.is_empty():
		if script_path.is_empty():
			script_path = scene_path.get_basename() + ".gd"
		script_path = _ensure_res_path(script_path)
		if not FileAccess.file_exists(script_path):
			var body := _movement_template(movement, body_type)
			var wf := FileAccess.open(script_path, FileAccess.WRITE)
			if wf == null:
				return {&"ok": false, &"error": "Could not write script: " + script_path}
			wf.store_string(body)
			wf.close()
			script_written = script_path
			_refresh_filesystem()
		var at := attach_script({&"scene_path": scene_path, &"node_path": ".", &"script_path": script_path})
		if not at.get(&"ok", true):
			return at

	return {
		&"ok": true, &"scene_path": scene_path, &"entity_name": entity_name,
		&"body_type": body_type, &"nodes_created": created,
		&"script_path": script_path, &"script_written": script_written,
		&"message": "Scaffolded %s with %d nodes%s" % [entity_name, created.size(), (" + " + movement + " movement script") if movement != "none" else ""],
	}

func _shape_class_for(shape: String, dim: String) -> String:
	var s := shape.to_lower()
	if dim == "2D":
		match s:
			"capsule": return "CapsuleShape2D"
			"rect", "rectangle", "box": return "RectangleShape2D"
			"circle": return "CircleShape2D"
	else:
		match s:
			"capsule": return "CapsuleShape3D"
			"rect", "rectangle", "box": return "BoxShape3D"
			"circle", "sphere": return "SphereShape3D"
	return ""

## Starter movement scripts. Kept close to the official docs' versions so the
## generated code is what a Godot dev expects to read, not a bespoke dialect.
func _movement_template(movement: String, _body_type: String) -> String:
	match movement:
		"platformer":
			return """extends CharacterBody2D

const SPEED := 300.0
const JUMP_VELOCITY := -400.0


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)

	move_and_slide()
"""
		"topdown":
			return """extends CharacterBody2D

const SPEED := 300.0


func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = direction * SPEED
	move_and_slide()
"""
		_:
			return """extends CharacterBody2D


func _physics_process(_delta: float) -> void:
	pass
"""

# =============================================================================
# scaffold_state_machine — a StateMachine node plus one script per state, wired
# to a shared base State class. Replaces the copy-paste-the-enemy-FSM ritual.
# =============================================================================
func scaffold_state_machine(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var host_path: String = str(args.get(&"host_path", "."))
	var states: Array = args.get(&"states", [])
	var out_dir: String = str(args.get(&"out_dir", ""))
	var machine_name: String = str(args.get(&"machine_name", "StateMachine"))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if states.is_empty():
		return {&"ok": false, &"error": "Provide at least one state name in 'states', e.g. [\"idle\",\"chase\"]"}

	if out_dir.strip_edges().is_empty():
		out_dir = str(scene_path.get_base_dir()).path_join("states")
	out_dir = _ensure_res_path(out_dir)
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(out_dir)):
		var mkerr := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		if mkerr != OK:
			return {&"ok": false, &"error": "Could not create %s (error %d)" % [out_dir, mkerr]}

	# Base class first: every state script extends it, so it must exist on disk
	# before the state scripts are attached or they fail to parse.
	var base_path := out_dir.path_join("state.gd")
	var written: Array = []
	if not FileAccess.file_exists(base_path):
		var bf := FileAccess.open(base_path, FileAccess.WRITE)
		if bf == null:
			return {&"ok": false, &"error": "Could not write " + base_path}
		bf.store_string(_state_base_template())
		bf.close()
		written.append(base_path)

	var machine_path := out_dir.path_join("state_machine.gd")
	if not FileAccess.file_exists(machine_path):
		var mf := FileAccess.open(machine_path, FileAccess.WRITE)
		if mf == null:
			return {&"ok": false, &"error": "Could not write " + machine_path}
		mf.store_string(_state_machine_template(base_path))
		mf.close()
		written.append(machine_path)
	_refresh_filesystem()

	var mr := add_node({
		&"scene_path": scene_path, &"parent_path": host_path,
		&"node_type": "Node", &"node_name": machine_name, &"script": machine_path,
	})
	if not mr.get(&"ok", true):
		return mr

	var machine_node_path := machine_name if host_path == "." else host_path + "/" + machine_name
	var state_nodes: Array = []
	for s in states:
		var raw := str(s).strip_edges()
		if raw.is_empty():
			continue
		var node_name := raw.to_pascal_case()
		var file_path := out_dir.path_join(raw.to_snake_case() + "_state.gd")
		if not FileAccess.file_exists(file_path):
			var sf := FileAccess.open(file_path, FileAccess.WRITE)
			if sf == null:
				return {&"ok": false, &"error": "Could not write " + file_path}
			sf.store_string(_state_template(node_name, base_path))
			sf.close()
			written.append(file_path)
		_refresh_filesystem()
		var nr := add_node({
			&"scene_path": scene_path, &"parent_path": machine_node_path,
			&"node_type": "Node", &"node_name": node_name, &"script": file_path,
		})
		if not nr.get(&"ok", true):
			return nr
		state_nodes.append(node_name)

	# Point the machine at the first state so it runs without hand-editing.
	if not state_nodes.is_empty():
		set_node_properties({
			&"scene_path": scene_path, &"node_path": machine_node_path,
			&"properties": {"initial_state": NodePath(str(state_nodes[0]))},
		})

	return {
		&"ok": true, &"scene_path": scene_path, &"machine_node": machine_node_path,
		&"states": state_nodes, &"scripts_written": written, &"out_dir": out_dir,
		&"initial_state": state_nodes[0] if not state_nodes.is_empty() else "",
		&"message": "Scaffolded %s with %d states (%d scripts written)" % [machine_name, state_nodes.size(), written.size()],
	}

## The generated scripts reference each other with preload() rather than
## `class_name`. Declaring global classes named State/StateMachine would collide
## with any FSM the project already has -- and a global-class collision is a
## project-wide parse error, not a local one.
func _state_base_template() -> String:
	return """extends Node
## Base class for a single state. The machine calls enter/exit around
## transitions and forwards the per-frame callbacks to the active state.

## Emit with a state name to ask the machine to transition.
signal transition_requested(next_state: StringName)

## The node this state acts on (set by the StateMachine on ready).
var host: Node


func enter(_previous: StringName) -> void:
	pass


func exit() -> void:
	pass


func update(_delta: float) -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


func handle_input(_event: InputEvent) -> void:
	pass
"""

func _state_machine_template(base_path: String) -> String:
	return """extends Node
## Owns the child state nodes (see __BASE_PATH__) and forwards frame callbacks
## to the active one.
##
## States are recognised by having an `enter` method rather than by a static
## type: giving the base a `class_name` would collide with any FSM the project
## already has, and a global-class collision breaks the whole project.

@export var initial_state: NodePath

var current: Node
var host: Node


func _ready() -> void:
	# The machine drives whatever it hangs off of, so states can act on the
	# character without each one re-deriving the reference.
	host = get_parent()
	for child in get_children():
		if _is_state(child):
			child.host = host
			child.transition_requested.connect(_on_transition_requested)

	var start: Node = get_node_or_null(initial_state)
	if start == null and get_child_count() > 0:
		start = get_child(0)
	if start and _is_state(start):
		current = start
		current.enter(&"")


func _is_state(node: Node) -> bool:
	return node.has_method(&"enter") and node.has_signal(&"transition_requested")


func _process(delta: float) -> void:
	if current:
		current.update(delta)


func _physics_process(delta: float) -> void:
	if current:
		current.physics_update(delta)


func _unhandled_input(event: InputEvent) -> void:
	if current:
		current.handle_input(event)


func transition_to(state_name: StringName) -> void:
	var next: Node = get_node_or_null(NodePath(str(state_name)))
	if next == null or not _is_state(next):
		push_warning("StateMachine: no state named '%s'" % state_name)
		return
	if next == current:
		return
	var previous := current.name if current else &""
	if current:
		current.exit()
	current = next
	current.enter(previous)


func _on_transition_requested(next_state: StringName) -> void:
	transition_to(next_state)
""".replace("__BASE_PATH__", base_path)

func _state_template(state_name: String, base_path: String) -> String:
	return """extends \"__BASE_PATH__\"
## __STATE_NAME__ state. Request a change with:
##     transition_requested.emit(&\"OtherState\")


func enter(_previous: StringName) -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


func exit() -> void:
	pass
""".replace("__BASE_PATH__", base_path).replace("__STATE_NAME__", state_name)

## Re-read the saved .tscn and confirm the [connection] is there. This catches
## the silent "pack stripped it" case.
func _signal_is_persisted(scene_path: String, from_node: String, signal_name: String, to_node: String, method: String) -> bool:
	# Force re-read from disk; the resource we just saved may still be cached
	# in memory from the in-editor loader.
	var packed := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return false
	var st := packed.get_state()
	var want_from := NodePath(from_node).get_concatenated_names()
	var want_to := NodePath(to_node).get_concatenated_names()
	for i in range(st.get_connection_count()):
		var src_path: NodePath = st.get_connection_source(i)
		var dst_path: NodePath = st.get_connection_target(i)
		var sig: StringName = st.get_connection_signal(i)
		var mth: StringName = st.get_connection_method(i)
		if String(sig) != signal_name or String(mth) != method:
			continue
		if src_path.get_concatenated_names() == want_from and dst_path.get_concatenated_names() == want_to:
			return true
	return false

func disconnect_signal(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var from_node: String = str(args.get(&"from_node", ""))
	var signal_name: String = str(args.get(&"signal", ""))
	var to_node: String = str(args.get(&"to_node", ""))
	var method: String = str(args.get(&"method", ""))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if from_node.is_empty() or signal_name.is_empty() or to_node.is_empty() or method.is_empty():
		return {&"ok": false, &"error": "from_node, signal, to_node, and method are all required"}

	# _acquire_scene, not _load_scene: on an OPEN scene, loading a disk copy and
	# saving it back discards the editor's unsaved state and the reload that
	# follows wipes the live tree with it.
	var acq := _acquire_scene(scene_path)
	if not acq[2].is_empty():
		return acq[2]
	var root: Node = acq[0]
	var is_live: bool = acq[1]
	var src := _find_node(root, from_node)
	var dst := _find_node(root, to_node)
	if not src or not dst:
		# Which one. "from_node or to_node not found" sent the caller to check
		# both, and the near-miss list is the part that actually resolves it.
		var missing := from_node if not src else to_node
		var label := "from_node" if not src else "to_node"
		var err := _node_not_found(root, missing, label)
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": str(err.get(&"error", "%s not found: %s" % [label, missing]))}

	var callable := Callable(dst, method)
	if not src.is_connected(signal_name, callable):
		_discard_scene(root, is_live)
		return {&"ok": true, &"already_disconnected": true,
			&"message": "Connection did not exist; no change."}

	src.disconnect(signal_name, callable)

	var serr := _finish_scene_edit(root, scene_path, is_live)
	if not serr.is_empty():
		return serr

	return {
		&"ok": true,
		&"message": "Disconnected %s.%s -> %s.%s" % [from_node, signal_name, to_node, method],
	}
