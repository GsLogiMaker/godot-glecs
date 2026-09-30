@tool
extends Node
class_name FileTools
## File operation tools for MCP.
## Handles: list_dir, read_file, search_project, create_script

## See ScriptTools: set by the ToolExecutor for one call when the caller passed
## dry_run, honoured at the write below.
var _dry_run := false
var _dry_run_skipped_write := false

const PathGuard = preload("res://addons/godot_mcp/utils/path_guard.gd")

const DEFAULT_MAX_BYTES := 200_000
const DEFAULT_MAX_RESULTS := 50
## A matched line is shown, not the file, so a single generated or minified
## line must not be able to dominate the answer. Long lines are cut here and
## say so.
const MAX_MATCH_CHARS := 200
const MAX_TRAVERSAL_DEPTH := 20
const _SKIP_EXTENSIONS: Dictionary = {
	".import": true, ".png": true, ".jpg": true, ".jpeg": true,
	".webp": true, ".svg": true, ".ogg": true, ".wav": true,
	".mp3": true, ".escn": true, ".glb": true, ".gltf": true,
	".uid": true,
}

var _editor_plugin: EditorPlugin = null

func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin

# =============================================================================
# list_dir - List files and folders in a directory
# =============================================================================
func list_dir(args: Dictionary) -> Dictionary:
	var root: String = str(args.get(&"root", "res://"))
	var include_hidden: bool = bool(args.get(&"include_hidden", false))

	var guarded := PathGuard.sanitize(root)
	if not guarded[&"ok"]:
		return {&"ok": false, &"error": guarded[&"error"]}
	root = guarded[&"path"]

	var dir := DirAccess.open(root)
	if dir == null:
		return {&"ok": false, &"error": "Cannot open directory: " + root}

	var files: PackedStringArray = []
	var folders: PackedStringArray = []

	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		# Skip hidden files unless requested
		if not include_hidden and name.begins_with("."):
			name = dir.get_next()
			continue

		# Skip .uid files
		if name.ends_with(".uid"):
			name = dir.get_next()
			continue

		if dir.current_is_dir():
			folders.append(name)
		else:
			files.append(name)

		name = dir.get_next()
	dir.list_dir_end()

	# Sort alphabetically
	files.sort()
	folders.sort()

	return {
		&"ok": true,
		&"path": root,
		&"files": files,
		&"folders": folders,
		&"total": files.size() + folders.size()
	}

# =============================================================================
# read_file - Read contents of a file
# =============================================================================

## Drop an incomplete multibyte UTF-8 sequence from the end of `buf`. Used when
## a byte-range read stops short of EOF and may have sliced through the middle
## of a codepoint, which would otherwise decode to a garbled tail character.
func _trim_incomplete_utf8_tail(buf: PackedByteArray) -> PackedByteArray:
	var n := buf.size()
	if n == 0:
		return buf
	# Walk back over continuation bytes (0b10xxxxxx) to find the last lead byte.
	var i := n - 1
	while i >= 0 and (buf[i] & 0xC0) == 0x80:
		i -= 1
	if i < 0:
		return buf
	var lead := buf[i]
	var expected := 0
	if lead & 0x80 == 0x00:
		expected = 1
	elif lead & 0xE0 == 0xC0:
		expected = 2
	elif lead & 0xF0 == 0xE0:
		expected = 3
	elif lead & 0xF8 == 0xF0:
		expected = 4
	else:
		return buf  # not a valid lead byte, leave it to the decoder
	# If fewer bytes are present than the codepoint needs, it was cut off.
	if n - i < expected:
		return buf.slice(0, i)
	return buf

func read_file(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	var start_line: int = int(args.get(&"start_line", 1))
	var end_line: int = int(args.get(&"end_line", 0))
	var max_bytes: int = int(args.get(&"max_bytes", DEFAULT_MAX_BYTES))

	if path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'path' parameter"}

	var guarded := PathGuard.sanitize(path)
	if not guarded[&"ok"]:
		return {&"ok": false, &"error": guarded[&"error"]}
	path = guarded[&"path"]

	if not FileAccess.file_exists(path):
		return {&"ok": false, &"error": "File not found: " + path}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {&"ok": false, &"error": "Cannot open file: " + path}

	var content: String
	var line_count: int = 0

	# If no line range specified, read up to max_bytes
	if end_line <= 0 and start_line <= 1:
		var size := mini(max_bytes, file.get_length())
		var buf := file.get_buffer(size)
		# Only when we stopped before EOF can the tail be a partial codepoint.
		if size < file.get_length():
			buf = _trim_incomplete_utf8_tail(buf)
		content = buf.get_string_from_utf8()
		# Count lines
		line_count = content.count("\n") + 1
	else:
		# Read specific line range
		var lines: Array = []
		var current_line := 0
		var total_bytes := 0

		while not file.eof_reached():
			var line := file.get_line()
			current_line += 1

			if current_line < start_line:
				continue
			if end_line > 0 and current_line > end_line:
				break

			lines.append(line)
			total_bytes += line.length() + 1  # +1 for newline

			if total_bytes > max_bytes:
				break

		content = "\n".join(lines)
		line_count = lines.size()

	file.close()

	return {
		&"ok": true,
		&"path": path,
		&"content": content,
		&"line_count": line_count,
		&"range": [start_line, end_line] if end_line > 0 else null
	}

# =============================================================================
# search_project - Search for text in project files
# =============================================================================
func search_project(args: Dictionary) -> Dictionary:
	var query: String = str(args.get(&"query", ""))
	var glob_filter: String = str(args.get(&"glob", ""))
	var max_results: int = int(args.get(&"max_results", DEFAULT_MAX_RESULTS))
	var case_sensitive: bool = bool(args.get(&"case_sensitive", false))
	var include_addons: bool = bool(args.get(&"include_addons", false))

	if query.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'query' parameter"}

	var search_query := query if case_sensitive else query.to_lower()
	var files := _collect_files("res://", glob_filter)
	var matches: Array = []
	var addon_hits := 0

	for file_path: String in files:
		if matches.size() >= max_results:
			break
		# Third-party addon source answers almost every common identifier, and
		# it is never what the caller meant — the hits crowd out the project's
		# own code and cost context to read. Same default as validate_references.
		if not include_addons and file_path.begins_with("res://addons/"):
			addon_hits += 1
			continue
		# delete_file leaves a .bak beside what it removed. Searching it back up
		# hands the caller the contents of a file they just deleted, as though it
		# were still part of the project.
		if file_path.ends_with(".bak"):
			continue

		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			continue

		var content := file.get_as_text()
		file.close()

		var search_content := content if case_sensitive else content.to_lower()
		if search_content.find(search_query) == -1:
			continue

		var lines := content.split("\n")
		for i: int in range(lines.size()):
			var line := lines[i]
			var search_line := line if case_sensitive else line.to_lower()
			if search_line.find(search_query) != -1:
				var content_line := line.strip_edges()
				var cut := content_line.length() > MAX_MATCH_CHARS
				matches.append({
					&"file": file_path,
					&"line": i + 1,
					&"content": content_line.substr(0, MAX_MATCH_CHARS) if cut else content_line,
					&"content_truncated": cut,
				})
				if matches.size() >= max_results:
					break

	# When the scan stops early there is no honest total to give: it stopped
	# looking. Reporting matches.size() as "total_matches" said 50 whether the
	# project held 51 or 20,000, which is a number that reads as measured and
	# was not. The count is only reported when it IS the count.
	var truncated := matches.size() >= max_results
	var out := {
		&"ok": true,
		&"query": query,
		&"matches": matches,
		&"returned": matches.size(),
		&"truncated": truncated,
	}
	if truncated:
		out[&"note"] = "Stopped at max_results (%d), so this is not how many matches exist. Narrow the query, pass a glob, or raise max_results." % max_results
	else:
		out[&"total_matches"] = matches.size()
	if addon_hits > 0:
		out[&"skipped_addon_files"] = addon_hits
		out[&"addons_note"] = "Skipped %d file(s) under res://addons/. Pass include_addons: true to search them." % addon_hits
	return out

func _collect_files(path: String, glob_filter: String) -> PackedStringArray:
	"""Recursively collect all searchable files."""
	var result: PackedStringArray = []
	_collect_files_recursive(path, glob_filter, result)
	return result

func _collect_files_recursive(path: String, glob_filter: String, out: PackedStringArray, depth: int = 0) -> void:
	if depth >= MAX_TRAVERSAL_DEPTH:
		return

	var dir := DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		# Skip hidden
		if name.begins_with("."):
			name = dir.get_next()
			continue

		var full_path := path.path_join(name)

		if dir.current_is_dir():
			_collect_files_recursive(full_path, glob_filter, out, depth + 1)
		else:
			var ext := "." + name.get_extension().to_lower()
			if not _SKIP_EXTENSIONS.has(ext):
				if glob_filter.is_empty() or _matches_glob(full_path, glob_filter):
					out.append(full_path)

		name = dir.get_next()
	dir.list_dir_end()

func _matches_glob(path: String, pattern: String) -> bool:
	"""Simple glob matching: *.gd, **/*.tscn, etc."""
	# Handle **/*.ext pattern
	if pattern.begins_with("**/"):
		var ext := pattern.substr(3)  # Remove **/
		return path.ends_with(ext.replace("*", ""))

	# Handle *.ext pattern
	if pattern.begins_with("*."):
		return path.ends_with(pattern.substr(1))

	# Simple contains check
	return path.find(pattern) != -1

# =============================================================================
# create_script - Create a new GDScript file
# =============================================================================
func create_script(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	var content: String = str(args.get(&"content", ""))

	if path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'path' parameter"}

	var guarded := PathGuard.sanitize(path)
	if not guarded[&"ok"]:
		return {&"ok": false, &"error": guarded[&"error"]}
	path = guarded[&"path"]

	# Add .gd extension if missing
	if not "." in path.get_file():
		path += ".gd"

	# Check if file already exists
	if FileAccess.file_exists(path):
		return {&"ok": false, &"error": "File already exists: " + path}

	# Ensure parent directory exists
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var err := DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			return {&"ok": false, &"error": "Could not create directory: " + dir_path}

	# Write file — a preview stops here, having already checked the path is
	# inside the sandbox, that nothing is there to overwrite, and that the
	# parent directory exists.
	if _dry_run:
		_dry_run_skipped_write = true
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return {&"ok": false, &"error": "Could not create file: " + path}

		file.store_string(content)
		file.close()

		# Refresh filesystem so Godot sees the new file
		_refresh_filesystem()

	return {
		&"ok": true,
		&"path": path,
		&"size_bytes": content.length(),
		&"message": "Script created successfully"
	}

## Create a Godot C# script (.cs) with the correct partial-class template. Godot's
## C# workflow needs a .NET build of Godot and a C# solution (Project > Tools > C# >
## Create C# solution, a one-time step); this writes the script itself — the boilerplate
## the community keeps asking not to hand-write. Attaching/running it needs the .NET
## editor (attach_script works on the .cs once the solution exists).
func create_csharp_script(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	var cls: String = str(args.get(&"class_name", "")).strip_edges()
	var base_type: String = str(args.get(&"base_type", "Node")).strip_edges()
	var ns: String = str(args.get(&"namespace", "")).strip_edges()

	if path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'path' parameter"}
	var guarded := PathGuard.sanitize(path)
	if not guarded[&"ok"]:
		return {&"ok": false, &"error": guarded[&"error"]}
	path = guarded[&"path"]
	if not path.ends_with(".cs"):
		path += ".cs"
	if FileAccess.file_exists(path):
		return {&"ok": false, &"error": "File already exists: " + path}
	if not ClassDB.class_exists(base_type):
		return {&"ok": false, &"error": "Invalid base_type '%s' (must be a Godot class name like Node, Node2D, CharacterBody2D)" % base_type}

	if cls.is_empty():
		cls = path.get_file().get_basename()
	cls = _to_csharp_identifier(cls)
	if cls.is_empty():
		return {&"ok": false, &"error": "Could not derive a valid C# class name from the path; pass 'class_name'"}

	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		if DirAccess.make_dir_recursive_absolute(dir_path) != OK:
			return {&"ok": false, &"error": "Could not create directory: " + dir_path}

	var content := _csharp_template(cls, base_type, ns)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {&"ok": false, &"error": "Could not create file: " + path}
	file.store_string(content)
	file.close()
	_refresh_filesystem()

	var result := {&"ok": true, &"path": path, &"class_name": cls, &"base_type": base_type,
		&"size_bytes": content.length(),
		&"message": "Created C# script %s (class %s : %s)." % [path, cls, base_type]}

	# The standard (non-.NET) Godot build cannot load a C# script AT ALL — it has
	# no CSharpScript class. Writing the file still "succeeds", so without this
	# the agent gets a green result and only discovers much later that attaching
	# it silently does nothing. Say it at creation time instead.
	var caps := _csharp_capability()
	result[&"csharp_supported"] = caps[&"editor_supports_csharp"]
	if not caps[&"editor_supports_csharp"]:
		result[&"warning"] = "This Godot build has no C# support (standard build, not the .NET one), so this script cannot be attached or run here. Install the .NET build of Godot to use it. Call csharp_status for the full picture."
	elif not caps[&"project_has_solution"]:
		result[&"warning"] = "No .csproj/.sln found in the project — Godot generates one the first time you build. Until then this script will not compile."
	return result

## What this editor and project can actually do with C#.
##
## The definitive editor check is whether ClassDB knows CSharpScript: the .NET
## build registers it, the standard build does not. Checking the executable name
## or looking for a GodotSharp folder would be guessing at the install layout.
func _csharp_capability() -> Dictionary:
	var editor_ok := ClassDB.class_exists("CSharpScript")
	var has_solution := false
	var solution_name := ""
	var dir := DirAccess.open("res://")
	if dir:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".sln") or f.ends_with(".csproj"):
				has_solution = true
				solution_name = f
				break
			f = dir.get_next()
		dir.list_dir_end()
	return {
		&"editor_supports_csharp": editor_ok,
		&"project_has_solution": has_solution,
		&"solution_file": solution_name,
	}

# =============================================================================
# csharp_status
# =============================================================================
## Report whether C# is usable here BEFORE the agent invests in writing any.
## A C# script in a non-.NET project is inert: it writes fine, attaches to
## nothing, and fails quietly.
func csharp_status(_args: Dictionary) -> Dictionary:
	var caps := _csharp_capability()
	var editor_ok: bool = caps[&"editor_supports_csharp"]
	var has_solution: bool = caps[&"project_has_solution"]

	var usable := editor_ok and has_solution
	var blockers: Array = []
	if not editor_ok:
		blockers.append("This is the standard Godot build, which has no C# support at all. Download the .NET build of Godot (same version) to use C#.")
	elif not has_solution:
		blockers.append("No .csproj/.sln in the project. Godot creates one on the first C# build (Project > Tools > C#), or when you create a C# script and build.")

	return {
		&"ok": true,
		&"csharp_usable": usable,
		&"editor_supports_csharp": editor_ok,
		&"project_has_solution": has_solution,
		&"solution_file": caps[&"solution_file"],
		&"godot_version": "%d.%d" % [Engine.get_version_info().major, Engine.get_version_info().minor],
		&"blockers": blockers,
		&"message": ("C# is usable in this project." if usable
			else "C# is NOT usable here — see 'blockers'. Write GDScript instead, or switch to a .NET Godot build."),
		&"note": "GDScript is fully supported either way; this only affects C#.",
	}

## Godot 4 C# node template (PascalCase overrides, partial class).
func _csharp_template(cls: String, base_type: String, ns: String) -> String:
	var lines := PackedStringArray()
	lines.append("using Godot;")
	lines.append("")
	if not ns.is_empty():
		lines.append("namespace %s;" % ns)
		lines.append("")
	lines.append("public partial class %s : %s" % [cls, base_type])
	lines.append("{")
	lines.append("\tpublic override void _Ready()")
	lines.append("\t{")
	lines.append("\t}")
	lines.append("")
	lines.append("\tpublic override void _Process(double delta)")
	lines.append("\t{")
	lines.append("\t}")
	lines.append("}")
	return "\n".join(lines) + "\n"

## Reduce a name to a valid C# identifier (letters/digits/underscore, not
## digit-initial). Keeps it simple — enough to turn "player-2d" into "player2d".
func _to_csharp_identifier(s: String) -> String:
	var out := ""
	for i in range(s.length()):
		var c := s[i]
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_" or (c >= "0" and c <= "9" and not out.is_empty()):
			out += c
	return out

func _refresh_filesystem() -> void:
	"""Tell Godot to rescan the filesystem."""
	if _editor_plugin != null:
		_editor_plugin.get_editor_interface().get_resource_filesystem().scan()
	elif Engine.is_editor_hint():
		# Fallback if no plugin reference
		var editor_interface = Engine.get_singleton("EditorInterface")
		if editor_interface:
			editor_interface.get_resource_filesystem().scan()
