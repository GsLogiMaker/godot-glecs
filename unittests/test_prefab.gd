
@tool
extends GutTest

var world:GFWorld

func before_all():
	world = GFWorld.new()

func after_all():
	world.free()

#region Tests

func test_prefab():
	world.new_system() \
		.with(Foo) \
		.with(Bar) \
		.for_each(func(_delta:float, f:Foo, b:Bar):
			f.b += 1
			f.c += 1.3
			b.a.x += f.c
			b.a.y += f.c * 2
			b.b = PI
			)

	var entity:= GFEntity.spawn(world)
	entity.add_entity(world.pair("flecs/core/IsA", MyPrefab))

	# Test inhereted componets exist entity
	var foo:Foo = entity.get_component(Foo)
	var bar:Bar = entity.get_component(Bar)
	assert_ne(foo, null)
	assert_ne(bar, null)

	# Test default values of inhereted  components
	assert_eq(foo.a, true)
	assert_eq(foo.b, 23)
	assert_almost_eq(foo.c, 2.33, 0.001)
	assert_almost_eq(bar.a, Vector2(2, 1.1), Vector2(0.001, 0.001))
	assert_almost_eq(bar.b, 5.6, 0.001)

	# Test process with inhereted components
	world.progress(0.0)
	assert_eq(foo.b, 24)
	assert_almost_eq(foo.c, 3.63, 0.001)
	assert_almost_eq(bar.a, Vector2(2+foo.c, 1.1+(foo.c*2)), Vector2(0.001, 0.001))
	assert_almost_eq(bar.b, PI, 0.001)

#endregion

#region Components

class Foo extends GFComponent:
	static func _get_members() -> Dictionary: return {
		a = false,
		b = 0,
		c = 0.0,
	}

class Bar extends GFComponent:
	static func _get_members() -> Dictionary: return {
		a = Vector2.ZERO,
		b = 0.0,
	}

class MyPrefab extends GFRegisterableEntity:

	static func _registered(world:GFWorld) -> void:
		var p:= GFEntity.from(MyPrefab, world)
		p.add_entity(Glecs.PREFAB)
		p.add_component(Foo, [true, 23, 2.33])
		p.add_component(Bar, [Vector2(2, 1.1), 5.6])

#endregion
