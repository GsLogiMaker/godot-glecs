
## Registers default Glecs modules with new worlds.

@tool
class_name _GlecsModules extends Node

const MODULES:= [
	"./rendering/rendering.gd",
]

static var x:= (func():
	Engine.register_singleton("_glecs_modules", _GlecsModules)
).call()

static func register_modules(w:GFWorld) -> void:
	var path:= (_GlecsModules as Script).resource_path.path_join("../")
	for module in MODULES:
		w.register_script(load(path.path_join(module)))
