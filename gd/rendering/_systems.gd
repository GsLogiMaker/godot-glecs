
## A component that gives entities functionality of a CanvasItem.

extends GFModule

func _register(w:GFWorld):
	var OnAdd:= w.lookup("/root/flecs/core/OnAdd")
	var OnSet:= w.lookup("/root/flecs/core/OnSet")
	var OnRemove:= w.lookup("/root/flecs/core/OnRemove")

	#region GFCanvasItem
	# Construct GFCanvasItem
	GFObserverBuilder.new().set_name("construct_canvas_item") \
		.set_events(OnAdd) \
		.with(GFCanvasItem) \
		.for_each(func(item:GFCanvasItem):
			item.set_rid(RenderingServer.canvas_item_create())
			# Set parent to root
			item.set_parent_canvas_item(
				GFCanvasItem.get_main_canvas()
				)
			)

	GFObserverBuilder.new().set_name("update_canvas_item_on_set") \
		.set_events(OnSet) \
		.with(GFCanvasItem) \
		.for_each(func(item:GFCanvasItem):
			item.set_parent_canvas_item(
				GFCanvasItem.get_main_canvas()
				)
			queue_redraw(item.get_source_entity())
			)

	GFObserverBuilder.new().set_name("destruct_canvas_item") \
		.set_events(OnRemove) \
		.with(GFCanvasItem) \
		.for_each(func(item:GFCanvasItem):
			RenderingServer.free_rid(item.get_rid())
			)

	GFObserverBuilder.new().set_name("update_canvas_item_transform") \
		.set_events(OnSet) \
		.with(GFCanvasItem).io_filter() \
		.with_maybe(GFPosition2D) \
		.with_maybe(GFRotation2D) \
		.with_maybe(GFScale2D) \
		.for_each(update_transform_c)
	#endregion

	#region GFTexture2D

	GFObserverBuilder.new().set_name("texture_2d_trigger_redraw") \
		.set_events(OnAdd, OnSet) \
		.with(GFCanvasItem) \
		.with(GFTexture2D) \
		.for_each(func(item:GFCanvasItem, sprite:GFTexture2D):
			queue_redraw(item.get_source_entity())
			)

	GFObserverBuilder.new().set_name("draw_texture_rect") \
		.set_events(GFOnDraw) \
		.with(GFCanvasItem) \
		.with(GFTexture2D) \
		.for_each(func(item:GFCanvasItem, sprite:GFTexture2D):
			var texture:= sprite.get_texture()
			if not texture:
				return

			RenderingServer.canvas_item_add_texture_rect(
				item.get_rid(),
				Rect2(-texture.get_size() / 2, texture.get_size()),
				texture,
				)
			)

	#endregion

	#region GFDrawRect2D

	GFObserverBuilder.new().set_name("draw_rect_2d_trigger_redraw") \
		.set_events(OnAdd, OnSet) \
		.with(GFCanvasItem) \
		.with(GFDrawRect2D) \
		.with_maybe(GFPosition2D, GFDrawRect2D) \
		.with_maybe(GFSize2D, GFDrawRect2D) \
		.for_each(func(
			item:GFCanvasItem,
			_position_gf:GFPosition2D,
			_size_gf:GFSize2D,
			):
			queue_redraw(item.get_source_entity())
			)

	GFObserverBuilder.new().set_name("trigger_redraw_on_set_draw_rect_size") \
		.set_events(OnSet) \
		.with(GFCanvasItem).io_filter() \
		.with(GFSize2D, GFDrawRect2D) \
		.for_each(func(
			item:GFCanvasItem,
			_value,
			):
			queue_redraw(item.get_source_entity())
			)

	GFObserverBuilder.new().set_name("draw_rect") \
		.set_events(GFOnDraw) \
		.with(GFCanvasItem) \
		.with(GFDrawRect2D) \
		.with_maybe(GFPosition2D, GFDrawRect2D) \
		.with_maybe(GFSize2D, GFDrawRect2D) \
		.for_each(func(
			item:GFCanvasItem,
			rect_c:GFDrawRect2D,
			position_gf:GFPosition2D,
			size_gf:GFSize2D,
			):
			#var size:= Vector2(32, 32)
			#var pos:= -size / Vector2(2, 2)
			prints(size_gf)
			var size = size_gf.get_size() \
				if size_gf \
				else Vector2(32, 32)
			var pos = position_gf.get_vec() \
				if position_gf \
				else -size / Vector2(2, 2)
			RenderingServer.canvas_item_add_rect(
				item.get_rid(),
				Rect2(pos, size),
				Color.RED
				)
			)

	#endregion

static func queue_redraw(entity:GFEntity) -> void:
	var item:= entity.get(GFCanvasItem)
	if not item:
		return

	RenderingServer.canvas_item_clear(item.get_rid())
	GFEntity.from(GFOnDraw, entity.get_world()) \
		.emit(entity)

static func update_transform_c(
	item:GFCanvasItem,
	pos:GFPosition2D,
	rot:GFRotation2D,
	scale:GFScale2D,
) -> void:
	var loc:Vector2 = pos.get_vec() if pos else Vector2()
	var angle:float = rot.get_angle() if rot else 0.0
	var size:Vector2 = scale.get_scale() if scale else Vector2.ONE
	RenderingServer.canvas_item_set_transform(
		item.get_rid(),
		Transform2D(angle, size, 0, loc)
		)
