
class_name GFRect2 extends GFComponent

func get_value() -> Rect2: return getm(&"value")
func set_value(v:Rect2) -> void: return setm(&"value", v)
func _build(b: GFComponentBuilder) -> void:
	b.add_member("value", TYPE_RECT2)
