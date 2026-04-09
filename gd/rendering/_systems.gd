
## A component that gives entities functionality of a CanvasItem.

extends GFModule

func _register(w:GFWorld):
	var Any:= w.lookup("/root/flecs/core/*")
	var ChildOf:= w.lookup("/root/flecs/core/ChildOf")
	var OnAdd:= w.lookup("/root/flecs/core/OnAdd")
	var OnRemove:= w.lookup("/root/flecs/core/OnRemove")
	var OnSet:= w.lookup("/root/flecs/core/OnSet")

	#region GFCanvasItem
	# Construct GFCanvasItem
	GFObserverBuilder.new().set_name("construct_canvas_item") \
		.set_events(OnAdd) \
		.with(GFCanvasItem) \
		.for_each(func(item:GFCanvasItem):
			item.set_rid(RenderingServer.canvas_item_create())
			)
	
	GFObserverBuilder.new().set_name("canvas_item_material_set") \
		.set_events(OnSet) \
		.with(GFCanvasItem) \
		.with(GFCanvasItem.material) \
		.for_each(func(
			item:GFCanvasItem,
			material:GFCanvasItem.material,
			):
			var material_rid:= material.get_material().get_rid() \
				if material.get_material() \
				else RID()
			RenderingServer.canvas_item_set_material(
				item.get_rid(),
				material_rid,
				)
			)
	
	GFObserverBuilder.new().set_name("canvas_item_material_remove") \
		.set_events(OnRemove) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.material) \
		.for_each(func(
			item:GFCanvasItem,
			material:GFCanvasItem.material,
			):
			RenderingServer.canvas_item_set_material(
				item.get_rid(),
				RID()
				)
			)

	GFObserverBuilder.new().set_name("update_canvas_group_mode_clip") \
		.set_events(OnAdd) \
		.with(GFCanvasItem) \
		.with(GFCanvasItem.clip_children) \
		.for_each(func(item:GFCanvasItem, clip_children):
			RenderingServer.canvas_item_set_canvas_group_mode(
				item.get_rid(),
				RenderingServer.CanvasGroupMode.CANVAS_GROUP_MODE_CLIP_ONLY,
				)
			)
	GFObserverBuilder.new().set_name("update_canvas_group_mode_normal") \
		.set_events(OnRemove) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.clip_children) \
		.for_each(func(item:GFCanvasItem, clip_children):
			RenderingServer.canvas_item_set_canvas_group_mode(
				item.get_rid(),
				RenderingServer.CanvasGroupMode.CANVAS_GROUP_MODE_DISABLED,
				)
			)

	GFObserverBuilder.new().set_name("canvas_item_hide") \
		.set_events(OnAdd) \
		.with(GFCanvasItem) \
		.with(GFCanvasItem.hidden) \
		.for_each(func(item:GFCanvasItem, hidden):
			item.set_visible(false)
			)
	GFObserverBuilder.new().set_name("canvas_item_show") \
		.set_events(OnRemove) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.hidden) \
		.for_each(func(item:GFCanvasItem, hidden):
			item.set_visible(true)
			)
	
	GFObserverBuilder.new().set_name("canvas_item_use_parent_material_add") \
		.set_events(OnAdd) \
		.with(GFCanvasItem) \
		.with(GFCanvasItem.use_parent_material) \
		.for_each(func(item:GFCanvasItem, _1):
			RenderingServer.canvas_item_set_use_parent_material(
				item.get_rid(),
				true,
				)
			)
	GFObserverBuilder.new().set_name("canvas_item_use_parent_material_remove") \
		.set_events(OnRemove) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.use_parent_material) \
		.for_each(func(item:GFCanvasItem, _1):
			RenderingServer.canvas_item_set_use_parent_material(
				item.get_rid(),
				false,
				)
			)

	GFObserverBuilder.new().set_name("update_canvas_item_on_set") \
		.set_events(OnSet) \
		.with(GFCanvasItem) \
		.with_maybe(ChildOf, "$par") \
		.with_maybe(GFCanvasItem).src("$par") \
		.for_each(func(
			item:GFCanvasItem,
			_1,
			parent_item:GFCanvasItem,
			):
			var parent:= parent_item.get_rid() \
				if parent_item \
				else GFCanvasItem.get_main_canvas()
			item.set_parent_canvas_item(parent)

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

	#region GFRect2D

	GFObserverBuilder.new().set_name("trigger_rect_redraw") \
		.set_events(OnSet) \
		.with(GFCanvasItem).io_filter() \
		.with(GFRect2D).io_filter() \
		.with(GFPosition2D, GFRect2D) \
			.or_with(GFRect2D.size) \
			.or_with(GFRect2D.color) \
		.for_each(func(
			item:GFCanvasItem,
			_rect,
			_value,
			):
			queue_redraw(item.get_source_entity())
			)

	GFObserverBuilder.new().set_name("draw_rect") \
		.set_events(GFOnDraw) \
		.with(GFCanvasItem) \
		.with(GFRect2D) \
		.with_maybe(GFPosition2D, GFRect2D) \
		.with_maybe(GFRect2D.color) \
		.with_maybe(GFRect2D.size) \
		.for_each(func(
			item:GFCanvasItem,
			rect_c:GFRect2D,
			position_gf:GFPosition2D,
			color_gf:GFRect2D.color,
			size_gf:GFRect2D.size,
			):
			var color = color_gf.getm("color") \
				if color_gf \
				else Color.WHITE
			var size = size_gf.get_size() \
				if size_gf \
				else Vector2(10, 10)
			var pos = position_gf.get_vec() \
				if position_gf \
				else -size / Vector2(2, 2)
			RenderingServer.canvas_item_add_rect(
				item.get_rid(),
				Rect2(pos, size),
				color,
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
