
extends GutTest

const TEXTURE:= preload("res://icon.png")

var world:GFWorld = null

func before_each():
	world = GFWorld.new()

func after_each():
	world.free()

#region Tests

func test_rendering_texture():
	var e:= GFEntity.spawn(world) \
		.add_component(GFTexture2D, TEXTURE) \
		.add_component(GFCanvasItem)

	var draw_rect:= RenderingServer.debug_canvas_item_get_rect(
		e.get_component(GFCanvasItem).get_rid()
	)
	# This assert catches if the canvas item of the entity has a display size,
	# but not if it is actually rendering properly. It will still pass
	# if the parent is not setup correctly, causing the canvas item not to
	# render.
	assert_eq(draw_rect, Rect2(-(TEXTURE.get_size()/2), TEXTURE.get_size()))

#endregion
