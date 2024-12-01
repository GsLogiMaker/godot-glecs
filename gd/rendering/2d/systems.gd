
## A component that gives entities functionality of a CanvasItem.

extends GFModule

func _register(w:GFWorld):
	#region GFCanvasItem
	# On add GFCanvasItem
	w.observer_builder("/root/flecs/core/OnAdd") \
		.with(GFCanvasItem) \
		.for_each(func(item:GFCanvasItem):
			item.set_rid(RenderingServer.canvas_item_create())
			# Set parent to root
			item.set_parent_canvas_item(
				GFCanvasItem.get_main_canvas()
				)
			)

	# On set GFCanvasItem
	w.observer_builder("/root/flecs/core/OnSet") \
		.with(GFCanvasItem) \
		.for_each(func(item:GFCanvasItem):
			item.set_parent_canvas_item(
				GFCanvasItem.get_main_canvas()
				)
			)

	# On remove GFCanvasItem
	w.observer_builder("/root/flecs/core/OnRemove") \
		.with(GFCanvasItem) \
		.for_each(func(item:GFCanvasItem):
			RenderingServer.free_rid(item.get_rid())
			)
	#endregion
	
	#region GFPosition2D
	# On GFPosition2D set, update visual transform of CanvasItemC
	w.observer_builder("/root/flecs/core/OnSet") \
		.with(GFCanvasItem).access_filter() \
		.with(GFPosition2D) \
		.maybe_with(GFRotation2D) \
		.maybe_with(GFScale2D) \
		.for_each(func(
			item:GFCanvasItem,
			pos:GFPosition2D,
			rot:GFRotation2D,
			scl:GFScale2D,
		):
			item.update_transform_c(pos, rot, scl)
			)
	#endregion

	#region GFRotation2D
	# On GFPosition2D set, update visual transform of GFCanvasItem
	w.observer_builder("/root/flecs/core/OnSet") \
		.with(GFCanvasItem).access_filter() \
		.with(GFRotation2D) \
		.maybe_with(GFPosition2D) \
		.maybe_with(GFScale2D) \
		.for_each(func(
			item:GFCanvasItem,
			rot:GFRotation2D,
			pos:GFPosition2D,
			scl:GFScale2D,
		):
			item.update_transform_c(pos, rot, scl)
			)
	#endregion
	
	#region GFScale2D
	# On GFScale2D set, update visual transform of GFCanvasItem
	w.observer_builder("/root/flecs/core/OnSet") \
		.with(GFCanvasItem).access_filter() \
		.with(GFScale2D) \
		.maybe_with(GFPosition2D) \
		.maybe_with(GFRotation2D) \
		.for_each(func(
			item:GFCanvasItem,
			scal:GFScale2D,
			pos:GFPosition2D,
			rot:GFRotation2D,
		):
			item.update_transform_c(pos, rot, scal)
			)
	#endregion

	#region GFTexture2D
	w.observer_builder("/root/flecs/core/OnAdd") \
		.with(GFTexture2D) \
		.with(GFCanvasItem) \
		.for_each(GFTexture2D.update_texture_rect)
		
	w.observer_builder("/root/flecs/core/OnSet") \
		.with(GFTexture2D) \
		.with(GFCanvasItem) \
		.for_each(GFTexture2D.update_texture_rect)
	#endregion
