
## A component that gives entities functionality of a CanvasItem.

class_name GFCanvasItem extends GFComponent

func get_rid() -> RID: return getm(&"rid")
func set_rid(v:RID) -> void: setm(&"rid", v)
func _build(b: GFComponentBuilder) -> void:
	b.add_member("rid", TYPE_RID)
	

static func get_main_viewport_rid() -> RID:
	return Engine.get_main_loop() \
		.current_scene \
		.get_viewport() \
		.get_viewport_rid()


static func get_main_canvas() -> RID:
	return Engine.get_main_loop() \
		.current_scene \
		.get_viewport() \
		.get_world_2d() \
		.get_canvas()
		


## Sets the parent canvas item of this canvas item by its [RID].
func set_parent_canvas_item(rid:RID) -> void:
	RenderingServer.canvas_item_set_parent(
		get_rid(),
		rid
	)


## Updates the transform of this canvas item via the three 2D spatial
## components.
func update_transform_c(
	pos:GFPosition2D,
	rot:GFRotation2D,
	scale:GFScale2D,
) -> void:
	var loc:Vector2 = pos.get_vec() if pos else Vector2()
	var angle:float = rot.get_angle() if rot else 0.0
	var size:Vector2 = scale.get_scale() if scale else Vector2.ONE
	RenderingServer.canvas_item_set_transform(
		get_rid(),
		Transform2D(angle, size, 0, loc)
		)
