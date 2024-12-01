
@tool
extends GutTest

var world:GFWorld

func before_all():
	world = GFWorld.new()

func after_all():
	world.free()

#region Tests

# func test_pipelines():
	#world.new_pipeline(&"first")
	#world.new_pipeline(&"second")
#
	#var entity:= GFEntity.spawn(world) \
		#.add_component(Bools) \
		#.add_component(Ints) \
		#.set_name("Test")
	#var ints:Ints = entity.get_component(Ints)
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
	#assert_eq(entity.get_component(Ints).a, 0)
	#assert_eq(entity.get_component(Ints).b, 0)
	#world.run_pipeline(&"first", 0.0)
	#assert_eq(entity.get_component(Ints).a, 25)
	#assert_eq(entity.get_component(Ints).b, 0)
#
	#ints.a = 0
	#ints.b = 0
	#assert_eq(entity.get_component(Ints).a, 0)
	#assert_eq(entity.get_component(Ints).b, 0)
	#world.run_pipeline(&"second", 0.0)
	#assert_eq(entity.get_component(Ints).a, 0)
	#assert_eq(entity.get_component(Ints).b, 50)
#
	#entity.free()

func test_bools():
	world.system_builder() \
		.with(Bools) \
		.for_each(func(x:Bools):
			x.b = x.a
			x.a = not x.b
			)

	var entity:= GFEntity.spawn(world) \
		.add_component(Bools) \
		.set_name("Test")

	world.progress(0.0)

	assert_eq(entity.get_component(Bools).a, true)
	assert_eq(entity.get_component(Bools).b, false)

	entity.delete()

func test_ints():
	world.system_builder() \
		.with(Ints) \
		.for_each(func(x:Ints):
			x.b *= 2
			x.a += x.b
			)

	var entity:= GFEntity.spawn(world) \
		.add_component(Ints) \
		.set_name("Test")
	entity.get_component(Ints).b = 1

	world.progress(0.0)
	world.progress(0.0)
	world.progress(0.0)

	assert_eq(entity.get_component(Ints).a, 14)

	entity.delete()

func test_floats():
	world.system_builder() \
		.with(Floats) \
		.for_each(func(x:Floats):
			x.b *= 2
			x.a += x.b
			)

	var entity:= GFEntity.spawn(world) \
		.add_component(Floats) \
		.set_name("Test")
	entity.get_component(Floats).b = 1.2

	world.progress(0.0)
	world.progress(0.0)
	world.progress(0.0)

	assert_almost_eq(entity.get_component(Floats).a, 16.8, 0.05)

	entity.delete()

# test simple_systems strings
func test_strings():
	world.system_builder() \
		.with(Strings) \
		.for_each(func(x:Strings):
			x.b += "em"
			x.a += x.b
			)

	var entity:= GFEntity.spawn(world) \
		.set_name("Test") \
		.add_component(Strings, "", "po")
	var strings:Strings = entity.get_component(Strings)
	assert_eq(strings.a, "")
	assert_eq(strings.b, "po")

	world.progress(0.0)
	world.progress(0.0)
	world.progress(0.0)

	assert_eq(strings.a, "poempoemempoememem")
	assert_eq(strings.b, "poememem")

	entity.delete()

func test_byte_arrays():
	world.system_builder() \
		.with(ByteArrays) \
		.for_each(func(x:ByteArrays):
			for i in range(x.a.size()):
				x.a[i] += x.b[i]
			)

	var entity:= GFEntity.spawn(world) \
		.add_component(ByteArrays) \
		.set_name("Test")
	entity.get_component(ByteArrays).a = PackedByteArray([1, 2, 3])
	entity.get_component(ByteArrays).b = PackedByteArray([2, 4, 3])

	world.progress(0.0)
	world.progress(0.0)
	world.progress(0.0)

	assert_eq(entity.get_component(ByteArrays).a, PackedByteArray([7, 14, 12]))

	entity.delete()

# test simple_systems textures
func test_textures():
	world.system_builder() \
		.with(Textures) \
		.for_each(func(x:Textures):
			x.a = x.b
			)

	var entity:= GFEntity.spawn(world) \
		.add_component(Textures) \
		.set_name("Test")
	entity.get_component(Textures).a = null
	entity.get_component(Textures).b = load("res://icon.svg")

	# Assert that setting Object to null works
	assert_eq(entity.get_component(Textures).b, load("res://icon.svg"))
	entity.get_component(Textures).b = null
	assert_eq(entity.get_component(Textures).b, null)
	entity.get_component(Textures).b = load("res://icon.svg")

	world.progress(0.0)
	world.progress(0.0)
	world.progress(0.0)

	assert_eq(entity.get_component(Textures).a, load("res://icon.svg"))
	assert_eq(entity.get_component(Textures).b, load("res://icon.svg"))

	entity.delete()

func test_ref_counts():
	var rc:= RefCounted.new()
	assert_eq(rc.get_reference_count(), 1)

	var entity:= GFEntity.spawn(world) \
		.add_component(RefCounts) \
		.set_name("Test")

	entity.get_component(RefCounts).a = rc
	assert_eq(rc.get_reference_count(), 2)

	entity.get_component(RefCounts).a = null
	assert_eq(rc.get_reference_count(), 1)

	entity.delete()

func test_arrays():
	world.system_builder() \
		.with(Arrays) \
		.for_each(func(x:Arrays):
			for i in mini(x.a.size(), x.b.size()):
				x.b[i] += x.a[i]
			)

	var entity:= GFEntity.spawn(world) \
		.add_component(Arrays) \
		.set_name("Test")
	entity.get_component(Arrays).a = [23, 4, 6]
	entity.get_component(Arrays).b = [1, 2, 1]

	world.progress(0.0)
	world.progress(0.0)
	world.progress(0.0)

	assert_eq(entity.get_component(Arrays).a, [23, 4, 6])
	assert_eq(entity.get_component(Arrays).b, [70, 14, 19])

	entity.delete()

func test_dicts():
	world.system_builder() \
		.with(Dicts) \
		.for_each(func(x:Dicts):
			x.b["value"] += x.a["add_by"]
			)

	var entity:= GFEntity.spawn(world) \
		.add_component(Dicts) \
		.set_name("Test")
	entity.get_component(Dicts).a = {"add_by": 5}
	entity.get_component(Dicts).b = {"value": 2}

	world.progress(0.0)
	world.progress(0.0)
	world.progress(0.0)

	assert_eq(entity.get_component(Dicts).a, {"add_by":5})
	assert_eq(entity.get_component(Dicts).b, {"value":17})

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
