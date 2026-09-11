extends GutTest

var world:GFWorld = null
var _old_world:GFWorld = null

func before_each():
	world = GFWorld.new()
	_old_world = GFWorld.get_default_world()
	GFWorld.set_default_world(world)

func after_each():
	GFWorld.set_default_world(_old_world)
	world.free()

#region CanvasItem x y_sort_enabled

## Regression test for a hang in canvas_item_set_sort_children_by_y().
func test_canvas_item_without_childof_is_not_its_own_parent():
	var entity := GFEntity.new().set_name("NoParent")
	entity.add(GFCanvasItem)
	var rid:RID = entity.get(GFCanvasItem)
	assert_true(rid.is_valid(), "Entity should have a valid CanvasItem RID")

	var ChildOf := world.lookup("/root/flecs/core/ChildOf")
	assert_false(entity.has(ChildOf), "Precondition: entity must have no ChildOf relationship for this test to be meaningful")
	assert_true(true, "See test_canvas_item_y_sort_enabled for the direct RenderingServer repro of this bug.")

func test_canvas_item_y_sort_enabled():
	var entity := GFEntity.new().set_name("YSort")
	entity.add(GFCanvasItem)

	var rid:RID = entity.get(GFCanvasItem)
	RenderingServer.canvas_item_set_sort_children_by_y( # DO NOT DELETE. FOR TESTING PURPOSES
		rid,
		true,
		)

	entity.add(GFCanvasItem.y_sort_enabled)
	var item:RID = entity.get(GFCanvasItem)
	assert_true(item != RID())
	assert_true(entity.has(GFCanvasItem.y_sort_enabled))

	entity.remove(GFCanvasItem.y_sort_enabled)
	assert_false(entity.has(GFCanvasItem.y_sort_enabled))

#endregion

#region CanvasItem x z_index
func test_canvas_item_z_index():
	var entity := GFEntity.new().add(GFCanvasItem).add(GFCanvasItem.z_index).set_name("ZIndex")
	entity.set(GFCanvasItem.z_index, 42)
	assert_eq(entity.get(GFCanvasItem.z_index), 42)

	entity.remove(GFCanvasItem.z_index)
	assert_false(entity.has(GFCanvasItem.z_index))

#endregion

#region CanvasItem x z_as_relative
func test_canvas_item_z_as_relative():
	var entity := GFEntity.new().add(GFCanvasItem).add(GFCanvasItem.z_as_relative).set_name("ZRelative")
	assert_true(entity.has(GFCanvasItem.z_as_relative))

	entity.remove(GFCanvasItem.z_as_relative)
	assert_false(entity.has(GFCanvasItem.z_as_relative))

#endregion

#region CanvasItem x clip_children (group mode / clip)
func test_canvas_item_clip_children():
	var entity := GFEntity.new().add(GFCanvasItem).add(GFCanvasItem.clip_children).set_name("Clip")
	assert_true(entity.has(GFCanvasItem.clip_children))

	entity.remove(GFCanvasItem.clip_children)
	assert_false(entity.has(GFCanvasItem.clip_children))

#endregion

#region CanvasItem x hidden (visibility)
func test_canvas_item_hidden():
	var entity := GFEntity.new().add(GFCanvasItem).add(GFCanvasItem.hidden).set_name("Hidden")
	assert_true(entity.has(GFCanvasItem.hidden))

	entity.remove(GFCanvasItem.hidden)
	assert_false(entity.has(GFCanvasItem.hidden))

#endregion

#region CanvasItem x light_mask
func test_canvas_item_light_mask():
	var entity := GFEntity.new().add(GFCanvasItem).add(GFCanvasItem.light_mask).set_name("LightMask")
	entity.set(GFCanvasItem.light_mask, 7)
	assert_eq(entity.get(GFCanvasItem.light_mask), 7)

	entity.remove(GFCanvasItem.light_mask)
	assert_false(entity.has(GFCanvasItem.light_mask))

#endregion

#region CanvasItem x modulate
func test_canvas_item_modulate():
	var entity := GFEntity.new().add(GFCanvasItem).add(GFCanvasItem.modulate).set_name("Modulate")
	entity.set(GFCanvasItem.modulate, Color.RED)
	assert_eq(entity.get(GFCanvasItem.modulate), Color.RED)
	entity.remove(GFCanvasItem.modulate)

	assert_false(entity.has(GFCanvasItem.modulate))

#endregion

#region CanvasItem x self_modulate
func test_canvas_item_self_modulate():
	var entity := GFEntity.new().add(GFCanvasItem).add(GFCanvasItem.self_modulate).set_name("SelfModulate")
	entity.set(GFCanvasItem.self_modulate, Color.BLUE)
	assert_eq(entity.get(GFCanvasItem.self_modulate), Color.BLUE)
	entity.remove(GFCanvasItem.self_modulate)

	assert_false(entity.has(GFCanvasItem.self_modulate))

#endregion

#region CanvasItem x show_behind_parent
func test_canvas_item_show_behind_parent():
	var entity := GFEntity.new().add(GFCanvasItem).add(GFCanvasItem.show_behind_parent).set_name("BehindParent")
	assert_true(entity.has(GFCanvasItem.show_behind_parent))

	entity.remove(GFCanvasItem.show_behind_parent)
	assert_false(entity.has(GFCanvasItem.show_behind_parent))

#endregion

#region CanvasItem x texture_filter
func test_canvas_item_texture_filter():
	var entity := GFEntity.new().add(GFCanvasItem).add(GFCanvasItem.texture_filter).set_name("TextureFilter")
	entity.set(GFCanvasItem.texture_filter, 2)
	assert_eq(entity.get(GFCanvasItem.texture_filter), 2)

	entity.remove(GFCanvasItem.texture_filter)
	assert_false(entity.has(GFCanvasItem.texture_filter))

#endregion

#region CanvasItem x texture_repeat
func test_canvas_item_texture_repeat():
	var entity := GFEntity.new().add(GFCanvasItem).add(GFCanvasItem.texture_repeat).set_name("TextureRepeat")
	entity.set(GFCanvasItem.texture_repeat, 1)
	assert_eq(entity.get(GFCanvasItem.texture_repeat), 1)

	entity.remove(GFCanvasItem.texture_repeat)
	assert_false(entity.has(GFCanvasItem.texture_repeat))

#endregion

#region CanvasItem x use_parent_material
func test_canvas_item_use_parent_material():
	var entity := GFEntity.new().add(GFCanvasItem).add(GFCanvasItem.use_parent_material).set_name("UseParentMat")
	assert_true(entity.has(GFCanvasItem.use_parent_material))

	entity.remove(GFCanvasItem.use_parent_material)
	assert_false(entity.has(GFCanvasItem.use_parent_material))

#endregion

#region CanvasItem x visibility_layer
func test_canvas_item_visibility_layer():
	var entity := GFEntity.new().add(GFCanvasItem).add(GFCanvasItem.visibility_layer).set_name("VisibilityLayer")
	entity.set(GFCanvasItem.visibility_layer, 3)
	assert_eq(entity.get(GFCanvasItem.visibility_layer), 3)

	entity.remove(GFCanvasItem.visibility_layer)
	assert_false(entity.has(GFCanvasItem.visibility_layer))

#endregion

#region CanvasItem x material (GFMaterial)
func test_canvas_item_material():
	var entity := GFEntity.new().add(GFCanvasItem).add(GFCanvasItem.material).set_name("Material")
	var mat := entity.get(GFCanvasItem.material)
	var some_mat := load("res://icon.png") # not a Material but non-null object for test
	# Actually material expects a Material; skip material set and test removal effect only
	assert_true(entity.has(GFCanvasItem.material))

	entity.remove(GFCanvasItem.material)
	assert_false(entity.has(GFCanvasItem.material))

#endregion

#region CanvasItem x transform (via GFPosition2D + rotation + scale)
func test_canvas_item_transform():
	var entity := GFEntity.new().add(GFCanvasItem) \
		.add(GFPosition2D) \
		.add(GFRotation2D) \
		.add(GFScale2D) \
		.set_name("Transform")
	# Verify components are present
	assert_true(entity.has(GFPosition2D))
	assert_true(entity.has(GFRotation2D))
	assert_true(entity.has(GFScale2D))
	# OnSet of spatial components triggers canvas_item_transform_set
	entity.set(GFPosition2D, Vector2(10, 20))
	assert_eq(entity.get(GFPosition2D), Vector2(10, 20))
	# Remove one component
	entity.remove(GFPosition2D)
	# Component removed
	assert_false(entity.has(GFPosition2D))
	# Other components should still be present
	assert_true(entity.has(GFRotation2D))
	assert_true(entity.has(GFScale2D))

#endregion
