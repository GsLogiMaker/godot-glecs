
extends GutTest

var world:GFWorld = null

func before_all():
	world = GFWorld.new()

func after_all():
	world.free()

#region Tests

func test_component_get_and_set():
	var e:GFEntity = GFEntity.new_in_world(world) \
		.add_component(Foo) \
		.set_name("Test")

	var foo:Foo = e.get_component(Foo)
	assert_almost_eq(foo.value, 0.0, 0.01)

	foo.value = 2.3
	assert_almost_eq(foo.value, 2.3, 0.01)

	e.delete()

func test_component_string_get_and_set():
	var e:= GFEntity.new_in_world(world) \
		.add_component(Stringy) \
		.set_name("Test")

	var foo:Stringy = e.get_component(Stringy)
	foo.a = "po"
	foo.b = "em"
	assert_eq(foo.a, "po")

	foo.a += foo.b

	assert_eq(foo.a, "poem")
	assert_eq(foo.b, "em")

func test_new_entity_with_unregistered_component():
	var e:GFEntity = GFEntity.new_in_world(world) \
		.add_component(Unregistered) \
		.set_name("Test")
	assert_eq(e.get_component(Unregistered).value, 0)

func test_creating_entity_by_new():
	# Test that an entity is invalidated by being deleted
	var e:= GFEntity.new_in_world(world)
	assert_eq(e.is_alive(), true)
	e.delete()
	assert_eq(e.is_alive(), false)

	# Test that an entity is invalidated by its world being deleted
	var w:= GFWorld.new()
	var e2:= GFEntity.new_in_world(w)
	assert_eq(e2.is_alive(), true)
	w.free()
	assert_eq(e2.is_alive(), false)

func test_entity_from():
	var id:= 0
	if true:
		var tmp_entity = GFEntity.new_in_world(world)
		tmp_entity.set_name(&"Cool Name")
		id = tmp_entity.get_id()
	assert_ne(id, 0)

	var e:= GFEntity.from(id, world)
	assert_ne(e, null)
	assert_eq(e.get_name(), &"Cool Name")

func test_entity_created_in_singleton():
	var e:= GFEntity.new()
	assert_eq(e.is_alive(), true)

	var e2:= GFEntity.new_in_world(GFGlobalWorld)
	assert_eq(e2.is_alive(), true)

	assert_eq(e.get_world(), e2.get_world())

	e.delete()
	e2.delete()

func test_builder():
	var e:= GFEntityBuilder.new_in_world(world) \
		.set_name("Built") \
		.add_entity(Foo) \
		.add_pair(Foo, Stringy) \
		.add_pair(Stringy, Foo) \
		.build()
	
	assert_eq(e.get_name(), "Built", "Expected entity to be named 'Built'")
	
	var query:GFQuery = GFQueryBuilder.new_in_world(world) \
		.with(Foo) \
		.with(world.pair(Foo, Stringy)) \
		.with(world.pair(Stringy, Foo)) \
		.build()
	
	var i:= 0
	for _x in query.iterate():
		i += 1
	
	assert_eq(i, 1, "Expected query to find the built entity")


func test_add_get_child():
	var child:= GFEntity.new_in_world(world).set_name("Child")
	var par:= GFEntity.new_in_world(world) \
		.set_name("Parent") \
		.add_child(child)
	
	assert_eq(
		child.get_id(),
		par.get_child("Child").get_id(),
		"Expected to find `Child` as a child of `Parent`",
	)


func test_set_get_parent():
	var child:= GFEntity.new_in_world(world) \
		.set_name("Child") \
		.set_parent(
			GFEntity.new_in_world(world).set_name("Parent")
		)
	
	assert_eq(
		child.get_parent().get_name(),
		"Parent",
		"Expected to find `Child` as a child of `Parent`"
	)

#endregion

#region Classes

class Foo extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void: b_ \
		.set_name("Foo") \
		.add_member("value", TYPE_FLOAT)
	var value:float:
		get: return getm(&"value")
		set(v): setm(&"value", v)

class Stringy extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void: b_ \
		.set_name("Stringy") \
		.add_member("a", TYPE_STRING) \
		.add_member("b", TYPE_STRING)
	var a:String:
		get: return getm(&"a")
		set(v): setm(&"a", v)
	var b:String:
		get: return getm(&"b")
		set(v): setm(&"b", v)

class Unadded extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void: b_ \
		.set_name("Unadded") \
		.add_member("value", TYPE_INT)
	var value:int:
		get: return getm(&"value")
		set(v): setm(&"value", v)

class Unregistered extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void: b_ \
		.set_name("Unregistered") \
		.add_member("value", TYPE_INT)
	var value:int:
		get: return getm(&"value")
		set(v): setm(&"value", v)

#endregion
