extends RefCounted
class_name McpActivityLog
## Ring buffer of editor activity, tagged human vs agent.
##
## Split out of plugin.gd so the buffering/tagging/digest rules can be tested
## headless: an EditorPlugin cannot be instantiated outside the editor, and the
## alternative (a human clicking around in a live editor) is not automatable.

const CAP := 200
## Editor signals fire DEFERRED — a frame or two after the tool call that caused
## them returns. So instead of an "is a tool running" flag, a window runs through
## the call and a little past it; activity inside it is the agent's own.
const AGENT_GRACE_MS := 350
## Longest a single tool call is assumed to run. The window is bounded by this
## even while a call is still in flight, because a handler that dies mid-coroutine
## never reaches end_agent_call() — and an unbounded window would then tag every
## later human action as the agent's own, silencing the feed until the editor is
## restarted. Overshooting on a genuinely long call only mis-tags that call's own
## late events; the failure it prevents costs the whole session.
const AGENT_MAX_CALL_MS := 120000
## How many events ride along on a tool response. The full history is available
## through get_editor_activity; this is only a nudge, so it stays cheap.
const DIGEST_MAX := 5

## Longest a single event's detail may be. Godot hands `resources_reimported` an
## array of EVERY path it just imported, and this digest rides on every tool
## response — so dropping an asset pack into the project made the next unrelated
## tool call return 1.5 MB (~390,000 tokens). Measured, in the server whose whole
## argument is that context is expensive. DIGEST_MAX caps how many events ride
## along; nothing capped how big one could be.
const DETAIL_MAX_ITEMS := 8
const DETAIL_MAX_CHARS := 300

## Emitted for each HUMAN-sourced event as it happens, so the plugin can push it
## to the server instead of the server polling for it. Agent-sourced events are
## not emitted: the agent already knows what it did, and pushing them back would
## make every tool call generate traffic.
signal human_activity(event: Dictionary)

var _ring: Array = []
var _seq: int = 0
var _agent_depth: int = 0
var _agent_deadline_ms: int = 0
var _digest_cursor: int = 0

## Open the agent window for the duration of a tool call. Counted rather than a
## flag: calls can overlap across their await points, and an inner one finishing
## must not un-tag the work the outer one is still doing.
func begin_agent_call() -> void:
	_agent_depth += 1
	_agent_deadline_ms = Time.get_ticks_msec() + AGENT_MAX_CALL_MS

## Close it, leaving the grace period for deferred signals. Only the outermost
## call closes the window.
func end_agent_call() -> void:
	_agent_depth = maxi(0, _agent_depth - 1)
	if _agent_depth == 0:
		_agent_deadline_ms = Time.get_ticks_msec() + AGENT_GRACE_MS

func record(type: String, detail) -> void:
	_seq += 1
	# Best-effort attribution: a human action within the grace window can be
	# mis-tagged agent, and a very slow deferred signal can slip to human.
	var source := "agent" if Time.get_ticks_msec() < _agent_deadline_ms else "human"
	var event := {&"id": _seq, &"t_ms": Time.get_ticks_msec(), &"type": type, &"detail": _clamp_detail(detail), &"source": source}
	_ring.append(event)
	if _ring.size() > CAP:
		_ring = _ring.slice(_ring.size() - CAP)
	if source == "human":
		human_activity.emit(event)

## Bound one event's detail. Keeps the shape (array stays an array, string stays
## a string) so readers do not need a special case, and reports what was dropped
## instead of silently truncating — "reimported 8 files" when it was 3,000 would
## be a lie the agent cannot detect.
func _clamp_detail(detail):
	if detail is Array:
		var arr: Array = detail
		if arr.size() <= DETAIL_MAX_ITEMS:
			return arr
		var head: Array = arr.slice(0, DETAIL_MAX_ITEMS)
		head.append("... and %d more (%d total)" % [arr.size() - DETAIL_MAX_ITEMS, arr.size()])
		return head
	if detail is String:
		var s: String = detail
		if s.length() <= DETAIL_MAX_CHARS:
			return s
		return s.substr(0, DETAIL_MAX_CHARS) + "... (%d chars)" % s.length()
	return detail

## Events after `since_id` (0 = everything buffered), newest last. `source_filter`
## of "human"/"agent" narrows to that origin. `latest_id` lets a poller advance
## its cursor: call again with since_id = latest_id to get only what is new.
func query(since_id: int, limit: int, source_filter: String = "") -> Dictionary:
	var out: Array = []
	for e in _ring:
		if int(e[&"id"]) <= since_id:
			continue
		if not source_filter.is_empty() and str(e.get(&"source", "")) != source_filter:
			continue
		out.append(e)
	if out.size() > limit:
		out = out.slice(out.size() - limit, out.size())
	return {&"events": out, &"latest_id": _seq, &"count": out.size()}

## Event types that carry no information the agent can act on, and are therefore
## left out of the piggybacked digest (query() still returns them).
##
## `filesystem_changed` is the whole reason this exists. It fires on every file
## the AGENT writes, but arrives deferred — after end_agent_call() — so it is
## attributed to the human and rides along on nearly every response. Across one
## session it was ~90% of all digest content, always as
## `{"type":"filesystem_changed","detail":""}`: pure token toll telling the agent
## it had written a file it had just written.
const _DIGEST_NOISE: Array[String] = ["filesystem_changed"]

## Compact summary of human events since the last call, or {} if there were none.
## Advances its own cursor (kept separate from query()'s caller-supplied since_id,
## so the two do not consume each other's events) — each event is digested once.
func human_digest() -> Dictionary:
	var events: Array = []
	for e in _ring:
		if int(e[&"id"]) <= _digest_cursor:
			continue
		if str(e.get(&"source", "")) != "human":
			continue
		if str(e.get(&"type", "")) in _DIGEST_NOISE:
			continue
		events.append(e)
	_digest_cursor = _seq
	if events.is_empty():
		return {}

	var recent: Array = events.slice(maxi(0, events.size() - DIGEST_MAX), events.size())
	var compact: Array = []
	for e in recent:
		compact.append({&"type": e[&"type"], &"detail": e[&"detail"]})
	return {
		&"human_events_since_last_call": events.size(),
		&"recent": compact,
		&"note": "The developer did this in the editor while you were working. Call get_editor_activity for the full history.",
	}
