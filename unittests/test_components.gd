
extends GutTest

var world:GFWorld = null

func before_each():
	world = GFWorld.new()


func after_each():
	world.free()


func test_add_entity():
	var _entity:= GFEntity.spawn(world)

	# Can't assert, but should be fine as long as it doesn't crash
	assert_null(null)


func test_world_deletion():
	var w:= GFWorld.new()
	var e:= GFEntity.spawn(w) \
		.add_component(Foo) \
		.set_name("Test")
	var foo:= e.get_component(Foo)
	var e2:= GFEntity.spawn(w) \
		.add_component(Foo) \
		.set_name("Test")
	var foo2:= e2.get_component(Foo)

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
	var w:= world

	var e:= GFEntity.spawn(world) \
		.add_component(RegistrationA) \
		.add_component(RegistrationB) \
		.set_name("Test")

	e.get_component(RegistrationA).set_value(3)
	e.get_component(RegistrationB).set_value(11)

	# A system defined in RegistrationA's _registered function should run
	# on GFWorld's process pipeline
	w.progress(0.0)

	assert_almost_eq(e.get_component(RegistrationA).get_result(), 14.0, .001)
	assert_almost_eq(e.get_component(RegistrationB).get_result(), 33.0, .001)


func test_simple_system():
	world.system_builder() \
		.with(Foo) \
		.for_each(func(foo:Foo):
			foo.set_value(Vector2(2, 5))
			)

	var entity:= GFEntity.spawn(world) \
		.add_component(Foo) \
		.set_name("Test")

	world.progress(0.0)

	assert_eq(entity.get_component(Foo).get_value(), Vector2(2, 5))


# test components components_in_relationships
func test_components_in_relationships():
	var w:= GFWorld.new()

	var e:= GFEntity.spawn(w)
	var foo:Foo = e.add_pair(Targets, Foo) \
		.get_component(w.pair(Targets, Foo))

	foo.set_value(Vector2(54, 6))
	assert_almost_eq(foo.get_value(), Vector2(54, 6), Vector2(.001, .001))

	foo = e.get_component(w.pair(Targets, Foo))
	assert_almost_eq(foo.get_value(), Vector2(54, 6), Vector2(.001, .001))

	w.free()


class Targets extends GFRegisterableEntity: pass


class Foo extends GFComponent:
	func _build(b: GFComponentBuilder) -> void:
		b.add_member("value", TYPE_VECTOR2)

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
		w.system_builder() \
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

	func _register(world:GFWorld):
		world.system_builder() \
			.with(RegistrationA) \
			.with(RegistrationB) \
			.for_each(func(reg_a:RegistrationA, reg_b:RegistrationB):
				reg_b.set_result(reg_a.get_value() * reg_b.get_value())
				)


class NoDefine extends GFComponent:
	pass
