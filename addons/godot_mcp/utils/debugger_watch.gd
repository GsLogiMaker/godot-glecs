extends EditorDebuggerPlugin
## Reports the running game's life to the activity feed, so the agent hears about
## a crash instead of discovering it on the next tool call.
##
## Why here and not in the runtime autoload: an engine error inside a running
## game is not observable from GDScript in that game — there is no supported hook
## for it. The error travels to the EDITOR over the debugger channel, so the
## editor is the only side that can see it at all.
##
## This deliberately captures nothing (`_has_capture` returns false). It only
## listens to session lifecycle; the debugger's own UI keeps handling everything
## else exactly as before.

## type/detail pairs, shaped for McpActivityLog.record().
signal game_event(type: String, detail)


func _has_capture(_prefix: String) -> bool:
	return false


func _setup_session(session_id: int) -> void:
	var session := get_session(session_id)
	if session == null:
		return
	session.started.connect(func() -> void: game_event.emit("game_running", ""))
	session.stopped.connect(func() -> void: game_event.emit("game_stopped", ""))
	session.continued.connect(func() -> void: game_event.emit("game_resumed", ""))
	# `breaked` covers both halts: a breakpoint the developer set, and a runtime
	# error that stopped the game. `can_debug` tells them apart — false means the
	# game is dead rather than paused, which is the case worth interrupting for.
	session.breaked.connect(func(can_debug: bool) -> void:
		game_event.emit(
			"game_paused" if can_debug else "game_crashed",
			{&"can_debug": can_debug}
		)
	)
