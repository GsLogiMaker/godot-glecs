
class_name GFVector2 extends GFComponent

func get_value() -> Vector2: return getm(&"value")
func set_value(v:Vector2) -> void: return setm(&"value", v)
func _build(b: GFComponentBuilder) -> void:
	b.add_member("value", TYPE_VECTOR2)
