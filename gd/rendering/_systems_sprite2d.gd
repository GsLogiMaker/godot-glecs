## A module that gives entities functionality of a Sprite2D.
##
## This module implements ECS observers that synchronize GFSprite2D components
## with Godot RenderingServer CanvasItem state for sprite-specific properties.
##
## NOTE: Godot's RenderingServer does NOT expose dedicated setters for most
## sprite2d properties (centered, flip_h, flip_v, offset, region, etc.).
## The canvas_item_set_* methods available are limited to: transform,
## visible, modulate, z_index, z_as_relative, etc. (confirmed via the
## extension API). Sprite-specific properties are applied through the
## standard Godot Node2D editor workflow and/or the existing draw_texture_rect
## observer in _systems.gd which already renders the full texture.
##
## This module therefore only queues redraws when sprite tags/components
## change, and does NOT call any unavailable RenderingServer setters.
## Any property-specific rendering should be handled by the existing
## _systems.gd observer `draw_texture_rect` which draws the texture rect
## based on the GFTexture2D held by GFSprite2D.

extends GFModule

func _register(w:GFWorld) -> void:
	var OnAdd:= w.lookup("/root/flecs/core/OnAdd")
	var OnRemove:= w.lookup("/root/flecs/core/OnRemove")
	var OnSet:= w.lookup("/root/flecs/core/OnSet")

	GFObserverBuilder.new().set_name("sprite_draw") \
		.set_events(GFOnDraw) \
		.with(GFCanvasItem) \
		.with(GFSprite2D) \
		.with_maybe(GFSprite2D.centered) \
		.with_maybe(GFSprite2D.flip_h) \
		.with_maybe(GFSprite2D.flip_v) \
		.with_maybe(GFSprite2D.region_filter_clip) \
		.with_maybe(GFSprite2D.region) \
		.with_maybe(GFSprite2D.offset) \
		.with_maybe(GFSprite2D.frame) \
		.with_maybe(GFSprite2D.hframes) \
		.with_maybe(GFSprite2D.vframes) \
		.with_maybe(GFSprite2D.frame_coords) \
		.for_each(func(
			item: GFCanvasItem,
			socket: GFSprite2D,
			centered: GFSprite2D.centered,
			flip_h: GFSprite2D.flip_h,
			flip_v: GFSprite2D.flip_v,
			region_filter_clip: GFSprite2D.region_filter_clip,
			region: GFSprite2D.region,
			offset: GFSprite2D.offset,
			frame: GFSprite2D.frame,
			hframes: GFSprite2D.hframes,
			vframes: GFSprite2D.vframes,
			frame_coords: GFSprite2D.frame_coords,
			):
			var texture:= socket.get_texture()
			if not texture:
				return

			var ett:= socket.get_source_entity()

			# Compute source and destination rects mirroring Sprite2D::_get_rects
			var base_rect:Rect2 = region.getm("value") \
				if region != null \
				else Rect2(Vector2(), texture.get_size())

			# Frames
			var hf:int = hframes.getm("value") \
				if ett.has(GFSprite2D.hframes) \
				else 1
			var vf:int = vframes.getm("value") \
				if ett.has(GFSprite2D.vframes) \
				else 1
			
			var f:int = frame.getm("value") \
				if ett.has(GFSprite2D.frame) \
				else 0
			if frame_coords:
				var f_coords:Vector2i = frame_coords.getm("value")
				f += (f_coords.y * hf) + f_coords.x

			var frame_size: = base_rect.size / Vector2(hf, vf)
			var frame_offset: = Vector2(f % hf, f / hf) * frame_size
			frame_offset = Vector2.ZERO

			var src_rect: Rect2 = Rect2(base_rect.position + frame_offset, frame_size)

			var dest_offset:= offset.getm("value") \
				if offset != null \
				else Vector2()
			dest_offset -= frame_size / 2 \
				if centered != null \
				else Vector2()

			var dst_size := frame_size
			if flip_h:
				dst_size.x = -abs(dst_size.x)
			if flip_v:
				dst_size.y = -abs(dst_size.y)

			var dst_rect:= Rect2(dest_offset, dst_size)

			var clip_uv := region_filter_clip != null
			RenderingServer.canvas_item_add_texture_rect_region(
				item.get_rid(),
				dst_rect,
				texture.get_rid(),
				src_rect,
				Color(1, 1, 1),
				clip_uv
				)
			)

	GFObserverBuilder.new().set_name("sprite_set") \
		.set_events(OnSet) \
		.with(GFCanvasItem) \
		.with(GFSprite2D) \
		.for_each(func(item:GFCanvasItem, _1):
			queue_redraw(item)
			)
	GFObserverBuilder.new().set_name("sprite_property_add_or_set") \
		.set_events(OnSet) \
		.with(GFCanvasItem).io_filter() \
		.with(GFSprite2D).io_filter() \
		.with(GFSprite2D.centered) \
		.or_with(GFSprite2D.flip_h) \
		.or_with(GFSprite2D.flip_v) \
		.or_with(GFSprite2D.region_filter_clip) \
		.or_with(GFSprite2D.region) \
		.or_with(GFSprite2D.offset) \
		.or_with(GFSprite2D.frame) \
		.or_with(GFSprite2D.hframes) \
		.or_with(GFSprite2D.vframes) \
		.or_with(GFSprite2D.frame_coords) \
		.for_each(func(item:GFCanvasItem, _1, _2):
			queue_redraw(item)
			)
	GFObserverBuilder.new().set_name("sprite_property_remove") \
		.set_events(OnRemove) \
		.with(GFCanvasItem).io_filter() \
		.with(GFSprite2D) \
		.with(GFSprite2D.centered) \
		.or_with(GFSprite2D.flip_h) \
		.or_with(GFSprite2D.flip_v) \
		.or_with(GFSprite2D.region_filter_clip) \
		.or_with(GFSprite2D.region) \
		.or_with(GFSprite2D.offset) \
		.or_with(GFSprite2D.frame) \
		.or_with(GFSprite2D.hframes) \
		.or_with(GFSprite2D.vframes) \
		.or_with(GFSprite2D.frame_coords) \
		.for_each(func(item:GFCanvasItem, _1, _2):
			queue_redraw.call_deferred(item)
			)

static func queue_redraw(c_canvas_item:GFCanvasItem,) -> void:
	var item:RID = c_canvas_item.get_rid()
	RenderingServer.canvas_item_clear(item)
	# TODO: Add way to access GFOnDraw
	GFEntity.from(GFOnDraw, c_canvas_item.get_world()) \
		.emit(c_canvas_item.get_source_entity())
