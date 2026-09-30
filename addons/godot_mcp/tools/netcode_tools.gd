@tool
extends SceneToolBase
class_name NetcodeTools
## Multiplayer scaffolding tools for MCP.
## Handles: mp_add_spawner, mp_add_synchronizer, mp_wire_rpc, mp_scaffold_lobby,
##          mp_diagnose
##
## The runtime side of multiplayer (spawn_headless_peers, call_rpc_runtime,
## get_multiplayer_status) already exists for TESTING netcode. These build it:
## the high-level replication nodes Godot 4 uses (MultiplayerSpawner /
## MultiplayerSynchronizer) plus the RPC boilerplate, which are fiddly to author
## by hand because the useful state lives in a sub-resource
## (SceneReplicationConfig) rather than in plain properties.
##
## API verified against ClassDB on Godot 4.7 before writing.


# =============================================================================
# mp_add_spawner
# =============================================================================
## A MultiplayerSpawner replicates *node creation* from the authority to every
## peer: it watches `spawn_path` and, for scenes in its spawnable list, recreates
## them remotely. Without one, a node the server adds simply never exists on the
## clients.
func mp_add_spawner(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var parent_path: String = str(args.get(&"parent_path", "."))
	var node_name: String = str(args.get(&"node_name", "MultiplayerSpawner"))
	var spawn_path: String = str(args.get(&"spawn_path", "")).strip_edges()
	var spawnable_scenes: Array = args.get(&"spawnable_scenes", [])
	var spawn_limit: int = int(args.get(&"spawn_limit", 0))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if spawn_path.is_empty():
		return {&"ok": false, &"error": "Missing 'spawn_path' - the node new instances get added under (e.g. \"../Players\"), relative to the spawner."}

	# Validate every spawnable scene BEFORE touching the tree: on an open scene
	# a later failure cannot be rolled back (_discard_scene is a no-op there),
	# so a bad path must be caught while nothing has been mutated yet.
	var validated: Array = []
	for s in spawnable_scenes:
		var p: String = _ensure_res_path(str(s))
		if PathGuard.is_bad(p):
			return {&"ok": false, &"error": "Spawnable scene path escapes the project sandbox: " + str(s)}
		if not ResourceLoader.exists(p):
			return {&"ok": false, &"error": "Spawnable scene not found: " + p}
		validated.append(p)

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

	var spawner := MultiplayerSpawner.new()
	spawner.name = node_name
	spawner.spawn_path = NodePath(spawn_path)
	if spawn_limit > 0:
		spawner.spawn_limit = spawn_limit
	for p in validated:
		spawner.add_spawnable_scene(p)

	# Undo entry opened here, after the validations above: an action left open
	# by an early return would sit unclosed on the editor's undo stack.
	var ctx := _begin_edit(is_live, "MCP: add %s" % spawner.name, root)
	_edit_add_child(ctx, parent, spawner, root)
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	return {&"ok": true, &"scene_path": scene_path, &"node_name": spawner.name,
		&"spawn_path": spawn_path, &"spawnable_scenes": validated,
		&"message": "Added MultiplayerSpawner '%s' spawning into '%s' (%d scene(s))." % [spawner.name, spawn_path, validated.size()]}


# =============================================================================
# mp_add_synchronizer
# =============================================================================
## A MultiplayerSynchronizer replicates *property values* over time. The list of
## replicated properties lives in a SceneReplicationConfig sub-resource, where
## each entry carries independent spawn/sync flags - that indirection is what
## makes this tedious to write by hand.
##
## Property paths are relative to root_path and take the form ".:property"
## (e.g. ".:position"), matching what the editor's Replication dock produces.
func mp_add_synchronizer(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get(&"scene_path", "")))
	var parent_path: String = str(args.get(&"parent_path", "."))
	var node_name: String = str(args.get(&"node_name", "MultiplayerSynchronizer"))
	var root_path: String = str(args.get(&"root_path", "..")).strip_edges()
	var properties: Array = args.get(&"properties", [])
	var replication_interval: float = float(args.get(&"replication_interval", 0.0))

	if scene_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'scene_path'"}
	if properties.is_empty():
		return {&"ok": false, &"error": "Missing 'properties' - a non-empty array of property paths to replicate, e.g. [\".:position\", \".:velocity\"]."}

	# Normalise and validate before mutating anything (same reasoning as above).
	var prop_specs: Array = []
	for entry in properties:
		var path := ""
		var do_spawn := true
		var do_sync := true
		if entry is String:
			path = str(entry)
		elif entry is Dictionary:
			path = str(entry.get(&"path", ""))
			do_spawn = bool(entry.get(&"spawn", true))
			do_sync = bool(entry.get(&"sync", true))
		else:
			return {&"ok": false, &"error": "Each 'properties' entry must be a string or {path, spawn?, sync?}"}
		path = path.strip_edges()
		if path.is_empty():
			return {&"ok": false, &"error": "A 'properties' entry has an empty path"}
		# ".:position" is the form the Replication dock writes; accept a bare
		# "position" and normalise it rather than silently replicating nothing.
		if not path.contains(":"):
			path = ".:" + path
		prop_specs.append({&"path": path, &"spawn": do_spawn, &"sync": do_sync})

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

	var config := SceneReplicationConfig.new()
	for spec in prop_specs:
		var np := NodePath(str(spec[&"path"]))
		config.add_property(np, -1)
		config.property_set_spawn(np, bool(spec[&"spawn"]))
		config.property_set_sync(np, bool(spec[&"sync"]))

	var sync := MultiplayerSynchronizer.new()
	sync.name = node_name
	sync.root_path = NodePath(root_path)
	sync.replication_config = config
	if replication_interval > 0.0:
		sync.replication_interval = replication_interval

	# Undo entry opened here, after the validations above: an action left open
	# by an early return would sit unclosed on the editor's undo stack.
	var ctx := _begin_edit(is_live, "MCP: add %s" % sync.name, root)
	_edit_add_child(ctx, parent, sync, root)
	_edit_commit(ctx)

	var err := _finish_scene_edit(root, scene_path, is_live)
	if not err.is_empty():
		return err

	var applied: Array = []
	for spec in prop_specs:
		applied.append(spec[&"path"])

	return {&"ok": true, &"scene_path": scene_path, &"node_name": sync.name,
		&"root_path": root_path, &"properties": applied,
		&"message": "Added MultiplayerSynchronizer '%s' replicating %d propert%s." % [sync.name, applied.size(), "y" if applied.size() == 1 else "ies"]}


# =============================================================================
# mp_wire_rpc
# =============================================================================
## Append a correctly-annotated @rpc method to a script. Getting the annotation
## wrong is the classic Godot-4 multiplayer bug: the call silently does nothing
## remotely, with no error, because the mode did not match how it was invoked.
func mp_wire_rpc(args: Dictionary) -> Dictionary:
	var script_path: String = _ensure_res_path(str(args.get(&"script_path", "")))
	var method: String = str(args.get(&"method", "")).strip_edges()
	var mode: String = str(args.get(&"mode", "authority")).strip_edges()
	var transfer: String = str(args.get(&"transfer_mode", "reliable")).strip_edges()
	var call_local: bool = bool(args.get(&"call_local", false))
	var params: Array = args.get(&"params", [])

	if script_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'script_path'"}
	if method.is_empty():
		return {&"ok": false, &"error": "Missing 'method'"}
	if not method.is_valid_identifier():
		return {&"ok": false, &"error": "'%s' is not a valid GDScript identifier" % method}
	if mode not in ["authority", "any_peer"]:
		return {&"ok": false, &"error": "Invalid 'mode': %s. Use \"authority\" (only the authority may call it) or \"any_peer\"." % mode}
	if transfer not in ["reliable", "unreliable", "unreliable_ordered"]:
		return {&"ok": false, &"error": "Invalid 'transfer_mode': %s. Use reliable, unreliable, or unreliable_ordered." % transfer}

	if not FileAccess.file_exists(script_path):
		return {&"ok": false, &"error": "Script not found: " + script_path}

	var f := FileAccess.open(script_path, FileAccess.READ)
	if f == null:
		return {&"ok": false, &"error": "Could not read " + script_path}
	var source := f.get_as_text()
	f.close()

	# A second @rpc with the same name would compile but shadow confusingly.
	if source.contains("func %s(" % method):
		return {&"ok": false, &"error": "Script already defines a method named '%s'" % method}

	var param_list: Array = []
	for p in params:
		if p is String:
			param_list.append(str(p))
		elif p is Dictionary:
			var pname := str(p.get(&"name", ""))
			var ptype := str(p.get(&"type", ""))
			if pname.is_empty():
				return {&"ok": false, &"error": "Each 'params' entry needs a name"}
			param_list.append(pname if ptype.is_empty() else "%s: %s" % [pname, ptype])
		else:
			return {&"ok": false, &"error": "Each 'params' entry must be a string or {name, type?}"}

	var annotation := "@rpc(\"%s\", \"%s\"%s)" % [
		mode, transfer, ", \"call_local\"" if call_local else ""
	]
	var body := "%s\nfunc %s(%s) -> void:\n\tpass # TODO: implement\n" % [
		annotation, method, ", ".join(param_list)
	]

	if not source.ends_with("\n"):
		source += "\n"
	source += "\n" + body

	var w := FileAccess.open(script_path, FileAccess.WRITE)
	if w == null:
		return {&"ok": false, &"error": "Could not write " + script_path}
	w.store_string(source)
	w.close()

	return {&"ok": true, &"script_path": script_path, &"method": method,
		&"annotation": annotation,
		&"generated": body.strip_edges(),
		&"message": "Added %s %s() to %s. Call it from the runtime with call_rpc_runtime." % [annotation, method, script_path],
		&"note": "\"authority\" means only the node's authority may invoke it; use \"any_peer\" if clients need to call it on the server."}


# =============================================================================
# mp_scaffold_lobby
# =============================================================================
## Build the host/join plumbing every Godot multiplayer project needs: an
## ENetMultiplayerPeer set up as either server or client, plus the peer
## connect/disconnect signal handlers. This is the boilerplate that is identical
## in every project and easy to get subtly wrong.
func mp_scaffold_lobby(args: Dictionary) -> Dictionary:
	var script_path: String = _ensure_res_path(str(args.get(&"script_path", "")))
	var port: int = int(args.get(&"port", 7777))
	var max_clients: int = int(args.get(&"max_clients", 8))
	var default_address: String = str(args.get(&"default_address", "127.0.0.1"))

	if script_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'script_path' (where to write the lobby script, e.g. res://net/lobby.gd)"}
	if FileAccess.file_exists(script_path):
		return {&"ok": false, &"error": "Refusing to overwrite an existing file: " + script_path}
	if port < 1 or port > 65535:
		return {&"ok": false, &"error": "'port' must be between 1 and 65535"}

	var dir := script_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	var src := """extends Node
## Multiplayer lobby: hosting, joining, and peer tracking.
## Generated by godot-mcp-bridge (mp_scaffold_lobby).

signal peer_joined(id: int)
signal peer_left(id: int)
signal connection_failed()
signal connected_to_server()

const PORT := %d
const MAX_CLIENTS := %d
const DEFAULT_ADDRESS := "%s"

var peers: Array[int] = []

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): connected_to_server.emit())
	multiplayer.connection_failed.connect(func(): connection_failed.emit())

## Start listening. Returns OK, or the error code from create_server.
func host() -> int:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		push_error("Failed to host on port %%d: %%d (is it already in use?)" %% [PORT, err])
		return err
	multiplayer.multiplayer_peer = peer
	return OK

## Connect to a host. Returns OK, or the error code from create_client.
func join(address: String = DEFAULT_ADDRESS) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		push_error("Failed to connect to %%s:%%d: %%d" %% [address, PORT, err])
		return err
	multiplayer.multiplayer_peer = peer
	return OK

## Drop the connection and reset to single-player.
func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	peers.clear()

func is_hosting() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()

func _on_peer_connected(id: int) -> void:
	if not peers.has(id):
		peers.append(id)
	peer_joined.emit(id)

func _on_peer_disconnected(id: int) -> void:
	peers.erase(id)
	peer_left.emit(id)
""" % [port, max_clients, default_address]

	var w := FileAccess.open(script_path, FileAccess.WRITE)
	if w == null:
		return {&"ok": false, &"error": "Could not write " + script_path}
	w.store_string(src)
	w.close()

	return {&"ok": true, &"script_path": script_path, &"port": port,
		&"max_clients": max_clients,
		&"message": "Scaffolded lobby at %s (host/join/leave + peer tracking on port %d)." % [script_path, port],
		&"next_steps": [
			"Register it as an autoload with setup_autoload so any scene can reach it.",
			"Call host() or join(address) from your menu UI.",
			"Add a MultiplayerSpawner (mp_add_spawner) for the player scene.",
		]}

# =============================================================================
# mp_diagnose
# =============================================================================
## Find the multiplayer mistakes that fail SILENTLY.
##
## The scaffolding tools above build a correct setup. This one checks an
## existing one, and it targets specific failure shapes that recur on the Godot
## forum - all of which share the property that nothing errors at author time
## and the game looks fine until a second peer joins:
##
## - An `.rpc()` call to a method with no `@rpc` annotation. The call is a no-op
##   on the remote peer. No error, anywhere.
## - A MultiplayerSynchronizer whose replication config is empty: it replicates
##   nothing, forever, silently.
## - A MultiplayerSpawner with no spawnable scenes, or a `spawn_path` that does
##   not resolve: nodes the server adds simply never appear on clients, which
##   reads as "the client is broken" rather than "the spawner is misconfigured".
## - A synchronizer or spawner whose target path points outside the scene.
##
## Static only: it reads scenes and scripts, never runs the game. It cannot see
## a node added at runtime under a path no spawner covers - that one needs the
## runtime harness (spawn_headless_peers + the runtime tools).
func mp_diagnose(args: Dictionary) -> Dictionary:
	var scene_arg: String = str(args.get(&"scene_path", "")).strip_edges()
	var include_addons: bool = bool(args.get(&"include_addons", false))

	var scenes: Array = []
	if not scene_arg.is_empty():
		scenes.append(_ensure_res_path(scene_arg))
	else:
		_collect_scenes("res://", scenes, include_addons)

	var findings: Array = []
	var scanned := 0
	for path in scenes:
		var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
		if packed == null:
			continue
		var root := _instantiate_packed_scene_for_edit(packed)
		if root == null:
			continue
		scanned += 1
		_diagnose_node_tree(root, root, path, findings)
		root.queue_free()

	# The @rpc check is per-script, not per-scene: a script calling .rpc() on a
	# method it never annotated is wrong regardless of where it is instanced.
	var scripts: Array = []
	_collect_gd_scripts("res://", scripts, include_addons)
	for script_path in scripts:
		_diagnose_rpc_calls(script_path, findings)

	var by_severity := {&"error": 0, &"warning": 0}
	for f in findings:
		var sev := str(f.get(&"severity", "warning"))
		by_severity[sev] = int(by_severity.get(sev, 0)) + 1

	return {
		&"ok": true,
		&"scenes_scanned": scanned,
		&"scripts_scanned": scripts.size(),
		&"finding_count": findings.size(),
		&"errors": by_severity[&"error"],
		&"warnings": by_severity[&"warning"],
		&"findings": findings,
		&"note": "Static analysis: scenes and scripts only, the game is never run. A node added at runtime under a path no spawner covers cannot be seen this way - use spawn_headless_peers with the runtime tools for that.",
	}

func _collect_scenes(dir_path: String, out: Array, include_addons: bool, depth: int = 0) -> void:
	if depth > 12:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if entry != "addons" or include_addons:
				_collect_scenes(full, out, include_addons, depth + 1)
		elif full.get_extension().to_lower() == "tscn":
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()

func _collect_gd_scripts(dir_path: String, out: Array, include_addons: bool, depth: int = 0) -> void:
	if depth > 12:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if entry != "addons" or include_addons:
				_collect_gd_scripts(full, out, include_addons, depth + 1)
		elif full.get_extension().to_lower() == "gd":
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()

func _add_finding(findings: Array, severity: String, where: String, issue: String, fix: String) -> void:
	findings.append({&"severity": severity, &"where": where, &"issue": issue, &"fix": fix})

func _diagnose_node_tree(node: Node, root: Node, scene_path: String, findings: Array) -> void:
	var where := "%s::%s" % [scene_path, str(root.get_path_to(node))]

	if node is MultiplayerSpawner:
		var spawner: MultiplayerSpawner = node
		if spawner.get_spawnable_scene_count() == 0:
			_add_finding(findings, "error", where,
				"MultiplayerSpawner has no spawnable scenes, so it can never replicate anything.",
				"Add the scene(s) it should spawn (mp_add_spawner takes spawnable_scenes).")
		var sp := str(spawner.spawn_path)
		if sp.is_empty():
			_add_finding(findings, "error", where,
				"MultiplayerSpawner has no spawn_path set.",
				"Point spawn_path at the node new instances get added under.")
		elif node.get_node_or_null(spawner.spawn_path) == null:
			_add_finding(findings, "error", where,
				"MultiplayerSpawner's spawn_path '%s' does not resolve in this scene." % sp,
				"Fix the path, or add the node it should point at. Spawning into a missing node silently does nothing on clients.")

	if node is MultiplayerSynchronizer:
		var sync: MultiplayerSynchronizer = node
		var config := sync.replication_config
		if config == null or config.get_properties().is_empty():
			_add_finding(findings, "error", where,
				"MultiplayerSynchronizer replicates no properties, so it syncs nothing.",
				"Add the properties to replicate (mp_add_synchronizer takes properties).")
		var rp := str(sync.root_path)
		if not rp.is_empty() and node.get_node_or_null(sync.root_path) == null:
			_add_finding(findings, "error", where,
				"MultiplayerSynchronizer's root_path '%s' does not resolve in this scene." % rp,
				"Point root_path at the node whose properties should replicate.")

	for child in node.get_children():
		_diagnose_node_tree(child, root, scene_path, findings)

## Flag `.rpc("name")` / `.rpc_id(id, "name")` calls whose target method is
## declared in the SAME script without an `@rpc` annotation.
##
## Deliberately narrow: it only reports when the method is defined in the file
## doing the calling, so a call into another node's script is never guessed at.
## That keeps this free of the false positives that would make it noise.
func _diagnose_rpc_calls(script_path: String, findings: Array) -> void:
	var src := FileAccess.get_file_as_string(script_path)
	if src.is_empty() or not src.contains("rpc"):
		return

	# Methods declared in this file, and which of them carry an @rpc annotation
	# on a preceding line.
	var annotated: Dictionary = {}
	var declared: Dictionary = {}
	var lines := src.split("\n")
	var re_func := RegEx.new()
	re_func.compile("^\\s*(static\\s+)?func\\s+([A-Za-z_][A-Za-z0-9_]*)")
	for i in range(lines.size()):
		var m := re_func.search(lines[i])
		if m == null:
			continue
		var fname := m.get_string(2)
		declared[fname] = true
		# Walk back over decorators/comments to find an @rpc.
		var j := i - 1
		while j >= 0:
			var prev := str(lines[j]).strip_edges()
			if prev.is_empty() or prev.begins_with("#"):
				j -= 1
				continue
			if prev.begins_with("@rpc"):
				annotated[fname] = true
			break
		j = i

	var re_call := RegEx.new()
	# Matches both `node.rpc("name")` and the bare `rpc("name")` on self, which
	# is the more common form. The lookbehind keeps `my_rpc(` and `foo.rpc_bar(`
	# from matching.
	re_call.compile("(?<![A-Za-z0-9_])rpc(?:_id)?\\s*\\(\\s*(?:[^,()]+,\\s*)?[\"&']([A-Za-z_][A-Za-z0-9_]*)[\"']")
	var reported: Dictionary = {}
	for m in re_call.search_all(src):
		var target := m.get_string(1)
		if reported.has(target):
			continue
		if not declared.has(target):
			continue  # defined elsewhere: not ours to judge
		if annotated.has(target):
			continue
		reported[target] = true
		_add_finding(findings, "error", "%s::%s" % [script_path, target],
			"'%s' is called with .rpc()/.rpc_id() but has no @rpc annotation, so the remote call is silently dropped." % target,
			"Add an @rpc annotation to the method (mp_wire_rpc writes a correct one).")



# =============================================================================
# mp_set_authority
# =============================================================================
## Write the code that assigns a node's multiplayer authority.
##
## Authority decides whose writes count: a MultiplayerSynchronizer replicates
## only FROM the authority, and an @rpc("authority") call is refused anywhere
## else. Getting it wrong gives the classic Godot 4 symptom — the call runs,
## nothing happens, no error.
##
## This generates code rather than editing the scene because there is nothing to
## edit: `multiplayer_authority` is NOT a property. Node exposes only
## set_multiplayer_authority(), so authority is runtime state with no .tscn
## representation at all — verified against the engine rather than assumed.
## Anything claiming to "set authority in the scene file" is writing a value
## Godot will never read back.
func mp_set_authority(args: Dictionary) -> Dictionary:
	var script_path: String = _ensure_res_path(str(args.get(&"script_path", "")))
	var peer_id = args.get(&"peer_id")
	var recursive: bool = bool(args.get(&"recursive", false))
	var node_expr: String = str(args.get(&"node", "self"))

	if script_path.strip_edges() == "res://":
		return {&"ok": false, &"error": "Missing 'script_path' (the script that should claim authority)"}
	if not FileAccess.file_exists(script_path):
		return {&"ok": false, &"error": "Script not found: " + script_path}
	if peer_id == null:
		return {&"ok": false, &"error": "Missing 'peer_id'. Use 1 for the server/host, or the string \"owner\" to claim authority for the peer that spawned this node (multiplayer.get_unique_id())."}

	var f := FileAccess.open(script_path, FileAccess.READ)
	if f == null:
		return {&"ok": false, &"error": "Could not read " + script_path}
	var source := f.get_as_text()
	f.close()

	if source.contains("set_multiplayer_authority("):
		return {&"ok": false, &"error": "%s already calls set_multiplayer_authority(); edit it directly rather than adding a second assignment that would fight the first." % script_path}

	var value_expr := ""
	if typeof(peer_id) == TYPE_STRING and str(peer_id) == "owner":
		value_expr = "multiplayer.get_unique_id()"
	else:
		var pid := int(peer_id)
		if pid < 0:
			return {&"ok": false, &"error": "'peer_id' must be >= 0 (1 = server, 0 = no authority), or the string \"owner\""}
		value_expr = str(pid)

	var body := "

## Claim multiplayer authority. Written by mp_set_authority.
"
	body += "## Authority is runtime state — it has no representation in the .tscn, so it
"
	body += "## has to be assigned in code before any replication or @rpc(\"authority\") call.
"
	body += "func _mcp_claim_authority() -> void:
"
	body += "	%s.set_multiplayer_authority(%s%s)
" % [node_expr, value_expr, ", true" if recursive else ""]

	var call_line := "	_mcp_claim_authority()
"
	var new_source := source
	# Prefer calling it from an existing _ready(); otherwise write one.
	var ready_idx := new_source.find("func _ready(")
	if ready_idx != -1:
		var line_end := new_source.find("
", ready_idx)
		if line_end == -1:
			return {&"ok": false, &"error": "Could not parse the existing _ready() in " + script_path}
		new_source = new_source.substr(0, line_end + 1) + call_line + new_source.substr(line_end + 1)
	else:
		body += "
func _ready() -> void:
" + call_line

	if not new_source.ends_with("
"):
		new_source += "
"
	new_source += body

	var w := FileAccess.open(script_path, FileAccess.WRITE)
	if w == null:
		return {&"ok": false, &"error": "Could not write " + script_path}
	w.store_string(new_source)
	w.close()

	# `node` is an EXPRESSION, and a wrong one only shows up as a parse error in
	# a file this tool just rewrote — the call answering ok with the script left
	# broken. Check what was written and put the original back if it does not
	# compile: a tool must not hand back a file that no longer parses.
	var check := GDScript.new()
	check.source_code = new_source
	if check.reload() != OK:
		var restore := FileAccess.open(script_path, FileAccess.WRITE)
		if restore != null:
			restore.store_string(source)
			restore.close()
		_refresh_filesystem()
		return {&"ok": false,
			&"error": "The generated code does not compile, so %s was left unchanged. `node` is an expression, not a node name: pass \"self\", or \"$%s\" to reach a child." % [script_path, node_expr],
			&"node": node_expr}
	_refresh_filesystem()

	return {
		&"ok": true, &"script_path": script_path,
		&"peer_id": value_expr, &"recursive": recursive, &"node": node_expr,
		&"called_from_existing_ready": ready_idx != -1,
		&"message": "Wrote _mcp_claim_authority() into %s (authority = %s%s)" % [script_path, value_expr, ", recursive" if recursive else ""],
	}
