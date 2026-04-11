
@tool
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

# test prefab prefab
func test_prefab():
	GFSystemBuilder.new() \
		.with(Foo) \
		.with(Bar) \
		.for_each(func(f:Foo, b:Bar):
			f.b += 1
			f.c += 1.3
			b.a.x += f.c
			b.a.y += f.c * 2
			b.b = PI
			)

	var entity:= GFEntity.new()
	var isa:= world.coerce_id("flecs/core/IsA")
	var myprefab:= world.coerce_id(MyPrefab)
	var pair:= world.pair(isa, myprefab)
	entity.add(pair)

	# Test inhereted components exist entity
	var foo:Foo = entity.get(Foo)
	var bar:Bar = entity.get(Bar)
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
	var a:bool:
		get: return getm("a")
		set(v): setm("a", v)
	var b:int:
		get: return getm("b")
		set(v): setm("b", v)
	var c:float:
		get: return getm("c")
		set(v): setm("c", v)
	func _build(b_: GFComponentBuilder) -> void:
		b_.add_member("a", TYPE_BOOL)
		b_.add_member("b", TYPE_INT)
		b_.add_member("c", TYPE_FLOAT)

class Bar extends GFComponent:
	var a:Vector2:
		get: return getm("a")
		set(v): setm("a", v)
	var b:float:
		get: return getm("b")
		set(v): setm("b", v)
	func _build(b_: GFComponentBuilder) -> void:
		b_.add_member("a", TYPE_VECTOR2)
		b_.add_member("b", TYPE_FLOAT)

class MyPrefab extends GFRegisterableEntity:
	func _register(_world:GFWorld) -> void:
		add("flecs/core/Prefab")
		set(Foo, true, 23, 2.33)
		set(Bar, Vector2(2, 1.1), 5.6)

#endregion
