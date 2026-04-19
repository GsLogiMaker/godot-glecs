
class_name GFCollisionShape2D extends GFComponent

func get_shape() -> Shape2D: return getm("shape")
func set_shape(v:Shape2D): return setm("shape", v)

func _build(b:GFComponentBuilder) -> void: b \
	.add_member("shape", TYPE_OBJECT)
