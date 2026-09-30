@tool
extends SceneToolBase
class_name TileMapTools
## TileMap operation tools for MCP.
## Handles: tilemap_set_cell, tilemap_fill_rect, tilemap_get_cell, tilemap_clear,
##          tilemap_get_info, tilemap_get_used_cells
## Written against the Godot 4.3+ TileMapLayer API. If the target node is a
## pre-4.3 TileMap (has a "layer" parameter on its cell methods), we assume
## TileMapLayer and do not attempt to special-case the old API.


func _to_vector2i(value: Variant, default: Vector2i = Vector2i.ZERO) -> Vector2i:
	var parsed = VariantCodec.parse_value(value)
	if parsed is Vector2i:
		return parsed
	if parsed is Vector2:
		return Vector2i(parsed)
	if parsed is Dictionary:
		return Vector2i(int(parsed.get(&"x", default.x)), int(parsed.get(&"y", default.y)))
	# [x, y] is what most other tools here take for a coordinate (add_node's
	# position, setup_collision's size), so an agent reasonably tries it. Falling
	# through to the default instead would paint at (0, 0) and report success —
	# a wrong result reported as a right one.
	if parsed is Array and parsed.size() >= 2:
		return Vector2i(int(parsed[0]), int(parsed[1]))
	return default

## Validate that the target node exists and is a TileMapLayer. Returns
## [node_or_null, error_string].
func _get_tilemap_layer(root: Node, node_path: String) -> Array:
	var target = _find_node(root, node_path)
	if not target:
		return [null, "Node not found: " + node_path]
	if not (target is TileMapLayer):
		return [null, "Node '%s' is %s, expected TileMapLayer (Godot 4.3+)" % [node_path, target.get_class()]]
	return [target, ""]

## Warning text when a layer has no TileSet, or "" when it does.
##
## Painting cells on such a layer stores the data and reports success, but
## nothing can render: a source_id resolves against the TileSet, and there isn't
## one. Not an error — a caller may legitimately assign the TileSet afterwards,
## and refusing would break that. But reporting plain success for an edit the
## user cannot see is the silent-no-op shape this project treats as a bug, so
## the result says so.
func _tileset_warning(layer: TileMapLayer) -> String:
	if layer.tile_set != null:
		return ""
	return "This TileMapLayer has no TileSet, so the cells are stored but cannot render. Assign a TileSet to the layer (or to its parent TileMap) for them to appear."

# ---------------------------------------------------------------------------
# Undo for cell edits
# ---------------------------------------------------------------------------
# A TileMapLayer keeps every cell in one `tile_map_data` blob, so a single
# before/after pair covers one painted cell or a hundred-thousand-cell fill at
# the same cost. Recording a do/undo per coordinate would make a large fill_rect
# allocate two entries per cell and bloat the editor's undo history for nothing.

func _begin_cells(is_live: bool, action_name: String, layer: TileMapLayer) -> Dictionary:
	# The layer itself is the history context — it belongs to the edited scene,
	# which is all EditorUndoRedoManager needs to file the entry correctly.
	var ctx := _begin_edit(is_live, action_name, layer)
	ctx[&"layer"] = layer
	# PackedByteArray assignment copies, so this is a real snapshot.
	ctx[&"before"] = layer.tile_map_data
	return ctx

func _commit_cells(ctx: Dictionary) -> void:
	var layer: TileMapLayer = ctx.get(&"layer")
	if layer and is_instance_valid(layer):
		_edit_record(ctx, layer, &"set", [&"tile_map_data", layer.tile_map_data],
			&"set", [&"tile_map_data", ctx.get(&"before")])
	_edit_commit(ctx)

# =============================================================================
# tilemap_set_cell
# =============================================================================
func tilemap_set_cell(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var coords: Vector2i = _to_vector2i(args.get(&"coords"))
	var source_id: int = int(args.get(&"source_id", 0))
	var atlas_coords: Vector2i = _to_vector2i(args.get(&"atlas_coords"), Vector2i.ZERO)
	var alternative_tile: int = int(args.get(&"alternative_tile", 0))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var layer_result := _get_tilemap_layer(root, node_path)
	if not layer_result[1].is_empty():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": layer_result[1]}
	var layer: TileMapLayer = layer_result[0]

	var tileset_warning := _tileset_warning(layer)
	var ctx := _begin_cells(is_live, "MCP: set cell %s" % coords, layer)
	layer.set_cell(coords, source_id, atlas_coords, alternative_tile)
	_commit_cells(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	var out := {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"coords": {&"x": coords.x, &"y": coords.y}, &"source_id": source_id,
		&"message": "Set cell (%d, %d) on '%s'" % [coords.x, coords.y, node_path]}
	if not tileset_warning.is_empty():
		out[&"warning"] = tileset_warning
	return out

# =============================================================================
# tilemap_fill_rect
# =============================================================================
func tilemap_fill_rect(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var from_coords: Vector2i = _to_vector2i(args.get(&"from_coords"))
	var to_coords: Vector2i = _to_vector2i(args.get(&"to_coords"))
	var source_id: int = int(args.get(&"source_id", 0))
	var atlas_coords: Vector2i = _to_vector2i(args.get(&"atlas_coords"), Vector2i.ZERO)
	var alternative_tile: int = int(args.get(&"alternative_tile", 0))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var layer_result := _get_tilemap_layer(root, node_path)
	if not layer_result[1].is_empty():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": layer_result[1]}
	var layer: TileMapLayer = layer_result[0]

	var min_x := mini(from_coords.x, to_coords.x)
	var max_x := maxi(from_coords.x, to_coords.x)
	var min_y := mini(from_coords.y, to_coords.y)
	var max_y := maxi(from_coords.y, to_coords.y)

	var tileset_warning := _tileset_warning(layer)
	var ctx := _begin_cells(is_live, "MCP: fill tiles", layer)
	var cell_count := 0
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			layer.set_cell(Vector2i(x, y), source_id, atlas_coords, alternative_tile)
			cell_count += 1
	_commit_cells(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	var out := {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"cells_filled": cell_count,
		&"message": "Filled %d cells on '%s'" % [cell_count, node_path]}
	if not tileset_warning.is_empty():
		out[&"warning"] = tileset_warning
	return out

# =============================================================================
# tilemap_get_cell
# =============================================================================
func tilemap_get_cell(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var coords: Vector2i = _to_vector2i(args.get(&"coords"))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var layer_result := _get_tilemap_layer(root, node_path)
	if not layer_result[1].is_empty():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": layer_result[1]}
	var layer: TileMapLayer = layer_result[0]

	var source_id := layer.get_cell_source_id(coords)
	var atlas_coords := layer.get_cell_atlas_coords(coords)
	var alternative_tile := layer.get_cell_alternative_tile(coords)

	_discard_scene(root, is_live)

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"coords": {&"x": coords.x, &"y": coords.y},
		&"source_id": source_id,
		&"atlas_coords": {&"x": atlas_coords.x, &"y": atlas_coords.y},
		&"alternative_tile": alternative_tile,
		&"is_empty": source_id == -1}

# =============================================================================
# tilemap_clear
# =============================================================================
func tilemap_clear(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var has_region: bool = args.has(&"from_coords") and args.has(&"to_coords")

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var layer_result := _get_tilemap_layer(root, node_path)
	if not layer_result[1].is_empty():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": layer_result[1]}
	var layer: TileMapLayer = layer_result[0]

	var ctx := _begin_cells(is_live, "MCP: clear tiles", layer)
	var cleared := 0
	if has_region:
		var from_coords: Vector2i = _to_vector2i(args.get(&"from_coords"))
		var to_coords: Vector2i = _to_vector2i(args.get(&"to_coords"))
		var min_x := mini(from_coords.x, to_coords.x)
		var max_x := maxi(from_coords.x, to_coords.x)
		var min_y := mini(from_coords.y, to_coords.y)
		var max_y := maxi(from_coords.y, to_coords.y)
		for x in range(min_x, max_x + 1):
			for y in range(min_y, max_y + 1):
				var c := Vector2i(x, y)
				if layer.get_cell_source_id(c) != -1:
					layer.erase_cell(c)
					cleared += 1
	else:
		cleared = layer.get_used_cells().size()
		layer.clear()
	_commit_cells(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"cells_cleared": cleared,
		&"message": "Cleared %d cells on '%s'" % [cleared, node_path]}

# =============================================================================
# tilemap_get_info
# =============================================================================
func tilemap_get_info(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var layer_result := _get_tilemap_layer(root, node_path)
	if not layer_result[1].is_empty():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": layer_result[1]}
	var layer: TileMapLayer = layer_result[0]

	var tile_set := layer.tile_set
	if not tile_set:
		_discard_scene(root, is_live)
		return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
			&"has_tile_set": false, &"message": "TileMapLayer '%s' has no TileSet assigned" % node_path}

	var sources: Array = []
	for i in range(tile_set.get_source_count()):
		var source_id := tile_set.get_source_id(i)
		var source := tile_set.get_source(source_id)
		var entry := {&"source_id": source_id, &"type": source.get_class()}
		if source is TileSetAtlasSource:
			var atlas_source: TileSetAtlasSource = source
			entry[&"texture_region_size"] = {&"x": atlas_source.texture_region_size.x, &"y": atlas_source.texture_region_size.y}
			entry[&"tiles_count"] = atlas_source.get_tiles_count()
		sources.append(entry)

	_discard_scene(root, is_live)

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"has_tile_set": true,
		&"tile_size": {&"x": tile_set.tile_size.x, &"y": tile_set.tile_size.y},
		&"sources": sources,
		&"source_count": sources.size()}

# =============================================================================
# tilemap_get_used_cells
# =============================================================================
func tilemap_get_used_cells(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var layer_result := _get_tilemap_layer(root, node_path)
	if not layer_result[1].is_empty():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": layer_result[1]}
	var layer: TileMapLayer = layer_result[0]

	var cells: Array = []
	for c: Vector2i in layer.get_used_cells():
		cells.append({
			&"x": c.x, &"y": c.y,
			&"source_id": layer.get_cell_source_id(c),
			&"atlas_coords": {&"x": layer.get_cell_atlas_coords(c).x, &"y": layer.get_cell_atlas_coords(c).y},
			&"alternative_tile": layer.get_cell_alternative_tile(c),
		})

	_discard_scene(root, is_live)

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"cells": cells, &"cell_count": cells.size()}

# =============================================================================
# tilemap_set_terrain_cells
# =============================================================================
## Paints cells using the TileSet's built-in terrain autotiling
## (TileMapLayer.set_cells_terrain_connect / set_cells_terrain_path).
## The terrain_set/terrain indices must already exist on the TileSet
## (configured by hand in the TileSet editor — this tool does not create
## terrain sets, only paints with ones that already exist).
func tilemap_set_terrain_cells(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var terrain_set: int = int(args.get(&"terrain_set", -1))
	var terrain: int = int(args.get(&"terrain", -1))
	var mode: String = str(args.get(&"mode", "connect"))
	var ignore_empty_terrains: bool = bool(args.get(&"ignore_empty_terrains", true))
	var raw_cells: Array = args.get(&"cells", [])

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if raw_cells.is_empty():
		return {&"ok": false, &"error": "Missing 'cells' (non-empty array of coordinates)"}
	if mode != "connect" and mode != "path":
		return {&"ok": false, &"error": "Invalid 'mode': must be 'connect' or 'path'"}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var layer_result := _get_tilemap_layer(root, node_path)
	if not layer_result[1].is_empty():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": layer_result[1]}
	var layer: TileMapLayer = layer_result[0]

	var tile_set := layer.tile_set
	if not tile_set:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "TileMapLayer '%s' has no TileSet assigned" % node_path}
	if terrain_set < 0 or terrain_set >= tile_set.get_terrain_sets_count():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Invalid terrain_set %d (TileSet has %d terrain set(s)). Terrain sets must be created by hand in the TileSet editor first." % [terrain_set, tile_set.get_terrain_sets_count()]}
	if terrain < 0 or terrain >= tile_set.get_terrains_count(terrain_set):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "Invalid terrain %d for terrain_set %d (has %d terrain(s))" % [terrain, terrain_set, tile_set.get_terrains_count(terrain_set)]}

	var cells: Array[Vector2i] = []
	for raw in raw_cells:
		cells.append(_to_vector2i(raw))

	var ctx := _begin_cells(is_live, "MCP: terrain %s" % mode, layer)
	if mode == "connect":
		layer.set_cells_terrain_connect(cells, terrain_set, terrain, ignore_empty_terrains)
	else:
		layer.set_cells_terrain_path(cells, terrain_set, terrain, ignore_empty_terrains)
	_commit_cells(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"terrain_set": terrain_set, &"terrain": terrain, &"mode": mode,
		&"cells_painted": cells.size(),
		&"message": "Painted %d terrain cell(s) on '%s' using terrain_set=%d terrain=%d (mode=%s)" % [cells.size(), node_path, terrain_set, terrain, mode]}

# =============================================================================
# tilemap_autotile — deterministic bitmask autotiling (NOT the native solver)
# =============================================================================
## Autotile a region by picking each cell's atlas tile from its neighbour bitmask,
## then set_cell — deterministic, main-thread, order-independent. This deliberately
## avoids Godot 4's native terrain solver (set_cells_terrain_connect), which is a
## constraint-solver that is non-deterministic, ~20x slower, and can cascade errors
## (see RESEARCH_SUMMARY.md §2). The caller supplies `mask_to_atlas`, a map from a
## neighbour bitmask to the atlas coordinate for that tile shape, so the tool stays
## agnostic to any specific tileset's atlas layout.
##
## Bit order (a neighbour counts as "filled" if it's in `cells` or, when
## include_existing, already has a tile):
##   neighbours="4": N=1, E=2, S=4, W=8            (mask 0..15)
##   neighbours="8": N=1, NE=2, E=4, SE=8, S=16, SW=32, W=64, NW=128
func tilemap_autotile(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var source_id: int = int(args.get(&"source_id", 0))
	var neighbours: String = str(args.get(&"neighbours", "4"))
	var raw_cells: Array = args.get(&"cells", [])
	var mask_map: Dictionary = args.get(&"mask_to_atlas", {})
	var include_existing: bool = bool(args.get(&"include_existing", true))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if raw_cells.is_empty():
		return {&"ok": false, &"error": "Missing 'cells' (non-empty array of coordinates to autotile)"}
	if mask_map.is_empty():
		return {&"ok": false, &"error": "Missing 'mask_to_atlas' (map of bitmask -> atlas coord, e.g. {\"0\": {\"x\":0,\"y\":0}, \"15\": {\"x\":1,\"y\":1}})"}
	if neighbours != "4" and neighbours != "8":
		return {&"ok": false, &"error": "Invalid 'neighbours': must be \"4\" (edges) or \"8\" (edges+corners)"}

	var result := _acquire_scene(scene_path)
	if not result[2].is_empty():
		return result[2]
	var root: Node = result[0]
	var is_live: bool = result[1]

	var layer_result := _get_tilemap_layer(root, node_path)
	if not layer_result[1].is_empty():
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": layer_result[1]}
	var layer: TileMapLayer = layer_result[0]
	if not layer.tile_set:
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "TileMapLayer '%s' has no TileSet assigned" % node_path}
	if not layer.tile_set.has_source(source_id):
		_discard_scene(root, is_live)
		return {&"ok": false, &"error": "TileSet has no source with id %d" % source_id}

	# Which offsets, in bit order.
	var offsets: Array[Vector2i]
	if neighbours == "4":
		offsets = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	else:
		offsets = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
			Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]

	# Build the "filled" lookup: the region being autotiled, plus (optionally) tiles
	# already on the layer so the region connects to existing geometry.
	var filled: Dictionary = {}
	var targets: Array[Vector2i] = []
	for raw in raw_cells:
		var c := _to_vector2i(raw)
		filled[c] = true
		targets.append(c)
	if include_existing:
		for c in layer.get_used_cells():
			filled[c] = true

	var painted := 0
	var unmapped: Array = []
	var ctx := _begin_cells(is_live, "MCP: autotile", layer)
	for cell in targets:
		var mask := 0
		for i in range(offsets.size()):
			if filled.has(cell + offsets[i]):
				mask |= (1 << i)
		var key := str(mask)
		if mask_map.has(key):
			layer.set_cell(cell, source_id, _to_vector2i(mask_map[key]), 0)
			painted += 1
		elif unmapped.size() < 20:
			unmapped.append({&"cell": {&"x": cell.x, &"y": cell.y}, &"mask": mask})
	_commit_cells(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_path": node_path,
		&"source_id": source_id, &"neighbours": neighbours,
		&"cells_painted": painted, &"unmapped_count": raw_cells.size() - painted,
		&"unmapped_sample": unmapped, &"live_editor_scene": is_live,
		&"message": "Autotiled %d/%d cell(s) on '%s' (%s-neighbour bitmask); %d had no mask_to_atlas entry" % [painted, raw_cells.size(), node_path, neighbours, raw_cells.size() - painted]}
