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

func test_sprite2d_component_lifecycle():
	var entity := GFEntity.new().set_name("Sprite")
	entity.add(GFSprite2D)

	# Tags
	entity.add(GFSprite2D.centered)
	entity.add(GFSprite2D.flip_h)
	entity.add(GFSprite2D.flip_v)
	entity.add(GFSprite2D.region_filter_clip_enabled)

	assert_true(entity.has(GFSprite2D.centered))
	assert_true(entity.has(GFSprite2D.flip_h))
	assert_true(entity.has(GFSprite2D.flip_v))

	# Component with member: offset
	entity.add(GFSprite2D.offset)
	assert_true(entity.has(GFSprite2D.offset))
	var offset_c := entity.get(GFSprite2D.offset)
	offset_c.set(GFSprite2D.offset, Vector2(10, 20))
	assert_eq(entity.get(GFSprite2D.offset).get(GFSprite2D.offset), Vector2(10, 20))

	# Component with member: region
	entity.add(GFSprite2D.region)
	var region_c := entity.get(GFSprite2D.region)
	region_c.set(GFSprite2D.region, Rect2(5, 5, 32, 32))

	# Component removal
	entity.remove(GFSprite2D.offset)
	assert_false(entity.has(GFSprite2D.offset))

	entity.remove(GFSprite2D.region)
	assert_false(entity.has(GFSprite2D.region))

	# Tag removal
	entity.remove(GFSprite2D.centered)
	assert_false(entity.has(GFSprite2D.centered))

	entity.delete()
	assert_false(entity.is_alive())
