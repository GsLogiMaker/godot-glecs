
class_name GFRigidBody2D extends GFPhysicsBody2D

func _register(world: GFWorld) -> void:
	add(GFExtends, GFPhysicsBody2D)


class GFAngularDamp extends GFComponent: pass
class GFAngularDampMode extends GFComponent: pass
class GFCanSleep extends GFRegisterableEntity: pass
class GFCenterOfMass extends GFPosition2D: pass
class GFConstantForce extends GFComponent: pass
class GFConstantTorque extends GFComponent: pass
class GFContinueousCDGFRay extends GFRegisterableEntity: pass
class GFContinueousCDGFGFShape extends GFRegisterableEntity: pass
class GFCustomIntegrator extends GFRegisterableEntity: pass
class GFFreeze extends GFRegisterableEntity: pass
class GFFreezeModeKinematic extends GFRegisterableEntity: pass
class GFGravityScale extends GFComponent: pass
class GFInertia extends GFComponent: pass
class GFLinearDamp extends GFComponent: pass
class GFLinearDampMode extends GFComponent: pass
class GFLockRotation extends GFRegisterableEntity: pass
