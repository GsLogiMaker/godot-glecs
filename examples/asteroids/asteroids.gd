
extends Node


var texture:= load("res://icon.png")
var e:GFEntity
var c:GFEntity

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	e = GFEntity.new()
	e.set(GFSprite2D.offset, Vector2(1, 1))
	e.set_name("Test")
	e.add(GFSprite2D)
	e.set(GFSprite2D, load("res://icon.png"))


func _process(delta: float) -> void:
	GFWorld.get_default_world().progress(0)

func _on_centered_pressed() -> void:
	if e.has(GFSprite2D.centered):
		e.remove(GFSprite2D.centered)
	else:
		e.add(GFSprite2D.centered)


func _on_offset_x_value_changed(value: float) -> void:
	var offset = e.get(GFSprite2D.offset, Vector2())
	e.set(GFSprite2D.offset, Vector2(value, offset.y))


func _on_offset_y_value_changed(value: float) -> void:
	var offset = e.get(GFSprite2D.offset, Vector2())
	e.set(GFSprite2D.offset, Vector2(offset.x, value))
