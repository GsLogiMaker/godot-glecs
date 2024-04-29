
@tool
extends GutTest

var world:GlecsWorldNode

func before_all():
	world = GlecsWorldNode.new()
	add_child(world)

func after_all():
	world.free()

#region Tests

func test_prefab():
	world.new_system() \
		.with(Foo) \
		.with(Bar) \
		.for_each(func(_delta:float, foo:Foo, bar:Bar):
			foo.a = true
			foo.b += 1
			foo.c += 1.3
			bar.a.x += foo.c
			bar.a.y += foo.c * 2
			bar.b = PI
			)
	var entity:= world.new_entity_with_prefab("Test", PrefabPck)
	
	world.run_pipeline(&"process", 0.0)
	world.run_pipeline(&"process", 0.0)
	world.run_pipeline(&"process", 0.0)
	
	var foo:Foo = entity.get_component(Foo)
	var bar:Bar = entity.get_component(Bar)
	assert_ne(foo, null)
	assert_ne(bar, null)

#endregion

#region Components

class Foo extends GlecsComponent:
	const _VAR_a:= false
	const _VAR_b:= 0
	const _VAR_c:= 0.0

class Bar extends GlecsComponent:
	const _VAR_a:= Vector2.ZERO
	const _VAR_b:= 0.0
	
class PrefabPck extends _GlecsPrefab:
	const COMPONENTS:= [
		Foo,
		Bar,
	]
		
#endregion
