@tool
extends Node
class_name SceneToolBase
## Shared base for every tool node that reads or mutates scenes. Centralizes the
## helpers that were previously copy-pasted — and had started to diverge — across
## ~12 tool files: path sanitizing, scene load/save, node lookup, editor refresh,
## and the live-editor-tree detection used to avoid clobbering unsaved edits.
##
## Before this existed, `_load_scene` had 3 different implementations and only
## scene_tools.gd carried the live-tree route, so every other scene-editing tool
## silently overwrote unsaved editor changes. Keeping one copy here means a fix
## lands everywhere at once. Tool files `extends SceneToolBase` and drop their
## local copies.

const VariantCodec = preload("res://addons/godot_mcp/utils/variant_codec.gd")
const PathGuard = preload("res://addons/godot_mcp/utils/path_guard.gd")

var _editor_plugin: EditorPlugin = null

func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin

func _refresh_filesystem() -> void:
	if _editor_plugin:
		_editor_plugin.get_editor_interface().get_resource_filesystem().scan()

## Rescan the filesystem and, if the edited scene is the one that changed on disk,
## reload it so the editor view matches. Only meaningful after a disk save.
func _refresh_and_reload(scene_path: String) -> void:
	if _editor_plugin:
		var ei = _editor_plugin.get_editor_interface()
		ei.get_resource_filesystem().scan()
		var edited = ei.get_edited_scene_root()
		if edited and edited.scene_file_path == scene_path:
			ei.reload_scene_from_path(scene_path)

## Sanitizes a res://-relative path and blocks traversal outside the project
## (e.g. "../../../Windows/System32"). On rejection returns a path that can never
## resolve to a real file, so every downstream FileAccess/load() fails closed with
## a clear error instead of silently escaping the sandbox. See MERGE_NOTES.md — a
## plain "res://" prefix check does NOT stop "../" traversal.
func _ensure_res_path(path: String) -> String:
	var guarded := PathGuard.sanitize(path)
	if not guarded[&"ok"]:
		if path.strip_edges().is_empty():
			return PathGuard.MISSING
		push_warning("[MCP] Rejected path outside project sandbox: %s (%s)" % [path, guarded[&"error"]])
		return PathGuard.REJECTED
	return guarded[&"path"]

## If `scene_path` is the scene currently open in the editor, return its LIVE root
## (the tree holding the user's unsaved edits). Otherwise null. Mutating this live
## tree (ideally via _get_undo_redo) is undo-safe and does NOT clobber unsaved
## changes — unlike the disk load→save path, which overwrites whatever wasn't saved.
func _edited_root_if_open(scene_path: String) -> Node:
	# A preview must not touch the open scene at all: editing the live tree
	# marks it unsaved and pushes an undo entry, which is a change the caller
	# did not ask for. Dry runs therefore always take the disk path, where the
	# work happens on a throwaway copy.
	if _dry_run:
		return null
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

## Returns [scene_root, error_dict]. If error_dict is not empty, scene_root is null.
## The instantiated tree is a disk copy the caller owns and must free (or hand to
## _save_scene / _finish_scene_edit, which free it).
func _load_scene(scene_path: String) -> Array:
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

## Instantiate with the right edit-state flag so sub-resources and inherited
## scenes round-trip correctly through a re-save (a plain instantiate() loses
## edit state and can corrupt inherited scenes). `as_instance` is for embedding
## one scene inside another (instance_scene).
func _instantiate_packed_scene_for_edit(packed: PackedScene, as_instance: bool = false) -> Node:
	if not packed:
		return null
	if not Engine.is_editor_hint():
		return packed.instantiate()
	if as_instance:
		return packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var state = packed.get_state()
	if state and state.get_base_scene_state() != null:
		return packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN_INHERITED)
	return packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)

## Pack and save a disk-loaded scene root, then free it. Returns {} on success or
## an error dict. NEVER call this on a live edited root — it frees the node.
## Set by the ToolExecutor for the duration of one call when the caller passed
## dry_run. Lives here rather than in each tool because every scene mutation in
## this addon funnels through the two helpers below: honour it once and every
## tool that edits a scene previews correctly, including ones written later.
var _dry_run := false

## True when the current call previewed instead of writing. The executor reads
## it to label the answer, so a tool cannot forget to say it did nothing.
var _dry_run_skipped_write := false


func _save_scene(scene_root: Node, scene_path: String) -> Dictionary:
	if PathGuard.is_bad(scene_path):
		scene_root.queue_free()
		return PathGuard.error_for(scene_path, "scene_path")
	if _dry_run:
		# The mutation already happened in memory, on a copy loaded from disk;
		# throwing it away here is what makes the preview free. The scene file
		# is never opened for writing, so its bytes cannot change.
		_dry_run_skipped_write = true
		scene_root.queue_free()
		return {}
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
	var found := scene_root.get_node_or_null(node_path)
	if found != null:
		return found
	# Callers routinely write the path the way a scene dump prints it, rooted at
	# the root's own name ("Player" or "Player/Sprite2D") rather than relative to
	# it. Godot resolves neither. Accept both, but only after the literal lookup
	# missed, so a child that happens to share the root's name still wins.
	var root_name := String(scene_root.name)
	if node_path == root_name:
		return scene_root
	if node_path.begins_with(root_name + "/"):
		return scene_root.get_node_or_null(node_path.substr(root_name.length() + 1))
	return null

## Standard error for a node path that did not resolve.
##
## "Node not found: Player/Sprite" tells an agent that it was wrong; it does not
## tell it what to try instead, and the usual next move is another guess. This
## answers with the paths that DO exist, so one failed call is enough.
## `label` distinguishes which argument was bad ("Parent node", "from_node").
func _node_not_found(scene_root: Node, node_path: String, label: String = "Node") -> Dictionary:
	var available := _node_paths_in(scene_root)
	var near: Array[String] = []
	for candidate in available:
		# Godot's own similarity, so a near-miss on case or a missing segment
		# still surfaces. 0.6 keeps the list short enough to be a suggestion.
		if node_path.similarity(candidate) >= 0.6:
			near.append(candidate)

	var hint := ""
	if not near.is_empty():
		hint = " Did you mean: %s?" % ", ".join(near.slice(0, 5))
	elif not available.is_empty():
		var shown: Array[String] = available.slice(0, 20)
		hint = " Paths in this scene: %s%s." % [
			", ".join(shown),
			" (+%d more)" % (available.size() - shown.size()) if available.size() > shown.size() else "",
		]
	return {&"ok": false, &"error": "%s not found: '%s'.%s" % [label, node_path, hint]}

## Every node path in the scene, relative to its root, "." for the root itself.
func _node_paths_in(scene_root: Node) -> Array[String]:
	var out: Array[String] = ["."]
	if scene_root == null:
		return out
	_collect_node_paths(scene_root, scene_root, out)
	return out

func _collect_node_paths(scene_root: Node, node: Node, out: Array[String]) -> void:
	for child in node.get_children():
		out.append(str(scene_root.get_path_to(child)))
		_collect_node_paths(scene_root, child, out)

## The dimension a node lives in, or "" when it says nothing either way.
##
## Tools that take an explicit `dimension` defaulted to "2D" no matter what they
## were building into, so a NavigationRegion2D or a RayCast2D landed under a
## Node3D and did nothing — with an ok answer. Infer from the parent instead;
## an explicit argument still wins.
func _dimension_of(node: Node) -> String:
	if node is Node3D:
		return "3D"
	if node is CanvasItem:
		return "2D"
	return ""

func _parse_value(value: Variant) -> Variant:
	return VariantCodec.parse_value(value)

func _parse_typed_value(value: Variant, type_hint: int) -> Variant:
	return VariantCodec.parse_typed_value(value, type_hint)

func _serialize_value(value: Variant) -> Variant:
	return VariantCodec.serialize_value(value)

## Apply properties to a node. RETURNS the names it could not apply, because a
## property the node does not have is the failure mode that costs the most time:
## `node.set()` on an unknown name does nothing at all and reports nothing.
##
## That is not hypothetical. Building a game with these tools, a scene was
## created with `max_health: 400` and came back with 100 — the node's script had
## not compiled yet, so the exported property did not exist, and create_scene
## answered "ok". The wrong value was only noticed hours later, at runtime.
## Callers must surface what comes back here.
func _set_node_properties(node: Node, properties: Dictionary) -> Array[String]:
	# Parse against the property's DECLARED type rather than guessing from the
	# value's shape. Without the hint, `[100, 100]` for a Vector2 property stays
	# an Array, `node.set()` quietly does nothing, and the caller gets "set had
	# no effect (type mismatch?)" for a value that reads perfectly natural — and
	# that some other tools here do accept.
	var types := _property_type_map(node)
	var unknown: Array[String] = []
	for prop_name: String in properties:
		if not types.has(prop_name):
			unknown.append(prop_name)
			continue
		var hint: int = int(types.get(prop_name, -1))
		var wanted: Variant = VariantCodec.parse_typed_value(properties[prop_name], hint)
		node.set(prop_name, wanted)

		# Read it back. A property can exist, accept the assignment without
		# complaint, and still hold something else — Godot clamps and coerces
		# silently. A TextureRect asked for size.y = 6.667 keeps 16, because a
		# Control's minimum size is its texture's; the scene then looks wrong for
		# reasons nothing reported. Cheap to check, and it is the only way the
		# caller finds out.
		if not _values_match(node.get(prop_name), wanted):
			_note_property_mismatch(node, prop_name, wanted, node.get(prop_name))
	return unknown

## Did the value that landed match what was asked for?
##
## Lives in the base because more than one tool needs it. It was previously
## defined on SceneTools alone, so anything else extending this class that
## compared a written value got no implementation at all — and a second copy
## written here would have re-broken the number case below, which is a bug this
## project has already shipped once.
func _values_match(a: Variant, b: Variant) -> bool:
	if typeof(a) == typeof(b):
		# Floating point: an exact == on values that round-tripped through the
		# codec reports a mismatch for the last decimal place.
		match typeof(a):
			TYPE_FLOAT:
				return is_equal_approx(a, b)
			TYPE_VECTOR2:
				return (a as Vector2).is_equal_approx(b)
			TYPE_VECTOR3:
				return (a as Vector3).is_equal_approx(b)
			TYPE_RECT2:
				return (a as Rect2).is_equal_approx(b)
			TYPE_COLOR:
				return (a as Color).is_equal_approx(b)
			_:
				return a == b

	# Numbers must be compared numerically, not as text.
	#
	# JSON has one number type, so every integer an MCP client sends arrives as a
	# float. Setting an int property with it works — Godot coerces — but the
	# read-back returns an int, and a string fallback compares "1" against "1.0"
	# and calls a perfectly good write a failure. That is why setting
	# collision_layer/collision_mask once reported "set had no effect (type
	# mismatch?)", and why a single-property call then saved nothing at all.
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return str(a) == str(b)

func _note_property_mismatch(node: Node, property: String, wanted: Variant, actual: Variant) -> void:
	_pending_warnings.append("'%s.%s' was set to %s but holds %s — Godot clamped or coerced it (a Control's minimum size, an enum range, a node that rejects the value)." % [
		node.name, property, str(wanted), str(actual)])

## Warnings collected while building nodes, drained into the tool's response.
##
## A plain accumulator rather than a return value threaded through every call:
## node creation recurses through children, and widening five signatures to
## carry a warnings array would touch far more code than the problem is worth.
var _pending_warnings: Array[String] = []

## Start collecting. Call at the top of any tool that creates or edits nodes.
func _clear_warnings() -> void:
	_pending_warnings.clear()

## Record that a node rejected some properties. Names them AND the likely cause,
## since by far the most common one is a script the editor has not compiled yet.
func _note_unknown_properties(node: Node, unknown: Array[String]) -> void:
	if unknown.is_empty():
		return
	var script_hint := ""
	if node.get_script() != null:
		script_hint = " The node has a script — if it was created during this session the editor may not have compiled it yet: call rescan_filesystem, or restart_editor when the script declares a new class_name or autoload."
	_pending_warnings.append("Ignored %d propert%s not found on '%s' (%s): %s.%s" % [
		unknown.size(), "y" if unknown.size() == 1 else "ies",
		node.name, node.get_class(), ", ".join(unknown), script_hint])

## Merge any collected warnings into a tool response. Returns it unchanged when
## there is nothing to say, so a clean call stays clean.
func _with_warnings(result: Dictionary) -> Dictionary:
	if not _pending_warnings.is_empty():
		result[&"warnings"] = _pending_warnings.duplicate()
	return result

## name -> Variant.Type for the node's declared properties.
func _property_type_map(node: Object) -> Dictionary:
	var out: Dictionary = {}
	for p in node.get_property_list():
		out[str(p.get(&"name", ""))] = int(p.get(&"type", TYPE_NIL))
	return out

## Acquire the scene root to mutate. Returns [root, is_live, error_dict]:
##   - is_live true  → root is the editor's LIVE tree; mutate in place, do NOT
##                     free it, and pass is_live to _finish_scene_edit (no disk save).
##   - is_live false → root is a disk copy; caller must _finish_scene_edit to persist.
## This is the single choke point that makes scene-editing tools stop clobbering
## unsaved edits when the target scene is open.
func _acquire_scene(scene_path: String) -> Array:
	var live := _edited_root_if_open(scene_path)
	if live != null:
		return [live, true, {}]
	var r := _load_scene(scene_path)
	if not r[1].is_empty():
		return [null, false, r[1]]
	return [r[0], false, {}]

## Finish a scene edit started with _acquire_scene. Disk copy → pack+save (frees
## root). Live tree → mark the edited scene unsaved so the user sees the dirty
## marker and knows to save; the mutation already landed on the editor's tree and
## persists on save, unclobbered. Returns {} on success / error dict.
func _finish_scene_edit(root: Node, scene_path: String, is_live: bool) -> Dictionary:
	if _dry_run and is_live:
		# Should not be reachable: _edited_root_if_open refuses to hand out the
		# live root during a dry run, so a live edit cannot have started. Kept
		# because "should not" is not "cannot", and marking a scene unsaved is
		# exactly the side effect a preview must not have.
		_dry_run_skipped_write = true
		return {}
	if is_live:
		if _editor_plugin:
			_editor_plugin.get_editor_interface().mark_scene_as_unsaved()
		return {}
	return _save_scene(root, scene_path)

## Free a disk-loaded scene root on an error path. No-op when the root is the LIVE
## edited tree — freeing that would crash the editor. Lets tools keep their
## `root.queue_free()` error cleanup by swapping in `_discard_scene(root, is_live)`.
func _discard_scene(root: Node, is_live: bool) -> void:
	if not is_live and is_instance_valid(root):
		root.queue_free()

# ---------------------------------------------------------------------------
# Undoable live edits
# ---------------------------------------------------------------------------
# Only scene_tools.gd's structural ops used to register undo entries. Every other
# tool mutated the editor's live tree directly, so Ctrl+Z did nothing for them:
# the change was in the scene and the only way back was closing without saving.
#
# These helpers put an edit on Godot's own undo stack without changing how tools
# are written. The trick is that the write is applied IMMEDIATELY and the action
# is committed with `commit_action(false)` ("don't execute the do, it already
# happened"). That matters because tools routinely read a value back, or compute
# the next step from the mutated node — deferring the write until commit would
# silently break all of that.
#
# Usage, mirroring the plain code it replaces:
#
#     var ctx := _begin_edit(is_live, "MCP: set up lighting")
#     _edit_add_child(ctx, parent, light, root)
#     _edit_set(ctx, light, &"energy", 1.5)
#     _edit_commit(ctx)
#
# On the disk path (is_live false) every helper degrades to the direct call, so
# one code path covers both.

## Open an edit batch. Everything until _edit_commit lands as one undo entry.
##
## `context` MUST be a node belonging to the edited scene (the root, or the node
## being changed). It is not optional decoration: EditorUndoRedoManager keeps a
## separate undo history per scene, and with no explicit context it infers one
## from the FIRST object registered. Register a Resource first — a material, an
## AnimationLibrary — and the entry can land in a history that Ctrl+Z on the
## scene never reaches, so the edit looks undoable and isn't. That exact bug
## shipped in add_node, whose first registered object was the tool node itself.
func _begin_edit(is_live: bool, action_name: String, context: Object) -> Dictionary:
	var ur: EditorUndoRedoManager = _get_undo_redo() if is_live else null
	if ur:
		ur.create_action(action_name, UndoRedo.MERGE_DISABLE, context)
	return {&"ur": ur, &"dirty": false}

## Set a property now, and record how to put it back.
func _edit_set(ctx: Dictionary, obj: Object, prop: StringName, value: Variant) -> void:
	if not is_instance_valid(obj):
		return
	var old: Variant = obj.get(prop)
	obj.set(prop, value)
	var ur: EditorUndoRedoManager = ctx.get(&"ur")
	if ur:
		ur.add_do_property(obj, prop, value)
		ur.add_undo_property(obj, prop, old)
		ctx[&"dirty"] = true

## Apply a {name: value} batch, parsing each value the way tool args arrive.
func _edit_set_many(ctx: Dictionary, obj: Object, properties: Dictionary) -> void:
	for prop_name: String in properties:
		_edit_set(ctx, obj, StringName(prop_name), _parse_value(properties[prop_name]))

## Parent a node now, and record how to detach it.
##
## `owner` is set as part of the same action on purpose: a redo that re-adds the
## node without restoring its owner produces a node the scene dock shows but that
## never gets written to the .tscn — a corrupted-looking scene with no error.
func _edit_add_child(ctx: Dictionary, parent: Node, node: Node, root: Node) -> void:
	parent.add_child(node, true)
	node.owner = root
	var ur: EditorUndoRedoManager = ctx.get(&"ur")
	if ur:
		ur.add_do_method(parent, &"add_child", node, true)
		ur.add_do_property(node, &"owner", root)
		# Without this the node is freed once the action is undone, and redo
		# resurrects a dangling reference.
		ur.add_do_reference(node)
		ur.add_undo_method(parent, &"remove_child", node)
		ctx[&"dirty"] = true

## Record an edit whose inverse is another method call, for changes that aren't
## property writes: adding an animation track, inserting a keyframe, painting a
## tilemap cell. The call itself has already been made — this only teaches the
## undo stack how to replay and reverse it.
##
## Example, after `var idx := anim.add_track(type)`:
##     _edit_record(ctx, anim, &"add_track", [type], &"remove_track", [idx])
func _edit_record(ctx: Dictionary, obj: Object, do_method: StringName, do_args: Array,
		undo_method: StringName, undo_args: Array) -> void:
	var ur: EditorUndoRedoManager = ctx.get(&"ur")
	if ur == null or not is_instance_valid(obj):
		return
	# callv because add_do_method is variadic and the argument list is dynamic.
	ur.callv(&"add_do_method", [obj, do_method] + do_args)
	ur.callv(&"add_undo_method", [obj, undo_method] + undo_args)
	ctx[&"dirty"] = true

## Abandon an edit that has ALREADY written to the scene, putting it back.
##
## This is the structural answer to a bug shape this codebase has produced six
## times: a tool applies some properties, validates a later argument, fails, and
## calls `_discard_scene` — which is a no-op on an open scene, because the target
## IS the editor's live node rather than a copy. The tool then reports total
## failure with half its writes still applied.
##
## Validating everything before the first write avoids it and is still the better
## habit. But it isn't always possible (a value may only be checkable after an
## earlier one is set), and "remember the rule" is exactly what failed six times.
## With undo recorded for every live edit, the batch can simply be committed and
## immediately undone, which reverts it through the same machinery Ctrl+Z uses.
##
## Use this instead of `_discard_scene` on any error path reached after the first
## `_edit_*` call. Before the first write, `_discard_scene` is still correct and
## cheaper.
func _abort_edit(ctx: Dictionary, root: Node, is_live: bool) -> void:
	if not is_live:
		_edit_commit(ctx)
		_discard_scene(root, is_live)
		return

	# Nothing was written, so there is nothing to take back. Undoing anyway would
	# pop the PREVIOUS entry off the history and destroy unrelated work — caught
	# by the live harness, where an aborted tool silently deleted a node an
	# earlier test had added.
	var wrote_something := bool(ctx.get(&"dirty", false))
	_edit_commit(ctx)
	if not wrote_something:
		return

	var manager: EditorUndoRedoManager = ctx.get(&"ur")
	if manager == null or not is_instance_valid(root):
		return
	var ur: UndoRedo = manager.get_history_undo_redo(manager.get_object_history_id(root))
	if ur and ur.has_undo():
		ur.undo()

## Close the batch. `false` = the writes already happened; don't replay them.
func _edit_commit(ctx: Dictionary) -> void:
	var ur: EditorUndoRedoManager = ctx.get(&"ur")
	if ur:
		ur.commit_action(false)

## Abandon a batch that ended up writing nothing (a validation failure before the
## first write). Committing an empty action would put a no-op entry on the user's
## undo stack, so Ctrl+Z would appear to do nothing once.
func _edit_abort(ctx: Dictionary) -> void:
	var ur: EditorUndoRedoManager = ctx.get(&"ur")
	if ur and not bool(ctx.get(&"dirty", false)):
		ur.commit_action(false)
	ctx[&"ur"] = null
