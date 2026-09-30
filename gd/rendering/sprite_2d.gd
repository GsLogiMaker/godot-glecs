
class_name GFSprite2D extends GFTexture2D

const SPRITE2D_COMOPONENTS = [
	GFSprite2D.centered,
	GFSprite2D.flip_h,
	GFSprite2D.flip_v,
	GFSprite2D.frame,
	GFSprite2D.frame_coords,
	GFSprite2D.hframes,
	GFSprite2D.offset,
	GFSprite2D.region,
	GFSprite2D.region_filter_clip,
	GFSprite2D.vframes,
]

func _register(world:GFWorld) -> void:
	add("/root/flecs/core/With", GFCanvasItem)
	# TODO: Fix cyclic of With chain causing game to crash with no errors
	#add("/root/flecs/core/With", GFSprite2D.centered)

class centered extends GFTag:
	func _register(world:GFWorld) -> void:
		add("/root/flecs/core/With", GFSprite2D)
class flip_h extends GFTag:
	func _register(world:GFWorld) -> void:
		add("/root/flecs/core/With", GFSprite2D)
class flip_v extends GFTag:
	func _register(world:GFWorld) -> void:
		add("/root/flecs/core/With", GFSprite2D)
class frame extends GFInt:
	func _register(world:GFWorld) -> void:
		add("/root/flecs/core/With", GFSprite2D)
class frame_coords extends GFVector2i:
	func _register(world:GFWorld) -> void:
		add("/root/flecs/core/With", GFSprite2D)
class hframes extends GFInt:
	func _register(world:GFWorld) -> void:
		add("/root/flecs/core/With", GFSprite2D)
class offset extends GFVector2:
	func _register(world:GFWorld) -> void:
		add("/root/flecs/core/With", GFSprite2D)
## When added, texture is cut from a larger atlas texture.
class region extends GFRect2:
	func _register(world:GFWorld) -> void:
		add("/root/flecs/core/With", GFSprite2D)
## When added, the outermost pixels get blurred out. [class GFCanvasItem.region_rect] must be added.
class region_filter_clip extends GFTag:
	func _register(world:GFWorld) -> void:
		add("/root/flecs/core/With", GFSprite2D)
class vframes extends GFTag:
	func _register(world:GFWorld) -> void:
		add("/root/flecs/core/With", GFSprite2D)
