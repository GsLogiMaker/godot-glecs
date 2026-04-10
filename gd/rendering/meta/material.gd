class_name GFMaterial extends GFComponent

func set_material(v:Material) -> void:
	setm("material", v)
func get_material() -> Material:
	return getm("material")

func _build(b:GFComponentBuilder) -> void:
	b.add_member("material", TYPE_OBJECT)
