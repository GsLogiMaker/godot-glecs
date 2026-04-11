
## A component that gives entities functionality of a CanvasItem.

extends GFModule

func _register(w:GFWorld):
	var Any:= w.lookup("/root/flecs/core/*")
	var ChildOf:= w.lookup("/root/flecs/core/ChildOf")
	var OnAdd:= w.lookup("/root/flecs/core/OnAdd")
	var OnRemove:= w.lookup("/root/flecs/core/OnRemove")
	var OnSet:= w.lookup("/root/flecs/core/OnSet")

	#region GFCanvasItem

	GFObserverBuilder.new().set_name("canvas_item_add") \
		.set_events(OnAdd) \
		.with(GFCanvasItem) \
		.for_each(func(item:GFCanvasItem):
			item.set_rid(RenderingServer.canvas_item_create())
			)
	GFObserverBuilder.new().set_name("canvas_item_set") \
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
	GFObserverBuilder.new().set_name("canvas_item_remove") \
		.set_events(OnRemove) \
		.with(GFCanvasItem) \
		.for_each(func(item:GFCanvasItem):
			RenderingServer.free_rid(item.get_rid())
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

	GFObserverBuilder.new().set_name("canvas_item_group_mode_add") \
		.set_events(OnAdd) \
		.with(GFCanvasItem) \
		.with(GFCanvasItem.clip_children) \
		.for_each(func(item:GFCanvasItem, clip_children):
			RenderingServer.canvas_item_set_canvas_group_mode(
				item.get_rid(),
				RenderingServer.CanvasGroupMode.CANVAS_GROUP_MODE_CLIP_ONLY,
				)
			)
	GFObserverBuilder.new().set_name("canvas_item_group_mode_remove") \
		.set_events(OnRemove) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.clip_children) \
		.for_each(func(item:GFCanvasItem, clip_children):
			RenderingServer.canvas_item_set_canvas_group_mode(
				item.get_rid(),
				RenderingServer.CanvasGroupMode.CANVAS_GROUP_MODE_DISABLED,
				)
			)

	GFObserverBuilder.new().set_name("canvas_item_visibility_hide") \
		.set_events(OnAdd) \
		.with(GFCanvasItem) \
		.with(GFCanvasItem.hidden) \
		.for_each(func(item:GFCanvasItem, hidden):
			item.set_visible(false)
			)
	GFObserverBuilder.new().set_name("canvas_item_visibility_show") \
		.set_events(OnRemove) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.hidden) \
		.for_each(func(item:GFCanvasItem, hidden):
			item.set_visible(true)
			)

	GFObserverBuilder.new().set_name("canvas_item_light_mask_set") \
		.set_events(OnSet) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.light_mask) \
		.for_each(func(item: GFCanvasItem, mask_c: GFCanvasItem.light_mask):
			RenderingServer.canvas_item_set_light_mask(
				item.get_rid(),
				mask_c.getm("mask"),
				)
			)
	GFObserverBuilder.new().set_name("canvas_item_light_mask_remove") \
		.set_events(OnRemove) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.light_mask) \
		.for_each(func(item: GFCanvasItem, _1):
			RenderingServer.canvas_item_set_light_mask(
				item.get_rid(),
				1,
				)
			)

	GFObserverBuilder.new().set_name("canvas_item_modulate_set") \
		.set_events(OnSet) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.modulate) \
		.for_each(func(item: GFCanvasItem, modulate_c: GFCanvasItem.modulate):
			RenderingServer.canvas_item_set_modulate(
				item.get_rid(),
				modulate_c.get_color(),
				)
			)
	GFObserverBuilder.new().set_name("canvas_item_modulate_remove") \
		.set_events(OnRemove) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.modulate) \
		.for_each(func(item: GFCanvasItem, _1):
			RenderingServer.canvas_item_set_modulate(
				item.get_rid(),
				Color.WHITE,
				)
			)

	GFObserverBuilder.new().set_name("canvas_item_self_modulate_set") \
		.set_events(OnSet) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.self_modulate) \
		.for_each(func(item: GFCanvasItem, modulate_c: GFCanvasItem.self_modulate):
			RenderingServer.canvas_item_set_self_modulate(
				item.get_rid(),
				modulate_c.get_color(),
				)
			)
	GFObserverBuilder.new().set_name("canvas_item_self_modulate_remove") \
		.set_events(OnRemove) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.self_modulate) \
		.for_each(func(item: GFCanvasItem, _1):
			RenderingServer.canvas_item_set_self_modulate(
				item.get_rid(),
				Color.WHITE,
				)
			)

	GFObserverBuilder.new().set_name("canvas_item_show_behind_parent_add") \
		.set_events(OnAdd) \
		.with(GFCanvasItem) \
		.with(GFCanvasItem.show_behind_parent) \
		.for_each(func(item:GFCanvasItem, _1):
			RenderingServer.canvas_item_set_draw_behind_parent(
				item.get_rid(),
				true,
				)
			)
	GFObserverBuilder.new().set_name("canvas_item_show_behind_parent_remove") \
		.set_events(OnRemove) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.show_behind_parent) \
		.for_each(func(item:GFCanvasItem, _1):
			RenderingServer.canvas_item_set_draw_behind_parent(
				item.get_rid(),
				false,
				)
			)

	GFObserverBuilder.new().set_name("canvas_item_transform_set") \
		.set_events(OnSet) \
		.with(GFCanvasItem).io_filter() \
		.with_maybe(GFPosition2D) \
		.with_maybe(GFRotation2D) \
		.with_maybe(GFSkew2D) \
		.with_maybe(GFScale2D) \
		.for_each(func(
			item_c:GFCanvasItem,
			pos_c:GFPosition2D,
			rot_c:GFRotation2D,
			skew_c:GFSkew2D,
			scale_c:GFScale2D,
			) -> void:
			var loc:Vector2 = pos_c.get_vec() if pos_c else Vector2()
			var angle:float = rot_c.get_angle() if rot_c else 0.0
			var skew:float = skew_c.get_skew() if skew_c else 0
			var size:Vector2 = scale_c.get_scale() if scale_c else Vector2.ONE
			RenderingServer.canvas_item_set_transform(
				item_c.get_rid(),
				Transform2D(angle, size, skew, loc),
				)
			)

	GFObserverBuilder.new().set_name("canvas_item_texture_filter_set") \
		.set_events(OnSet) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.texture_filter) \
		.for_each(func(item: GFCanvasItem, filter_c: GFCanvasItem.texture_filter):
			RenderingServer.canvas_item_set_default_texture_filter(
				item.get_rid(),
				filter_c.getm("value"),
				)
			)
	GFObserverBuilder.new().set_name("canvas_item_texture_filter_remove") \
		.set_events(OnRemove) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.texture_filter) \
		.for_each(func(item: GFCanvasItem, _1):
			RenderingServer.canvas_item_set_default_texture_filter(
				item.get_rid(),
				0,
				)
			)

	GFObserverBuilder.new().set_name("canvas_item_texture_repeat_set") \
		.set_events(OnSet) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.texture_repeat) \
		.for_each(func(item: GFCanvasItem, repeat_c: GFCanvasItem.texture_repeat):
			RenderingServer.canvas_item_set_default_texture_repeat(
				item.get_rid(),
				repeat_c.getm("value"),
				)
			)
	GFObserverBuilder.new().set_name("canvas_item_texture_repeat_remove") \
		.set_events(OnRemove) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.texture_repeat) \
		.for_each(func(item: GFCanvasItem, _1):
			RenderingServer.canvas_item_set_default_texture_repeat(
				item.get_rid(),
				0,
				)
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

	GFObserverBuilder.new().set_name("canvas_item_visibility_layer_set") \
		.set_events(OnSet) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.visibility_layer) \
		.for_each(func(item: GFCanvasItem, layer_c: GFCanvasItem.visibility_layer):
			RenderingServer.canvas_item_set_visibility_layer(
				item.get_rid(),
				layer_c.getm("layer"),
				)
			)
	GFObserverBuilder.new().set_name("canvas_item_visibility_layer_remove") \
		.set_events(OnRemove) \
		.with(GFCanvasItem).io_filter() \
		.with(GFCanvasItem.visibility_layer) \
		.for_each(func(item: GFCanvasItem, _1):
			RenderingServer.canvas_item_set_visibility_layer(
				item.get_rid(),
				1,
				)
			)

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

	#region GFColorRect

	GFObserverBuilder.new().set_name("color_rect_draw") \
		.set_events(GFOnDraw) \
		.with(GFCanvasItem) \
		.with(GFColorRect) \
		.with_maybe(GFPosition2D, GFColorRect) \
		.with_maybe(GFColorRect.color) \
		.with_maybe(GFColorRect.size) \
		.for_each(func(
			item:GFCanvasItem,
			rect_c:GFColorRect,
			position_gf:GFPosition2D,
			color_gf:GFColorRect.color,
			size_gf:GFColorRect.size,
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

	GFObserverBuilder.new().set_name("color_rect_position_set") \
		.set_events(OnSet) \
		.with(GFCanvasItem).io_filter() \
		.with(GFColorRect).io_filter() \
		.with(GFPosition2D, GFColorRect) \
			.or_with(GFColorRect.size) \
			.or_with(GFColorRect.color) \
		.for_each(func(
			item:GFCanvasItem,
			_rect,
			_value,
			):
			queue_redraw(item.get_source_entity())
			)

	#endregion

static func queue_redraw(entity:GFEntity) -> void:
	var item:RID = entity.get(GFCanvasItem)
	if not item:
		return

	RenderingServer.canvas_item_clear(item)
	GFEntity.from(GFOnDraw, entity.get_world()) \
		.emit(entity)
