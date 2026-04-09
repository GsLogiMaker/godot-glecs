
class_name GFColorRect extends GFTag

func _register(world:GFWorld) -> void:
	add_pair("/root/flecs/core/With", GFCanvasItem)
	world.register_script(color).set_name("Color")
	world.register_script(size).set_name("Size")

class color extends GFColor: pass
class size extends GFSize2D: pass
