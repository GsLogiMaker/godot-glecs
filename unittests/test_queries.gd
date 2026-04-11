
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

func test_optional_terms():
	var data:Dictionary = {ints=0, bools=0}
	var callable:= func(ints, bools):
		if ints:
			data.ints += 1
		if bools:
			data.bools += 1

	var empty:= GFEntity.new() \
		.set_name("Empty") \
		.add(Bools)
	var just_ints:= GFEntity.new() \
		.set_name("JustInts") \
		.add(Ints)
	var just_bools:= GFEntity.new() \
		.set_name("JustBools") \
		.add(Bools)
	var all:= GFEntity.new() \
		.set_name("All") \
		.add(Ints) \
		.add(Bools)

	data.ints = 0
	data.bools = 0
	GFSystemBuilder.new() \
		.with(Ints) \
		.with_maybe(Bools) \
		.for_each(callable)
	world.progress(0.0)
	assert_eq(data.ints, 2, "Expected `Ints` to be queried 2 times")
	assert_eq(data.bools, 1, "Expected `Bools` to be queried 1 times")

	data.ints = 0
	data.bools = 0
	GFSystemBuilder.new() \
		.with_maybe(Ints) \
		.with(Bools) \
		.for_each(callable)
	world.progress(0.0)
	assert_eq(data.ints, 1 + (2), "Expected `Ints` to be queried 3 times total") # Extra 2 from previous system running
	assert_eq(data.bools, 3 + (1), "Expected `Bools` to be queried 4 times total") # Extra 1 from previous system running

func test_or_operation_terms():
	var data:= {ints=0, bools=0}
	GFSystemBuilder.new() \
		.with(Bools).or_with(Ints) \
		.for_each(func(bools_or_ints:GFComponent):
			if bools_or_ints is Ints:
				data.ints += 1
			if bools_or_ints is Bools:
				data.bools += 1
			)

	GFEntity.new().add(Ints)
	GFEntity.new().add(Ints)
	GFEntity.new().add(Ints)
	GFEntity.new().add(Bools)
	GFEntity.new().add(Ints).add(Bools)

	world.progress(0.0)

	assert_eq(data.ints, 3)
	assert_eq(data.bools, 2)


func test_up_traversal():
	var par:= GFEntity.new() \
		.set_name("Parent") \
		.add(Bools)
	var child:= GFEntity.new() \
		.set_name("Child") \
		.add(Bools) \
		.add("flecs/core/ChildOf", par)

	var parent_descriptions:= GFQueryBuilder.new() \
		.with(Bools).up() \
		.with(Bools) \
		.build()

	var i:= 0
	for desc in parent_descriptions.iter():
		assert_true(desc[0].get_source_id() == par.get_id(), "Expecteded 1st item to be the parent")
		assert_true(desc[1].get_source_id() == child.get_id(), "Expecteded 2nd item to be the child")
		i += 1

	assert_eq(i, 1, "Expected query to match 1 item")


func _test_desc_traversal():
	# TODO: Implement test for desc traversal
	assert_true(false, "Unimplemnted")


func _test_cascade_traversal():
	# TODO: Implement test for cascade traversal
	assert_true(false, "Unimplemnted")


func test_with_pair():
	var data:= {ints_bools=0}

	GFEntityBuilder.new() \
		.add_pair(Ints, Bools) \
		.build()

	var query:GFQuery = GFQueryBuilder.new() \
		.with(Ints, Bools) \
		.build()

	var count:= 0
	for _x in query.iter():
		count += 1

	assert_eq(count, 1, "Expected query to find 1 entity")


func test_query_variable():
	# Setup tags and components
	var rendering:= GFEntity.new().set_name("Rendering")
	var world_e:= GFEntity.new().set_name("World")
	var world_3d:= GFComponentBuilder.new() \
		.set_name("World3D") \
		.add(world_e) \
		.add_member("origin", TYPE_VECTOR2) \
		.build()
	var world_2d:= GFEntity.new() \
		.set_name("World2D") \
		.add(world_e)

	# Setup entities to query for
	var item:= GFEntity.new() \
		.set_name("Item3D") \
		.add(rendering, world_3d)
	var item2:= GFEntity.new() \
		.set_name("Item2D") \
		.add(rendering, world_2d)

	# Run query
	var q:= GFQueryBuilder.new() \
		.with(rendering, "$world") \
		.with(world_e).from("$world") \
		.build()
	var results:= q.iter().into_array()

	assert_eq(results.size(), 2, "Expected 2 query results")
	assert_eq(
		results[0][0].get_id(),
		world.pair_ids(rendering.get_id(), world_3d.get_id()),
		"Expected " + str(results[0][0]) + " to equal "
			+ str(rendering.pair(world_3d))
	)
	assert_eq(
		results[1][0].get_id(),
		world.pair_ids(rendering.get_id(), world_2d.get_id()),
		"Expected " + str(results[1][0]) + " to equal "
			+ str(rendering.pair(world_2d))
	)

func test_src_doc_example():
	var Velocity = GFComponentBuilder.new() \
		.add_member("velocity", TYPE_VECTOR2) \
		.build()
	var ship = GFEntity.new() \
		.add(Velocity)
	var asteroid = GFEntity.new() \
		.add(Velocity)

	# Query only for Velocity of the ship, not the asteroid
	var query = GFQueryBuilder.new() \
		.with(Velocity).from(ship) \
		.build()

	var arr = query.iter().into_array()
	assert_eq(arr.size(), 1)

	var velocity_c:GFComponent = arr[0][0]
	assert_eq(velocity_c.get_id(), Velocity.get_id())
	assert_eq(velocity_c.get_source_id(), ship.get_id())


func test_query_source():
	var ChildOf = GFWorld.get_default_world().lookup("/root/flecs/core/ChildOf")

	var p1:= GFEntity.new()
	p1.set_name("WithBools")
	p1.add(Bools)
	var c1:= GFEntity.new()
	p1.add_child(c1)
	var p2:= GFEntity.new()
	p2.set_name("WithoutBools")
	p2.add_child(GFEntity.new())

	var builder:= GFQueryBuilder.new()
	builder.with(ChildOf, "$par")
	builder.with(Bools).src("$par")
	var query:GFQuery = builder.build()

	var results = query.iter().into_array()
	assert_eq(results.size(), 1)

	var bools_c:GFComponent = results[0][1]
	assert_eq(bools_c.get_source_entity().get_name(), "WithBools")

#endregion

#region Components

class Bools extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void:
		b_.add_member("a", TYPE_BOOL)
		b_.add_member("b", TYPE_BOOL)
		b_.set_name("Bools")
	var a:bool:
		get: return getm(&"a")
		set(v): setm(&"a", v)
	var b:bool:
		get: return getm(&"b")
		set(v): setm(&"b", v)

class Ints extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void:
		b_.add_member("a", TYPE_INT)
		b_.add_member("b", TYPE_INT)
		b_.set_name("Ints")
	var a:int:
		get: return getm(&"a")
		set(v): setm(&"a", v)
	var b:int:
		get: return getm(&"b")
		set(v): setm(&"b", v)

#endregion
