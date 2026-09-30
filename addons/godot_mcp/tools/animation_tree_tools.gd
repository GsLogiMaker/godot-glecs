@tool
extends SceneToolBase
class_name AnimationTreeTools
## AnimationTree / state machine tools for MCP.
## Handles: create_animation_tree, get_animation_tree_structure,
##          add_state_machine_state, remove_state_machine_state,
##          add_state_machine_transition, remove_state_machine_transition


# =============================================================================
# create_animation_tree
# =============================================================================
## anim_player_path is assumed to already be relative to the new AnimationTree
## node (i.e. the caller supplies the NodePath as Godot's `anim_player`
## property expects it, typically "../<AnimationPlayerName>").
func create_animation_tree(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var parent_path: String = str(args.get(&"parent_path", "."))
	var anim_player_path: String = str(args.get(&"anim_player_path", ""))
	var node_name: String = str(args.get(&"node_name", ""))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if anim_player_path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'anim_player_path'"}
	if node_name.strip_edges().is_empty():
		node_name = "AnimationTree"

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

	var tree := AnimationTree.new()
	tree.name = node_name
	# Undo entry opened here, after the validations above: an action left open
	# by an early return would sit unclosed on the editor's undo stack.
	var ctx := _begin_edit(is_live, "MCP: add %s" % tree.name, root)
	_edit_add_child(ctx, parent, tree, root)
	_edit_commit(ctx)

	_edit_set(ctx, tree, &"anim_player", NodePath(anim_player_path))
	_edit_set(ctx, tree, &"tree_root", AnimationNodeStateMachine.new())
	_edit_set(ctx, tree, &"active", true)
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_name": tree.name,
		&"message": "Added AnimationTree '%s' to '%s'" % [tree.name, parent_path]}

# =============================================================================
# get_animation_tree_structure
# =============================================================================
func get_animation_tree_structure(args: Dictionary) -> Dictionary:
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
	if not (target is AnimationTree):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) is not an AnimationTree" % [node_path, target.get_class()]}

	var tree_root = target.get(&"tree_root")
	if tree_root == null:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "AnimationTree has no tree_root set — call create_animation_tree or set one first"}
	if not (tree_root is AnimationNodeStateMachine):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "tree_root is not a state machine, it's a %s" % tree_root.get_class()}

	var state_machine: AnimationNodeStateMachine = tree_root

	var states: Array = []
	for state_name in state_machine.get_node_list():
		var node = state_machine.get_node(state_name)
		var position: Vector2 = state_machine.get_node_position(state_name)
		var animation: String = ""
		if node is AnimationNodeAnimation:
			animation = String(node.get(&"animation"))
		states.append({&"name": state_name, &"position": {&"x": position.x, &"y": position.y}, &"animation": animation})

	var transitions: Array = []
	for i in range(state_machine.get_transition_count()):
		var from: String = state_machine.get_transition_from(i)
		var to: String = state_machine.get_transition_to(i)
		var transition: AnimationNodeStateMachineTransition = state_machine.get_transition(i)
		transitions.append({
			&"from": from,
			&"to": to,
			&"switch_mode": transition.get(&"switch_mode"),
			&"advance_mode": transition.get(&"advance_mode"),
			&"advance_condition": String(transition.get(&"advance_condition")),
			&"xfade_time": transition.get(&"xfade_time"),
		})

	_discard_scene(root, is_live)
	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"states": states, &"transitions": transitions}

# =============================================================================
# add_state_machine_state
# =============================================================================
func add_state_machine_state(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var state_name: String = str(args.get(&"state_name", ""))
	var animation_name: String = str(args.get(&"animation_name", ""))
	var position_arg = args.get(&"position")

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if state_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'state_name'"}
	if animation_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'animation_name'"}

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
	if not (target is AnimationTree):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) is not an AnimationTree" % [node_path, target.get_class()]}

	var tree_root = target.get(&"tree_root")
	if tree_root == null:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "AnimationTree has no tree_root set — call create_animation_tree or set one first"}
	if not (tree_root is AnimationNodeStateMachine):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "tree_root is not a state machine, it's a %s" % tree_root.get_class()}

	var state_machine: AnimationNodeStateMachine = tree_root

	if state_machine.has_node(state_name):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "State '%s' already exists" % state_name}

	var position: Vector2 = VariantCodec.parse_value(position_arg) if position_arg != null else Vector2.ZERO

	var anim_node := AnimationNodeAnimation.new()
	anim_node.set(&"animation", StringName(animation_name))
	var ctx := _begin_edit(is_live, "MCP: add state '%s'" % state_name, root)
	state_machine.add_node(state_name, anim_node, position)
	_edit_record(ctx, state_machine, &"add_node", [state_name, anim_node, position],
		&"remove_node", [state_name])
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"state_name": state_name, &"animation_name": animation_name,
		&"message": "Added state '%s' (%s) to state machine" % [state_name, animation_name]}

# =============================================================================
# remove_state_machine_state
# =============================================================================
func remove_state_machine_state(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var state_name: String = str(args.get(&"state_name", ""))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if state_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'state_name'"}

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
	if not (target is AnimationTree):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) is not an AnimationTree" % [node_path, target.get_class()]}

	var tree_root = target.get(&"tree_root")
	if tree_root == null:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "AnimationTree has no tree_root set — call create_animation_tree or set one first"}
	if not (tree_root is AnimationNodeStateMachine):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "tree_root is not a state machine, it's a %s" % tree_root.get_class()}

	var state_machine: AnimationNodeStateMachine = tree_root

	if not state_machine.has_node(state_name):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "State '%s' does not exist" % state_name}

	# Capture the node and its layout position first: without them undo could
	# only recreate an empty state in the wrong place.
	var removed_node := state_machine.get_node(state_name)
	var removed_pos := state_machine.get_node_position(state_name)
	var ctx := _begin_edit(is_live, "MCP: remove state '%s'" % state_name, root)
	state_machine.remove_node(state_name)
	_edit_record(ctx, state_machine, &"remove_node", [state_name],
		&"add_node", [state_name, removed_node, removed_pos])
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"state_name": state_name, &"message": "Removed state '%s'" % state_name}

# =============================================================================
# add_state_machine_transition
# =============================================================================
## switch_mode: "immediate"|"sync"|"at_end" (default "immediate")
## advance_mode: "disabled"|"enabled"|"auto" — defaults to "auto" if
## advance_condition is provided, otherwise "enabled".
func add_state_machine_transition(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var from: String = str(args.get(&"from", ""))
	var to: String = str(args.get(&"to", ""))
	var switch_mode_str: String = str(args.get(&"switch_mode", "immediate"))
	var advance_condition = args.get(&"advance_condition")
	var advance_mode_str: String = str(args.get(&"advance_mode", "auto" if advance_condition != null else "enabled"))
	var xfade_time = args.get(&"xfade_time")

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if from.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'from'"}
	if to.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'to'"}

	var switch_modes := {
		"immediate": AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE,
		"sync": AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC,
		"at_end": AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END,
	}
	var advance_modes := {
		"disabled": AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED,
		"enabled": AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED,
		"auto": AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO,
	}
	if not switch_modes.has(switch_mode_str):
		return {&"ok": false, &"error": "Invalid 'switch_mode': %s. Use 'immediate', 'sync' or 'at_end'." % switch_mode_str}
	if not advance_modes.has(advance_mode_str):
		return {&"ok": false, &"error": "Invalid 'advance_mode': %s. Use 'disabled', 'enabled' or 'auto'." % advance_mode_str}

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
	if not (target is AnimationTree):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) is not an AnimationTree" % [node_path, target.get_class()]}

	var tree_root = target.get(&"tree_root")
	if tree_root == null:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "AnimationTree has no tree_root set — call create_animation_tree or set one first"}
	if not (tree_root is AnimationNodeStateMachine):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "tree_root is not a state machine, it's a %s" % tree_root.get_class()}

	var state_machine: AnimationNodeStateMachine = tree_root

	if not state_machine.has_node(from):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "State '%s' (from) does not exist" % from}
	if not state_machine.has_node(to):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "State '%s' (to) does not exist" % to}
	if state_machine.has_transition(from, to):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Transition '%s' -> '%s' already exists" % [from, to]}

	var transition := AnimationNodeStateMachineTransition.new()
	transition.set(&"switch_mode", switch_modes[switch_mode_str])
	transition.set(&"advance_mode", advance_modes[advance_mode_str])
	if advance_condition != null:
		transition.set(&"advance_condition", StringName(str(advance_condition)))
	if xfade_time != null:
		transition.set(&"xfade_time", float(xfade_time))

	var ctx := _begin_edit(is_live, "MCP: add transition %s -> %s" % [from, to], root)
	state_machine.add_transition(from, to, transition)
	_edit_record(ctx, state_machine, &"add_transition", [from, to, transition],
		&"remove_transition", [from, to])
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"from": from, &"to": to, &"message": "Added transition '%s' -> '%s'" % [from, to]}

# =============================================================================
# remove_state_machine_transition
# =============================================================================
func remove_state_machine_transition(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var from: String = str(args.get(&"from", ""))
	var to: String = str(args.get(&"to", ""))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if from.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'from'"}
	if to.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'to'"}

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
	if not (target is AnimationTree):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) is not an AnimationTree" % [node_path, target.get_class()]}

	var tree_root = target.get(&"tree_root")
	if tree_root == null:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "AnimationTree has no tree_root set — call create_animation_tree or set one first"}
	if not (tree_root is AnimationNodeStateMachine):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "tree_root is not a state machine, it's a %s" % tree_root.get_class()}

	var state_machine: AnimationNodeStateMachine = tree_root

	if not state_machine.has_transition(from, to):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Transition '%s' -> '%s' does not exist" % [from, to]}

	# AnimationNodeStateMachine has no find_transition(): the index has to be
	# located by walking from/to. Calling the nonexistent method aborted this
	# function mid-edit, so the tool returned an empty dictionary — neither
	# success nor error — with the undo action left open.
	var removed_transition: AnimationNodeStateMachineTransition = null
	for i in range(state_machine.get_transition_count()):
		if str(state_machine.get_transition_from(i)) == from and str(state_machine.get_transition_to(i)) == to:
			removed_transition = state_machine.get_transition(i)
			break

	var ctx := _begin_edit(is_live, "MCP: remove transition %s -> %s" % [from, to], root)
	state_machine.remove_transition(from, to)
	_edit_record(ctx, state_machine, &"remove_transition", [from, to],
		&"add_transition", [from, to, removed_transition])
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"from": from, &"to": to, &"message": "Removed transition '%s' -> '%s'" % [from, to]}
