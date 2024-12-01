
extends GutTest

var world:GFWorld

func before_each():
	world = GFWorld.new()

func after_each():
	world.free()

#region Tests

func test_add_and_set_pairs() -> void:
	var eats:= GFEntity.spawn(world).set_name("Eats")
	var grass:= GFEntity.spawn(world).set_name("Grass")
	
	var e:= GFEntity.spawn(world)
	
	e.add_pair("Eats", GFRotation2D, 3.0)
	assert_almost_eq(
		e.get_component(eats.pair(GFRotation2D)).get_angle(),
		3.0,
		0.01,
	)
	
	e.set_pair(eats, GFRotation2D, 1.5)
	e.add_pair(GFRotation2D, eats, 1.1)
	
	assert_almost_eq(
		e.get_pair(eats, GFRotation2D).get_angle(),
		1.5,
		0.01,
	)
	assert_almost_eq(
		e.get_pair(GFRotation2D, eats).get_angle(),
		1.1,
		0.01,
	)

func test_basic_query():
	var eats:= GFEntity.spawn(world) \
		.set_name("Eats")
	var apple:= GFEntity.spawn(world) \
		.set_name("Apple")
	var grass:= GFEntity.spawn(world) \
		.set_name("Grass")
	var man:= GFEntity.spawn(world) \
		.set_name("Man") \
		.add_pair("Eats", apple)
	var cow:= GFEntity.spawn(world) \
		.set_name("Cow") \
		.add_pair("Eats", grass)

	var grass_eater_iter:= world.query_builder() \
		.with(eats.pair(grass)) \
		.build() as GFQuery
	var grass_eater_count:= 0
	for _x in grass_eater_iter.iterate():
		grass_eater_count += 1
	assert_eq(grass_eater_count, 1)
	
	var eater_iter:= world.query_builder() \
		.with(eats.pair("flecs/core/*")) \
		.build() as GFQuery
	var eater_count:= 0
	for _x in eater_iter.iterate():
		eater_count += 1
	assert_eq(eater_count, 2)

func test_is_pair():
	var likes = GFEntity.spawn(world).set_name("Likes")
	var jill = GFEntity.spawn(world).set_name("Jill")
	var likes_jill = likes.pair(jill)
	
	assert_true(likes_jill.is_pair())

#endregion

#region Components

class Bools extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void:
		b_.add_member("a", TYPE_BOOL)
		b_.add_member("b", TYPE_BOOL)

#endregion
