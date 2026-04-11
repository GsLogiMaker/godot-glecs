
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

#region Tests

func test_add_and_set_pairs() -> void:
	var eats:= GFEntity.new().set_name("Eats")
	var grass:= GFEntity.new().set_name("Grass")

	var e:= GFEntity.new()

	e.add_pair("Eats", GFRotation2D, 3.0)
	assert_almost_eq(
		e.get(eats.pair(GFRotation2D)),
		3.0,
		0.01,
	)

	e.set_pair(eats, GFRotation2D, 3000)
	e.add_pair(GFRotation2D, eats, 1.1)

	assert_almost_eq(
		e.get(eats, GFRotation2D),
		3000.0,
		0.01,
	)
	assert_almost_eq(
		e.get(GFRotation2D, eats),
		1.1,
		0.01,
	)

func test_basic_query():
	var eats:= GFEntity.new() \
		.set_name("Eats")
	var apple:= GFEntity.new() \
		.set_name("Apple")
	var grass:= GFEntity.new() \
		.set_name("Grass")
	var man:= GFEntity.new() \
		.set_name("Man") \
		.add_pair("Eats", apple)
	var cow:= GFEntity.new() \
		.set_name("Cow") \
		.add_pair("Eats", grass)

	var grass_eater_iter:= GFQueryBuilder \
		.new() \
		.with(eats.pair(grass)) \
		.build() as GFQuery
	var grass_eater_count:= 0
	for _x in grass_eater_iter.iter():
		grass_eater_count += 1
	assert_eq(grass_eater_count, 1)

	var eater_iter:= GFQueryBuilder \
		.new() \
		.with(eats.pair("flecs/core/*")) \
		.build() as GFQuery
	var eater_count:= 0
	for _x in eater_iter.iter():
		eater_count += 1
	assert_eq(eater_count, 2)

func test_is_pair():
	var likes = GFEntity.new().set_name("Likes")
	var jill = GFEntity.new().set_name("Jill")
	var likes_jill = likes.pair(jill)

	assert_true(likes_jill.is_pair())

#endregion

#region Components

class Bools extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void:
		b_.add_member("a", TYPE_BOOL)
		b_.add_member("b", TYPE_BOOL)

#endregion
