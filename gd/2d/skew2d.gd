
## A component that represents skew in 2D space.

class_name GFSkew2D extends GFComponent

func get_skew() -> float: return getm(&"skew")
func set_skew(v:float) -> void: return setm(&"skew", v)
func _build(b: GFComponentBuilder) -> void:
	b.add_member("skew", TYPE_FLOAT)
