
class_name GFPhysicsBody2D extends GFComponent

func get_rid() -> RID: return getm("rid")
func _set_rid(rid:RID) -> void:
	setm("rid", rid)

func _build(b:GFComponentBuilder) -> void:
	b.add_member("rid", TYPE_RID)
	b.add("/root/flecs/core/With", "/root/flecs/core/OrderedChildren")

func get_position() -> Vector2:
	var tr:Transform2D = PhysicsServer2D.body_get_state(
		get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM
	)
	return tr.get_origin()

func get_rotation() -> float:
	var tr:Transform2D = PhysicsServer2D.body_get_state(
		get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM
	)
	return tr.get_rotation()

func get_transform() -> Transform2D:
	var tr:Transform2D = PhysicsServer2D.body_get_state(
		get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM
	)
	return tr

func set_position(v:Vector2) -> void:
	var state:= PhysicsServer2D.body_get_direct_state(
		get_rid(),
	)
	if not state:
		return
	state.transform.origin = v

func set_rotation(v:float) -> void:
	var state:= PhysicsServer2D.body_get_direct_state(
		get_rid(),
	)
	if not state:
		return
	state.transform = state.transform.rotated(
		v - state.transform.get_rotation(),
	)

func set_transform(v:Transform2D) -> void:
	var state:= PhysicsServer2D.body_get_direct_state(
		get_rid(),
	)
	if not state:
		return
	state.transform = v
