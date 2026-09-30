
class_name GFVector2i extends GFComponent

func get_value() -> Vector2i: return getm(&"value")
func set_value(v:Vector2i) -> void: return setm(&"value", v)
func _build(b: GFComponentBuilder) -> void:
	b.add_member("value", TYPE_VECTOR2I)
