
class_name GFInt extends GFComponent

func get_value() -> int: return getm(&"value")
func set_value(v:int) -> void: return setm(&"value", v)
func _build(b: GFComponentBuilder) -> void:
	b.add_member("value", TYPE_INT)
