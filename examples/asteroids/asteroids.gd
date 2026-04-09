
extends Node2D


var texture:= load("res://icon.png")
var e:GFEntity
var c:GFEntity

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	e = GFEntity.new()
	e.set_name("Test")
	e.add(GFCanvasItem)
	e.add(GFColorRect)
	e.add(GFRotation2D)
	e.add(GFSkew2D)
	e.set(GFScale2D, Vector2.ONE)
	e.set(GFCanvasItem.material, $ColorRect.material)
	e.set(GFColorRect.size, Vector2(100, 22))

	c = GFEntity.new().set_name("Child") \
		.set_parent(e) \
		.set(GFPosition2D, Vector2(10, 100)) \
		.add(GFColorRect)
	c.set(GFPosition2D, Vector2(10, 100))

	GFEntity.from(GFOnDraw, e.get_world()).emit(e)

	GFWorld.get_default_world().start_rest_api()


func _process(delta: float) -> void:
	GFWorld.get_default_world().progress(0)
	
	c.get(GFCanvasItem).set_parent_canvas_item(e.get(GFCanvasItem).get_rid())

	var rot_c:GFRotation2D = e.get(GFRotation2D)
	if Input.get_axis("ui_left", "ui_right"):
		rot_c.set_angle(rot_c.get_angle() + (delta * Input.get_axis("ui_left", "ui_right")))

	var v_axis:= Input.get_axis("ui_up", "ui_down")
	if v_axis:
		var size_c:GFColorRect.size = e.get(GFColorRect.size)
		size_c.set_y(size_c.get_y() - (100 * delta * v_axis))

	if Input.is_action_just_pressed("ui_text_delete"):
		if e.has(GFCanvasItem.hidden):
			e.remove(GFCanvasItem.hidden)
		else:
			e.add(GFCanvasItem.hidden)
	
	if Input.is_action_just_pressed("ui_end"):
		if e.has(GFCanvasItem.clip_children):
			e.remove(GFCanvasItem.clip_children)
		else:
			e.add(GFCanvasItem.clip_children)
	
	if Input.is_action_just_pressed("ui_focus_next"):
		if c.has(GFCanvasItem.use_parent_material):
			c.remove(GFCanvasItem.use_parent_material)
		else:
			c.add(GFCanvasItem.use_parent_material)
		
	if Input.is_action_just_pressed("ui_accept"):
		e.set(GFColorRect.color, Color(randf(), randf(), randf()))
		c.set(GFColorRect.color, Color(randf(), randf(), randf()))
	
	var skew_c:= e.get(GFSkew2D)
	prints(Input.is_key_pressed(KEY_6), int(Input.is_key_pressed(KEY_6)))
	skew_c.set_skew(
		skew_c.get_skew()
		+ (int(Input.is_key_pressed(KEY_6)) - int(Input.is_key_pressed(KEY_5)))
		* delta
		)

func _input(event: InputEvent) -> void:
	if Input.is_key_pressed(KEY_1):
		e.set(GFCanvasItem.modulate, Color(randf(), randf(), randf()))
	if Input.is_key_pressed(KEY_2):
		if e.has(GFCanvasItem.modulate):
			e.remove(GFCanvasItem.modulate)
		else:
			e.add(GFCanvasItem.modulate)
	if Input.is_key_pressed(KEY_3):
		e.set(GFCanvasItem.self_modulate, Color(randf(), randf(), randf()))
	if Input.is_key_pressed(KEY_4):
		if e.has(GFCanvasItem.self_modulate):
			e.remove(GFCanvasItem.self_modulate)
		else:
			e.add(GFCanvasItem.self_modulate)
	
