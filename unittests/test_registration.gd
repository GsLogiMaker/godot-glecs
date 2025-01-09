
@tool
extends GutTest

const AModule = preload("./scripts/a_module.gd")
const AComponent = preload("./scripts/a_component.gd")
const AEntity = preload("./scripts/a_entity.gd")

var world:GFWorld

func before_all():
	world = GFWorld.new()

func after_all():
	world.free()

#region Tests

func test_auto_register_script():
	GFEntity.new_in_world(world) \
		.add(AComponent)

	assert_ne(
		world.lookup(
			"AComponent"
		),
		null,
	)

func test_register_script_module():
	world.register_script(AModule)

	assert_ne(
		world.lookup(
			"a_module"
		),
		null,
	)
	assert_ne(
		world.lookup(
			"a_module/SubEntity"
		),
		null,
	)
	assert_ne(
		world.lookup(
			"a_module/b_module/MyBComponent"
		),
		null,
	)

func test_register_script_component_script():
	world.register_script(AComponent)

	assert_ne(
		world.lookup(
			"AComponent"
		),
		null,
	)

func test_register_script_entity_script():
	world.register_script(AEntity)

	assert_ne(
		world.lookup(
			"AEntity"
		),
		null,
	)

func test_register_script_sub_class():
	var foo:= world.register_script(Foo).set_name("Foo")
	var bar:= world.register_script(Bar).set_name("Bar")

	assert_eq(
		world.lookup(
			"Foo"
		).get_id(),
		foo.get_id(),
	)
	assert_eq(
		world.lookup(
			"Bar"
		).get_id(),
		bar.get_id(),
	)

func test_name_conflic():
	GFEntity.new_in_world(world) \
		.set_name("Foo")
	world.register_script(Foo)

	assert_ne(
		world.lookup(
			"Foo"
		).is_alive(),
		null,
	)

#endregion

#region Components

class Foo extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void:
		b_.add_member("a", TYPE_BOOL)
		b_.add_member("b", TYPE_INT)
		b_.add_member("c", TYPE_FLOAT)

class Bar extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void:
		b_.add_member("a", TYPE_VECTOR2)
		b_.add_member("b", TYPE_FLOAT)

#endregion
