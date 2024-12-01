
extends Node2D

var world:= GFWorld.new()

var texture:= load("res://icon.png")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GFEntity.spawn(world) \
		.set_name("Test") \
		.add_component(GFTexture2D, texture) \
		.add_component(GFCanvasItem) \
		.add_component(GFPosition2D)

	world.start_rest_api()


func _process(delta: float) -> void:
	world.progress(delta)
	world.lookup("Test") \
		.get_component(GFPosition2D) \
		.set_vec(get_global_mouse_position())
