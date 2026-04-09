
## A component containing a [Texture2D].

class_name GFTexture2D extends GFComponent

func get_texture() -> Texture2D: return getm(&"texture")
func set_texture(v:Texture2D) -> void: return setm(&"texture", v)
func _build(b: GFComponentBuilder) -> void:
	b.add_member("texture", TYPE_OBJECT)
