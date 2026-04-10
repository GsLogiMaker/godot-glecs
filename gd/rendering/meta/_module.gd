extends GFModule

func _register(world: GFWorld) -> void:
	set_name("meta")
	world.register_script(GFColor)
	world.register_script(GFMaterial)
	world.register_script(GFTexture2D)
