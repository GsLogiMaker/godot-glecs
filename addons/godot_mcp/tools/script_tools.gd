@tool
extends Node
class_name ScriptTools
## Script and file management tools for MCP.
## Handles: edit_script, validate_script, list_scripts,
##          create_folder, delete_file, rename_file,
##          generate_property_forwarder

## Set by the ToolExecutor for one call when the caller passed dry_run, and
## read at every point below that would write. The scene tools inherit this
## from SceneToolBase; these write FILES, which is the more irreversible half
## of the surface and had no preview at all.
var _dry_run := false
var _dry_run_skipped_write := false

const PathGuard = preload("res://addons/godot_mcp/utils/path_guard.gd")

var _editor_plugin: EditorPlugin = null

func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin

func _refresh_filesystem() -> void:
	if _editor_plugin:
		_editor_plugin.get_editor_interface().get_resource_filesystem().scan()

## res:// paths of the scripts currently open in the editor's ScriptEditor.
## Used to warn when a disk write (edit_script/rename_file) lands under an open
## buffer: the editor keeps its unsaved in-memory copy, so our write is silently
## clobbered on the next editor save. We can't safely mutate the editor buffer
## from GDScript without touching fragile version-dependent internals, so we
## surface the conflict to the caller instead of pretending it didn't happen.
func _open_script_paths() -> PackedStringArray:
	var out := PackedStringArray()
	if not _editor_plugin:
		return out
	var se = _editor_plugin.get_editor_interface().get_script_editor()
	if not se:
		return out
	for s in se.get_open_scripts():
		if s and not s.resource_path.is_empty():
			out.append(s.resource_path)
	return out

## Returns the sanitized path on success, or "" and appends {ok:false, error}
## to `err_out` (a single-element Array used as an out-param) on rejection.
## Callers: `var e := []; path = _guard_path(path, e); if e: return e[0]`
func _guard_path(path: String, err_out: Array) -> String:
	var guarded := PathGuard.sanitize(path)
	if not guarded[&"ok"]:
		err_out.append({&"ok": false, &"error": guarded[&"error"]})
		return ""
	return guarded[&"path"]

# =============================================================================
# edit_script - Apply a small surgical code edit to a GDScript file
# =============================================================================
func edit_script(args: Dictionary) -> Dictionary:
	var edit: Dictionary = args.get(&"edit", {})
	if edit.is_empty():
		return {&"ok": false, &"error": "Missing 'edit' payload"}

	var path: String = str(edit.get(&"file", ""))
	if path.is_empty():
		return {&"ok": false, &"error": "Missing 'file' in edit"}

	var _err0 := []
	path = _guard_path(path, _err0)
	if _err0: return _err0[0]

	if not FileAccess.file_exists(path):
		return {&"ok": false, &"error": "File not found: " + path}

	var spec_type: String = str(edit.get(&"type", "snippet_replace"))
	if spec_type != "snippet_replace":
		return {&"ok": false, &"error": "Only 'snippet_replace' type is supported"}

	var old_snippet: String = str(edit.get(&"old_snippet", ""))
	var new_snippet: String = str(edit.get(&"new_snippet", ""))
	var context_before: String = str(edit.get(&"context_before", ""))
	var context_after: String = str(edit.get(&"context_after", ""))

	if old_snippet.is_empty():
		return {&"ok": false, &"error": "Missing 'old_snippet' in edit"}

	# Read current file content
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {&"ok": false, &"error": "Cannot read file: " + path}
	var content := file.get_as_text()
	file.close()

	# Find and replace the snippet
	var search_text := old_snippet
	var pos := content.find(search_text)
	var matched_len := old_snippet.length()
	var effective_new_snippet := new_snippet
	var via_fallback := false

	# If not found directly, try with context
	if pos == -1 and not context_before.is_empty():
		var ctx_pos := content.find(context_before)
		if ctx_pos != -1:
			var after_ctx := ctx_pos + context_before.length()
			var remaining := content.substr(after_ctx)
			var snippet_pos := remaining.find(old_snippet)
			if snippet_pos != -1:
				pos = after_ctx + snippet_pos

	# Fallback: exact matching failed, which in practice is almost always a
	# tabs-vs-spaces mismatch (GDScript is indentation-sensitive). Retry by
	# matching line-by-line with leading/trailing whitespace ignored, then
	# re-indent new_snippet so the result still has real tabs even if the
	# caller sent old_snippet/new_snippet with spaces.
	if pos == -1:
		var fallback := _find_snippet_tolerant(content, old_snippet, new_snippet, context_before)
		if fallback[&"found"]:
			pos = fallback[&"pos"]
			matched_len = fallback[&"matched_len"]
			effective_new_snippet = fallback[&"new_snippet"]
			via_fallback = true

	if pos == -1:
		return {&"ok": false, &"error": "Could not find old_snippet in file. This usually means old_snippet doesn't match the file's indentation exactly (e.g. spaces were sent instead of real tabs). Try re-copying old_snippet directly from the file, or use less surrounding context so a single mismatched line doesn't break the whole match."}

	# Check for multiple occurrences (only meaningful for the exact-match case;
	# the tolerant fallback already picked a single line-range match).
	if not via_fallback:
		var second_pos := content.find(search_text, pos + 1)
		if second_pos != -1 and context_before.is_empty() and context_after.is_empty():
			return {&"ok": false, &"error": "old_snippet appears multiple times. Add context_before or context_after for disambiguation."}

	# Apply the replacement
	var original_content := content
	var new_content := content.substr(0, pos) + effective_new_snippet + content.substr(pos + matched_len)

	# Write back — unless this is a preview, in which case everything above
	# (finding the snippet, disambiguating it, building the new content) has
	# already answered the question the caller actually has: would it match,
	# and what would it produce.
	if _dry_run:
		_dry_run_skipped_write = true
	else:
		file = FileAccess.open(path, FileAccess.WRITE)
		if not file:
			return {&"ok": false, &"error": "Cannot write file: " + path}
		file.store_string(new_content)
		file.close()

	# Count changes
	var old_lines := old_snippet.split("\n")
	var new_lines := effective_new_snippet.split("\n")
	var added := maxi(0, new_lines.size() - old_lines.size())
	var removed := maxi(0, old_lines.size() - new_lines.size())

	if not _dry_run:
		_refresh_filesystem()

	var result := {
		&"ok": true,
		&"path": path,
		&"added": added,
		&"removed": removed,
		&"auto_applied": not _dry_run,
		&"message": ("Would apply edit to %s (+%d -%d lines); nothing written." if _dry_run
			else "Applied edit to %s (+%d -%d lines)") % [path, added, removed]
	}

	# If the script is open in the editor, its unsaved buffer will overwrite this
	# disk edit on the next editor save. Flag it so the caller can reload/redo.
	if path in _open_script_paths():
		result[&"warning"] = "%s is open in the editor. Unsaved changes in that buffer will overwrite this edit on the next save. Reload the script in the editor to pick up this change." % path

	return result

## Tolerant fallback for edit_script: locates old_snippet by comparing lines
## with leading/trailing whitespace stripped, so tabs-vs-spaces differences
## don't cause a false "not found". Returns the matched byte range in
## `content` plus new_snippet re-indented to the file's actual indentation.
func _find_snippet_tolerant(content: String, old_snippet: String, new_snippet: String, context_before: String) -> Dictionary:
	var search_from := 0
	if not context_before.is_empty():
		var ctx_pos := content.find(context_before)
		if ctx_pos == -1:
			return {&"found": false}
		search_from = ctx_pos + context_before.length()

	var old_lines := old_snippet.split("\n")
	if old_lines.is_empty():
		return {&"found": false}

	var region := content.substr(search_from)
	var region_lines := region.split("\n")

	var start_line := -1
	for i in range(region_lines.size() - old_lines.size() + 1):
		var is_match := true
		for j in range(old_lines.size()):
			if region_lines[i + j].strip_edges() != old_lines[j].strip_edges():
				is_match = false
				break
		if is_match:
			start_line = i
			break

	if start_line == -1:
		return {&"found": false}

	# Byte offset of start_line within `region`.
	var offset := 0
	for i in range(start_line):
		offset += region_lines[i].length() + 1 # +1 for the '\n' consumed by split

	var matched_len := 0
	for j in range(old_lines.size()):
		matched_len += region_lines[start_line + j].length()
		if j < old_lines.size() - 1:
			matched_len += 1 # '\n' between matched lines

	# Re-indent new_snippet from the level implied by old_snippet's first
	# line to the level actually found in the file, using real tabs.
	var file_indent := _indent_level(_leading_ws(region_lines[start_line]))
	var snippet_indent := _indent_level(_leading_ws(old_lines[0]))
	var reindented := _reindent_snippet(new_snippet, file_indent - snippet_indent)

	return {
		&"found": true,
		&"pos": search_from + offset,
		&"matched_len": matched_len,
		&"new_snippet": reindented,
	}

func _leading_ws(line: String) -> String:
	var i := 0
	while i < line.length() and (line[i] == "\t" or line[i] == " "):
		i += 1
	return line.substr(0, i)

## Converts leading whitespace to an indentation "level": each tab counts as
## one level, and every 4 spaces counts as one level.
func _indent_level(ws: String) -> int:
	var tabs := 0
	var spaces := 0
	for c in ws:
		if c == "\t":
			tabs += 1
		elif c == " ":
			spaces += 1
	return tabs + int(spaces / 4.0)

## Rewrites each non-blank line's leading whitespace to real tabs, shifting
## the indentation level by `level_offset` (may be negative). Always
## normalizes to tabs, even when level_offset is 0, so a new_snippet written
## with spaces still ends up matching the file's real indentation.
func _reindent_snippet(snippet: String, level_offset: int) -> String:
	var lines := snippet.split("\n")
	for i in range(lines.size()):
		var line: String = lines[i]
		var ws := _leading_ws(line)
		var rest := line.substr(ws.length())
		if rest.is_empty():
			continue # keep blank lines blank
		var level := maxi(0, _indent_level(ws) + level_offset)
		lines[i] = "\t".repeat(level) + rest
	return "\n".join(lines)

# =============================================================================
# validate_script
# =============================================================================
func validate_script(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	if path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'path'"}

	var _err1 := []
	path = _guard_path(path, _err1)
	if _err1: return _err1[0]

	if not FileAccess.file_exists(path):
		return {&"ok": false, &"error": "File not found: " + path}

	return _validate_one(path)

## Monotonic suffix for the throwaway validation scripts' resource paths, so
## two validations never claim the same cache slot.
var _validate_seq: int = 0

## Validate a single .gd by loading it the way the ENGINE does.
##
## This used to build a GDScript in memory and call reload() on the source. That
## compiles the file in ISOLATION, and isolation is exactly what a real project
## script does not have: it reported
##   - `Identifier not found: <Autoload>` (err 36) for any file touching a
##     singleton, because autoloads are not visible to a standalone compile even
##     inside the editor — the old comment here claimed they were, and that
##     claim was simply wrong;
##   - `Could not find base class <X>` (err 43) for any file extending a global
##     class declared in another file.
## Measured against a real project: 4 of 4 scripts reported invalid, all 4
## compiled and ran fine. A validator with false positives on ordinary code is
## worse than no validator, because it trains you to ignore it.
##
## ResourceLoader.load() runs the same path the editor uses when it opens the
## file, so autoloads, global classes and inherited scripts all resolve. Errors
## still surface — a file that does not parse loads as null.
func _validate_one(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {&"ok": false, &"valid": false, &"path": path, &"error": "File not found: " + path}

	# REPLACE, not REUSE and emphatically not IGNORE:
	#   REUSE   — hands back the cached copy without re-reading disk, so a script
	#             edited a moment ago validates as its previous version. Useless
	#             for the main use of this tool.
	#   IGNORE  — reads disk but builds a SEPARATE copy each time. Sweeping a set
	#             of scripts that extend each other then produces two live copies
	#             of the same global class, and the engine hard-crashes (exit 5,
	#             reproduced on a 3-file sweep of this very addon).
	#   REPLACE — reads disk and updates the one cached entry. Fresh, and no
	#             duplicate class. This is what the editor itself does when it
	#             notices a file changed underneath it.
	var script := ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_REPLACE) as GDScript
	if script == null:
		return _invalid(path, "Could not load as a GDScript")

	# load() alone is NOT a verdict: a file that fails to parse still comes back
	# as a GDScript object, just an unusable one. The verdict is whether the
	# parser resolved a base type.
	#
	# It has to be get_instance_base_type() and NOT can_instantiate(), and the
	# difference is the whole point of this rewrite. Measured across 13 shapes:
	#
	#   file                            base   can_instantiate
	#   valid                           Node   true
	#   valid, calls an autoload        Node   FALSE   <- can_instantiate lies
	#   valid, extends a global class   Node   true
	#   valid, extends Resource         Resource  true
	#   missing colon                   ''     false
	#   calls an undefined function     ''     false
	#   extends a class that not exist  ''     false
	#   assigns a String to an int      ''     false
	#
	# can_instantiate() is false for a perfectly good script that references a
	# singleton — singletons only exist at runtime — so using it is what made
	# this tool report 4 of 4 healthy scripts as broken. The base type comes from
	# the parse, which is the thing actually being asked about.
	#
	# Do NOT "improve" this by calling reload(): reload() compiles in isolation
	# and brings every autoload false positive straight back. Verified twice.
	if script.get_instance_base_type() == &"":
		return _invalid(path, "Could not be parsed — no base type resolved. If it extends a class_name declared in a file added during this session, call rescan_filesystem first: an unregistered global class looks exactly like a missing one")

	return {
		&"ok": true,
		&"valid": true,
		&"path": path,
		&"message": "No syntax errors found"
	}

func _invalid(path: String, reason: String = "", err: int = OK) -> Dictionary:
	var errors := _collect_recent_script_errors(path)
	var detail := ""
	if errors.size() > 0:
		detail = " Details: " + "; ".join(errors)
	elif not reason.is_empty():
		detail = " " + reason + "."
	else:
		detail = " Check the Godot console for details."
	var out := {
		&"ok": true,
		&"valid": false,
		&"path": path,
		&"errors": errors,
		&"message": "Script has errors." + detail,
	}
	if err != OK:
		out[&"error_code"] = err
	return out

## Delete a throwaway validation script if the engine actually wrote one out.
## Godot also drops a sidecar `.uid` next to any script it resolves, so both go.
func _discard_validation_artifact(res_path: String) -> void:
	for p in [res_path, res_path + ".uid"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

## Remove any `__mcp_snippet_*.gd` left behind by an earlier validation.
##
## The discard above runs immediately after `reload()`, and a run_tests case
## asserts nothing survives — yet one was found sitting in a real project's
## addons folder, committed-adjacent and confusing. The engine can flush a
## GDScript that carries a res:// resource_path back to disk later (a Save All
## while it is still in the resource cache will do it), which is after the
## discard has already run. Sweeping before each validation bounds the litter
## to one file that only exists between two calls, rather than trusting a
## single delete to be the last word.
func _sweep_validation_artifacts() -> void:
	var dir := DirAccess.open("res://addons/godot_mcp")
	if dir == null:
		return
	for file in dir.get_files():
		if file.begins_with("__mcp_snippet_") and (file.ends_with(".gd") or file.ends_with(".gd.uid")):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("res://addons/godot_mcp/" + file))

## Compile a game_eval snippet HERE, in the editor, before it is sent to the game.
##
## Not called by agents — the MCP server calls it on their behalf (see the
## snippet pre-check in godot-bridge.ts). It exists because of where a parse
## error lands: a snippet that does not compile is reported through the engine's
## global error handler, and in a game launched from the editor that handler
## makes the DEBUGGER BREAK. The game pauses mid-call, the helper stops
## answering, and the agent's typo comes back as "Runtime helper is not
## connected" ~25s later. Nothing is debugging the editor, so the same compile
## here is harmless and the typo stays a typo.
##
## The wrapper must match `_compile_eval` in runtime/mcp_runtime.gd — same
## `extends`, same signature, same indent — or this checks something the game
## never runs.
func validate_eval_snippet(args: Dictionary) -> Dictionary:
	var code := str(args.get(&"code", ""))
	if code.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'code'"}

	var src := "extends RefCounted\nfunc _mcp_eval(tree, node):\n"
	for line in code.split("\n"):
		src += "\t" + line + "\n"

	_sweep_validation_artifacts()

	var script := GDScript.new()
	# Under res://addons/ on purpose: `exclude_addons` (on by default) mutes the
	# warnings there, so a project that promotes warnings to errors cannot make
	# this pre-check reject a snippet that would have run. It must only ever fail
	# on a real parse error — a false block is worse than the break it prevents.
	_validate_seq += 1
	script.resource_path = "res://addons/godot_mcp/__mcp_snippet_%d.gd" % _validate_seq
	script.source_code = src
	var err := script.reload()
	_discard_validation_artifact(script.resource_path)
	if err != OK:
		return {
			&"ok": true,
			&"valid": false,
			&"error_code": err,
			&"errors": _collect_recent_script_errors(script.resource_path),
		}
	return {&"ok": true, &"valid": true}

## Removes the top-level `class_name X` declaration so a standalone
## GDScript.reload() doesn't collide with the already-registered global class.
## Replaces it with a blank line so reported error line numbers stay accurate.
func _strip_class_name(source: String) -> String:
	var lines := source.split("\n")
	var out := PackedStringArray()
	for line in lines:
		var s := line.strip_edges(true, false)  # class_name sits at indent 0
		if s.begins_with("class_name") and s.length() > 10 and (s[10] == " " or s[10] == "\t"):
			out.append("")
		else:
			out.append(line)
	return "\n".join(out)

## Validate many scripts in one call. Pass `paths` (array of res:// .gd paths) to
## check a specific set, or omit it to sweep every .gd in the project. Returns
## only the per-file results plus a summary — useful after a refactor to catch
## every broken script at once instead of N separate calls.
func validate_scripts(args: Dictionary) -> Dictionary:
	var paths_arg = args.get(&"paths", [])
	var include_addons: bool = bool(args.get(&"include_addons", false))
	var targets: Array = []

	if paths_arg is Array and not paths_arg.is_empty():
		for p in paths_arg:
			var _e := []
			var gp := _guard_path(str(p), _e)
			if _e:
				return _e[0]
			if FileAccess.file_exists(gp):
				targets.append(gp)
			else:
				return {&"ok": false, &"error": "File not found: " + gp}
	else:
		_collect_gd_files("res://", targets)
		# addons/ is skipped by default. Validating a whole project costs ~34ms
		# per script on the editor's main thread, and plugin code is usually the
		# bulk of it — on a big project the sweep can outlast the bridge's own
		# 20s ping watchdog and kill the connection it is reporting through, the
		# same way find_unused_resources used to. You did not write the addons;
		# pass include_addons when you actually want them checked.
		if not include_addons:
			var own: Array = []
			for t: String in targets:
				if not t.begins_with("res://addons/"):
					own.append(t)
			targets = own

	if targets.is_empty():
		return {&"ok": true, &"total": 0, &"invalid_count": 0, &"invalid": [], &"message": "No .gd scripts to validate."}

	var started := Time.get_ticks_msec()
	var invalid: Array = []
	for t: String in targets:
		var r := _validate_one(t)
		if not r.get(&"valid", false):
			# The MESSAGE, not just error_code: a bare code with an empty errors
			# array is what made this tool's output useless to act on. The
			# message always says something, even when the engine logged nothing.
			invalid.append({
				&"path": t,
				&"errors": r.get(&"errors", []),
				&"message": r.get(&"message", "Script has errors."),
			})

	var elapsed := Time.get_ticks_msec() - started
	var out := {
		&"ok": true,
		&"total": targets.size(),
		&"invalid_count": invalid.size(),
		&"invalid": invalid,
		&"elapsed_ms": elapsed,
		&"message": "Validated %d script(s): %d invalid." % [targets.size(), invalid.size()],
	}
	# Loud about its own cost, so a sweep that is creeping toward the watchdog is
	# visible before it takes the connection down.
	if elapsed > 8000:
		out[&"warning"] = "This sweep took %.1fs on the editor's main thread. Pass an explicit 'paths' list to keep it fast; past ~20s the bridge's ping watchdog drops the connection mid-call." % (elapsed / 1000.0)
	return out

func _collect_gd_files(dir_path: String, out: Array, depth: int = 0) -> void:
	if depth > 20:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			_collect_gd_files(full, out, depth + 1)
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()

func _collect_recent_script_errors(script_path: String) -> Array:
	"""Grab recent SCRIPT ERROR / Parse Error lines from the editor Output panel
	that mention the given script path.  Best-effort — returns [] if the panel
	cannot be accessed."""
	var errors: Array = []
	if not _editor_plugin:
		return errors

	# Find the editor's Output panel RichTextLabel
	var base := _editor_plugin.get_editor_interface().get_base_control()
	var editor_log := _find_node_by_class(base, "EditorLog")
	if not editor_log:
		return errors
	var rtl := _find_child_rtl(editor_log)
	if not rtl:
		return errors

	var text: String = rtl.get_parsed_text()
	var short_path := script_path.get_file()  # e.g. "player.gd"

	for line: String in text.split("\n"):
		line = line.strip_edges()
		if line.is_empty():
			continue
		if short_path in line or script_path in line:
			if line.begins_with("SCRIPT ERROR:") or line.begins_with("Parse Error:") \
				or line.begins_with("ERROR:") or line.begins_with("at:"):
				errors.append(line)

	# Keep only the last 10 relevant lines
	if errors.size() > 10:
		errors = errors.slice(errors.size() - 10)
	return errors

func _find_node_by_class(root: Node, cls_name: String) -> Node:
	if root.get_class() == cls_name:
		return root
	for child: Node in root.get_children():
		var found := _find_node_by_class(child, cls_name)
		if found:
			return found
	return null

func _find_child_rtl(node: Node) -> RichTextLabel:
	for child: Node in node.get_children():
		if child is RichTextLabel:
			return child
		var found := _find_child_rtl(child)
		if found:
			return found
	return null

# =============================================================================
# list_scripts
# =============================================================================
func list_scripts(args: Dictionary) -> Dictionary:
	var scripts: Array = []
	_collect_scripts("res://", scripts)

	return {
		&"ok": true,
		&"scripts": scripts,
		&"count": scripts.size()
	}

func _collect_scripts(path: String, out: Array) -> void:
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
			_collect_scripts(full_path, out)
		elif name.ends_with(".gd"):
			out.append(full_path)

		name = dir.get_next()
	dir.list_dir_end()

# =============================================================================
# create_folder
# =============================================================================
func create_folder(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	if path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'path'"}

	var _err2 := []
	path = _guard_path(path, _err2)
	if _err2: return _err2[0]

	if DirAccess.dir_exists_absolute(path):
		return {&"ok": true, &"path": path, &"message": "Directory already exists"}

	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		return {&"ok": false, &"error": "Failed to create directory: " + str(err)}

	_refresh_filesystem()

	return {&"ok": true, &"path": path, &"message": "Directory created"}

# =============================================================================
# delete_file
# =============================================================================
func delete_file(args: Dictionary) -> Dictionary:
	var path: String = str(args.get(&"path", ""))
	var confirm: bool = bool(args.get(&"confirm", false))
	var create_backup: bool = bool(args.get(&"create_backup", true))
	var force: bool = bool(args.get(&"force", false))

	if path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'path'"}
	if not confirm:
		return {&"ok": false, &"error": "Must set confirm=true to delete"}

	var _err3 := []
	path = _guard_path(path, _err3)
	if _err3: return _err3[0]

	if not FileAccess.file_exists(path):
		return {&"ok": false, &"error": "File not found: " + path}

	# Refuse to delete files the editor currently has open. Deleting the
	# live scene/script out from under the editor (especially the active tab)
	# can crash Godot because internal pointers still reference the
	# in-memory copy. The agent must close the tab first, then retry.
	var open_info := _file_is_open_in_editor(path)
	if open_info[&"open"] and not force:
		return {
			&"ok": false,
			&"error": "Refusing to delete %s: it is currently open in the editor (%s). Close the tab first, or pass force=true to delete anyway (WILL LIKELY CRASH if it's the active scene)." % [path, open_info[&"where"]],
			&"open_in_editor": true,
			&"where": open_info[&"where"],
			&"is_active": open_info[&"is_active"],
		}

	if create_backup:
		var backup_path := path + ".bak"
		# Abort rather than delete-without-backup: a caller who asked for a backup
		# is relying on it, so a silent copy failure must not proceed to remove.
		var backup_err := DirAccess.copy_absolute(path, backup_path)
		if backup_err != OK:
			return {&"ok": false, &"error": "Backup failed (%s); file NOT deleted: %s" % [str(backup_err), path]}

	if _dry_run:
		_dry_run_skipped_write = true
		return {&"ok": true, &"path": path, &"existed": true,
			&"message": "Would delete %s." % path}

	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return {&"ok": false, &"error": "Failed to delete file: " + str(err)}

	_refresh_filesystem()

	return {&"ok": true, &"path": path, &"message": "File deleted" + (" (backup created)" if create_backup else "")}

## Detect whether `path` is currently open in the editor (either as an edited
## scene tab or as a script in the script editor). Returns a dict with:
##   open:      bool — open anywhere in the editor
##   where:     String — short human description (which tab/panel)
##   is_active: bool — true if it's the CURRENTLY FOCUSED scene tab (deleting
##              this case is the most crash-prone)
func _file_is_open_in_editor(path: String) -> Dictionary:
	var out := {&"open": false, &"where": "", &"is_active": false}
	if _editor_plugin == null:
		return out
	var ei := _editor_plugin.get_editor_interface()

	# Scene tabs
	if ei.has_method("get_open_scenes"):
		var open_scenes: PackedStringArray = ei.get_open_scenes()
		if open_scenes.has(path):
			out[&"open"] = true
			out[&"where"] = "scene tab"
			var edited = ei.get_edited_scene_root()
			if edited and edited.scene_file_path == path:
				out[&"is_active"] = true
				out[&"where"] = "active scene tab"
			return out

	# Script editor
	var se := ei.get_script_editor()
	if se:
		for s in se.get_open_scripts():
			if s is Script and s.resource_path == path:
				out[&"open"] = true
				out[&"where"] = "script editor"
				var cur := se.get_current_script()
				if cur and cur.resource_path == path:
					out[&"is_active"] = true
					out[&"where"] = "active script editor tab"
				return out

	return out

# =============================================================================
# rename_file
# =============================================================================
func rename_file(args: Dictionary) -> Dictionary:
	var old_path: String = str(args.get(&"old_path", ""))
	var new_path: String = str(args.get(&"new_path", ""))
	var update_references: bool = bool(args.get(&"update_references", true))

	if old_path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'old_path'"}
	if new_path.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'new_path'"}

	var _err4 := []
	old_path = _guard_path(old_path, _err4)
	if _err4: return _err4[0]
	new_path = _guard_path(new_path, _err4)
	if _err4: return _err4[0]

	if not FileAccess.file_exists(old_path):
		return {&"ok": false, &"error": "File not found: " + old_path}
	if FileAccess.file_exists(new_path):
		return {&"ok": false, &"error": "Target already exists: " + new_path}

	# Ensure target directory exists
	var dir_path := new_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	if _dry_run:
		# Checked above that the source exists and the target does not, which is
		# what a preview of a rename is for.
		_dry_run_skipped_write = true
		return {&"ok": true, &"old_path": old_path, &"new_path": new_path,
			&"message": "Would rename %s to %s." % [old_path, new_path]}

	var err := DirAccess.rename_absolute(old_path, new_path)
	if err != OK:
		return {&"ok": false, &"error": "Failed to rename: " + str(err)}

	var updated_files: Array = []
	if update_references:
		updated_files = _update_path_references(old_path, new_path)

	_refresh_filesystem()

	var result := {&"ok": true, &"old_path": old_path, &"new_path": new_path,
		&"updated_references": updated_files, &"updated_reference_count": updated_files.size(),
		&"message": "Renamed %s to %s (%d reference(s) updated)" % [old_path, new_path, updated_files.size()]}

	# The rename moved the file on disk and rewrote reference files directly. Any
	# of those open in the editor now hold a stale buffer that will clobber the
	# rewrite on save. Flag exactly which open files are affected.
	var open_scripts := _open_script_paths()
	var conflicted: Array = []
	if old_path in open_scripts:
		conflicted.append(old_path)
	for f in updated_files:
		if f in open_scripts:
			conflicted.append(f)
	if conflicted:
		result[&"warning"] = "Open in the editor with a now-stale buffer (reload to avoid overwriting the rename on save): %s" % ", ".join(conflicted)

	return result

## Replace references to the old res:// path with the new one across
## .gd/.tscn/.tres files — covers preload()/load() calls and ext_resource
## paths in scene/resource files. Only replaces occurrences delimited by
## quotes or parens (the forms paths actually appear in), NOT the bare
## substring: a plain replace would corrupt paths where old_path is a prefix
## of another (renaming res://player.gd must not touch res://player.gd.uid or
## res://player_data.gd).
func _update_path_references(old_path: String, new_path: String) -> Array:
	var updated: Array = []
	var files: PackedStringArray = []
	_collect_gd_tscn_tres_files("res://", files)

	for file_path: String in files:
		var f := FileAccess.open(file_path, FileAccess.READ)
		if not f:
			continue
		var content := f.get_as_text()
		f.close()

		if content.find(old_path) == -1:
			continue

		var new_content := content
		new_content = new_content.replace('"' + old_path + '"', '"' + new_path + '"')
		new_content = new_content.replace("'" + old_path + "'", "'" + new_path + "'")
		new_content = new_content.replace("(" + old_path + ")", "(" + new_path + ")")
		if new_content == content:
			continue

		var wf := FileAccess.open(file_path, FileAccess.WRITE)
		if not wf:
			continue
		wf.store_string(new_content)
		wf.close()
		updated.append(file_path)

	return updated

func _collect_gd_tscn_tres_files(path: String, out: PackedStringArray, depth: int = 0) -> void:
	if depth >= 24:
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
			_collect_gd_tscn_tres_files(full_path, out, depth + 1)
		else:
			var ext := "." + name.get_extension().to_lower()
			if ext == ".gd" or ext == ".tscn" or ext == ".tres":
				out.append(full_path)
		name = dir.get_next()

# =============================================================================
# generate_property_forwarder - append a Godot 4 get/set property that
# forwards to a nested target, avoiding hand-written getter/setter boilerplate
# (community request: godot-proposals#6750)
# =============================================================================
func generate_property_forwarder(args: Dictionary) -> Dictionary:
	var script_path_raw: String = str(args.get(&"script_path", ""))
	var property_name: String = str(args.get(&"property_name", "")).strip_edges()
	var target_expression: String = str(args.get(&"target_expression", "")).strip_edges()
	var target_property: String = str(args.get(&"target_property", "")).strip_edges()
	var type_hint: String = str(args.get(&"type_hint", "")).strip_edges()

	if script_path_raw.strip_edges().is_empty():
		return {&"ok": false, &"error": "Missing 'script_path'"}

	var _err5 := []
	var script_path: String = _guard_path(script_path_raw, _err5)
	if _err5: return _err5[0]
	if property_name.is_empty():
		return {&"ok": false, &"error": "Missing 'property_name'"}
	if target_expression.is_empty():
		return {&"ok": false, &"error": "Missing 'target_expression' (e.g. '$Target' or 'target_node')"}
	if target_property.is_empty():
		return {&"ok": false, &"error": "Missing 'target_property'"}
	if not FileAccess.file_exists(script_path):
		return {&"ok": false, &"error": "File not found: " + script_path}

	var file := FileAccess.open(script_path, FileAccess.READ)
	if not file:
		return {&"ok": false, &"error": "Cannot read file: " + script_path}
	var content := file.get_as_text()
	file.close()

	var name_check := RegEx.new()
	name_check.compile("\\bvar\\s+" + property_name + "\\b")
	if name_check.search(content):
		return {&"ok": false, &"error": "Property '%s' already declared in %s" % [property_name, script_path]}

	var type_suffix: String = ": " + type_hint if not type_hint.is_empty() else ""
	var block := "\nvar %s%s:\n\tget:\n\t\treturn %s.%s\n\tset(value):\n\t\t%s.%s = value\n" % [
		property_name, type_suffix, target_expression, target_property, target_expression, target_property
	]

	var new_content := content.rstrip("\n") + "\n" + block

	file = FileAccess.open(script_path, FileAccess.WRITE)
	if not file:
		return {&"ok": false, &"error": "Cannot write file: " + script_path}
	file.store_string(new_content)
	file.close()

	_refresh_filesystem()

	return {&"ok": true, &"script_path": script_path, &"property_name": property_name,
		&"generated": block.strip_edges(),
		&"message": "Appended forwarding property '%s' -> %s.%s" % [property_name, target_expression, target_property]}
