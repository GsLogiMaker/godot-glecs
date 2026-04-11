
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

func test_stuff():
	pass
	#world.system_builder(&"test_pipeline") \
	GFSystemBuilder.new() \
		.with(Bools) \
		.for_each(func(boo:Bools):
			boo.b = boo.a
			)

	var e:= GFEntity.new() \
		.add(Bools) \
		.set_name("Test")
	world.register_script(Bools)
	var bools = e.get(Bools)
	bools.a = true
	bools.b = false

	assert_eq(bools.a, true)
	assert_eq(bools.b, false)

	# world.run_pipeline(&"test_pipeline", 1.0)
	world.progress(1.0)

	assert_eq(bools.a, true)
	assert_eq(bools.b, true)

#endregion

#region Components

class Bools extends GFComponent:
	func _build(builder: GFComponentBuilder) -> void:
		builder.add_member("a", TYPE_BOOL)
		builder.add_member("b", TYPE_BOOL)
	var a:bool:
		get: return getm(&"a")
		set(v): setm(&"a", v)
	var b:bool:
		get: return getm(&"b")
		set(v): setm(&"b", v)

#endregion
