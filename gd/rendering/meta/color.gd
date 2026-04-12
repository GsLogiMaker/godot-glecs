class_name GFColor extends GFComponent

func get_color() -> Color: return getm("color")
func set_color(v:Color) -> void: setm("color", v)

func _build(b:GFComponentBuilder) -> void:
	b.add_member("color", TYPE_COLOR)
