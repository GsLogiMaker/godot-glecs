
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

# func test_pipelines():
	#world.new_pipeline(&"first")
	#world.new_pipeline(&"second")
#
	#var entity:= GFEntity.new() \
		#.add(Bools) \
		#.add(Ints) \
		#.set_name("Test")
	#var ints:Ints = entity.get(Ints)
#
	#world.system_builder(&"first") \
		#.with(Ints) \
		#.for_each(func(x:Ints):
			#x.a = 25
			#)
	#world.system_builder(&"second") \
		#.with(Ints) \
		#.for_each(func(x:Ints):
			#x.b = 50
			#)
#
	#ints.a = 0
	#ints.b = 0
	#assert_eq(entity.get(Ints).a, 0)
	#assert_eq(entity.get(Ints).b, 0)
	#world.run_pipeline(&"first", 0.0)
	#assert_eq(entity.get(Ints).a, 25)
	#assert_eq(entity.get(Ints).b, 0)
#
	#ints.a = 0
	#ints.b = 0
	#assert_eq(entity.get(Ints).a, 0)
	#assert_eq(entity.get(Ints).b, 0)
	#world.run_pipeline(&"second", 0.0)
	#assert_eq(entity.get(Ints).a, 0)
	#assert_eq(entity.get(Ints).b, 50)
#
	#entity.free()

func test_bools():
	GFSystemBuilder.new() \
		.with(Bools) \
		.for_each(func(x:Bools):
			x.b = x.a
			x.a = not x.b
			)

	var entity:= GFEntity.new() \
		.add(Bools) \
		.set_name("Test")

	world.progress(0.0)

	assert_eq(entity.get(Bools).a, true)
	assert_eq(entity.get(Bools).b, false)

	entity.delete()

func test_ints():
	GFSystemBuilder.new() \
		.with(Ints) \
		.for_each(func(x:Ints):
			x.b *= 2
			x.a += x.b
			)

	var entity:= GFEntity.new() \
		.add(Ints) \
		.set_name("Test")
	entity.get(Ints).b = 1

	world.progress(0.0)
	world.progress(0.0)
	world.progress(0.0)

	assert_eq(entity.get(Ints).a, 14)

	entity.delete()

func test_floats():
	GFSystemBuilder.new() \
		.with(Floats) \
		.for_each(func(x:Floats):
			x.b *= 2
			x.a += x.b
			)

	var entity:= GFEntity.new() \
		.add(Floats) \
		.set_name("Test")
	entity.get(Floats).b = 1.2

	world.progress(0.0)
	world.progress(0.0)
	world.progress(0.0)

	assert_almost_eq(entity.get(Floats).a, 16.8, 0.05)

	entity.delete()

# test simple_systems strings
func test_strings():
	GFSystemBuilder.new() \
		.with(Strings) \
		.for_each(func(x:Strings):
			x.b += "em"
			x.a += x.b
			)

	var entity:= GFEntity.new() \
		.set_name("Test") \
		.add(Strings, "", "po")
	var strings:Strings = entity.get(Strings)
	assert_eq(strings.a, "")
	assert_eq(strings.b, "po")

	world.progress(0.0)
	world.progress(0.0)
	world.progress(0.0)

	assert_eq(strings.a, "poempoemempoememem")
	assert_eq(strings.b, "poememem")

	entity.delete()

func test_byte_arrays():
	GFSystemBuilder.new() \
		.with(ByteArrays) \
		.for_each(func(x:ByteArrays):
			for i in range(x.a.size()):
				x.a[i] += x.b[i]
			)

	var entity:= GFEntity.new() \
		.add(ByteArrays) \
		.set_name("Test")
	entity.get(ByteArrays).a = PackedByteArray([1, 2, 3])
	entity.get(ByteArrays).b = PackedByteArray([2, 4, 3])

	world.progress(0.0)
	world.progress(0.0)
	world.progress(0.0)

	assert_eq(entity.get(ByteArrays).a, PackedByteArray([7, 14, 12]))

	entity.delete()

# test simple_systems textures
func test_textures():
	GFSystemBuilder.new() \
		.with(Textures) \
		.for_each(func(x:Textures):
			x.a = x.b
			)

	var entity:= GFEntity.new() \
		.add(Textures) \
		.set_name("Test")
	entity.get(Textures).a = null
	entity.get(Textures).b = load("res://icon.png")

	# Assert that setting Object to null works
	assert_eq(entity.get(Textures).b, load("res://icon.png"))
	entity.get(Textures).b = null
	assert_eq(entity.get(Textures).b, null)
	entity.get(Textures).b = load("res://icon.png")

	world.progress(0.0)
	world.progress(0.0)
	world.progress(0.0)

	assert_eq(entity.get(Textures).a, load("res://icon.png"))
	assert_eq(entity.get(Textures).b, load("res://icon.png"))

	entity.delete()

func test_ref_counts():
	var rc:= RefCounted.new()
	assert_eq(rc.get_reference_count(), 1)

	var entity:= GFEntity.new() \
		.add(RefCounts) \
		.set_name("Test")

	entity.get(RefCounts).a = rc
	assert_eq(rc.get_reference_count(), 2)

	entity.get(RefCounts).a = null
	assert_eq(rc.get_reference_count(), 1)

	entity.delete()

func test_arrays():
	GFSystemBuilder.new() \
		.with(Arrays) \
		.for_each(func(x:Arrays):
			for i in mini(x.a.size(), x.b.size()):
				x.b[i] += x.a[i]
			)

	var entity:= GFEntity.new() \
		.add(Arrays) \
		.set_name("Test")
	entity.get(Arrays).a = [23, 4, 6]
	entity.get(Arrays).b = [1, 2, 1]

	world.progress(0.0)
	world.progress(0.0)
	world.progress(0.0)

	assert_eq(entity.get(Arrays).a, [23, 4, 6])
	assert_eq(entity.get(Arrays).b, [70, 14, 19])

	entity.delete()

func test_dicts():
	GFSystemBuilder.new() \
		.with(Dicts) \
		.for_each(func(x:Dicts):
			x.b["value"] += x.a["add_by"]
			)

	var entity:= GFEntity.new() \
		.add(Dicts) \
		.set_name("Test")
	entity.get(Dicts).a = {"add_by": 5}
	entity.get(Dicts).b = {"value": 2}

	world.progress(0.0)
	world.progress(0.0)
	world.progress(0.0)

	assert_eq(entity.get(Dicts).a, {"add_by":5})
	assert_eq(entity.get(Dicts).b, {"value":17})

	entity.delete()

#endregion

#region Components

class Bools extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void:
		b_.add_member("a", TYPE_BOOL)
		b_.add_member("b", TYPE_BOOL)
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
	var a:int:
		get: return getm(&"a")
		set(v): setm(&"a", v)
	var b:int = 25:
		get: return getm(&"b")
		set(v): setm(&"b", v)

class Floats extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void:
		b_.add_member("a", TYPE_FLOAT)
		b_.add_member("b", TYPE_FLOAT)
	var a:float:
		get: return getm(&"a")
		set(v): setm(&"a", v)
	var b:float:
		get: return getm(&"b")
		set(v): setm(&"b", v)

class Strings extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void:
		b_.add_member("a", TYPE_STRING)
		b_.add_member("b", TYPE_STRING)
	var a:String:
		get: return getm(&"a")
		set(v): setm(&"a", v)
	var b:String:
		get: return getm(&"b")
		set(v): setm(&"b", v)

class ByteArrays extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void:
		b_.add_member("a", TYPE_PACKED_BYTE_ARRAY)
		b_.add_member("b", TYPE_PACKED_BYTE_ARRAY)
	var a:PackedByteArray:
		get: return getm(&"a")
		set(v): setm(&"a", v)
	var b:PackedByteArray:
		get: return getm(&"b")
		set(v): setm(&"b", v)

class Textures extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void:
		b_.add_member("a", TYPE_OBJECT)
		b_.add_member("b", TYPE_OBJECT)
	var a:Texture2D:
		get: return getm(&"a")
		set(v): setm(&"a", v)
	var b:Texture2D:
		get: return getm(&"b")
		set(v): setm(&"b", v)

class RefCounts extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void:
		b_.add_member("a", TYPE_OBJECT)
		b_.add_member("b", TYPE_OBJECT)
	var a:RefCounted:
		get: return getm(&"a")
		set(v): setm(&"a", v)
	var b:RefCounted:
		get: return getm(&"b")
		set(v): setm(&"b", v)

class Arrays extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void:
		b_.add_member("a", TYPE_ARRAY)
		b_.add_member("b", TYPE_ARRAY)
	var a:Array:
		get: return getm(&"a")
		set(v): setm(&"a", v)
	var b:Array:
		get: return getm(&"b")
		set(v): setm(&"b", v)

class Dicts extends GFComponent:
	func _build(b_: GFComponentBuilder) -> void:
		b_.add_member("a", TYPE_DICTIONARY)
		b_.add_member("b", TYPE_DICTIONARY)
	var a:Dictionary:
		get: return getm(&"a")
		set(v): setm(&"a", v)
	var b:Dictionary:
		get: return getm(&"b")
		set(v): setm(&"b", v)

#endregion
