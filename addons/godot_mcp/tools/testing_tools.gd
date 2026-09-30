@tool
extends SceneToolBase
class_name TestingTools
## Static QA/testing tools for MCP: assertions and integrity checks against
## saved scene (.tscn) state. These do NOT require a running game — they load
## the scene the same way the editor would and inspect it directly, so they
## work as a pre-flight check before spending time on live runtime testing
## (query_runtime_node / send_input, already exposed by MCPRuntime).
##
## Handles: assert_node_property, run_scene_assertions, validate_scene_integrity,
##          validate_meshes, run_gut_tests

# =============================================================================
# run_gut_tests — run the project's GUT (Godot Unit Test) suite headlessly
# =============================================================================
## Run the project's GUT suite in a separate `godot --headless` process and return
## structured results. GUT (the community-standard unit-test framework) must be
## installed at res://addons/gut. Fast suites run synchronously (default). For large
## or integration suites that would exceed the request timeout / freeze the editor,
## pass async=true: it returns a job_id immediately and you poll get_gut_status.
var _gut_jobs: Dictionary = {}
var _gut_mutex := Mutex.new()

func run_gut_tests(args: Dictionary) -> Dictionary:
	var test_dir: String = str(args.get(&"test_dir", "res://test"))
	var include_subdirs: bool = bool(args.get(&"include_subdirs", true))
	var run_async: bool = bool(args.get(&"async", false))

	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://addons/gut")):
		return {&"ok": false, &"error": "GUT is not installed (res://addons/gut not found). Install the 'Gut' addon from the AssetLib first."}

	if not run_async:
		return _run_gut(test_dir, include_subdirs)

	var job_id := "gut_%d" % Time.get_ticks_msec()
	_gut_mutex.lock()
	_gut_jobs[job_id] = {"status": "running", "test_dir": test_dir}
	_gut_mutex.unlock()
	var thread := Thread.new()
	thread.start(_run_gut_thread.bind(job_id, test_dir, include_subdirs))
	_gut_mutex.lock()
	_gut_jobs[job_id]["thread"] = thread
	_gut_mutex.unlock()
	return {&"ok": true, &"status": "started", &"job_id": job_id, &"test_dir": test_dir,
		&"message": "GUT run started in the background. Poll get_gut_status with job_id \"%s\"." % job_id}

## Blocking GUT run + parse — shared by the sync path and the async worker thread.
func _run_gut(test_dir: String, include_subdirs: bool) -> Dictionary:
	var proj := ProjectSettings.globalize_path("res://")
	var argv := ["--path", proj, "--headless", "-s", "res://addons/gut/gut_cmdln.gd", "-gdir=" + test_dir, "-gexit"]
	if include_subdirs:
		argv.append("-ginclude_subdirs")

	var out_lines: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), argv, out_lines, true, false)
	var text := "\n".join(out_lines)

	var total := _gut_num(text, "Tests")
	var passing := _gut_num(text, "Passing Tests")
	var scripts := _gut_num(text, "Scripts")
	if total < 0:
		return {&"ok": false, &"error": "Could not parse GUT output — is the test dir '%s' correct and does it contain GutTest scripts?" % test_dir,
			&"exit_code": exit_code, &"log": _tail(text, 3000)}
	var failed := maxi(0, total - maxi(0, passing))
	var all_passed := text.contains("All tests passed") or (total > 0 and failed == 0)

	return {&"ok": true, &"test_dir": test_dir, &"scripts": maxi(0, scripts),
		&"total": total, &"passed": maxi(0, passing), &"failed": failed,
		&"all_passed": all_passed, &"exit_code": exit_code, &"log": _tail(text, 3000),
		&"message": "GUT: %d/%d test(s) passed across %d script(s)%s" % [maxi(0, passing), total, maxi(0, scripts), "" if all_passed else " — see log for failures"]}

## Async worker: runs the (blocking) GUT suite off the main thread and stores the
## result in the job so the editor stays responsive during a long run.
func _run_gut_thread(job_id: String, test_dir: String, include_subdirs: bool) -> void:
	var result := _run_gut(test_dir, include_subdirs)
	_gut_mutex.lock()
	if _gut_jobs.has(job_id):
		result["status"] = "done"
		result["thread"] = _gut_jobs[job_id].get("thread")
		_gut_jobs[job_id] = result
	_gut_mutex.unlock()

## Poll an async GUT run started by run_gut_tests({async:true}).
func get_gut_status(args: Dictionary) -> Dictionary:
	var job_id := str(args.get(&"job_id", "")).strip_edges()
	if job_id.is_empty():
		return {&"ok": false, &"error": "Missing 'job_id' (returned by run_gut_tests with async:true)"}
	_gut_mutex.lock()
	if not _gut_jobs.has(job_id):
		_gut_mutex.unlock()
		return {&"ok": false, &"error": "Unknown job_id: " + job_id}
	var job: Dictionary = _gut_jobs[job_id].duplicate()
	var status := str(job.get("status"))
	var thread = _gut_jobs[job_id].get("thread")
	_gut_mutex.unlock()

	if status != "running" and thread is Thread and thread.is_started():
		thread.wait_to_finish()
		_gut_mutex.lock()
		if _gut_jobs.has(job_id):
			_gut_jobs[job_id].erase("thread")
		_gut_mutex.unlock()

	job.erase("thread")
	job[&"ok"] = true
	job[&"job_id"] = job_id
	if status == "running":
		job[&"message"] = "GUT run still in progress…"
	return job

## Read a numeric value from a GUT summary line like "Passing Tests   2".
func _gut_num(text: String, label: String) -> int:
	var re := RegEx.new()
	re.compile("(?m)^\\s*%s\\s+(\\d+)\\s*$" % label)
	var m := re.search(text)
	return int(m.get_string(1)) if m else -1

func _tail(s: String, n: int) -> String:
	return s if s.length() <= n else "...(truncated)...\n" + s.substr(s.length() - n)


# Properties that, if left at their default null/empty Resource, usually mean
# a node was added but never actually configured. Not exhaustive by design —
# just the common ones that silently produce an invisible/inert node.
const _REQUIRED_RESOURCE_PROPS: Dictionary = {
	"CollisionShape2D": ["shape"],
	"CollisionShape3D": ["shape"],
	"Sprite2D": ["texture"],
	"Sprite3D": ["texture"],
	"MeshInstance3D": ["mesh"],
	"AudioStreamPlayer": ["stream"],
	"AudioStreamPlayer2D": ["stream"],
	"AudioStreamPlayer3D": ["stream"],
}


# =============================================================================
# assert_node_property
# =============================================================================
func assert_node_property(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var node_path: String = str(args.get(&"node_path", "."))
	var property_name: String = str(args.get(&"property", ""))
	var expected = args.get(&"expected")
	var operator: String = str(args.get(&"operator", "eq"))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if property_name.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'property'"}
	if not args.has(&"expected"):
		return {&"ok": false, &"error": "Missing 'expected'"}

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]
	var root: Node = result[0]

	var out := _assert_one(root, node_path, property_name, expected, operator)
	root.queue_free()
	out[&"ok"] = true
	out[&"scene_path"] = scene_path
	return out

## Runs one assertion against an already-loaded scene tree. Returns a
## dictionary WITHOUT `ok` (caller sets that) so run_scene_assertions can
## reuse it per-item without a nested "ok" that means something different.
func _assert_one(root: Node, node_path: String, property_name: String, expected, operator: String) -> Dictionary:
	var target := _find_node(root, node_path)
	if not target:
		return {&"pass": false, &"node_path": node_path, &"property": property_name,
			&"error": "Node not found: " + node_path}

	var prop_exists := false
	for prop: Dictionary in target.get_property_list():
		if prop[&"name"] == property_name:
			prop_exists = true
			break
	if not prop_exists:
		return {&"pass": false, &"node_path": node_path, &"property": property_name,
			&"error": "Property '%s' not found on %s (%s)" % [property_name, node_path, target.get_class()]}

	var actual = target.get(property_name)
	# Coerce `expected` to the actual property's type so a stringified scalar
	# (e.g. "false" arriving as a String over JSON-RPC) compares correctly.
	var expected_parsed = VariantCodec.parse_typed_value(expected, typeof(actual))

	var passed := false
	var op_error := ""
	match operator:
		"eq":
			passed = actual == expected_parsed
		"neq":
			passed = actual != expected_parsed
		"gt", "gte", "lt", "lte":
			if not (actual is int or actual is float) or not (expected_parsed is int or expected_parsed is float):
				op_error = "Operator '%s' requires a numeric property (got %s)" % [operator, type_string(typeof(actual))]
			else:
				match operator:
					"gt": passed = actual > expected_parsed
					"gte": passed = actual >= expected_parsed
					"lt": passed = actual < expected_parsed
					"lte": passed = actual <= expected_parsed
		_:
			op_error = "Unknown operator '%s' (use eq, neq, gt, gte, lt, lte)" % operator

	if not op_error.is_empty():
		return {&"pass": false, &"node_path": node_path, &"property": property_name, &"error": op_error}

	return {
		&"pass": passed,
		&"node_path": node_path,
		&"property": property_name,
		&"operator": operator,
		&"actual": VariantCodec.serialize_value(actual),
		&"expected": VariantCodec.serialize_value(expected_parsed),
	}

# =============================================================================
# run_scene_assertions — batch of assert_node_property against one scene
# =============================================================================
func run_scene_assertions(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var assertions: Array = args.get(&"assertions", [])

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if assertions.is_empty():
		return {&"ok": false, &"error": "Missing 'assertions' (non-empty array)"}

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]
	var root: Node = result[0]

	var results: Array = []
	var passed_count := 0
	for item_v in assertions:
		if not item_v is Dictionary:
			results.append({&"pass": false, &"error": "Each assertion must be an object with node_path/property/expected"})
			continue
		var item: Dictionary = item_v
		var node_path: String = str(item.get(&"node_path", "."))
		var property_name: String = str(item.get(&"property", ""))
		var operator: String = str(item.get(&"operator", "eq"))
		if property_name.strip_edges().is_empty():
			results.append({&"pass": false, &"node_path": node_path, &"error": "Missing 'property'"})
			continue
		if not item.has(&"expected"):
			results.append({&"pass": false, &"node_path": node_path, &"property": property_name, &"error": "Missing 'expected'"})
			continue
		var one := _assert_one(root, node_path, property_name, item.get(&"expected"), operator)
		if one.get(&"pass", false):
			passed_count += 1
		results.append(one)

	root.queue_free()

	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"total": results.size(),
		&"passed": passed_count,
		&"failed": results.size() - passed_count,
		&"all_passed": passed_count == results.size(),
		&"results": results,
	}

# =============================================================================
# validate_scene_integrity — flag nodes with empty required resource slots
# =============================================================================
func validate_scene_integrity(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]
	var root: Node = result[0]

	var issues: Array = []
	_walk_for_issues(root, issues)
	root.queue_free()

	return {
		&"ok": true,
		&"scene_path": scene_path,
		&"issue_count": issues.size(),
		&"issues": issues,
	}

## Validate mesh resources for empty/degenerate geometry. Pass `paths` (res://
## .mesh/.obj/.tres/.res files) to check a specific set, or omit to sweep every
## mesh resource in the project. A mesh is flagged when it fails to load, has
## zero surfaces, or has a surface with zero vertices — the "created/imported but
## empty" mistakes that silently render nothing. This is the mesh analogue of
## validate_scripts (sweep + verdict); get_resource_info describes one resource,
## this one judges many.
func validate_meshes(args: Dictionary) -> Dictionary:
	var paths_arg = args.get(&"paths", [])
	var targets: PackedStringArray = []
	var explicit: bool = paths_arg is Array and not (paths_arg as Array).is_empty()
	if explicit:
		for p in paths_arg:
			targets.append(_ensure_res_path(str(p)))
	else:
		_collect_mesh_files("res://", targets)

	var invalid: Array = []
	var skipped: Array = []
	var checked := 0
	for path in targets:
		if not FileAccess.file_exists(path):
			invalid.append({&"path": path, &"issues": ["File not found"]})
			continue
		var res = load(path)
		if res == null:
			invalid.append({&"path": path, &"issues": ["Failed to load (corrupt or unreadable)"]})
			continue
		if not (res is Mesh):
			# Silent in a project-wide sweep, where skipping non-meshes is the
			# whole point. Named when the caller asked for this path by hand:
			# passing a .tscn otherwise came back "Validated 0 mesh(es)" with
			# nothing saying the file had been dropped.
			if explicit:
				skipped.append({&"path": path, &"reason": "Not a mesh resource (%s). This tool reads mesh files; a scene's meshes live inside its MeshInstance nodes." % [res.get_class()]})
			continue
		checked += 1
		var issues := _mesh_issues(res)
		if not issues.is_empty():
			invalid.append({&"path": path, &"issues": issues})

	var out := {
		&"ok": true,
		&"total": checked,
		&"invalid_count": invalid.size(),
		&"invalid": invalid,
		&"message": "Validated %d mesh(es): %d with issues." % [checked, invalid.size()],
	}
	if not skipped.is_empty():
		out[&"skipped"] = skipped
	return out

## Problems with a mesh, human-readable (empty array = healthy).
func _mesh_issues(m: Mesh) -> Array:
	var issues: Array = []
	var sc := m.get_surface_count()
	if sc == 0:
		issues.append("Mesh has no surfaces (renders nothing)")
		return issues
	for i in range(sc):
		var arr := m.surface_get_arrays(i)
		var verts := 0
		if arr and arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] != null:
			verts = arr[Mesh.ARRAY_VERTEX].size()
		if verts == 0:
			issues.append("Surface %d has no vertices" % i)
	return issues

func _collect_mesh_files(dir_path: String, out: PackedStringArray, depth: int = 0) -> void:
	if depth > 20:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.begins_with("."):
			fname = dir.get_next()
			continue
		var full := dir_path.path_join(fname)
		if dir.current_is_dir():
			_collect_mesh_files(full, out, depth + 1)
		else:
			var ext := fname.get_extension().to_lower()
			if ext == "mesh" or ext == "obj" or ext == "res" or ext == "tres":
				out.append(full)
		fname = dir.get_next()
	dir.list_dir_end()

func _walk_for_issues(node: Node, issues: Array, root: Node = null) -> void:
	if root == null:
		root = node
	var node_class := node.get_class()
	if _REQUIRED_RESOURCE_PROPS.has(node_class):
		for prop_name in _REQUIRED_RESOURCE_PROPS[node_class]:
			var value = node.get(prop_name)
			if value == null:
				issues.append({
					&"node_path": _relative_path(node),
					&"node_class": node_class,
					&"property": prop_name,
					&"issue": "'%s' is empty on this %s" % [prop_name, node_class],
				})
	if node != root and not node.scene_file_path.is_empty():
		var lost := _script_lost_by_instance(node)
		if not lost.is_empty():
			issues.append({
				&"node_path": _relative_path(node),
				&"node_class": node_class,
				&"property": "script",
				&"issue": "Instance of %s has no script, but that scene's root carries %s. A 'script = null' override silently disables the node - it stops running _ready/_process with no error." % [node.scene_file_path, lost],
			})
	for child in node.get_children():
		_walk_for_issues(child, issues, root)

## Script an instanced node should have inherited from its source scene but
## does not, or "" when nothing is wrong.
##
## This exists because of a real incident: a Player instance came back with
## `script = null` written as an instance override, and the character simply
## stopped moving - no script, no _physics_process, no error anywhere. Neither
## the disk path nor the live path reproduces it, so rather than keep guessing
## at the cause, the failure mode is at least no longer silent.
##
## The source scene is read through SceneState instead of being instantiated:
## instantiating it here would pull in its whole dependency chain for every
## instanced node in the tree.
func _script_lost_by_instance(node: Node) -> String:
	if node.get_script() != null:
		return ""
	var packed := load(node.scene_file_path) as PackedScene
	if packed == null:
		return ""
	var state := packed.get_state()
	if state == null or state.get_node_count() == 0:
		return ""
	for i in range(state.get_node_property_count(0)):
		if state.get_node_property_name(0, i) != &"script":
			continue
		var value = state.get_node_property_value(0, i)
		if value is Script:
			var path: String = value.resource_path
			return path if not path.is_empty() else "a built-in script"
	return ""

func _relative_path(node: Node) -> String:
	# The scene root has owner == null; walk up via owner to find it so the
	# reported path is relative to the scene, not an absolute engine path.
	var scene_root := node
	while scene_root.owner != null:
		scene_root = scene_root.owner
	if scene_root == node:
		return "."
	return str(scene_root.get_path_to(node))
