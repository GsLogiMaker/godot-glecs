
extends GFModule

func _register(world: GFWorld) -> void:
	set_name("2d")
	world.register_script(GFPosition2D)
	world.register_script(GFRotation2D)
	world.register_script(GFScale2D)
	world.register_script(GFSize2D)
	world.register_script(GFSkew2D)
