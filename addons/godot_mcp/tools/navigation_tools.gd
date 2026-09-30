@tool
extends SceneToolBase
class_name NavigationTools
## Navigation tools for MCP.
## Handles: setup_navigation_region, bake_navigation_mesh,
##          setup_navigation_agent, set_navigation_layers, get_navigation_info


func _layers_to_mask(layers: Array) -> int:
	var mask := 0
	for l in layers:
		var idx := int(l)
		if idx >= 1 and idx <= 32:
			mask |= 1 << (idx - 1)
	return mask

func _mask_to_layers(mask: int) -> Array:
	var layers: Array = []
	for i in range(32):
		if mask & (1 << i):
			layers.append(i + 1)
	return layers

# =============================================================================
# setup_navigation_region
# =============================================================================
func setup_navigation_region(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var parent_path: String = str(args.get(&"parent_path", "."))
	var dimension: String = str(args.get(&"dimension", ""))
	var node_name: String = str(args.get(&"node_name", ""))

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

	var node_type: String = "NavigationRegion2D" if dimension == "2D" else "NavigationRegion3D"
	if node_name.strip_edges().is_empty():
		node_name = node_type

	var region: Node = ClassDB.instantiate(node_type)
	region.name = node_name

	if dimension == "2D":
		region.set(&"navigation_polygon", NavigationPolygon.new())
	else:
		region.set(&"navigation_mesh", NavigationMesh.new())

	# Undo entry opened here, after the validations above: an action left open
	# by an early return would sit unclosed on the editor's undo stack.
	var ctx := _begin_edit(is_live, "MCP: add %s" % region.name, root)
	_edit_add_child(ctx, parent, region, root)
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_name": region.name, &"node_type": node_type,
		&"message": "Added %s (%s) to '%s'" % [region.name, node_type, parent_path]}

# =============================================================================
# bake_navigation_mesh
# =============================================================================
## Bakes from the region's own children (collision shapes / meshes act as
## source geometry by default). Runs synchronously (on_thread=false) since
## this is a one-shot RPC call that needs the result immediately.
##
## 2D gotcha (confirmed against Godot's own docs and by direct testing, both
## in-editor and in a running game): parsed geometry — StaticBody2D colliders,
## Polygon2D, TileMap — is ALWAYS parsed as OBSTRUCTION geometry for 2D
## navigation, never as the walkable surface itself. There is no "floor mesh
## = walkable" concept in 2D the way there is in 3D. Without a traversable
## outline already on the NavigationPolygon, baking silently produces an
## empty result (has_baked_data reads true, but polygon_count is 0) no matter
## what collision geometry exists as children. `outline` lets the caller
## supply that walkable boundary directly; without it we still detect and
## report an empty bake instead of falsely claiming success.
func bake_navigation_mesh(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var outline_arg = args.get(&"outline")

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

	var is_2d := target is NavigationRegion2D
	var is_3d := target is NavigationRegion3D
	if not is_2d and not is_3d:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) is not a NavigationRegion2D/3D" % [node_path, target.get_class()]}

	# A bake rewrites the nav resource in place, so there is no per-property
	# inverse to record. Deep-copy the resource first and let undo swap the whole
	# thing back — the outline and the baked polygons go together anyway.
	var nav_prop: StringName = &"navigation_polygon" if is_2d else &"navigation_mesh"
	var pre_bake: Resource = target.get(nav_prop)
	if pre_bake:
		pre_bake = pre_bake.duplicate(true)

	if is_2d:
		if not target.get(&"navigation_polygon"):
			target.set(&"navigation_polygon", NavigationPolygon.new())
		var np: NavigationPolygon = target.get(&"navigation_polygon")

		if outline_arg != null:
			if not (outline_arg is Array) or outline_arg.size() < 3:
				_discard_scene(root, is_live)
				return {&"ok": false, &"error": "'outline' must be an array of at least 3 {x,y} points describing the walkable boundary in the region's local space"}
			var pts := PackedVector2Array()
			for p in outline_arg:
				# Typed parse so [x, y] works alongside {x, y}, matching what
				# every other coordinate-taking tool here accepts.
				var parsed_p = VariantCodec.parse_typed_value(p, TYPE_VECTOR2)
				if not (parsed_p is Vector2):
					_discard_scene(root, is_live)
					return {&"ok": false, &"error": "Each 'outline' point must be a Vector2: {\"x\":0,\"y\":0} or [0, 0]"}
				pts.append(parsed_p)
			np.clear_outlines()
			np.add_outline(pts)

		target.call(&"bake_navigation_polygon", false)

		if np.get_polygon_count() == 0:
			_discard_scene(root, is_live)
			var why := "no traversable outline is defined on this region" if np.get_outline_count() == 0 \
				else "the defined outline produced no walkable polygon after baking (fully consumed by obstruction geometry, or degenerate)"
			return {&"ok": false, &"error": "Bake produced an empty navigation mesh: %s. Parsed geometry (StaticBody2D colliders, Polygon2D, TileMap) is always OBSTRUCTION geometry for 2D navigation, never the walkable surface — pass 'outline' with the walkable boundary's points." % why}
	else:
		if not target.get(&"navigation_mesh"):
			target.set(&"navigation_mesh", NavigationMesh.new())
		target.call(&"bake_navigation_mesh", false)

	# NavigationRegion3D exposes get_bounds() (AABB) directly on the node.
	# NavigationRegion2D's bounds are normally read from NavigationServer2D by
	# region RID, but that RID-keyed data only gets synced by the server on an
	# actual running SceneTree tick — reading it right after an editor-context
	# bake reliably returns a stale/empty Rect2 even when the polygon itself
	# just baked real geometry (confirmed: vertices/polygons present on disk,
	# region_get_bounds() still {0,0,0,0}). Compute 2D bounds directly from the
	# baked vertices instead, which has no such dependency.
	var bounds
	if is_3d:
		bounds = target.call(&"get_bounds")
	else:
		bounds = _navigation_polygon_bounds(target.get(&"navigation_polygon"))

	# Registered only here: every failure path above bails out before this, and
	# an action opened earlier would have been left hanging on the undo stack.
	var ctx := _begin_edit(is_live, "MCP: bake navigation for %s" % node_path, root)
	_edit_record(ctx, target, &"set", [nav_prop, target.get(nav_prop)],
		&"set", [nav_prop, pre_bake])
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"bounds": VariantCodec.serialize_value(bounds),
		&"message": "Baked navigation mesh for '%s'" % node_path}

## Bounding rect over a NavigationPolygon's baked vertices, in the region's
## local space. See the comment in bake_navigation_mesh for why this is used
## instead of NavigationServer2D.region_get_bounds().
func _navigation_polygon_bounds(np: NavigationPolygon) -> Rect2:
	if not np or np.vertices.is_empty():
		return Rect2()
	var r := Rect2(np.vertices[0], Vector2.ZERO)
	for v: Vector2 in np.vertices:
		r = r.expand(v)
	return r

# =============================================================================
# setup_navigation_agent
# =============================================================================
func setup_navigation_agent(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var parent_path: String = str(args.get(&"parent_path", "."))
	var dimension: String = str(args.get(&"dimension", ""))
	var node_name: String = str(args.get(&"node_name", ""))
	var radius = args.get(&"radius")
	var max_speed = args.get(&"max_speed")

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

	var node_type: String = "NavigationAgent2D" if dimension == "2D" else "NavigationAgent3D"
	if node_name.strip_edges().is_empty():
		node_name = node_type

	var agent: Node = ClassDB.instantiate(node_type)
	agent.name = node_name
	if radius != null:
		agent.set(&"radius", float(radius))
	if max_speed != null:
		agent.set(&"max_speed", float(max_speed))

	# Undo entry opened here, after the validations above: an action left open
	# by an early return would sit unclosed on the editor's undo stack.
	var ctx := _begin_edit(is_live, "MCP: add %s" % agent.name, root)
	_edit_add_child(ctx, parent, agent, root)
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_name": agent.name, &"node_type": node_type,
		&"message": "Added %s to '%s'" % [agent.name, parent_path]}

# =============================================================================
# set_navigation_layers
# =============================================================================
## Works on any node with a navigation_layers property: NavigationRegion2D/3D,
## NavigationAgent2D/3D.
func set_navigation_layers(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var layers = args.get(&"layers")

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if layers == null:
		return {&"ok": false, &"error": "Missing 'layers'"}

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
	if not (&"navigation_layers" in target):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Node '%s' (%s) has no 'navigation_layers' property" % [node_path, target.get_class()]}

	var mask: int = _layers_to_mask(layers) if layers is Array else int(layers)
	var ctx := _begin_edit(is_live, "MCP: set navigation layers on %s" % node_path, root)
	_edit_set(ctx, target, &"navigation_layers", mask)
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"navigation_layers": mask, &"navigation_layers_bits": _mask_to_layers(mask),
		&"message": "Updated navigation_layers on '%s'" % node_path}

# =============================================================================
# get_navigation_info
# =============================================================================
func get_navigation_info(args: Dictionary) -> Dictionary:
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

	var info: Dictionary = {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"node_type": target.get_class()}

	if &"navigation_layers" in target:
		var mask: int = int(target.get(&"navigation_layers"))
		info[&"navigation_layers"] = mask
		info[&"navigation_layers_bits"] = _mask_to_layers(mask)

	if target is NavigationRegion2D or target is NavigationRegion3D:
		info[&"enabled"] = bool(target.get(&"enabled"))
		info[&"is_baking"] = bool(target.call(&"is_baking"))
		# get_bounds() only exists on NavigationRegion3D (AABB); for 2D, computed
		# directly from the baked vertices — see bake_navigation_mesh's comment
		# on why NavigationServer2D.region_get_bounds() isn't used here.
		var region_bounds
		if target is NavigationRegion3D:
			region_bounds = target.call(&"get_bounds")
		else:
			region_bounds = _navigation_polygon_bounds(target.get(&"navigation_polygon"))
		info[&"bounds"] = VariantCodec.serialize_value(region_bounds)
		# A non-null NavigationPolygon/NavigationMesh doesn't mean it's non-empty —
		# setup_navigation_region assigns one immediately with nothing baked yet —
		# so check for actual geometry rather than just resource presence.
		var mesh_res = target.get(&"navigation_polygon") if target is NavigationRegion2D else target.get(&"navigation_mesh")
		var has_data := false
		if mesh_res:
			has_data = not mesh_res.vertices.is_empty() if target is NavigationRegion2D else mesh_res.get_vertices().size() > 0
		info[&"has_baked_data"] = has_data

	if target is NavigationAgent2D or target is NavigationAgent3D:
		info[&"radius"] = float(target.get(&"radius"))
		info[&"max_speed"] = float(target.get(&"max_speed"))
		info[&"avoidance_enabled"] = bool(target.get(&"avoidance_enabled"))

	# node_path defaults to the root, which is rarely the navigation node — the
	# answer was then a shell naming the root's class and nothing else, with no
	# sign that the tool had simply been pointed at the wrong node. Say so, and
	# name the nodes it would have something to report on.
	if info.size() == 4:
		var found: Array[String] = []
		_collect_navigation_nodes(root, root, found)
		info[&"note"] = "'%s' (%s) holds no navigation settings." % [node_path, target.get_class()]
		info[&"navigation_nodes"] = found
		if found.is_empty():
			info[&"note"] += " This scene has no navigation nodes — setup_navigation_region adds one."
		else:
			info[&"note"] += " Pass one of navigation_nodes as node_path."

	_discard_scene(root, is_live)
	return info

func _collect_navigation_nodes(scene_root: Node, node: Node, out: Array[String]) -> void:
	for child in node.get_children():
		if child is NavigationRegion2D or child is NavigationRegion3D 			or child is NavigationAgent2D or child is NavigationAgent3D:
			out.append(str(scene_root.get_path_to(child)))
		_collect_navigation_nodes(scene_root, child, out)
