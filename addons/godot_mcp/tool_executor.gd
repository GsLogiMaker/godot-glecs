@tool
extends Node
class_name ToolExecutor
## Routes tool invocations to the appropriate handler.

var _editor_plugin: EditorPlugin = null
var _mcp_client: Object = null

var _file_tools: Node
var _scene_tools: Node
var _script_tools: Node
var _project_tools: Node
var _asset_tools: Node
var _visualizer_tools: Node
var _tilemap_tools: Node
var _animation_tools: Node
var _audio_tools: Node
var _physics_tools: Node
var _theme_tools: Node
var _particle_tools: Node
var _scene3d_tools: Node
var _batch_tools: Node
var _navigation_tools: Node
var _netcode_tools: Node
var _animation_tree_tools: Node
var _shader_tools: Node
var _testing_tools: Node
var _analysis_tools: Node

# Tool name → [handler_node, method_name]
var _tool_map: Dictionary = {}

var _initialized := false

func _init_tools() -> void:
	"""Initialize all tool handlers. Called from set_editor_plugin."""
	if _initialized:
		return
	_initialized = true
	
	_file_tools = preload("res://addons/godot_mcp/tools/file_tools.gd").new()
	_file_tools.name = "FileTools"
	add_child(_file_tools)

	_scene_tools = preload("res://addons/godot_mcp/tools/scene_tools.gd").new()
	_scene_tools.name = "SceneTools"
	add_child(_scene_tools)

	_script_tools = preload("res://addons/godot_mcp/tools/script_tools.gd").new()
	_script_tools.name = "ScriptTools"
	add_child(_script_tools)

	_project_tools = preload("res://addons/godot_mcp/tools/project_tools.gd").new()
	_project_tools.name = "ProjectTools"
	add_child(_project_tools)

	_asset_tools = preload("res://addons/godot_mcp/tools/asset_tools.gd").new()
	_asset_tools.name = "AssetTools"
	add_child(_asset_tools)

	_visualizer_tools = preload("res://addons/godot_mcp/tools/visualizer_tools.gd").new()
	_visualizer_tools.name = "VisualizerTools"
	add_child(_visualizer_tools)

	_tilemap_tools = preload("res://addons/godot_mcp/tools/tilemap_tools.gd").new()
	_tilemap_tools.name = "TileMapTools"
	add_child(_tilemap_tools)

	_animation_tools = preload("res://addons/godot_mcp/tools/animation_tools.gd").new()
	_animation_tools.name = "AnimationTools"
	add_child(_animation_tools)

	_audio_tools = preload("res://addons/godot_mcp/tools/audio_tools.gd").new()
	_audio_tools.name = "AudioTools"
	add_child(_audio_tools)

	_physics_tools = preload("res://addons/godot_mcp/tools/physics_tools.gd").new()
	_physics_tools.name = "PhysicsTools"
	add_child(_physics_tools)

	_theme_tools = preload("res://addons/godot_mcp/tools/theme_tools.gd").new()
	_theme_tools.name = "ThemeTools"
	add_child(_theme_tools)

	_particle_tools = preload("res://addons/godot_mcp/tools/particle_tools.gd").new()
	_particle_tools.name = "ParticleTools"
	add_child(_particle_tools)

	_scene3d_tools = preload("res://addons/godot_mcp/tools/scene3d_tools.gd").new()
	_scene3d_tools.name = "Scene3DTools"
	add_child(_scene3d_tools)

	_batch_tools = preload("res://addons/godot_mcp/tools/batch_tools.gd").new()
	_batch_tools.name = "BatchTools"
	add_child(_batch_tools)

	_navigation_tools = preload("res://addons/godot_mcp/tools/navigation_tools.gd").new()
	_navigation_tools.name = "NavigationTools"
	add_child(_navigation_tools)

	_netcode_tools = preload("res://addons/godot_mcp/tools/netcode_tools.gd").new()
	_netcode_tools.name = "NetcodeTools"
	add_child(_netcode_tools)

	_animation_tree_tools = preload("res://addons/godot_mcp/tools/animation_tree_tools.gd").new()
	_animation_tree_tools.name = "AnimationTreeTools"
	add_child(_animation_tree_tools)

	_shader_tools = preload("res://addons/godot_mcp/tools/shader_tools.gd").new()
	_shader_tools.name = "ShaderTools"
	add_child(_shader_tools)

	_testing_tools = preload("res://addons/godot_mcp/tools/testing_tools.gd").new()
	_testing_tools.name = "TestingTools"
	add_child(_testing_tools)

	_analysis_tools = preload("res://addons/godot_mcp/tools/analysis_tools.gd").new()
	_analysis_tools.name = "AnalysisTools"
	add_child(_analysis_tools)

	# Build tool routing map
	_tool_map = {
		&"list_dir": [_file_tools, &"list_dir"],
		&"read_file": [_file_tools, &"read_file"],
		&"search_project": [_file_tools, &"search_project"],
		&"create_script": [_file_tools, &"create_script"],
		&"create_csharp_script": [_file_tools, &"create_csharp_script"],
		&"csharp_status": [_file_tools, &"csharp_status"],

		&"create_scene": [_scene_tools, &"create_scene"],
		&"read_scene": [_scene_tools, &"read_scene"],
		&"add_node": [_scene_tools, &"add_node"],
		&"batch_scene_edit": [_scene_tools, &"batch_scene_edit"],
		&"remove_node": [_scene_tools, &"remove_node"],
		&"modify_node_property": [_scene_tools, &"modify_node_property"],
		&"rename_node": [_scene_tools, &"rename_node"],
		&"move_node": [_scene_tools, &"move_node"],
		&"attach_script": [_scene_tools, &"attach_script"],
		&"detach_script": [_scene_tools, &"detach_script"],
		&"set_collision_shape": [_scene_tools, &"set_collision_shape"],
		&"set_sprite_texture": [_scene_tools, &"set_sprite_texture"],
		&"instance_scene": [_scene_tools, &"instance_scene"],
		&"set_mesh": [_scene_tools, &"set_mesh"],
		&"set_node_reference": [_scene_tools, &"set_node_reference"],
		&"set_material": [_scene_tools, &"set_material"],
		&"get_node_spatial_info": [_scene_tools, &"get_node_spatial_info"],
		&"measure_node_distance": [_scene_tools, &"measure_node_distance"],
		&"snap_node_to_grid": [_scene_tools, &"snap_node_to_grid"],
		&"get_scene_hierarchy": [_scene_tools, &"get_scene_hierarchy"],
		&"get_scene_node_properties": [_scene_tools, &"get_scene_node_properties"],
		&"set_scene_node_property": [_scene_tools, &"set_scene_node_property"],
		&"set_node_properties": [_scene_tools, &"set_node_properties"],
		&"set_node_groups": [_scene_tools, &"set_node_groups"],
		&"get_node_groups": [_scene_tools, &"get_node_groups"],
		&"find_nodes_in_group": [_scene_tools, &"find_nodes_in_group"],
		&"set_resource_property": [_scene_tools, &"set_resource_property"],
		&"save_resource_to_file": [_scene_tools, &"save_resource_to_file"],
		&"get_resource_info": [_scene_tools, &"get_resource_info"],
		&"list_signal_connections": [_scene_tools, &"list_signal_connections"],
		&"connect_signal": [_scene_tools, &"connect_signal"],
		&"wire_signal": [_scene_tools, &"wire_signal"],
		&"generate_onready_refs": [_scene_tools, &"generate_onready_refs"],
		&"scaffold_entity": [_scene_tools, &"scaffold_entity"],
		&"scaffold_state_machine": [_scene_tools, &"scaffold_state_machine"],

		&"get_project_statistics": [_analysis_tools, &"get_project_statistics"],
		&"find_unused_resources": [_analysis_tools, &"find_unused_resources"],
		&"detect_circular_dependencies": [_analysis_tools, &"detect_circular_dependencies"],
		&"analyze_scene_complexity": [_analysis_tools, &"analyze_scene_complexity"],
		&"analyze_signal_flow": [_analysis_tools, &"analyze_signal_flow"],
		&"validate_references": [_analysis_tools, &"validate_references"],
		&"compare_screenshots": [_analysis_tools, &"compare_screenshots"],
		&"texture_info": [_analysis_tools, &"texture_info"],
		&"analyze_2d_layout": [_analysis_tools, &"analyze_2d_layout"],
		&"scene_diff": [_analysis_tools, &"scene_diff"],
		&"disconnect_signal": [_scene_tools, &"disconnect_signal"],
		&"duplicate_node": [_scene_tools, &"duplicate_node"],
		&"set_anchor_preset": [_scene_tools, &"set_anchor_preset"],

		&"edit_script": [_script_tools, &"edit_script"],
		&"validate_script": [_script_tools, &"validate_script"],
		&"validate_eval_snippet": [_script_tools, &"validate_eval_snippet"],
		&"validate_scripts": [_script_tools, &"validate_scripts"],
		&"list_scripts": [_script_tools, &"list_scripts"],
		&"create_folder": [_script_tools, &"create_folder"],
		&"delete_file": [_script_tools, &"delete_file"],
		&"rename_file": [_script_tools, &"rename_file"],
		&"generate_property_forwarder": [_script_tools, &"generate_property_forwarder"],

		&"get_project_settings": [_project_tools, &"get_project_settings"],
		&"list_settings": [_project_tools, &"list_settings"],
		&"update_project_settings": [_project_tools, &"update_project_settings"],
		&"set_main_scene": [_project_tools, &"set_main_scene"],
		&"get_input_map": [_project_tools, &"get_input_map"],
		&"configure_input_map": [_project_tools, &"configure_input_map"],
		&"sync_localization": [_project_tools, &"sync_localization"],
		&"get_collision_layers": [_project_tools, &"get_collision_layers"],
		&"setup_autoload": [_project_tools, &"setup_autoload"],
		&"get_node_properties": [_project_tools, &"get_node_properties"],
		&"get_console_log": [_project_tools, &"get_console_log"],
		&"get_errors": [_project_tools, &"get_errors"],
		&"clear_console_log": [_project_tools, &"clear_console_log"],
		&"open_in_godot": [_project_tools, &"open_in_godot"],
		&"scene_tree_dump": [_project_tools, &"scene_tree_dump"],
		&"get_editor_activity": [_project_tools, &"get_editor_activity"],
		&"spawn_headless_peers": [_project_tools, &"spawn_headless_peers"],
		&"stop_headless_peers": [_project_tools, &"stop_headless_peers"],
		&"classdb_query": [_project_tools, &"classdb_query"],
		&"rescan_filesystem": [_project_tools, &"rescan_filesystem"],
		&"render_scene_preview": [_project_tools, &"render_scene_preview"],
		&"restart_editor": [_project_tools, &"restart_editor"],
		&"undo_last": [_project_tools, &"undo_last"],
		&"redo_last": [_project_tools, &"redo_last"],
		&"run_scene": [_project_tools, &"run_scene"],
		&"stop_scene": [_project_tools, &"stop_scene"],
		&"is_playing": [_project_tools, &"is_playing"],
		&"get_runtime_status": [_project_tools, &"get_runtime_status"],
		&"wait": [_project_tools, &"wait"],
		&"get_uid": [_project_tools, &"get_uid"],
		&"list_export_presets": [_project_tools, &"list_export_presets"],
		&"get_export_info": [_project_tools, &"get_export_info"],
		&"export_project": [_project_tools, &"export_project"],
		&"get_export_status": [_project_tools, &"get_export_status"],

		&"generate_2d_asset": [_asset_tools, &"generate_2d_asset"],

		&"map_project": [_visualizer_tools, &"map_project"],
		&"map_scenes": [_visualizer_tools, &"map_scenes"],

		&"tilemap_set_cell": [_tilemap_tools, &"tilemap_set_cell"],
		&"tilemap_fill_rect": [_tilemap_tools, &"tilemap_fill_rect"],
		&"tilemap_get_cell": [_tilemap_tools, &"tilemap_get_cell"],
		&"tilemap_clear": [_tilemap_tools, &"tilemap_clear"],
		&"tilemap_get_info": [_tilemap_tools, &"tilemap_get_info"],
		&"tilemap_get_used_cells": [_tilemap_tools, &"tilemap_get_used_cells"],
		&"tilemap_set_terrain_cells": [_tilemap_tools, &"tilemap_set_terrain_cells"],
		&"tilemap_autotile": [_tilemap_tools, &"tilemap_autotile"],

		&"list_animations": [_animation_tools, &"list_animations"],
		&"create_animation": [_animation_tools, &"create_animation"],
		&"add_animation_track": [_animation_tools, &"add_animation_track"],
		&"create_sprite_animation": [_animation_tools, &"create_sprite_animation"],
		&"create_sprite_frames": [_animation_tools, &"create_sprite_frames"],
		&"set_animation_keyframe": [_animation_tools, &"set_animation_keyframe"],
		&"get_animation_info": [_animation_tools, &"get_animation_info"],
		&"remove_animation": [_animation_tools, &"remove_animation"],

		&"add_audio_player": [_audio_tools, &"add_audio_player"],
		&"add_audio_bus": [_audio_tools, &"add_audio_bus"],
		&"get_audio_bus_layout": [_audio_tools, &"get_audio_bus_layout"],

		&"add_raycast": [_physics_tools, &"add_raycast"],
		&"setup_collision": [_physics_tools, &"setup_collision"],
		&"set_physics_layers": [_physics_tools, &"set_physics_layers"],
		&"get_collision_info": [_physics_tools, &"get_collision_info"],
		&"set_collision_preset": [_physics_tools, &"set_collision_preset"],
		&"get_collision_presets": [_physics_tools, &"get_collision_presets"],
		&"apply_collision_preset": [_physics_tools, &"apply_collision_preset"],

		&"create_theme": [_theme_tools, &"create_theme"],
		&"set_theme_color": [_theme_tools, &"set_theme_color"],
		&"set_theme_constant": [_theme_tools, &"set_theme_constant"],
		&"set_theme_font_size": [_theme_tools, &"set_theme_font_size"],
		&"set_theme_stylebox": [_theme_tools, &"set_theme_stylebox"],
		&"get_theme_info": [_theme_tools, &"get_theme_info"],

		&"create_particles": [_particle_tools, &"create_particles"],
		&"set_particle_material": [_particle_tools, &"set_particle_material"],
		&"set_particle_color_gradient": [_particle_tools, &"set_particle_color_gradient"],
		&"apply_particle_preset": [_particle_tools, &"apply_particle_preset"],
		&"get_particle_info": [_particle_tools, &"get_particle_info"],

		&"add_mesh_instance": [_scene3d_tools, &"add_mesh_instance"],
		&"setup_lighting": [_scene3d_tools, &"setup_lighting"],
		&"set_material_3d": [_scene3d_tools, &"set_material_3d"],
		&"setup_environment": [_scene3d_tools, &"setup_environment"],
		&"setup_camera_3d": [_scene3d_tools, &"setup_camera_3d"],
		&"add_gridmap": [_scene3d_tools, &"add_gridmap"],
		&"get_skeleton_info": [_scene3d_tools, &"get_skeleton_info"],
		&"add_bone": [_scene3d_tools, &"add_bone"],
		&"set_bone_pose": [_scene3d_tools, &"set_bone_pose"],

		&"find_nodes_by_type": [_batch_tools, &"find_nodes_by_type"],
		&"batch_set_property": [_batch_tools, &"batch_set_property"],
		&"get_scene_dependencies": [_batch_tools, &"get_scene_dependencies"],
		&"rename_symbol_project_wide": [_batch_tools, &"rename_symbol_project_wide"],

		&"setup_navigation_region": [_navigation_tools, &"setup_navigation_region"],
		&"bake_navigation_mesh": [_navigation_tools, &"bake_navigation_mesh"],
		&"setup_navigation_agent": [_navigation_tools, &"setup_navigation_agent"],
		&"set_navigation_layers": [_navigation_tools, &"set_navigation_layers"],
		&"get_navigation_info": [_navigation_tools, &"get_navigation_info"],
		&"mp_add_spawner": [_netcode_tools, &"mp_add_spawner"],
		&"mp_add_synchronizer": [_netcode_tools, &"mp_add_synchronizer"],
		&"mp_wire_rpc": [_netcode_tools, &"mp_wire_rpc"],
		&"mp_set_authority": [_netcode_tools, &"mp_set_authority"],
		&"mp_scaffold_lobby": [_netcode_tools, &"mp_scaffold_lobby"],
		&"mp_diagnose": [_netcode_tools, &"mp_diagnose"],

		&"create_animation_tree": [_animation_tree_tools, &"create_animation_tree"],
		&"get_animation_tree_structure": [_animation_tree_tools, &"get_animation_tree_structure"],
		&"add_state_machine_state": [_animation_tree_tools, &"add_state_machine_state"],
		&"remove_state_machine_state": [_animation_tree_tools, &"remove_state_machine_state"],
		&"add_state_machine_transition": [_animation_tree_tools, &"add_state_machine_transition"],
		&"remove_state_machine_transition": [_animation_tree_tools, &"remove_state_machine_transition"],

		&"create_shader": [_shader_tools, &"create_shader"],
		&"read_shader": [_shader_tools, &"read_shader"],
		&"edit_shader": [_shader_tools, &"edit_shader"],
		&"assign_shader_material": [_shader_tools, &"assign_shader_material"],
		&"set_shader_param": [_shader_tools, &"set_shader_param"],
		&"get_shader_params": [_shader_tools, &"get_shader_params"],

		&"get_editor_selection": [_project_tools, &"get_editor_selection"],
		&"select_nodes": [_project_tools, &"select_nodes"],
		&"clear_editor_selection": [_project_tools, &"clear_editor_selection"],
		&"close_scene_tab": [_project_tools, &"close_scene_tab"],
		&"save_scene": [_project_tools, &"save_scene"],
		&"get_performance_monitors": [_project_tools, &"get_performance_monitors"],
		&"get_editor_performance": [_project_tools, &"get_editor_performance"],
		&"create_resource": [_project_tools, &"create_resource"],
		&"remove_autoload": [_project_tools, &"remove_autoload"],

		&"assert_node_property": [_testing_tools, &"assert_node_property"],
		&"run_scene_assertions": [_testing_tools, &"run_scene_assertions"],
		&"validate_scene_integrity": [_testing_tools, &"validate_scene_integrity"],
		&"validate_meshes": [_testing_tools, &"validate_meshes"],
		&"run_gut_tests": [_testing_tools, &"run_gut_tests"],
		&"get_gut_status": [_testing_tools, &"get_gut_status"],
	}

func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin
	
	# Initialize tools first (must be done synchronously)
	_init_tools()
	
	# Pass editor plugin reference to all tool handlers
	if _file_tools: _file_tools.set_editor_plugin(plugin)
	if _scene_tools: _scene_tools.set_editor_plugin(plugin)
	if _script_tools: _script_tools.set_editor_plugin(plugin)
	if _project_tools: _project_tools.set_editor_plugin(plugin)
	if _asset_tools: _asset_tools.set_editor_plugin(plugin)
	if _tilemap_tools: _tilemap_tools.set_editor_plugin(plugin)
	if _animation_tools: _animation_tools.set_editor_plugin(plugin)
	if _audio_tools: _audio_tools.set_editor_plugin(plugin)
	if _physics_tools: _physics_tools.set_editor_plugin(plugin)
	if _theme_tools: _theme_tools.set_editor_plugin(plugin)
	if _particle_tools: _particle_tools.set_editor_plugin(plugin)
	if _scene3d_tools: _scene3d_tools.set_editor_plugin(plugin)
	if _batch_tools: _batch_tools.set_editor_plugin(plugin)
	if _navigation_tools: _navigation_tools.set_editor_plugin(plugin)
	if _netcode_tools: _netcode_tools.set_editor_plugin(plugin)
	if _animation_tree_tools: _animation_tree_tools.set_editor_plugin(plugin)
	if _shader_tools: _shader_tools.set_editor_plugin(plugin)
	if _testing_tools: _testing_tools.set_editor_plugin(plugin)
	# Missing this made every analysis tool read the LAST SAVED scene: without
	# the plugin, _edited_root_if_open can never find the live tree, so
	# scene_diff reported "no changes" for an edit sitting unsaved in the editor
	# — the exact stale-read class 1.1.1 fixed for the other read tools.
	if _analysis_tools: _analysis_tools.set_editor_plugin(plugin)
	if _visualizer_tools:
		_visualizer_tools.set_editor_plugin(plugin)
		# Pass scene_tools reference for visualizer internal scene functions
		_visualizer_tools.set_scene_tools_ref(_scene_tools)

func set_mcp_client(client: Object) -> void:
	_mcp_client = client
	if _project_tools and _project_tools.has_method("set_mcp_client"):
		_project_tools.set_mcp_client(client)

## Tools that are coroutines (contain `await`). They MUST be dispatched via
## a direct method call + await so the return value is preserved. Generic
## `node.call()` / `callv()` do NOT return the right value for coroutines in
## GDScript 4 (see godotengine/godot#50894, #103887). Keep this set small.
const _COROUTINE_TOOLS := {
	"wait": true,
	"run_scene": true,
	"render_scene_preview": true,
}

## Tools that write to the project (files, nodes, scenes, settings). Blocked
## when read-only mode is active (GODOT_MCP_READ_ONLY=true env var).
const _DESTRUCTIVE_TOOLS := {
	"create_script": true, "create_csharp_script": true, "delete_file": true, "rename_file": true, "create_folder": true,
	"create_scene": true, "add_node": true, "batch_scene_edit": true, "remove_node": true, "modify_node_property": true,
	"rename_node": true, "move_node": true, "attach_script": true, "detach_script": true,
	"set_collision_shape": true, "set_sprite_texture": true, "instance_scene": true,
	"set_mesh": true, "set_material": true, "snap_node_to_grid": true,
	"set_node_reference": true,
	"set_scene_node_property": true, "set_node_properties": true, "set_node_groups": true,
	"set_resource_property": true, "save_resource_to_file": true, "connect_signal": true,
	"wire_signal": true, "generate_onready_refs": true,
	"scaffold_entity": true, "scaffold_state_machine": true,
	"disconnect_signal": true, "edit_script": true, "update_project_settings": true, "set_main_scene": true,
	"spawn_headless_peers": true, "stop_headless_peers": true,
	"configure_input_map": true, "setup_autoload": true, "generate_2d_asset": true,
	"sync_localization": true,
	"duplicate_node": true, "set_anchor_preset": true,
	"tilemap_set_cell": true, "tilemap_fill_rect": true, "tilemap_clear": true,
	"tilemap_set_terrain_cells": true, "tilemap_autotile": true,
	"create_animation": true, "add_animation_track": true, "set_animation_keyframe": true,
	"remove_animation": true,
	"add_audio_player": true, "add_audio_bus": true,
	"add_raycast": true, "setup_collision": true, "set_physics_layers": true,
	"set_collision_preset": true, "apply_collision_preset": true,
	"create_theme": true, "set_theme_color": true, "set_theme_constant": true,
	"set_theme_font_size": true, "set_theme_stylebox": true,
	"create_particles": true, "set_particle_material": true, "set_particle_color_gradient": true,
	"apply_particle_preset": true,
	"add_mesh_instance": true, "setup_lighting": true, "set_material_3d": true,
	"setup_environment": true, "setup_camera_3d": true, "add_gridmap": true,
	"select_nodes": true, "clear_editor_selection": true, "close_scene_tab": true,
	"batch_set_property": true, "rename_symbol_project_wide": true,
	"setup_navigation_region": true, "bake_navigation_mesh": true,
	"setup_navigation_agent": true, "set_navigation_layers": true,
	"mp_add_spawner": true, "mp_add_synchronizer": true,
	"mp_wire_rpc": true, "mp_scaffold_lobby": true,
	"create_resource": true, "remove_autoload": true,
	"create_animation_tree": true, "add_state_machine_state": true,
	"remove_state_machine_state": true, "add_state_machine_transition": true,
	"remove_state_machine_transition": true,
	"generate_property_forwarder": true,
	"create_shader": true, "edit_shader": true, "assign_shader_material": true,
	"set_shader_param": true, "export_project": true,
}

func _is_read_only() -> bool:
	return OS.get_environment("GODOT_MCP_READ_ONLY").to_lower() == "true"

## Tools that live in the GAME, not the editor. Named here only so the
## unknown-tool error can say WHY they are missing: batch_execute dispatches
## through this executor, which has no route to the running game, so asking for
## one of these inside a batch used to look like a typo.
const _RUNTIME_ONLY_HINT := [
	"take_screenshot", "send_input", "query_runtime_node", "get_runtime_log",
	"game_eval", "serialize_runtime_tree", "call_method_runtime",
	"set_runtime_property", "await_signal_runtime", "await_condition",
	"step_frames", "seed_rng", "time_scale", "monitor_properties",
	"click_control_runtime", "dump_control_tree", "assert_screen_text",
]


## A few likely names, not all ~180.
##
## The old message appended every registered tool name: ~4,000 characters, and
## batch_execute repeats the error once per failed operation, so a single
## mistyped name in a two-operation batch cost about 2,000 tokens — more than a
## quarter of this server's entire default tool surface, in a server whose whole
## argument is that context is expensive. Measured, then fixed.
func _suggest_tools(name: String) -> String:
	if _RUNTIME_ONLY_HINT.has(name):
		return " That tool runs inside the GAME, not the editor, so batch_execute cannot dispatch it — call it directly while a scene is running."

	var hits: Array = []
	for key in _tool_map.keys():
		var candidate := str(key)
		if candidate.contains(name) or name.contains(candidate):
			hits.append(candidate)
	if hits.is_empty():
		# Nothing contains it; fall back to sharing a leading word, which catches
		# the common "right area, wrong verb" mistake (set_node_group).
		var head: String = name.split("_")[0]
		if head.length() >= 3:
			for key in _tool_map.keys():
				if str(key).begins_with(head):
					hits.append(str(key))
	if hits.is_empty():
		return " Call list_toolsets to find the tool you want and which toolset holds it."
	hits.sort()
	return " Did you mean: %s?" % ", ".join(hits.slice(0, mini(hits.size(), 8)))


func execute_tool(tool_name: String, args: Dictionary) -> Dictionary:
	"""Execute a tool by name with the given arguments.

	This function is a coroutine because at least one tool (`wait`) uses
	`await` to yield to the SceneTree. Callers MUST `await` the result or
	they'll get a GDScriptFunctionState instead of a Dictionary."""

	# Handle internal visualizer commands (not exposed as MCP tools)
	if tool_name.begins_with("visualizer._internal_"):
		var vmethod: String = tool_name.replace("visualizer.", "")
		if _visualizer_tools and _visualizer_tools.has_method(vmethod):
			return _visualizer_tools.call(vmethod, args)
		else:
			return {&"ok": false, &"error": "Internal method not found: " + vmethod}

	# batch_execute runs many tool calls in ONE round-trip (dispatched here so it
	# can recurse into execute_tool). Handled before the _tool_map lookup.
	if tool_name == "batch_execute":
		return await _batch_execute(args)

	if not _tool_map.has(tool_name):
		return {&"ok": false, &"error": "Unknown tool: %s.%s" % [tool_name, _suggest_tools(tool_name)]}

	if _DESTRUCTIVE_TOOLS.has(tool_name) and _is_read_only():
		return {&"ok": false, &"error": "Blocked: read-only mode is active (GODOT_MCP_READ_ONLY=true). This tool modifies the project."}

	var handler: Array = _tool_map[tool_name]
	var node: Node = handler[0]
	var method: StringName = handler[1]

	if not node.has_method(method):
		return {&"ok": false, &"error": "Tool handler not found: %s.%s" % [node.name, method]}

	_parse_stringified_args(args)

	# dry_run is honoured centrally, not per tool. Every scene mutation in this
	# addon writes through SceneToolBase._save_scene / _finish_scene_edit, so
	# setting the flag on the handler for the duration of the call makes the
	# whole family preview correctly — including tools written after this. The
	# handler still does its real work, on a copy loaded from disk; what the
	# flag removes is the write at the end and any chance of touching the open
	# scene. Cleared in every exit path below, or the next caller silently gets
	# a preview instead of an edit.
	var dry_run := bool(args.get(&"dry_run", false))
	# Checked by property rather than `is SceneToolBase`: a global class_name is
	# only registered when the editor has scanned the project, so the typed
	# version parses fine in the editor and turns tool_executor.gd into a broken
	# script the moment it is loaded standalone — which is exactly how the
	# headless suite loads it.
	var previews := dry_run and ("_dry_run" in node)
	if previews:
		node._dry_run = true
		node._dry_run_skipped_write = false

	var result: Variant
	if _COROUTINE_TOOLS.has(tool_name):
		# Direct method dispatch for coroutine tools so `await` returns the
		# Dictionary correctly.
		match tool_name:
			"wait":
				result = await node.wait(args)
			"run_scene":
				result = await node.run_scene(args)
			"render_scene_preview":
				result = await node.render_scene_preview(args)
			_:
				push_error("[MCP] Coroutine tool '%s' has no direct dispatch case." % tool_name)
				result = {&"ok": false, &"error": "Coroutine tool '%s' missing dispatch case" % tool_name}
	else:
		result = node.call(method, args)

	var skipped_write: bool = previews and node._dry_run_skipped_write
	if previews:
		node._dry_run = false
		node._dry_run_skipped_write = false

	if result == null or not (result is Dictionary):
		push_error("[MCP] Tool '%s' returned invalid result: %s" % [tool_name, str(result)])
		return {&"ok": false, &"error": "Tool '%s' returned null or non-Dictionary (possible crash — check Godot console)" % tool_name}
	if not result.has(&"ok"):
		result[&"ok"] = false
		result[&"error"] = result.get(&"error", "Tool returned no status")

	# Say it plainly in the answer. A preview that reads like a completed edit
	# is worse than no preview: the agent believes the change landed.
	# Two shapes reach here. Most tools do their work and get stopped at the
	# write by the base class (skipped_write). A handful predate this and answer
	# with their own preview dict, which sets dry_run but knows nothing about
	# `written`; both must look identical to a caller.
	if (skipped_write or (dry_run and result.get(&"dry_run", false) == true)) and result.get(&"ok", false):
		result[&"dry_run"] = true
		result[&"written"] = false
		result[&"message"] = "%s Nothing was written — this was a dry run. Call again without dry_run to apply it." % str(result.get(&"message", "Preview only."))
	elif dry_run and not previews and result.get(&"ok", false) and not result.has(&"dry_run"):
		# The tool took dry_run as an ordinary argument and did whatever it does
		# with it; do not claim a guarantee this layer did not provide.
		pass
	return result

## Run a sequence of tool calls in a single request, cutting N WebSocket
## round-trips down to one. Each op is `{tool, args}` and goes through
## execute_tool (so read-only gating and arg-parsing apply per op). NOT a
## transaction — ops run in order and each scene tool still does its own
## load/save; `stop_on_error` halts the run on the first failure.
func _batch_execute(args: Dictionary) -> Dictionary:
	var ops = args.get(&"operations", [])
	if ops is String:
		var parsed = JSON.parse_string(ops)
		if parsed is Array:
			ops = parsed
	if not ops is Array or ops.is_empty():
		return {&"ok": false, &"error": "Missing 'operations' (non-empty array of {tool, args})"}
	if ops.size() > 100:
		return {&"ok": false, &"error": "Too many operations (max 100 per batch)"}

	var stop_on_error := bool(args.get(&"stop_on_error", false))
	var results: Array = []
	var all_ok := true

	for op_v in ops:
		if not op_v is Dictionary or not op_v.has(&"tool"):
			results.append({&"ok": false, &"error": "Each operation must be an object with a 'tool' field"})
			all_ok = false
			if stop_on_error: break
			continue
		var op: Dictionary = op_v
		var op_tool := str(op.get(&"tool", ""))
		if op_tool == "batch_execute":
			results.append({&"ok": false, &"error": "batch_execute cannot be nested"})
			all_ok = false
			if stop_on_error: break
			continue
		var op_args = op.get(&"args", {})
		if not op_args is Dictionary:
			op_args = {}
		var r = await execute_tool(op_tool, op_args)
		results.append(r)
		if not r.get(&"ok", false):
			all_ok = false
			if stop_on_error: break

	return {
		&"ok": true,
		&"count": results.size(),
		&"all_ok": all_ok,
		&"results": results,
		&"message": "Ran %d operation(s); all_ok=%s" % [results.size(), str(all_ok)],
	}

## Some MCP clients stringify scalar arguments (particularly booleans) when a
## tool's JSON schema doesn't declare an explicit type for that field (e.g.
## a polymorphic "value" property). Confirmed via live testing: a `value`
## argument of JSON `false` can arrive here as the GDScript String "false"
## instead of a real bool — this silently breaks any tool.set(prop, parsed)
## call, since Godot's dynamic property setter doesn't coerce String->bool.
## Reinterpret exact "true"/"false" strings as bool, same speculative-but-
## accepted heuristic already used below for {...}/[...] JSON containers.
# Fields that are genuinely polymorphic (their type comes from the value, so a
# stringified number should become a number). Kept to a whitelist so a legitimately
# string-typed field with a numeric-looking value (a node named "5", a text "42") is
# never coerced — that's why we don't reinterpret numbers for ALL keys.
const _NUMERIC_VALUE_KEYS: Dictionary = {&"value": true, &"expected": true, &"final_value": true}

# Keys whose value is FREE-FORM TEXT, where "true"/"false" is a legitimate string
# and must survive untouched: a node actually named "true", a group called
# "false", script content or a property value that is the word itself.
#
# The bool coercion below exists because the MCP layer can hand every scalar
# across as a string and Godot's setter won't turn "true" into a bool. Applying
# it to every key was documented as harmless "because all consumers str()-coerce"
# — that held only by luck, and quietly corrupted any of these fields.
const _TEXT_ONLY_KEYS: Dictionary = {
	&"name": true, &"node_name": true, &"new_name": true, &"class_name": true,
	&"content": true, &"text": true, &"code": true, &"snippet": true,
	&"old_snippet": true, &"new_snippet": true,
	&"method": true, &"signal": true, &"signal_name": true,
	&"property": true, &"property_name": true, &"group": true,
	&"old_name": true, &"animation_name": true, &"state_name": true,
	&"param_name": true, &"expression": true,
}

func _parse_stringified_args(args: Dictionary) -> void:
	for key in args:
		var val = args[key]
		if val is String:
			var s: String = val.strip_edges()
			if _TEXT_ONLY_KEYS.has(key):
				continue  # free-form text: "true" means the word, not the bool
			if s == "true":
				args[key] = true
			elif s == "false":
				args[key] = false
			elif (s.begins_with("{") and s.ends_with("}")) or (s.begins_with("[") and s.ends_with("]")):
				var parsed = JSON.parse_string(s)
				if parsed != null:
					args[key] = parsed
			elif _NUMERIC_VALUE_KEYS.has(key) and s.is_valid_float():
				args[key] = int(s) if s.is_valid_int() else s.to_float()

func get_available_tools() -> Array:
	"""Return list of available tool names."""
	return _tool_map.keys()
