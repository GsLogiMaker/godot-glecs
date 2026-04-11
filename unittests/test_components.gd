
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


func test_add_entity():
	var _entity:= GFEntity.new()

	# Can't assert, but should be fine as long as it doesn't crash
	assert_null(null)


func test_world_deletion():
	var w:= GFWorld.new()

	var e:= GFEntity.new_in_world(w) \
		.add(Foo) \
		.set_name("Test")
	var foo:= e.get(Foo)
	assert_eq(e.get_world(), w)

	var e2:= GFEntity.new_in_world(w) \
		.add(Foo) \
		.set_name("Test")
	var foo2:= e2.get(Foo)
	assert_eq(e2.get_world(), w)

	foo.set_value(Vector2(24.3, 2.1))
	foo2.set_value(Vector2(125.1, 3.3))

	e2.delete()
	assert_eq(e2.is_alive(), false)
	assert_eq(foo2.is_alive(), false)

	foo.delete()
	assert_eq(e.is_alive(), true)
	assert_eq(foo.is_alive(), false)

	w.free()
	assert_eq(is_instance_valid(w), false)
	assert_eq(e.is_alive(), false)
	assert_eq(foo.is_alive(), false)


func test_registration():
	var e:= GFEntity.new() \
		.add(RegistrationA) \
		.add(RegistrationB) \
		.set_name("Test")

	e.get(RegistrationA).set_value(3)
	e.get(RegistrationB).set_value(11)

	# A system defined in RegistrationA's _registered function should run
	# on GFWorld's process pipeline
	world.progress(0.0)

	assert_almost_eq(e.get(RegistrationA).get_result(), 14.0, .001)
	assert_almost_eq(e.get(RegistrationB).get_result(), 33.0, .001)


func test_simple_system():
	GFSystemBuilder.new() \
		.with(Foo) \
		.for_each(func(foo):
			foo.set_value(Vector2(2, 5))
			)

	var entity:= GFEntity.new() \
		.add(Foo) \
		.set_name("Test")

	world.progress(0.0)

	assert_eq(entity.get(Foo).get_value(), Vector2(2, 5))


# test components components_in_relationships
func test_components_in_relationships():
	var w:= GFWorld.new()

	var e:= GFEntity.new_in_world(w)
	var foo:Foo = e.add_pair(Targets, Foo) \
		.get(w.pair(Targets, Foo))

	foo.set_value(Vector2(54, 6))
	assert_almost_eq(foo.get_value(), Vector2(54, 6), Vector2(.001, .001))

	foo = e.get(w.pair(Targets, Foo))
	assert_almost_eq(foo.get_value(), Vector2(54, 6), Vector2(.001, .001))

	w.free()


func test_setm_no_notify():
	var e:= GFEntity.new() \
		.add(Foo)

	var data:= {i = 0}
	GFObserverBuilder.new() \
		.set_events("/root/flecs/core/OnSet") \
		.with(Foo) \
		.for_each(func(c): data.i += 1)

	var foo:Foo = e.get(Foo)
	foo.setm_no_notify("value", Vector2(23, 17))
	assert_eq(foo.getm("value"), Vector2(23, 17))
	assert_eq(data.i, 0)

	foo.setm("value", Vector2.ONE)
	assert_eq(foo.getm("value"), Vector2.ONE)
	assert_eq(data.i, 1)


func test_primitive():
	var Int:= world.lookup("/root/glecs/meta/int")
	var array:= world.lookup("/root/glecs/meta/Array")
	
	var e:= GFEntity.new()
	e.add(Int)
	e.set(Int, 25)
	assert_eq(e.get(Int), 25)
	
	e.add(array)
	e.set(array, [2, 3])
	var arr = e.get(array)
	assert_eq(arr.size(), 2)
	assert_eq(arr[0], 2)
	assert_eq(arr[1], 3)


class Targets extends GFRegisterableEntity: pass


class Foo extends GFComponent:
	func _build(b: GFComponentBuilder) -> void:
		b.add_member("value", TYPE_VECTOR2)
		b.add_member("_", TYPE_VECTOR2)

	func get_value() -> Vector2:
		return getm(&"value")

	func set_value(v:Vector2) -> void:
		setm(&"value", v)


class WithDefaults extends GFComponent:
	func _build(b: GFComponentBuilder) -> void:
		b.add_member("int", TYPE_INT)
		b.add_member("string", TYPE_STRING)
		b.add_member("script", TYPE_OBJECT)

	func get_int() -> int:
		return getm(&"int")
	func get_string() -> String:
		return getm(&"string")
	func get_script_2() -> Script:
		return getm(&"script")


class RegistrationA extends GFComponent:
	func _build(b: GFComponentBuilder) -> void:
		b.add_member("value", TYPE_FLOAT)
		b.add_member("result", TYPE_FLOAT)

	func get_value() -> float:
		return getm(&"value")
	func set_value(v:float) -> void:
		setm(&"value", v)
	func get_result() -> float:
		return getm(&"result")
	func set_result(v:float) -> void:
		setm(&"result", v)

	func _register(w: GFWorld):
		GFSystemBuilder.new_in_world(w) \
			.with(RegistrationA) \
			.with(RegistrationB) \
			.for_each(func(reg_a:RegistrationA, reg_b:RegistrationB):
				reg_a.set_result(reg_a.get_value() + reg_b.get_value())
				)


class RegistrationB extends GFComponent:
	func _build(b: GFComponentBuilder) -> void:
		b.add_member("value", TYPE_FLOAT)
		b.add_member("result", TYPE_FLOAT)

	func get_value() -> float:
		return getm(&"value")
	func set_value(v:float) -> void:
		setm(&"value", v)
	func get_result() -> float:
		return getm(&"result")
	func set_result(v:float) -> void:
		setm(&"result", v)

	func _register(w:GFWorld):
		GFSystemBuilder.new_in_world(w) \
			.with(RegistrationA) \
			.with(RegistrationB) \
			.for_each(func(reg_a:RegistrationA, reg_b:RegistrationB):
				reg_b.set_result(reg_a.get_value() * reg_b.get_value())
				)


class NoDefine extends GFComponent:
	pass
