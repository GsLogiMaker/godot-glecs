@tool
extends RefCounted
class_name PathGuard
## Confines every filesystem-touching MCP tool to res:// (project root) and
## user:// (Godot's per-project data dir). Every tool that accepts a path
## argument MUST route it through sanitize() before touching FileAccess/
## DirAccess — see MERGE_NOTES.md for why this exists (path traversal via
## "../" was previously unmitigated: a plain res://<path> prefix check does
## NOT stop "res://../../../../Windows/System32/...", since Godot resolves
## res:// relative to the project dir and ".." walks back out of it).

## What a tool holds instead of a path once sanitize() refused it. Two markers,
## not one: an empty argument is a missing argument, and answering it with
## "Path escapes the project sandbox" sent callers hunting for a traversal bug
## in a call whose real problem was that they never passed the path at all.
const REJECTED := "res://__mcp_rejected_path__"
const MISSING := "res://__mcp_missing_path__"

static func is_bad(path: String) -> bool:
	return path == REJECTED or path == MISSING

static func error_for(path: String, label: String = "path") -> Dictionary:
	if path == MISSING:
		return {&"ok": false, &"error": "Missing '%s': the argument was empty or not provided." % label}
	return {&"ok": false, &"error": "Path escapes the project sandbox (rejected)"}

## Returns {ok: true, path: String} on success, {ok: false, error: String} on
## a rejected path. `path` in the result is the normalized, safe res:///user://
## path — callers should use THAT value, not the original argument.
static func sanitize(raw_path: String) -> Dictionary:
	var path := raw_path.strip_edges()
	if path.is_empty():
		return {&"ok": false, &"error": "Empty path"}

	if not (path.begins_with("res://") or path.begins_with("user://")):
		path = "res://" + path

	var scheme := "res://" if path.begins_with("res://") else "user://"
	var normalized := path.simplify_path()

	if not normalized.begins_with(scheme):
		return {&"ok": false, &"error": "Path escapes the project sandbox: '%s' (resolved outside %s)" % [raw_path, scheme]}

	# simplify_path() collapses "a/../b" -> "b" but a leading run of ".." with
	# nothing before it to cancel against (e.g. "res://../etc") still slips
	# through as a normalized path that no longer starts with the scheme once
	# stripped — double-check the remainder has no residual "..".
	var remainder := normalized.substr(scheme.length())
	if remainder.begins_with("..") or "/../" in ("/" + remainder + "/"):
		return {&"ok": false, &"error": "Path escapes the project sandbox: '%s'" % raw_path}

	return {&"ok": true, &"path": normalized}
