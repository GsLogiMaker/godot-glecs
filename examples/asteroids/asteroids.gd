
extends Node2D


var texture:= load("res://icon.png")
var e:GFEntity

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	e = GFEntity.new()
	e.set_name("Test")
	e.add(GFRect2D)
	e.add(GFRotation2D)
	e.set(GFRect2D.size, Vector2(100, 22))

	GFEntity.from(GFOnDraw, e.get_world()).emit(e)

	GFWorld.get_default_world().start_rest_api()


func _process(delta: float) -> void:
	GFWorld.get_default_world().progress(0)
	
	var rot_c:GFRotation2D = e.get(GFRotation2D)
	rot_c.set_angle(rot_c.get_angle() + (delta * Input.get_axis("ui_left", "ui_right")))

	var v_axis:= Input.get_axis("ui_up", "ui_down")
	if v_axis:
		var size_c:GFRect2D.size = e.get(GFRect2D.size)
		size_c.set_y(size_c.get_y() - (100 * delta * v_axis))

	if Input.is_action_just_pressed("ui_accept"):
		e.set(GFRect2D.color, Color(randf(), randf(), randf()))
