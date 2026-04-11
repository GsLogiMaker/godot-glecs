
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

func test_component_get_and_set():
	var e:GFEntity = GFEntity.new()
	e.add(Foo)
	e.set_name("Test")

	var x = e.get(Foo)

	assert_almost_eq(e.get(Foo), 0.0, 0.01)

	e.set(Foo, 2.3)
	assert_almost_eq(e.get(Foo), 2.3, 0.01)

	e.delete()

func test_component_string_get_and_set():
	var e:= GFEntity.new() \
		.add(Stringy) \
		.set_name("Test")

	var foo:Stringy = e.get(Stringy)
	foo.a = "po"
	foo.b = "em"
	assert_eq(foo.a, "po")

	foo.a += foo.b

	assert_eq(foo.a, "poem")
	assert_eq(foo.b, "em")

func test_new_entity_with_unregistered_component():
	var e:GFEntity = GFEntity.new() \
		.add(Unregistered) \
		.set_name("Test")
	assert_eq(e.get(Unregistered), 0)

func test_creating_entity_by_new():
	# Test that an entity is invalidated by being deleted
	var e:= GFEntity.new()
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
		var tmp_entity = GFEntity.new()
		tmp_entity.set_name(&"Cool Name")
		id = tmp_entity.get_id()
	assert_ne(id, 0)

	var e:= GFEntity.from(id, world)
	assert_ne(e, null)
	assert_eq(e.get_name(), &"Cool Name")

func test_entity_created_in_singleton():
	var e:= GFEntity.new()
	assert_eq(e.is_alive(), true)

	var e2:= GFEntity.new_in_world(GFWorld.get_singleton())
	assert_eq(e2.is_alive(), true)

	assert_ne(world, GFWorld.get_singleton(), "Expected world not to be the global one")
	assert_eq(e.get_world(), world, "Expected e1 to be created in local thread world")
	assert_eq(e2.get_world(), GFWorld.get_singleton(), "Expected e2 to be created in global world")

	e.delete()
	e2.delete()

func test_builder():
	var e:= GFEntityBuilder.new() \
		.set_name("Built") \
		.add(Foo) \
		.add(Foo, Stringy) \
		.add(Stringy, Foo) \
		.build()

	assert_eq(e.get_name(), "Built", "Expected entity to be named 'Built'")

	var query:GFQuery = GFQueryBuilder.new() \
		.with(Foo) \
		.with(world.pair(Foo, Stringy)) \
		.with(world.pair(Stringy, Foo)) \
		.build()

	var i:= 0
	for _x in query.iter():
		i += 1

	assert_eq(i, 1, "Expected query to find the built entity")


func test_add_get_child():
	var child:= GFEntity.new().set_name("Child")
	var par:= GFEntity.new() \
		.set_name("Parent") \
		.add_child(child)

	assert_eq(
		child.get_id(),
		par.get_child("Child").get_id(),
		"Expected to find `Child` as a child of `Parent`",
	)


func test_set_get_parent():
	var child:= GFEntity.new() \
		.set_name("Child") \
		.set_parent(
			GFEntity.new().set_name("Parent")
		)

	assert_eq(
		child.get_parent().get_name(),
		"Parent",
		"Expected to find `Child` as a child of `Parent`"
	)


func test_has_child():
	var flecs:= GFEntity.from("flecs", world)
	assert_true(
		flecs.has_child("core"),
		"Expected `flecs` module to have a child named `core`"
	)
	assert_true(
		flecs.has_child("core/OnAdd"),
		"Expected `flecs` module to have a grandchild named `core/OnAdd`"
	)


func test_iter_children():
	var parent:= GFEntity.new() \
		.add_child(GFEntity.new()
			.set_name("George")
		) \
		.add_child(GFEntity.new()
			.set_name("Riley")
		)

	var child_count:= 0
	var has_george:= false
	var has_riley:= false
	for child in parent.iter_children():
		has_george = has_george or child.get_name() == "George"
		has_riley = has_riley or child.get_name() == "Riley"
		child_count += 1

	assert_eq(child_count, 2, "Expected to iterate over 2 children")
	assert_true(has_george, "Expected to iterate over the entity named George")
	assert_true(has_riley, "Expected to iterate over the entity named Riley")

func test_get_children():
	var parent:= GFEntity.new() \
		.add_child(GFEntity.new()
			.set_name("George")
		) \
		.add_child(GFEntity.new()
			.set_name("Riley")
		)

	var children = parent.get_children()
	var has_george:= false
	var has_riley:= false
	for child in children:
		has_george = has_george or child.get_name() == "George"
		has_riley = has_riley or child.get_name() == "Riley"

	assert_eq(children.size(), 2, "Expected to array to have 2 children")
	assert_true(has_george, "Expected to array to have the entity named George")
	assert_true(has_riley, "Expected to array to have the entity named Riley")

func test_remove():
	var e:= GFEntity.new() \
		.set_name("RemovingFrom") \
		.set(Foo, 2.24) \
		.setp(Foo, Stringy, 234.1)

	assert_true(e.has(Foo), "Expected RemovingFrom to have (Foo, Stringy)")
	assert_almost_eq(e.get(Foo), 2.24, 0.01)
	assert_true(e.has(Foo, Stringy), "Expected RemovingFrom to have (Foo, Stringy)")
	assert_almost_eq(e.get(Foo, Stringy), 234.1, 0.01)

	e.remove(Foo)
	e.remove(Foo, Stringy)

	assert_false(e.has(Foo))
	assert_false(e.has(Foo, Stringy))

func test_add_sibling():
	var par:= GFEntity.new()
	var bill:= GFEntity.new() \
		.set_name("Bill") \
		.set_parent(par) \
		.add_sibling(GFEntity.new()
			.set_name("Bob")
		)

	assert_true(par.has_child("Bill"), "Expected parent to have have child named Bill")
	assert_true(par.has_child("Bob"), "Expected parent to have have child named Bob")

func test_inheritance():
	var ship_pfb:= GFEntityBuilder.new() \
		.add("flecs/core/Prefab") \
		.add(GFPosition2D) \
		.build() \
		.set(GFPosition2D, Vector2(2, 3))

	assert_true(
		ship_pfb.has(GFPosition2D),
		"Expected `ship_pfb` to have position"
	)
	assert_almost_eq(
		ship_pfb.get(GFPosition2D),
		Vector2(2, 3),
		Vector2(0.01, 0.01),
		"Expected position in `ship_pfb` to have been set",
	)

	var e:= GFEntity.new()
	assert_false(
		e.is_inheriting(ship_pfb),
		"Expected `e` to NOT inheret `ship_pfb` yet",
	)
	assert_false(
		e.has(GFPosition2D),
		"Expected `e` to NOT have position yet",
	)

	e.inherit(ship_pfb)

	assert_true(
		e.is_inheriting(ship_pfb),
		"Expected `e` to have inherited `ship_pfb`",
	)
	assert_true(
		e.has(GFPosition2D),
		"Expected `e` to have inherited position from `ship_pfb`",
	)

	e.set(GFPosition2D, Vector2(5, 4))

	assert_almost_eq(
		e.get(GFPosition2D),
		Vector2(5, 4),
		Vector2(0.01, 0.01),
		"Expected position in `e` to have been set",
	)
	assert_almost_ne(
		e.get(GFPosition2D),
		ship_pfb.get(GFPosition2D),
		Vector2(0.01, 0.01),
		"Expected position in `e` to differ from position in `ship_pfb`",
	)

func test_inheritance_doc_example():
	var health = GFEntity.new()
	var spaceship = GFEntity.new()
	spaceship.add("flecs/core/Prefab")
	spaceship.add(health)

	var enterprise = GFEntity.new()
	enterprise.inherit(spaceship)

	assert_true(enterprise.is_inheriting(spaceship)) # true
	assert_true(enterprise.has(health)) # true

func test_get_target_for():
	var enterprise:= GFEntity.new() \
		.set_name("Enterprise") \
		.add(GFPosition2D, GFScale2D) \
		.add(GFPosition2D, GFRotation2D)

	var targets:= []
	var i:= 0
	while true:
		var target:= enterprise.get_target_for(GFPosition2D, i)
		if target:
			targets.append(target.get_id())
		else:
			break
		i += 1

	assert_true(
		world.coerce_id(GFRotation2D) in targets,
		"Expected Enterprise to have a position pair with a rotation target",
	)
	assert_true(
		world.coerce_id(GFScale2D) in targets,
		"Expected Enterprise to have a position pair with a scale",
	)
	assert_eq(
		targets.size(),
		2,
		"Expected Enterprise to have two position pairs",
	)

func test_is_owner_of():
	world.start_rest_api()

	var isa:= world.coerce_id("flecs/core/IsA")
	var inherit:= world.pair("flecs/core/OnInstantiate", "flecs/core/Inherit")

	var pos:= GFComponentBuilder.new() \
		.set_name("Pos") \
		.add(inherit) \
		.add_member("_", TYPE_INT) \
		.build()
	var rot:= GFComponentBuilder.new() \
		.set_name("Rot") \
		.add_member("_", TYPE_INT) \
		.build()
	var scl:= GFComponentBuilder.new() \
		.set_name("Scl") \
		.add_member("_", TYPE_INT) \
		.build()

	var spaceship:= GFEntity.new() \
		.set_name("Spaceship") \
		.add("flecs/core/Prefab") \
		.add(pos) \
		.add(rot)

	var enterprise:= GFEntity.new() \
		.set_name("Enterprise") \
		.inherit(spaceship) \
		.add(scl)
	var voyager:= GFEntity.new() \
		.set_name("Voyager") \
		.inherit(spaceship) \
		.add(pos)

	assert_false(enterprise.is_owner_of(pos), "Expected position to be owned by spaceship, not enterprise")
	assert_true(enterprise.is_owner_of(rot), "Expected rotation to be owned by enterprise")
	assert_true(enterprise.is_owner_of(scl), "Expected rotation to be owned by enterprise")

	assert_true(voyager.is_owner_of(pos), "Expected position to be owned by voyager")
	assert_true(voyager.is_owner_of(rot), "Expected rotation to be owned by voyager")

	enterprise.remove(isa, spaceship)
	voyager.remove(isa, spaceship)

	assert_false(enterprise.has(isa, spaceship), "Expected isa pair to have been removed from enterprise")
	assert_false(voyager.has(isa, spaceship), "Expected isa pair to have been removed from voyager")

	assert_false(enterprise.has(pos), "Expected pos to have been removed from enterprise")
	assert_true(enterprise.has(rot), "Expected enterprise to have rot")
	assert_true(voyager.has(pos), "Expected voyager to have pos")
	assert_true(voyager.has(rot), "Expected voyager to have rot")

func test_clear():
	var tag:= GFEntity.new().set_name("tag")

	var e:= GFEntity.new() \
		.set_name("Entity") \
		.add(tag)

	assert_true(e.has(tag))

	e.clear()

	assert_false(e.has(tag))

func test_set_name():
	# Entities should get a unique name when
	# their name is explicitely set.
	var e1:= GFEntity.new().set_name("E1")
	var e2:= GFEntity.new().set_name("E1")
	var e3:= GFEntity.new().set_name("E1")
	assert_eq(e1.get_name(), "E1")
	assert_eq(e2.get_name(), "E2")
	assert_eq(e3.get_name(), "E3")

	# Entities should make get a unique name
	# when moved to a parent.
	var parent:= GFEntity.new()
	var child_1:= GFEntity.new() \
		.set_name("Child") \
		.set_parent(parent)

	var child_2:= GFEntity.new()
	child_2.set_name("Child")
	child_2.set_parent(parent)

	assert_eq(child_1.get_name(), "Child")
	assert_eq(child_2.get_name(), "Child1")

#endregion

#region Classes

class Foo extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void: b_ \
		.set_name("Foo") \
		.add_member("value", TYPE_FLOAT)

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
