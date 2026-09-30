
## A component containing a [Texture2D].

class_name GFTexture2D extends GFComponent

func get_texture() -> Texture2D: return getm(&"value")
func set_texture(v:Texture2D) -> void: return setm(&"value", v)
func _build(b: GFComponentBuilder) -> void:
	b.add_member("value", TYPE_OBJECT)
