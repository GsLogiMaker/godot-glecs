
class_name Glecs

static var ON_ADD:= _GlecsBindings._flecs_on_add()
static var ON_REMOVE:= _GlecsBindings._flecs_on_remove()
static var ON_SET:= _GlecsBindings._flecs_on_set()
static var UN_SET:= _GlecsBindings._flecs_un_set()
static var MONITOR:= _GlecsBindings._flecs_monitor()
static var ON_DELETE:= _GlecsBindings._flecs_on_delete()
static var ON_TABLE_CREATE:= _GlecsBindings._flecs_on_table_create()
static var ON_TABLE_DELETE:= _GlecsBindings._flecs_on_table_delete()
static var ON_TABLE_EMPTY:= _GlecsBindings._flecs_on_table_empty()
static var ON_TABLE_FILL:= _GlecsBindings._flecs_on_table_fill()
static var PREFAB:= _GlecsBindings._flecs_prefab()
static var IS_A:= _GlecsBindings._flecs_is_a()

class Component extends _GlecsBaseComponent:

	static func _registered(world:Glecs.World) -> void:
		pass

	func copy_from_component(from_component: Glecs.Component) -> void:
		_copy_from_component(from_component)
		
	func get_type_name() -> StringName:
		return _get_type_name()
		
	func getc(property: StringName) -> Variant:
		return _getc(property)
		
	func setc(property: StringName, value:Variant) -> void:
		return _setc(property, value)
		
	func delete() -> void:
		_delete()

	func is_valid() -> bool:
		return _is_valid()


## A reference to an entity.
##
## TODO: Explain conversions from Variant to Glecs.Entity
class Entity extends _GlecsBaseEntity:
	
	## Called when the script is registered in [param world]. [br] [br]
	##
	## The main use for this function is for creating prefabs from classes,
	## like so:
	## [codeblock]
	## class MyPrefab extends Glecs.Entity:
	##     static func _registered(world: Glecs.World) -> void:
	##         var my_prefab = Glecs.Entity.from(MyPrefab, world) \
	##             .add_entity(Glecs.PREFAB) \
	##             .add_component(SomeComponent)
	## [/codeblock]
	## For more on prefabs, see [method add_entity]. [br]
	## See also: [method from], [method add_entity], [method add_component]
	static func _registered(world: Glecs.World) -> void:
		pass

	## Creates a new entity in [param world]. [br] [br]
	##
	## Example:
	## [codeblock]
	## var entity = Glecs.Entity.spawn()
	## [/codeblock]
	## See also: [method from]
	static func spawn(world: Glecs.World = null) -> Glecs.Entity:
		return _GlecsBaseEntity._spawn(world)
	
	## Returns a reference to an existing [param entity],
	## in [param world]. [br] [br]
	##
	## Example:
	## [codeblock]
	## var id = Glecs.PREFAB
	## var entity = Glecs.Entity.from(id)
	## [/codeblock]
	## See also: [method spawn]
	static func from(entity: Variant, world: Glecs.World = null) -> Entity:
		return _GlecsBaseEntity._from(entity, world)

	## Adds component data to this entity, with an optional
	## [param default_value]. [br] [br]
	##
	## Example:
	## [codeblock]
	## var entity = Glecs.Entity.spawn()
	## entity.add_component(MyComponent)
	## [/codeblock]
	## For more on components, see [Glecs.Component]. [br]
	## See also: [method get_component], [method remove_component]
	func add_component(component:Variant, default_value:Variant=null) -> Entity:
		_add_component(component, default_value)
		return self

	## Returns a reference to this entity's [param component] data. [br] [br]
	## 
	## For more information on components, see: [Glecs.Component]. [br]
	## See also: [method add_component], [method remove_component]
	func get_component(component:Variant) -> Component:
		return _get_component(component)

	## Removes component data from this entity. [br] [br]
	## 
	## For more information on components, see [Glecs.Component]. [br]
	## See also: [method add_component], [method has_component]
	func remove_component(component: Variant) -> Entity:
		_remove_component(component)
		return self

	## Deletes this entity from the ECS world. [br] [br]
	## 
	## This method does not delete this [Glecs.Entity], which is
	## a [RefCounted] object. The lifetime of an entity is completely separate
	## from the lifetime of a [Glecs.Entity], which acts like a reference to an
	## entity.
	## [br] [br]
	## See also: [method is_valid].
	func delete() -> void:
		_delete()

	## Adds an other entity as a tag or relationship to this entity. [br] [br]
	##
	## Example:
	## [codeblock]
	## var my_tag = Glecs.Entity.spawn()
	## var entity = Glecs.Entity.spawn()
	## 
	## entity.add_entity(my_tag)
	## [/codeblock]
	## See also: [method has_entity], [method remove_entity],
	## [method add_relation]
	func add_entity(tag: Variant) -> Entity:
		_add_entity(tag)
		return self

	## Returns true if this entity has the given tag or relationship. [br] [br]
	##
	## Example:
	## [codeblock]
	## var my_tag = Glecs.Entity.spawn()
	## var entity = Glecs.Entity.spawn()
	## entity.add_entity(my_tag)
	##
	## assert(entity.has_entity(my_tag) == true)
	## [/codeblock]
	## See also: [method add_entity], [method remove_entity],
	## [method has_relation]
	func has_entity(tag: Variant) -> bool:
		return _has_entity(tag)

	## Removes the given tag or relationship with this entity. [br] [br]
	##
	## Example:
	## [codeblock]
	## var my_tag = Glecs.Entity.spawn()
	## var entity = Glecs.Entity.spawn()
	## entity.add_entity(my_tag)
	##
	## entity.remove_entity(my_tag)
	## assert(entity.has_entity(my_tag) == false)
	## [/codeblock]
	## See also: [method add_entity], [method has_entity],
	## [method remove_relation]
	func remove_entity(tag: Variant) -> Entity:
		_remove_entity(tag)
		return self

	## Returns the ID of this entity from its world. [br] [br]
	##
	## Example:
	## [codeblock]
	## var first = Glecs.Entity.spawn()
	## var second = Glecs.Entity.from(first)
	##
	## assert(first.get_id() == second.get_id())
	## [/codeblock]
	## See also: [method get_world]
	func get_id() -> int:
		return _get_id()

	## Returns the name of this entity. [br] [br]
	##
	## Example:
	## [codeblock]
	## var entity = Glecs.Entity.spawn()
	## entity.set_name("MyEntity")
	##
	## assert(entity.get_name() == "MyEntity")
	## [/codeblock]
	## See also: [method set_name]
	func get_name() -> String:
		return _get_name()

	## Sets the name of this entity. [br] [br]
	##
	## Example:
	## [codeblock]
	## var entity = Glecs.Entity.spawn()
	## entity.set_name("MyEntity")
	##
	## assert(entity.get_name() == "MyEntity")
	## [/codeblock]
	## See also: [method get_name]
	func set_name(value: String) -> Entity:
		_set_name(value)
		return self

	## Adds an entity pair to this entity. [br] [br]
	##
	## Example:
	## [codeblock]
	## var eats = Glecs.Entity.spawn() # Define relation
	## var apples = Glecs.Entity.spawn() # Define relation target
	## var entity = Glecs.Entity.spawn()
	##
	## entity.add_relation(eats, apples)
	## assert(entity.has_relation(eats, apples) == true)
	## [/codeblock]
	## See also: [method has_relation], [method remove_relation],
	## [method add_entity]
	func add_relation(relation: Variant, with_entity: Variant) -> Entity:
		_add_relation(relation, with_entity)
		return self
	
	## Returns true if this entity has the given entity pair. [br] [br]
	##
	## Example:
	## [codeblock]
	## var eats = Glecs.Entity.spawn() # Define relation
	## var apples = Glecs.Entity.spawn() # Define relation target
	## var entity = Glecs.Entity.spawn()
	## entity.add_relation(eats, apples)
	##
	## assert(entity.has_relation(eats, apples) == true)
	## [/codeblock]
	## See also: [method add_relation], [method remove_relation],
	## [method has_entity]
	func has_relation(relation: Variant, with_entity: Variant) -> bool:
		breakpoint # TODO: implement Glecs.Entity.has_relation
		return false

	## Removes an entity pair from this entity. [br] [br]
	##
	## Example:
	## [codeblock]
	## var eats = Glecs.Entity.spawn() # Define relation
	## var apples = Glecs.Entity.spawn() # Define relation target
	## var entity = Glecs.Entity.spawn()
	## entity.add_relation(eats, apples)
	##
	## entity.remove_relation(eats, apples)
	## assert(entity.has_relation(eats, apples) == true)
	## [/codeblock]
	## See also: [method add_relation], [method has_relation],
	## [method remove_entity]
	func remove_relation(relation: Variant, with_entity: Variant) -> Entity:
		_remove_relation(relation, with_entity)
		return self

	## Returns true if this [Glecs.Entity] is a valid reference to an
	## entity. [br] [br]
	##
	## A [Glecs.Entity] is valid if the following are true: [br]
	## - The world is not [code]null[/code]. [br]
	## - The world is not deleted. [br]
	## - The ID of the [Glecs.Entity] is a real entity in the world. [br]
	## - The entity is not deleted.
	##
	## [br] [br]
	## Example:
	## [codeblock]
	## var entity = Glecs.Entity.spawn()
	## entity.delete()
	## assert(is_instance_valid(entity) == true)
	## assert(entity.is_valid() == false)
	## [/codeblock]
	## See also: [method delete]
	func is_valid() -> bool:
		return _is_valid()

	## Returns the world object this entity is in. [br] [br]
	## See also: [method get_id]
	func get_world() -> Glecs.World:
		return _get_world()


class World extends _GlecsBaseWorld:
	
	var PROCESS_PIPELINE:= id_from_variant(&"glecs.process"):
		set(_v): return
	var PHYSICS_PROCESS_PIPELINE:= id_from_variant(&"glecs.physics_process"):
		set(_v): return

	func new_event_listener(
		event:Variant,
	) -> GlecsSystemBuilder:
		return _new_event_listener(event)

	func id_from_variant(entity: Variant) -> int:
		return _id_from_variant(entity)

	func new_pipeline(
		identifier:Variant,
		additional_parameters:Array[Callable]=[],
	) -> void:
		_new_pipeline(identifier, additional_parameters)

	func new_system(pipeline: Variant = PROCESS_PIPELINE) -> GlecsSystemBuilder:
		return _new_system(pipeline)

	func new_entity(name:String, with_components:Array[Variant]=[]) -> Glecs.Entity:
		return _new_entity(name, with_components)


class WorldNode extends _GlecsBaseWorldNode:

	var PROCESS_PIPELINE:= id_from_variant(&"glecs.process"):
		set(_v): return
	var PHYSICS_PROCESS_PIPELINE:= id_from_variant(&"glecs.physics_process"):
		set(_v): return

	func _ready() -> void:
		new_pipeline(PROCESS_PIPELINE, [get_process_delta_time])
		new_pipeline(PHYSICS_PROCESS_PIPELINE, [get_physics_process_delta_time])

	func _process(delta: float) -> void:
		run_pipeline(PROCESS_PIPELINE, delta)

	func _physics_process(delta: float) -> void:
		run_pipeline(PHYSICS_PROCESS_PIPELINE, delta)

	func new_event_listener(
		event:Variant,
	) -> GlecsSystemBuilder:
		return _new_event_listener(event)

	func id_from_variant(entity: Variant) -> int:
		return _id_from_variant(entity)

	func new_pipeline(
		identifier:Variant,
		additional_parameters:Array[Callable]=[],
	) -> void:
		_new_pipeline(identifier, additional_parameters)

	func new_system(pipeline: Variant = PROCESS_PIPELINE) -> GlecsSystemBuilder:
		return _new_system(pipeline)

	func new_entity(name:String, with_components:Array[Variant]=[]) -> Glecs.Entity:
		return _new_entity(name, with_components)
