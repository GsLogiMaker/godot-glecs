
class_name GFRectangleShape2D extends GFComponent

func get_size() -> Vector2: return getm("size")
func set_size(v:Vector2) -> void: setm("size", v)
func get_rid() -> RID: return getm("rid")
func _set_rid(v:RID) -> void: setm("rid", v)

func _build(b:GFComponentBuilder) -> void: b \
	.add_member("size", TYPE_VECTOR2) \
	.add_member("rid", TYPE_RID) \
