extends GFModule

const Systems:= preload("./_systems.gd")
const SystemsSprite2D:= preload("./_systems_sprite2d.gd")

func _register(world: GFWorld) -> void:
	set_name("rendering")
	world.register_script(GFCanvasItem)
	world.register_script(GFColor)
	world.register_script(GFColorRect)
	world.register_script(GFOnDraw)
	world.register_script(GFTexture2D)
