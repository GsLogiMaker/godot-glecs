
## A component that gives entities functionality of a [Camera2D].

class_name GFCamera2D extends GFComponent

## Camera2D's constructor defaults for its limit sides
## (scene/2d/camera_2d.cpp, Camera2D::Camera2D).
const LIMIT_LEFT_DEFAULT:= -10000000
const LIMIT_TOP_DEFAULT:= -10000000
const LIMIT_RIGHT_DEFAULT:= 10000000
const LIMIT_BOTTOM_DEFAULT:= 10000000

## The viewport this camera drives. When unset, the main viewport is used.
func get_viewport_rid() -> RID: return getm(&"viewport")
func set_viewport_rid(v:RID) -> void: setm(&"viewport", v)
## The canvas this camera drives. When unset, the main viewport's 2D canvas
## is used.
func get_canvas_rid() -> RID: return getm(&"canvas")
func set_canvas_rid(v:RID) -> void: setm(&"canvas", v)

func _build(b: GFComponentBuilder) -> void:
	b.add_member("viewport", TYPE_RID)
	b.add_member("canvas", TYPE_RID)


static func get_main_viewport() -> Viewport:
	var main_loop:= Engine.get_main_loop()
	if main_loop == null or main_loop.current_scene == null:
		return null
	return main_loop.current_scene.get_viewport()


static func get_main_viewport_rid() -> RID:
	var viewport:= get_main_viewport()
	return viewport.get_viewport_rid() if viewport else RID()


static func get_main_canvas() -> RID:
	var viewport:= get_main_viewport()
	return viewport.get_world_2d().get_canvas() if viewport else RID()


## Screen size used by [method Camera2D._get_camera_screen_size]:
## [method Viewport.get_visible_rect] while running, falling back to the
## configured viewport size when there is no scene to measure.
static func get_main_screen_size() -> Vector2:
	var viewport:= get_main_viewport()
	if viewport:
		return viewport.get_visible_rect().size
	return Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1152),
		ProjectSettings.get_setting("display/window/size/viewport_height", 648),
	)


## Port of [method Camera2D.get_camera_transform] for the stateless subset of
## the camera this module supports, returning the transform to hand to
## [method RenderingServer.viewport_set_canvas_transform].
##
## Mirrors scene/2d/camera_2d.cpp (4.3-stable) in the non-smoothed, no-drag
## path, which is the branch Godot takes whenever position smoothing is
## disabled:
##
##     zoom_scale  = Vector2(1, 1) / zoom
##     screen_offset = screen_size * 0.5 * zoom_scale   # if anchor is DRAG_CENTER
##     screen_rect = Rect2(-screen_offset + camera_pos, screen_size * zoom_scale)
##     <clamp screen_rect to the limits>
##     screen_rect.position += offset
##     xform = scale_basis(zoom_scale) + set_rotation(angle) + set_origin(pos)
##     return xform.affine_inverse()
##
## The final transform is built with the [Transform2D] constructor rather than
## [method Transform2D.scale_basis]/[method Transform2D.set_origin], because
## neither is exposed to scripting. Transform2D(rotation, scale, skew, origin)
## produces exactly the same basis: scale_basis() followed by set_rotation()
## and set_origin() is equivalent to the four-argument constructor.
static func compute_canvas_transform(
		zoom:Vector2,
		camera_pos:Vector2,
		offset:Vector2,
		anchor_drag_center:bool,
		limit_left:int,
		limit_top:int,
		limit_right:int,
		limit_bottom:int,
		angle:float,
		screen_size:Vector2,
	) -> Transform2D:
	# Godot rejects a degenerate zoom: "Zoom level must be different from 0".
	# Vector2(1, 1) / zoom would otherwise produce infinities in the transform.
	if is_zero_approx(zoom.x) or is_zero_approx(zoom.y):
		return Transform2D()

	var zoom_scale:= Vector2.ONE / zoom

	var screen_offset:= Vector2.ZERO
	if anchor_drag_center:
		screen_offset = screen_size * 0.5 * zoom_scale

	var screen_rect:= Rect2(-screen_offset + camera_pos, screen_size * zoom_scale)

	# Limits are applied directly to screen_rect here, matching the
	# `!position_smoothing_enabled || !limit_smoothing_enabled` branch.
	if screen_rect.position.x < limit_left:
		screen_rect.position.x = limit_left
	if screen_rect.position.x + screen_rect.size.x > limit_right:
		screen_rect.position.x = limit_right - screen_rect.size.x
	if screen_rect.position.y + screen_rect.size.y > limit_bottom:
		screen_rect.position.y = limit_bottom - screen_rect.size.y
	if screen_rect.position.y < limit_top:
		screen_rect.position.y = limit_top

	if offset != Vector2():
		screen_rect.position += offset

	return Transform2D(angle, zoom_scale, 0.0, screen_rect.position).affine_inverse()


# --------------------------------------------------------
# --- Tags (presence means the non-default state) ---
# --------------------------------------------------------

## Camera is switched off. Godot's `enabled` defaults to true, so the tag marks
## the disabled state. While present the camera leaves the canvas transform
## alone instead of driving it.
class disabled extends GFTag: pass

## Rotate the canvas with the node's [GFRotation2D] angle. Godot's
## `ignore_rotation` defaults to true, so the tag marks the rotating state.
class follow_rotation extends GFTag: pass

## Anchor the camera by its top-left corner. Godot's `anchor_mode` defaults to
## `ANCHOR_MODE_DRAG_CENTER`, so the tag marks the non-default mode.
class fixed_top_left extends GFTag: pass


# --------------------------------------------------------
# --- Components (absent means the Godot default) ---
# --------------------------------------------------------

## Camera offset. Applied on top of the limits, matching `Camera2D.offset`.
class offset extends GFVector2: pass

## Camera zoom. Godot's default is Vector2(1, 1).
class zoom extends GFVector2: pass

## Camera limit sides. Godot's constructor defaults are -10000000 for the left
## and top edges and 10000000 for the right and bottom edges.
class limit_left extends GFInt: pass
class limit_top extends GFInt: pass
class limit_right extends GFInt: pass
class limit_bottom extends GFInt: pass
