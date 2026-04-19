
extends GFModule

static func get_main_tree() -> SceneTree:
	return Engine.get_main_loop()

static func get_main_space_2d() -> RID:
	return Engine.get_main_loop() \
		.current_scene \
		.get_viewport() \
		.world_2d \
		.space

	   
static func update_body_transform(
	body:GFPhysicsBody2D,
	pos_c:GFPosition2D,
	rot_c:GFRotation2D,
	scl_c:GFScale2D,
) -> void:
	var pos:= pos_c.get_vec() if pos_c else Vector2.ZERO
	var rot:= rot_c.get_angle() if rot_c else 0.0
	var scl:= scl_c.get_scale() if false else Vector2.ONE
	PhysicsServer2D.body_set_state(
		body.get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM,
		Transform2D(rot, scl, 0.0, pos),
	)


func _register(w: GFWorld) -> void:
	var OnAdd:= w.lookup("/root/flecs/core/OnAdd")
	var OnSet:= w.lookup("/root/flecs/core/OnSet")
	var OnRemove:= w.lookup("/root/flecs/core/OnRemove")
	var IsA:= w.lookup("/root/flecs/core/IsA")
	var Any:= w.lookup("/root/flecs/core/*")
	var ChildOf:= w.lookup("/root/flecs/core/ChildOf")

	#region GFPhysicsBody2D

	GFObserverBuilder.new().set_name("physics_body2d_add") \
		.set_events(OnAdd) \
		.with(GFPhysicsBody2D).or_with("$physics") \
		.with(GFExtends, GFPhysicsBody2D).src("$physics") \
		.for_each(func(body:GFPhysicsBody2D, _1):
			var rid:= PhysicsServer2D.body_create()
			PhysicsServer2D.body_set_space(
				rid,
				get_main_space_2d(),
				)
			
			PhysicsServer2D.body_set_state_sync_callback(
				rid,
				rigid_body_sync.bind(
					GFEntity.from(body.get_source_id(), body.get_world())
					),
				)
			body._set_rid(rid)
			)
	GFObserverBuilder.new().set_name("physics_body2d_remove") \
		.set_events(OnRemove) \
		.with(GFPhysicsBody2D).or_with("$physics") \
		.with(GFExtends, GFPhysicsBody2D).src("$physics") \
		.for_each(func(body:GFPhysicsBody2D, _1):
			PhysicsServer2D.free_rid(body.get_rid())
			)

	GFObserverBuilder.new().set_name("rigid_body2d_set") \
		.set_events(OnSet) \
		.with(GFRigidBody2D) \
		.for_each(func(body: GFRigidBody2D):
			PhysicsServer2D.body_set_mode(
				body.get_rid(),
				PhysicsServer2D.BODY_MODE_RIGID,
				)
			)

	GFObserverBuilder.new().set_name("static_body2d_set") \
		.set_events(OnSet) \
		.with(GFStaticBody2D) \
		.for_each(func(body: GFStaticBody2D):
			PhysicsServer2D.body_set_mode(
				body.get_rid(),
				PhysicsServer2D.BODY_MODE_STATIC,
				)
			)

	GFObserverBuilder.new().set_name("physics_body2d_set_transform") \
		.set_events(OnSet) \
		.with(GFPhysicsBody2D).or_with("$physics") \
		.with_maybe(GFPosition2D) \
		.with_maybe(GFRotation2D) \
		.with_maybe(GFScale2D) \
		.with(GFExtends, GFPhysicsBody2D).src("$physics") \
		.for_each(func(
			physics_body_c: GFPhysicsBody2D,
			pos_c: GFPosition2D,
			rot_c: GFRotation2D,
			scl_c: GFScale2D,
			_4,
			):
			update_body_transform(
				physics_body_c,
				pos_c,
				rot_c,
				scl_c,
				)
			)

	#endregion

	#region GFRectangleShape

	prints("HERE")
	GFObserverBuilder.new() \
		.set_name("collision_shape2d_add") \
		.set_events(OnAdd) \
		.with(GFPhysicsBody2D).src("$par") \
			.or_with("$physics").src("$par") \
		.with(GFCollisionShape2D) \
		.with(ChildOf, "$par") \
		.with(GFExtends, GFPhysicsBody2D).src("$physics") \
		.for_each(func(
			body:GFPhysicsBody2D,
			shape:GFCollisionShape2D,
			_0,
			_1,
			):
			if not shape.get_shape():
				return
			PhysicsServer2D.body_add_shape(
				body.get_rid(),
				shape.get_shape().get_rid(),
				)
			)
	GFObserverBuilder.new() \
		.set_name("collision_shape2d_set") \
		.set_events(OnSet) \
		.with(GFPhysicsBody2D) \
			.or_with("$physics") \
		.with(GFCollisionShape2D).src("$child") \
		.with(ChildOf, "$this").src("$child") \
		.with(GFExtends, GFPhysicsBody2D).src("$physics") \
		.for_each(func(
			body:GFPhysicsBody2D,
			shape:GFCollisionShape2D,
			_0,
			_1,
			):
			if not shape.get_shape():
				return
			PhysicsServer2D.body_add_shape(
				body.get_rid(),
				shape.get_shape().get_rid(),
				)
			)

	GFObserverBuilder.new() \
		.set_name("collision_shape2d_remove") \
		.set_events(OnRemove) \
		.with(GFPhysicsBody2D).or_with("$physics") \
		.with(GFRectangleShape2D) \
		.with(GFExtends, GFPhysicsBody2D).src("$physics") \
		.for_each(func(
			body:GFPhysicsBody2D,
			shape:GFCollisionShape2D,
			_0,
			):
			var index:= 0
			for child:GFEntity in body.iter_children():
				if child.get_id() == shape.get_id():
					break
				index += 1
			PhysicsServer2D.body_remove_shape(
				body.get_rid(),
				index,
				)
			)

	GFObserverBuilder.new() \
		.set_name("collision_shape2d_set_transform") \
		.set_events(OnSet) \
		.with(GFPhysicsBody2D).io_filter().up() \
			.or_with("$physics").io_filter().up() \
		.with(GFRectangleShape2D).io_filter() \
		.with_maybe(GFPosition2D).io_in() \
		.with_maybe(GFRotation2D).io_in() \
		.with_maybe(GFScale2D).io_in() \
		.with(GFExtends, GFPhysicsBody2D).src("$physics") \
		.for_each(func(
			body:GFPhysicsBody2D,
			shape:GFRectangleShape2D,
			pos_c:GFPosition2D,
			rot_c:GFRotation2D,
			scl_c:GFScale2D,
			_0,
			):
			if Engine.is_in_physics_frame():
				return
				
			var pos:= pos_c.get_vec() if pos_c else Vector2.ZERO
			var rot:= rot_c.get_angle() if rot_c else 0.0
			var scl:= scl_c.get_scale() if false else Vector2.ONE
			
			var index:= 0
			for child:GFEntity in body.iter_children():
				if child.get_id() == shape.get_id():
					break
				index += 1
				
			PhysicsServer2D.body_set_shape_transform(
				body.get_rid(),
				index,
				Transform2D(rot, scl, 0.0, pos),
				)
			)

	#endregion


static func rigid_body_sync(
	state:PhysicsDirectBodyState2D,
	entity:GFEntity,
) -> void:
	entity.set(GFPosition2D, state.transform.get_origin())
	entity.set(GFRotation2D, state.transform.get_rotation())

	GFEntity.from(
		GFOnTransformUpdate,
		entity.get_world(),
	).emit(entity)
