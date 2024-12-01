@tool
extends EditorPlugin

const modules:= preload("./gd/modules.gd")

func _enter_tree() -> void:
	add_autoload_singleton("_glecs_modules", "./gd/modules.gd")


func _exit_tree() -> void:
	remove_autoload_singleton("_glecs_modules")
	Engine.unregister_singleton("_glecs_modules")
