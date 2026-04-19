
extends GFModule

const Systems:= preload("./_systems.gd")

func _register(world: GFWorld) -> void:
	set_name("physics")
	world.register_script(GFPhysicsBody2D)
	world.register_script(GFCollisionShape2D)
	world.register_script(GFRigidBody2D)
	world.register_script(GFStaticBody2D)
