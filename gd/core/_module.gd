
extends GFModule

func _register(world: GFWorld) -> void:
	set_name("core")
	world.register_script(GFExtends)
