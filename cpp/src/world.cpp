
#include "world.h"
#include "entity.h"
#include "component.h"
#include "component_builder.h"
#include "gdextension_interface.h"
#include "godot_cpp/classes/global_constants.hpp"
#include "godot_cpp/classes/script.hpp"
#include "godot_cpp/classes/text_server_manager.hpp"
#include "godot_cpp/classes/wrapped.hpp"
#include "godot_cpp/core/memory.hpp"
#include "godot_cpp/core/property_info.hpp"
#include "godot_cpp/variant/packed_string_array.hpp"
#include "godot_cpp/variant/string.hpp"
#include "godot_cpp/variant/utility_functions.hpp"
#include "observer_builder.h"
#include "pair.h"
#include "query_builder.h"
#include "registerable_entity.h"
#include "system_builder.h"
#include "utils.h"

#include <cassert>
#include <cctype>
#include <cstring>
#include <flecs.h>
#include "godot_cpp/variant/dictionary.hpp"
#include "godot_cpp/variant/variant.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/variant/string_name.hpp>

using namespace godot;

ecs_entity_t GFWorld::glecs = 0;
ecs_entity_t GFWorld::glecs_meta = 0;
ecs_entity_t GFWorld::glecs_meta_real = 0;
ecs_entity_t GFWorld::glecs_meta_nil = 0;
ecs_entity_t GFWorld::glecs_meta_bool = 0;
ecs_entity_t GFWorld::glecs_meta_int = 0;
ecs_entity_t GFWorld::glecs_meta_float = 0;
ecs_entity_t GFWorld::glecs_meta_string = 0;
ecs_entity_t GFWorld::glecs_meta_vector2 = 0;
ecs_entity_t GFWorld::glecs_meta_vector2i = 0;
ecs_entity_t GFWorld::glecs_meta_rect2 = 0;
ecs_entity_t GFWorld::glecs_meta_rect2i = 0;
ecs_entity_t GFWorld::glecs_meta_vector3 = 0;
ecs_entity_t GFWorld::glecs_meta_vector3i = 0;
ecs_entity_t GFWorld::glecs_meta_transform2d = 0;
ecs_entity_t GFWorld::glecs_meta_vector4 = 0;
ecs_entity_t GFWorld::glecs_meta_vector4i = 0;
ecs_entity_t GFWorld::glecs_meta_plane = 0;
ecs_entity_t GFWorld::glecs_meta_quaternion = 0;
ecs_entity_t GFWorld::glecs_meta_aabb = 0;
ecs_entity_t GFWorld::glecs_meta_basis = 0;
ecs_entity_t GFWorld::glecs_meta_transform3d = 0;
ecs_entity_t GFWorld::glecs_meta_projection = 0;
ecs_entity_t GFWorld::glecs_meta_color = 0;
ecs_entity_t GFWorld::glecs_meta_string_name = 0;
ecs_entity_t GFWorld::glecs_meta_node_path = 0;
ecs_entity_t GFWorld::glecs_meta_rid = 0;
ecs_entity_t GFWorld::glecs_meta_object = 0;
ecs_entity_t GFWorld::glecs_meta_callable = 0;
ecs_entity_t GFWorld::glecs_meta_signal = 0;
ecs_entity_t GFWorld::glecs_meta_dictionary = 0;
ecs_entity_t GFWorld::glecs_meta_array = 0;
ecs_entity_t GFWorld::glecs_meta_packed_byte_array = 0;
ecs_entity_t GFWorld::glecs_meta_packed_int32_array = 0;
ecs_entity_t GFWorld::glecs_meta_packed_int64_array = 0;
ecs_entity_t GFWorld::glecs_meta_packed_float32_array = 0;
ecs_entity_t GFWorld::glecs_meta_packed_float64_array = 0;
ecs_entity_t GFWorld::glecs_meta_packed_string_array = 0;
ecs_entity_t GFWorld::glecs_meta_packed_vector2_array = 0;
ecs_entity_t GFWorld::glecs_meta_packed_vector3_array = 0;
ecs_entity_t GFWorld::glecs_meta_packed_color_array = 0;
ecs_entity_t GFWorld::glecs_meta_packed_vector4_array = 0;

GDObjectInstanceID GFWorld::global_thread_singleton = 0;
GDObjectInstanceID thread_local GFWorld::local_thread_singleton = 0;

GFWorld::~GFWorld() {
	ecs_fini(_raw);
}

String GFWorld::_to_string() const {
	return String("[")
		+ get_class()
		+ "#"
		+ String::num_int64(get_instance_id())
		+ "]";
}

void GFWorld::setup_glecs() {
	_raw = ecs_init();
	registered_entity_ids = Dictionary();
	registered_entity_scripts = Dictionary();
	ECS_IMPORT(raw(), FlecsStats);

	// Add glecs module
	ecs_component_desc_t empty_desc = {0};
	glecs = ecs_module_init(
		_raw,
		"glecs",
		&empty_desc
	);

	// Add glecs/meta module
	{
		ecs_component_desc_t comp_desc = {
			.entity = ecs_new_from_path(_raw, glecs, "meta"),
		};
		GLECS_SCOPE(this, glecs, {
			glecs_meta = ecs_module_init(
				_raw,
				"meta",
				&comp_desc
			);
		});
	}

	{ // Add glecs/meta/Real type
		ecs_primitive_kind_t kind;
		if (sizeof(real_t) == sizeof(float)) {
			kind = ecs_primitive_kind_t::EcsF32;
		} else if (sizeof(real_t) == sizeof(double)) {
			kind = ecs_primitive_kind_t::EcsF64;
		} else {
			throw "Godot's real_t type is somehow not a float or double";
		}
		ecs_primitive_desc_t primi_desc = {
			.entity = ecs_new_from_path(_raw, glecs_meta, "Real"),
			.kind = kind
		};
		glecs_meta_real = ecs_primitive_init(_raw, &primi_desc);
	}

	glecs_meta_nil = ecs_new(_raw);
	glecs_meta_bool = ecs_new(_raw);
	glecs_meta_int = ecs_new(_raw);
	glecs_meta_float = ecs_new(_raw);
	glecs_meta_string = ecs_new(_raw);
	glecs_meta_vector2 = ecs_new(_raw);
	glecs_meta_vector2i = ecs_new(_raw);
	glecs_meta_rect2 = ecs_new(_raw);
	glecs_meta_rect2i = ecs_new(_raw);
	glecs_meta_vector3 = ecs_new(_raw);
	glecs_meta_vector3i = ecs_new(_raw);
	glecs_meta_transform2d = ecs_new(_raw);
	glecs_meta_vector4 = ecs_new(_raw);
	glecs_meta_vector4i = ecs_new(_raw);
	glecs_meta_plane = ecs_new(_raw);
	glecs_meta_quaternion = ecs_new(_raw);
	glecs_meta_aabb = ecs_new(_raw);
	glecs_meta_basis = ecs_new(_raw);
	glecs_meta_transform3d = ecs_new(_raw);
	glecs_meta_projection = ecs_new(_raw);
	glecs_meta_color = ecs_new(_raw);
	glecs_meta_string_name = ecs_new(_raw);
	glecs_meta_node_path = ecs_new(_raw);
	glecs_meta_rid = ecs_new(_raw);
	glecs_meta_object = ecs_new(_raw);
	glecs_meta_callable = ecs_new(_raw);
	glecs_meta_signal = ecs_new(_raw);
	glecs_meta_dictionary = ecs_new(_raw);
	glecs_meta_array = ecs_new(_raw);
	glecs_meta_packed_byte_array = ecs_new(_raw);
	glecs_meta_packed_int32_array = ecs_new(_raw);
	glecs_meta_packed_int64_array = ecs_new(_raw);
	glecs_meta_packed_float32_array = ecs_new(_raw);
	glecs_meta_packed_float64_array = ecs_new(_raw);
	glecs_meta_packed_string_array = ecs_new(_raw);
	glecs_meta_packed_vector2_array = ecs_new(_raw);
	glecs_meta_packed_vector3_array = ecs_new(_raw);
	glecs_meta_packed_color_array = ecs_new(_raw);
	glecs_meta_packed_vector4_array = ecs_new(_raw);

	define_gd_literal("nil", ecs_primitive_kind_t::EcsUPtr, &glecs_meta_nil);
	define_gd_literal("bool", ecs_primitive_kind_t::EcsBool, &glecs_meta_bool);
	define_gd_literal("int", ecs_primitive_kind_t::EcsI64, &glecs_meta_int);
	define_gd_literal("float", ecs_primitive_kind_t::EcsF64, &glecs_meta_float);
	define_gd_component<String>("String", &glecs_meta_string);

	{ // Add glecs/meta/Vector2 type
		ecs_struct_desc_t desc = {
			.entity = glecs_meta_vector2,
			.members = {
				{.name = "x", .type = glecs_meta_real},
				{.name = "y", .type = glecs_meta_real}
			}
		}; ecs_struct_init(_raw, &desc);
		ecs_add_path_w_sep(
			_raw,
			glecs_meta_vector2,
			glecs_meta,
			"Vector2",
			"/",
			"/root/"
		);
	}

	{ // Add glecs/meta/Vector2i type
		ecs_struct_desc_t desc = {
			.entity = glecs_meta_vector2i,
			.members = {
				{.name = "x", .type = ecs_id(ecs_i32_t)},
				{.name = "y", .type = ecs_id(ecs_i32_t)}
			}
		}; ecs_struct_init(_raw, &desc);
		ecs_add_path_w_sep(
			_raw,
			glecs_meta_vector2i,
			glecs_meta,
			"Vector2I",
			"/",
			"/root/"
		);
	}

	{ // Add glecs/meta/Rect type
		ecs_struct_desc_t desc = {
			.entity = glecs_meta_rect2,
			.members = {
				{.name = "position", .type = glecs_meta_vector2},
				{.name = "size", .type = glecs_meta_vector2}
			}
		}; ecs_struct_init(_raw, &desc);
		ecs_add_path_w_sep(
			_raw,
			glecs_meta_rect2,
			glecs_meta,
			"Rect2",
			"/",
			"/root/"
		);
	}

	{ // Add glecs/meta/Rect2i type
		ecs_struct_desc_t desc = {
			.entity = glecs_meta_rect2i,
			.members = {
				{.name = "position", .type = glecs_meta_vector2i},
				{.name = "size", .type = glecs_meta_vector2i}
			}
		}; ecs_struct_init(_raw, &desc);
		ecs_add_path_w_sep(
			_raw,
			glecs_meta_rect2i,
			glecs_meta,
			"Rect2i",
			"/",
			"/root/"
		);
	}

	{ // Add glecs/meta/Vector3 type
		ecs_struct_desc_t desc = {
			.entity = glecs_meta_vector3,
			.members = {
				{.name = "x", .type = glecs_meta_real},
				{.name = "y", .type = glecs_meta_real},
				{.name = "z", .type = glecs_meta_real}
			}
		}; ecs_struct_init(_raw, &desc);
		ecs_add_path_w_sep(
			_raw,
			glecs_meta_vector3,
			glecs_meta,
			"Vector3",
			"/",
			"/root/"
		);
	}

	{ // Add glecs/meta/Vector3i type
		ecs_struct_desc_t desc = {
			.entity = glecs_meta_vector3i,
			.members = {
				{.name = "x", .type = ecs_id(ecs_i32_t)},
				{.name = "y", .type = ecs_id(ecs_i32_t)},
				{.name = "z", .type = ecs_id(ecs_i32_t)}
			}
		}; ecs_struct_init(_raw, &desc);
		ecs_add_path_w_sep(
			_raw,
			glecs_meta_vector3i,
			glecs_meta,
			"Vector3i",
			"/",
			"/root/"
		);
	}

	{ // Add glecs/meta/Transform2D type
		ecs_struct_desc_t desc = {
			.entity = glecs_meta_transform2d,
			.members = {
				{.name = "x", .type = glecs_meta_vector2},
				{.name = "y", .type = glecs_meta_vector2},
				{.name = "origin", .type = glecs_meta_vector2}
			}
		}; ecs_struct_init(_raw, &desc);
		ecs_add_path_w_sep(
			_raw,
			glecs_meta_transform2d,
			glecs_meta,
			"Transform2D",
			"/",
			"/root/"
		);
	}

	{ // Add glecs/meta/Vector4 type
		ecs_struct_desc_t desc = {
			.entity = glecs_meta_vector4,
			.members = {
				{.name = "x", .type = glecs_meta_real},
				{.name = "y", .type = glecs_meta_real},
				{.name = "z", .type = glecs_meta_real},
				{.name = "w", .type = glecs_meta_real}
			}
		}; ecs_struct_init(_raw, &desc);
		ecs_add_path_w_sep(
			_raw,
			glecs_meta_vector4,
			glecs_meta,
			"Vector4",
			"/",
			"/root/"
		);
	}

	{ // Add glecs/meta/Vector4i type
		ecs_struct_desc_t desc = {
			.entity = glecs_meta_vector4i,
			.members = {
				{.name = "x", .type = ecs_id(ecs_i32_t)},
				{.name = "y", .type = ecs_id(ecs_i32_t)},
				{.name = "z", .type = ecs_id(ecs_i32_t)},
				{.name = "w", .type = ecs_id(ecs_i32_t)}
			}
		}; ecs_struct_init(_raw, &desc);
		ecs_add_path_w_sep(
			_raw,
			glecs_meta_vector4i,
			glecs_meta,
			"Vector4i",
			"/",
			"/root/"
		);
	}

	{ // Add glecs/meta/Plane type
		ecs_struct_desc_t desc = {
			.entity = glecs_meta_plane,
			.members = {
				{.name = "x", .type = glecs_meta_real},
				{.name = "y", .type = glecs_meta_real},
				{.name = "z", .type = glecs_meta_real},
				{.name = "d", .type = glecs_meta_real},
				{.name = "normal", .type = glecs_meta_vector3}
			}
		}; ecs_struct_init(_raw, &desc);
		ecs_add_path_w_sep(
			_raw,
			glecs_meta_plane,
			glecs_meta,
			"Plane",
			"/",
			"/root/"
		);
	}

	{ // Add glecs/meta/Quaternion type
		ecs_struct_desc_t desc = {
			.entity = glecs_meta_quaternion,
			.members = {
				{.name = "x", .type = glecs_meta_real},
				{.name = "y", .type = glecs_meta_real},
				{.name = "z", .type = glecs_meta_real},
				{.name = "w", .type = glecs_meta_real}
			}
		}; ecs_struct_init(_raw, &desc);
		ecs_add_path_w_sep(
			_raw,
			glecs_meta_quaternion,
			glecs_meta,
			"Quaternion",
			"/",
			"/root/"
		);
	}

	{ // Add glecs/meta/AABB type
		ecs_struct_desc_t desc = {
			.entity = glecs_meta_aabb,
			.members = {
				{.name = "position", .type = glecs_meta_vector3},
				{.name = "size", .type = glecs_meta_vector3}
			}
		}; ecs_struct_init(_raw, &desc);
		ecs_add_path_w_sep(
			_raw,
			glecs_meta_aabb,
			glecs_meta,
			"AABB",
			"/",
			"/root/"
		);
	}

	{ // Add glecs/meta/Basis type
		ecs_struct_desc_t desc = {
			.entity = glecs_meta_basis,
			.members = {
				{.name = "x", .type = glecs_meta_vector3},
				{.name = "y", .type = glecs_meta_vector3},
				{.name = "z", .type = glecs_meta_vector3}
			}
		}; ecs_struct_init(_raw, &desc);
		ecs_add_path_w_sep(
			_raw,
			glecs_meta_basis,
			glecs_meta,
			"Basis",
			"/",
			"/root/"
		);
	}

	{ // Add glecs/meta/Transform3D type
		ecs_struct_desc_t desc = {
			.entity = glecs_meta_transform3d,
			.members = {
				{.name = "basis", .type = glecs_meta_basis},
				{.name = "origin", .type = glecs_meta_vector3}
			}
		}; ecs_struct_init(_raw, &desc);
		ecs_add_path_w_sep(
			_raw,
			glecs_meta_transform3d,
			glecs_meta,
			"Transform3D",
			"/",
			"/root/"
		);
	}

	{ // Add glecs/meta/Projection type
		ecs_struct_desc_t desc = {
			.entity = glecs_meta_projection,
			.members = {
				{.name = "x", .type = glecs_meta_vector4},
				{.name = "y", .type = glecs_meta_vector4},
				{.name = "z", .type = glecs_meta_vector4},
				{.name = "w", .type = glecs_meta_vector4}
			}
		}; ecs_struct_init(_raw, &desc);
		ecs_add_path_w_sep(
			_raw,
			glecs_meta_projection,
			glecs_meta,
			"Projection",
			"/",
			"/root/"
		);
	}

	{ // Add glecs/meta/Color type
		ecs_struct_desc_t desc = {
			.entity = glecs_meta_color,
			.members = {
				{.name = "r", .type = ecs_id(ecs_f32_t)},
				{.name = "g", .type = ecs_id(ecs_f32_t)},
				{.name = "b", .type = ecs_id(ecs_f32_t)},
				{.name = "a", .type = ecs_id(ecs_f32_t)}
			}
		}; ecs_struct_init(_raw, &desc);
		ecs_add_path_w_sep(
			_raw,
			glecs_meta_color,
			glecs_meta,
			"Color",
			"/",
			"/root/"
		);
	}

	define_gd_component<StringName>("StringName", &glecs_meta_string_name);
	define_gd_component<NodePath>("NodePath", &glecs_meta_node_path);
	define_gd_component<RID>("RID", &glecs_meta_rid);
	define_gd_component<Variant>("Object", &glecs_meta_object);
	define_gd_component<Callable>("Callable", &glecs_meta_callable);
	define_gd_component<Signal>("Signal", &glecs_meta_signal);
	define_gd_component<Dictionary>("Dictionary", &glecs_meta_dictionary);
	define_gd_component<Array>("Array", &glecs_meta_array);
	define_gd_component<PackedByteArray>("PackedByteArray", &glecs_meta_packed_byte_array);
	define_gd_component<PackedInt32Array>("PackedInt32Array", &glecs_meta_packed_int32_array);
	define_gd_component<PackedInt64Array>("PackedInt64Array", &glecs_meta_packed_int64_array);
	define_gd_component<PackedFloat32Array>("PackedFloat32Array", &glecs_meta_packed_float32_array);
	define_gd_component<PackedFloat64Array>("PackedFloat64Array", &glecs_meta_packed_float64_array);
	define_gd_component<PackedStringArray>("PackedStringArray", &glecs_meta_packed_string_array);
	define_gd_component<PackedVector2Array>("PackedVector2Array", &glecs_meta_packed_vector2_array);
	define_gd_component<PackedVector3Array>("PackedVector3Array", &glecs_meta_packed_vector3_array);
	define_gd_component<PackedColorArray>("PackedColorArray", &glecs_meta_packed_color_array);
	define_gd_component<PackedVector4Array>("PackedVector4Array", &glecs_meta_packed_vector4_array);

	#undef DEFINE_GD_COMPONENT
	#undef DEFINE_GD_COMPONENT_WITH_HOOKS

	_register_modules_from_scripts(0);
}

ecs_entity_t GFWorld::coerce_id(const Variant value) {
	String string;
	godot::CharString str;
	Vector2i vec;
	Object* obj;
	switch (value.get_type()) {
		case Variant::INT:
			return value;
		case Variant::VECTOR2I:
			vec = Vector2i(value);
			return ecs_pair(vec.x, vec.y);
		case Variant::OBJECT:
			obj = value;
			if (obj == nullptr) {
				ERR(0,
					"Failed to coerce Object to ID\n",
					"Null objects can't be coerced to valid entity IDs"
				);
			}
			if (obj->is_class(GFEntity::get_class_static())) {
				return Object::cast_to<GFEntity>(obj)->get_id();
			}
			if (obj->is_class(Script::get_class_static())) {
				Ref<Script> script = value;
				if (!ClassDB::is_parent_class(
					script->get_instance_base_type(),
					GFRegisterableEntity::get_class_static()
				)) {
					// Script does not inherit registerable entity
					ERR(0,
						"Failed to coerce Script to ID\n",
						"Script ", script, " does not derive from ",
						GFRegisterableEntity::get_class_static()
					);
				}
				if (!registered_entity_ids.has(script)) {
					// Script is not registered
					return register_script_id(script);
					// TODO: implement option to turn off auto registering

					// ERR(0,
					//	"Failed to coerce Script to ID\n",
					//	"The script ", script, " has not been registered with world ", this
					// );
				}
				ecs_entity_t id = registered_entity_ids.get(obj, 0);
				if (id == 0) {
					ERR(0,
						"Failed to coerce Script to ID\n",
						"Script ", script, " is not registered in world"
					);
				}
				return id;
			}
			ERR(0,
				"Failed to coerce Object to ID\n",
				"Objects of type ",
				obj->get_class(),
				" can't be coerced to valid entity IDs"
			);
			break;
		case Variant::STRING:
		case Variant::STRING_NAME:
		case Variant::NODE_PATH:
			string = value;
			str = string.utf8();
			return ecs_lookup_path_w_sep(raw(), 0, str, "/", "/root/", false);
		default:
			break;
	};

	ERR(0,
		"Variants of type ",
		value.get_type_name(value.get_type()),
		" can't be coerced to valid entity IDs"
	);
}

int64_t GFWorld::get_raw() const {
	assert(sizeof(int64_t) == sizeof(ecs_world_t*));
	return reinterpret_cast<int64_t>(raw());
}

Ref<GFEntity> GFWorld::lookup(const String path) {
	const char* path_ptr = path.utf8().get_data();
	ecs_entity_t id = ecs_lookup_path_w_sep(
		raw(),
		0,
		path_ptr,
		"/",
		"/root/",
		false
	);

	if (!ecs_is_alive(raw(), id)) {
		return nullptr;
	}

	return GFEntity::from_id(id, this);
}

Ref<GFPair> GFWorld::pair(const Variant first, const Variant second) {
	return GFPair::from_ids(coerce_id(first), coerce_id(second), this);
}

ecs_entity_t GFWorld::pair_ids(
	const ecs_entity_t first,
	const ecs_entity_t second
) const {
	if (ECS_IS_PAIR(first)) {
		ERR(0,
			"Could not pair IDs\n",
			"First ID is a pair, and pairs can not contain pairs recursively"
		);
	}
	if (ECS_IS_PAIR(second)) {
		ERR(0,
			"Could not pair IDs\n",
			"First ID is a pair, and pairs can not contain pairs recursively"
		);
	}
	return ecs_make_pair(first, second);
}

void GFWorld::progress(double delta) const {
	ecs_progress(raw(), delta);
}

Ref<GFRegisterableEntity> GFWorld::register_script(const Ref<Script> script) {
	Ref<GFRegisterableEntity> ett = register_script_id_no_user_call(script);
	if (ett == nullptr) {
		return nullptr;
	}
	ett->call_user_register();
	return ett;
}

ecs_entity_t GFWorld::register_script_id(const Ref<Script> script) {
	Ref<GFRegisterableEntity> ett = register_script_id_no_user_call(script);
	ett->call_user_register();
	return ett->get_id();
}

Ref<GFRegisterableEntity> GFWorld::register_script_id_no_user_call(const Ref<Script> script) {
	if (*script == nullptr) {
		ERR(nullptr,
			"Could not register script\n",
			"	Script is null."
		);
	}
	if (!godot::ClassDB::is_parent_class(
		script->get_instance_base_type(),
		GFRegisterableEntity::get_class_static()
	)) {
		ERR(nullptr,
			"Could not register script\n",
			"	Script, ", script, ", does not inherit from ",
			GFRegisterableEntity::get_class_static()
		);
	}

	if (registered_entity_ids.has(script)) {
		Ref<GFRegisterableEntity> reg_ett
			= GFRegisterableEntity::from_script(script, this);
		ERR(reg_ett,
			"Could not register script\n",
			"	Script ", script, " is already registered"
		);
		return reg_ett;
	}

	ecs_entity_t id = ecs_new(raw());
	registered_entity_ids[script] = id;
	registered_entity_scripts[id] = script;
	if (ecs_get_scope(raw()) != 0) {
		ecs_add_id(raw(), id, ecs_childof(ecs_get_scope(raw())));
	}

	Ref<GFRegisterableEntity> reg_ett
		= GFRegisterableEntity::from_script(script, this);

	reg_ett->call_internal_register();

	// Set name of registered entity
	if (ecs_get_name(raw(), id) == nullptr) {
		// Set name to script's global name if available, but fall back to script path.
		String name = script->get_global_name();
		if (name.length() == 0) {
			// Global name not found, get name from path
			String path = script->get_path();
			if (path.length() != 0) {
				PackedStringArray path_parts = path.get_basename().split("/");
				name = path_parts[path_parts.size()-1];

				if (!ecs_has_id(raw(), id, EcsModule)) {
					// Capitalize if entity is not a module
					name = Utils::into_pascal_case(name);
				} else {
					name = name.to_snake_case();
				}
			}
		}
		if (name.length() != 0) {
			// Found suitable name, set in entity
			ecs_set_name(raw(), id, name.utf8());
		}
	}

	return reg_ett;
}

void GFWorld::_register_modules_from_scripts(int depth=0) {
	const auto MODULES = "_glecs_modules";
	// Register modules from scripts
	Engine* engine = Engine::get_singleton();
	if (engine->has_singleton(MODULES)) {
		if (depth != 0) {
			UtilityFunctions::push_warning("Load modules from scripts was delayed.\n",
				"	Found \"", MODULES, "\" after", depth, " iteration(s)."
			);
		}
		GLECS_SCOPE(this, glecs, {
			Object* glecs_modules = engine->get_singleton(MODULES);
			glecs_modules->call("register_modules", this);
		});
	} else {
		if (depth == 10) {
			UtilityFunctions::push_warning("Failed to load modules from scripts.\n",
				"	Could not find \"", MODULES, "\"."
			);
			return;
		}
		call_deferred("_register_modules_from_scripts", depth+1);
	}
}

void GFWorld::start_rest_api() const {
	ecs_entity_t rest_id = ecs_lookup_path_w_sep(
		raw(),
		0,
		"flecs.rest.Rest",
		".",
		"",
		false
	);
	EcsRest rest = (EcsRest)EcsRest();
	ecs_set_id(raw(), rest_id, rest_id, sizeof(EcsRest), &rest);
}

void GFWorld::set_gd_struct_from_variant(
	const Variant value,
	const ecs_entity_t gd_struct,
	void* out
) const {
	Variant::Type type = id_as_variant_type(gd_struct);
	switch (type) {
        case Variant::NIL: ERR(/**/, "Can't set nil");
        case Variant::BOOL: *static_cast<bool*>(out) = value; break;
        case Variant::INT: *static_cast<int64_t*>(out) = value; break;
        case Variant::FLOAT: *static_cast<double*>(out) = value; break;
        case Variant::STRING: *static_cast<String*>(out) = value; break;
        case Variant::VECTOR2: *static_cast<Vector2*>(out) = value; break;
        case Variant::VECTOR2I: *static_cast<Vector2i*>(out) = value; break;
        case Variant::RECT2: *static_cast<Rect2*>(out) = value; break;
        case Variant::RECT2I: *static_cast<Rect2i*>(out) = value; break;
        case Variant::VECTOR3: *static_cast<Vector3*>(out) = value; break;
        case Variant::VECTOR3I: *static_cast<Vector3i*>(out) = value; break;
        case Variant::TRANSFORM2D: *static_cast<Transform2D*>(out) = value; break;
        case Variant::VECTOR4: *static_cast<Vector4*>(out) = value; break;
        case Variant::VECTOR4I: *static_cast<Vector4i*>(out) = value; break;
        case Variant::PLANE: *static_cast<Plane*>(out) = value; break;
        case Variant::QUATERNION: *static_cast<Quaternion*>(out) = value; break;
        case Variant::AABB: *static_cast<AABB*>(out) = value; break;
        case Variant::BASIS: *static_cast<Basis*>(out) = value; break;
        case Variant::TRANSFORM3D: *static_cast<Transform3D*>(out) = value; break;
        case Variant::PROJECTION: *static_cast<Projection*>(out) = value; break;
        case Variant::COLOR: *static_cast<Color*>(out) = value; break;
        case Variant::STRING_NAME: *static_cast<StringName*>(out) = value; break;
        case Variant::NODE_PATH: *static_cast<NodePath*>(out) = value; break;
        case Variant::RID: *static_cast<RID*>(out) = value; break;
        case Variant::OBJECT: *static_cast<Variant*>(out) = value; break;
        case Variant::CALLABLE: *static_cast<Callable*>(out) = value; break;
        case Variant::SIGNAL: *static_cast<Signal*>(out) = value; break;
        case Variant::DICTIONARY: *static_cast<Dictionary*>(out) = value; break;
        case Variant::ARRAY: *static_cast<Array*>(out) = value; break;
        case Variant::PACKED_BYTE_ARRAY: *static_cast<PackedByteArray*>(out) = value; break;
        case Variant::PACKED_INT32_ARRAY: *static_cast<PackedInt32Array*>(out) = value; break;
        case Variant::PACKED_INT64_ARRAY: *static_cast<PackedInt64Array*>(out) = value; break;
        case Variant::PACKED_FLOAT32_ARRAY: *static_cast<PackedFloat32Array*>(out) = value; break;
        case Variant::PACKED_FLOAT64_ARRAY: *static_cast<PackedFloat64Array*>(out) = value; break;
        case Variant::PACKED_STRING_ARRAY: *static_cast<PackedStringArray*>(out) = value; break;
        case Variant::PACKED_VECTOR2_ARRAY: *static_cast<PackedVector2Array*>(out) = value; break;
        case Variant::PACKED_VECTOR3_ARRAY: *static_cast<PackedVector3Array*>(out) = value; break;
        case Variant::PACKED_COLOR_ARRAY: *static_cast<PackedColorArray*>(out) = value; break;
        case Variant::PACKED_VECTOR4_ARRAY: *static_cast<PackedVector4Array*>(out) = value; break;
        case Variant::VARIANT_MAX: ERR(/**/, "Can't set Variant::VARIANT_MAX");
	}
}

ecs_entity_t GFWorld::variant_type_to_id(Variant::Type type) {
	if (type == Variant::Type::VARIANT_MAX) {
		throw "No ID exists for VARIANT_MAX";
	}
	return GFWorld::glecs_meta_nil + type;
}

String GFWorld::id_to_text(ecs_entity_t id) const {
	CHECK_ENTITY_ALIVE(id, this, "",
		"Failed to convert ID to text\n"
	);
	if (ecs_id_is_pair(id)) {
		return String("(")
			+ id_to_text(ECS_PAIR_FIRST(id)) + ", "
			+ id_to_text(ECS_PAIR_SECOND(id)) + ")"
		;
	}
	return String(ecs_get_name(raw(), id))
		+ "#" + String::num_int64(id)
	;
}



Variant::Type GFWorld::id_as_variant_type(ecs_entity_t id) const {
	if (id < GFWorld::glecs_meta_nil || id > glecs_meta_packed_vector4_array) {
		return godot::Variant::NIL;
	}
	Variant::Type type = Variant::Type(id - GFWorld::glecs_meta_nil);
	return type;
}

Variant::Type GFWorld::id_into_variant_type(ecs_entity_t id) const {
	Variant::Type type = id_as_variant_type(id);
	if (type != Variant::NIL) {
		return type;
	}

	const EcsPrimitive* primi_c = ecs_get(raw(), id, EcsPrimitive);
	if (primi_c == nullptr) {
		return Variant::NIL;
	}
	switch (primi_c->kind) {
        case EcsBool: return Variant::BOOL;
        case EcsChar: return Variant::STRING;
        case EcsByte: return Variant::INT;
        case EcsU8: return Variant::INT;
        case EcsU16: return Variant::INT;
        case EcsU32: return Variant::INT;
        case EcsU64: return Variant::INT;
        case EcsI8: return Variant::INT;
        case EcsI16: return Variant::INT;
        case EcsI32: return Variant::INT;
        case EcsI64: return Variant::INT;
        case EcsF32: return Variant::FLOAT;
        case EcsF64: return Variant::FLOAT;
        case EcsUPtr: return Variant::OBJECT;
        case EcsIPtr: return Variant::OBJECT;
        case EcsString: return Variant::STRING;
        case EcsEntity: return Variant::INT;
        case EcsId: return Variant::INT;
	}

	return type;
}

// ----------------------------------------------
// --- Maybe expose later ---
// ----------------------------------------------

PropertyInfo GFWorld::_comp_get_property_info(
	ecs_entity_t entity,
	ecs_entity_t component,
	const Variant member,
	String name_prefix
) const {
	ecs_entity_t main_id = get_main_id(component);
	if (!is_id_alive(main_id)) {
		return {};
	}

	auto info = PropertyInfo();
	info.usage = PROPERTY_USAGE_EDITOR;

	const EcsStruct* struct_c = ecs_get(raw(), main_id, EcsStruct);
	switch (member.get_type()) {
		case Variant::INT: {
			const ecs_member_t* member_c = ecs_vec_get_t(
				&struct_c->members,
				ecs_member_t,
				static_cast<int>(member)
			);
			info.name = name_prefix + member_c->name;
			info.type = id_into_variant_type(member_c->type);
			return info;
		}
		case Variant::STRING: {
			for (int i=0; i != struct_c->members.count; i++) {
				const ecs_member_t* member_c = ecs_vec_get_t(
					&struct_c->members,
					ecs_member_t,
					i
				);
				if (!strcmp(member_c->name, String(member).utf8())) {
					continue;
				}

				info.name = name_prefix + member_c->name;
				info.type = id_into_variant_type(member_c->type);
				return info;
			}
			return {};
		}
		default: ERR({}, "TODO: Add msg");
	}

	return {};
}

void GFWorld::_comp_get_property_list(
	ecs_entity_t entity,
	ecs_entity_t component,
	List<PropertyInfo>* list,
	String name_prefix
) const {
	ecs_entity_t main_id = get_main_id(component);
	if (!is_id_alive(main_id)) {
		return;
	}

	const EcsStruct* struct_c = ecs_get(raw(), main_id, EcsStruct);
	for (int i=0; i != struct_c->members.count; i++) {
		list->push_back(_comp_get_property_info(
			entity,
			component,
			i,
			name_prefix
		));
	}

	return;
}

Variant GFWorld::_comp_getm(ecs_entity_t source, ecs_entity_t comp, String member) const {
	if (!ecs_has_id(raw(), source, comp)) {
		ERR(nullptr, "Failed to get member",
			"\n	Entity ",
			source,
			" does not have component ",
			id_to_text(comp)
		);
	}

	// Get member data
	const EcsMember* member_data = _comp_get_member_data(comp, member);
	if (member_data == nullptr) {
		// Member data is null. This should never happen.
		ERR(nullptr,
			"Member metadata is null"
		);
	}
	void* member_value_ptr = _comp_get_member_ptr_mut_at(source, comp, member_data->offset);
	if (member_value_ptr == nullptr) {
		ERR(nullptr,
			"Member value is null"
		);
	}

	return _variant_from_member_ptr(member_value_ptr, member_data->type);
}

const EcsMember* GFWorld::_comp_get_member_data(ecs_entity_t comp, const String member) const {
	CharString member_char = member.utf8();

	ecs_entity_t main_id = get_main_id(comp);

	// Get member ID
	ecs_entity_t member_id = ecs_lookup_child(raw(), main_id, member_char);

	if (member_id == 0) {
		ERR(nullptr,
			"No member named \"",
			member,
			"\" found in component ",
			id_to_text(comp)
		);
	}

	// Get member data
	const EcsMember* member_data = ecs_get(raw(), member_id, EcsMember);

	return member_data;
}

bool GFWorld::_comp_setm(
	ecs_entity_t source,
	ecs_entity_t comp,
	String member,
	Variant value
) const {
	if (!_comp_setm_no_notify(source, comp, member, value)) {
		return false;
	}
	ecs_modified_id(raw(), source, comp);
	return true;
}

bool GFWorld::_comp_setm_no_notify(
	ecs_entity_t source,
	ecs_entity_t comp,
	String member,
	Variant value
) const {
	// Get member data
	const EcsMember* member_data = _comp_get_member_data(comp, member);
	if (member_data == nullptr) {
		// Member data is null. This should never happen.
		ERR(false,
			"Member metadata is null"
		);
	}
	void* member_ptr = _comp_get_member_ptr_mut_at(
		source,
		comp,
		member_data->offset
	);
	if (member_ptr == nullptr) {
		ERR(false,
			"Member pointer is null"
		);
	}

	Utils::set_type_from_variant(value, member_data->type, this, member_ptr);
	return true;
}

String GFWorld::entity_unique_name(ecs_entity_t parent, String name) const {
	if (ecs_lookup_child(
		raw(),
		parent,
		name.utf8()
	) == 0) {
		// No name conflicts, set name and return
		return name;
	}

	// Find have many digits are at the end of the name
	int trailing_digits = 0;
	for (int i=0; i != name.length(); i++) {
		char32_t digit = name[name.length()-i-1];
		if (digit >= '0' && digit <= '9') {
			trailing_digits++;
		} else {
			break;
		}
	}

	int number = name.substr(name.length()-trailing_digits).to_int();
	String base_name = name.substr(0, name.length()-trailing_digits);
	String unique_name = String();
	do {
		number += 1;
		unique_name = base_name + String::num_uint64(number);
	} while (ecs_lookup_child(
		raw(),
		parent,
		unique_name.utf8()
	));

	return unique_name;
}

// ----------------------------------------------
// --- Unexposed ---
// ----------------------------------------------

/// If id is a pair then returns the ID that is a component.
/// Id id is not a pair, then just returns id.
ecs_entity_t GFWorld::get_main_id(ecs_entity_t id) const {
	if (ECS_IS_PAIR(id)) {
		ecs_entity_t first = ECS_PAIR_FIRST(id);
		if (ecs_has_id(raw(), first, FLECS_IDEcsStructID_)) {
			return first;
		}
		return ECS_PAIR_SECOND(id);
	}
	return id;
}

ecs_entity_t GFWorld::get_registered_id(const Ref<Script> script) const {
	return registered_entity_ids.get(script, 0);
}

Ref<Script> GFWorld::get_registered_script(ecs_entity_t id) const {
	if (ecs_id_is_pair(id)) {
		Ref<Script> first = registered_entity_scripts.get(
			ECS_PAIR_FIRST(id),
			nullptr
		);
		Ref<Script> second = registered_entity_scripts.get(
			ECS_PAIR_SECOND(id),
			nullptr
		);
		if (first != nullptr && second != nullptr) {
			if (ClassDB::is_parent_class(
				second->get_instance_base_type(),
				GFComponent::get_class_static()
			)) {
				return second;
			}
			return first;
		}
		if (first != nullptr) {
			return first;
		}
		if (second != nullptr) {
			return second;
		}
		return nullptr;
	}
	return registered_entity_scripts.get(id, nullptr);
}

GFWorld* GFWorld::world_or_singleton(GFWorld* world) {
	if (
		world == nullptr
		|| !UtilityFunctions::is_instance_id_valid(
			world->get_instance_id()
		)
	) {
		return GFWorld::get_default_world();
	}
	return world;
}

GFWorld* GFWorld::get_singleton() {
	return GFWorld::get_global_thread_singleton();
}

void GFWorld::copy_component_ptr(
	const void* src_ptr,
	void* dst_ptr,
	ecs_entity_t component
) const {
	const EcsStruct* c_struct = ecs_get(_raw, component, EcsStruct);
	if (c_struct == nullptr) {
		return;
	}
	for (int i=0; i != ecs_vec_count(&c_struct->members); i++) {
		const ecs_member_t* member = ecs_vec_get_t(&c_struct->members, ecs_member_t, i);
		auto src_member_value = static_cast<const void*>(static_cast<const int8_t*>(src_ptr) + member->offset);
		auto dst_member_value = static_cast<void*>(static_cast<int8_t*>(dst_ptr) + member->offset);
		copy_gd_type_ptr(src_member_value, dst_member_value, member->type);
	}
}

void GFWorld::copy_gd_type_ptr(
	const void* src_ptr,
	void* dst_ptr,
	ecs_entity_t type
) const {
	Variant::Type vari_type = id_as_variant_type(type);

	switch (vari_type) {
	case(Variant::Type::NIL): {
		if (ecs_has(_raw, type, EcsStruct)) {
			copy_component_ptr(src_ptr, dst_ptr, type);
		};
		break;
	}
	case(Variant::Type::BOOL): *static_cast<bool*>(dst_ptr) = *static_cast<const bool*>(src_ptr); break;
	case(Variant::Type::INT): *static_cast<int64_t*>(dst_ptr) = *static_cast<const int64_t*>(src_ptr); break;
	case(Variant::Type::FLOAT): *static_cast<double*>(dst_ptr) = *static_cast<const double*>(src_ptr); break;
	case(Variant::Type::STRING): *static_cast<String*>(dst_ptr) = *static_cast<const String*>(src_ptr); break;
	case(Variant::Type::VECTOR2): *static_cast<Vector2*>(dst_ptr) = *static_cast<const Vector2*>(src_ptr); break;
	case(Variant::Type::VECTOR2I): *static_cast<Vector2i*>(dst_ptr) = *static_cast<const Vector2i*>(src_ptr); break;
	case(Variant::Type::RECT2): *static_cast<Rect2*>(dst_ptr) = *static_cast<const Rect2*>(src_ptr); break;
	case(Variant::Type::RECT2I): *static_cast<Rect2i*>(dst_ptr) = *static_cast<const Rect2i*>(src_ptr); break;
	case(Variant::Type::VECTOR3): *static_cast<Vector3*>(dst_ptr) = *static_cast<const Vector3*>(src_ptr); break;
	case(Variant::Type::VECTOR3I): *static_cast<Vector3i*>(dst_ptr) = *static_cast<const Vector3i*>(src_ptr); break;
	case(Variant::Type::TRANSFORM2D): *static_cast<Transform2D*>(dst_ptr) = *static_cast<const Transform2D*>(src_ptr); break;
	case(Variant::Type::VECTOR4): *static_cast<Vector4*>(dst_ptr) = *static_cast<const Vector4*>(src_ptr); break;
	case(Variant::Type::VECTOR4I): *static_cast<Vector4i*>(dst_ptr) = *static_cast<const Vector4i*>(src_ptr); break;
	case(Variant::Type::PLANE): *static_cast<Plane*>(dst_ptr) = *static_cast<const Plane*>(src_ptr); break;
	case(Variant::Type::QUATERNION): *static_cast<Quaternion*>(dst_ptr) = *static_cast<const Quaternion*>(src_ptr); break;
	case(Variant::Type::AABB): *static_cast<AABB*>(dst_ptr) = *static_cast<const AABB*>(src_ptr); break;
	case(Variant::Type::BASIS): *static_cast<Basis*>(dst_ptr) = *static_cast<const Basis*>(src_ptr); break;
	case(Variant::Type::TRANSFORM3D): *static_cast<Transform3D*>(dst_ptr) = *static_cast<const Transform3D*>(src_ptr); break;
	case(Variant::Type::PROJECTION): *static_cast<Projection*>(dst_ptr) = *static_cast<const Projection*>(src_ptr); break;
	case(Variant::Type::COLOR): *static_cast<Color*>(dst_ptr) = *static_cast<const Color*>(src_ptr); break;
	case(Variant::Type::STRING_NAME): *static_cast<StringName*>(dst_ptr) = *static_cast<const StringName*>(src_ptr); break;
	case(Variant::Type::NODE_PATH): *static_cast<NodePath*>(dst_ptr) = *static_cast<const NodePath*>(src_ptr); break;
	case(Variant::Type::RID): *static_cast<RID*>(dst_ptr) = *static_cast<const RID*>(src_ptr); break;
	case(Variant::Type::OBJECT): *static_cast<Variant*>(dst_ptr) = *static_cast<const Variant*>(src_ptr); break;
	case(Variant::Type::CALLABLE): *static_cast<Callable*>(dst_ptr) = *static_cast<const Callable*>(src_ptr); break;
	case(Variant::Type::SIGNAL): *static_cast<Signal*>(dst_ptr) = *static_cast<const Signal*>(src_ptr); break;
	case(Variant::Type::DICTIONARY): *static_cast<Dictionary*>(dst_ptr) = *static_cast<const Dictionary*>(src_ptr); break;
	case(Variant::Type::ARRAY): *static_cast<Array*>(dst_ptr) = *static_cast<const Array*>(src_ptr); break;
	case(Variant::Type::PACKED_BYTE_ARRAY): *static_cast<PackedByteArray*>(dst_ptr) = *static_cast<const PackedByteArray*>(src_ptr); break;
	case(Variant::Type::PACKED_INT32_ARRAY): *static_cast<PackedInt32Array*>(dst_ptr) = *static_cast<const PackedInt32Array*>(src_ptr); break;
	case(Variant::Type::PACKED_INT64_ARRAY): *static_cast<PackedInt64Array*>(dst_ptr) = *static_cast<const PackedInt64Array*>(src_ptr); break;
	case(Variant::Type::PACKED_FLOAT32_ARRAY): *static_cast<PackedFloat32Array*>(dst_ptr) = *static_cast<const PackedFloat32Array*>(src_ptr); break;
	case(Variant::Type::PACKED_FLOAT64_ARRAY): *static_cast<PackedFloat64Array*>(dst_ptr) = *static_cast<const PackedFloat64Array*>(src_ptr); break;
	case(Variant::Type::PACKED_STRING_ARRAY): *static_cast<PackedStringArray*>(dst_ptr) = *static_cast<const PackedStringArray*>(src_ptr); break;
	case(Variant::Type::PACKED_VECTOR2_ARRAY): *static_cast<PackedVector2Array*>(dst_ptr) = *static_cast<const PackedVector2Array*>(src_ptr); break;
	case(Variant::Type::PACKED_VECTOR3_ARRAY): *static_cast<PackedVector3Array*>(dst_ptr) = *static_cast<const PackedVector3Array*>(src_ptr); break;
	case(Variant::Type::PACKED_COLOR_ARRAY): *static_cast<PackedColorArray*>(dst_ptr) = *static_cast<const PackedColorArray*>(src_ptr); break;
	case(Variant::Type::PACKED_VECTOR4_ARRAY): *static_cast<PackedVector4Array*>(dst_ptr) = *static_cast<const PackedVector4Array*>(src_ptr); break;
	case(Variant::Type::VARIANT_MAX): throw "VARIANT_MAX can't be deinitialized";
	}
}

void GFWorld::deinit_component_ptr(
	void* ptr,
	ecs_entity_t component
) const {
	const EcsStruct* c_struct = ecs_get(_raw, component, EcsStruct);
	if (c_struct == nullptr) {
		return;
	}
	for (int i=0; i != ecs_vec_count(&c_struct->members); i++) {
		const ecs_member_t* member = ecs_vec_get_t(&c_struct->members, ecs_member_t, i);
		auto member_value = static_cast<void*>(static_cast<int8_t*>(ptr) + member->offset);
		deinit_gd_type_ptr(member_value, member->type);
	}
}

void GFWorld::deinit_gd_type_ptr(
	void* ptr,
	ecs_entity_t type
) const {
	Variant::Type vari_type = id_as_variant_type(type);

	switch (vari_type) {
	case(Variant::Type::NIL): {
		if (ecs_has(_raw, type, EcsStruct)) {
			deinit_component_ptr(ptr, type);
		};
		break;
	}
	case(Variant::Type::BOOL): break;
	case(Variant::Type::INT): break;
	case(Variant::Type::FLOAT): break;
	case(Variant::Type::STRING): (*static_cast<String*>(ptr)).~String(); break;
	case(Variant::Type::VECTOR2): (*static_cast<Vector2*>(ptr)).~Vector2(); break;
	case(Variant::Type::VECTOR2I): (*static_cast<Vector2i*>(ptr)).~Vector2i(); break;
	case(Variant::Type::RECT2): (*static_cast<Rect2*>(ptr)).~Rect2(); break;
	case(Variant::Type::RECT2I): (*static_cast<Rect2i*>(ptr)).~Rect2i(); break;
	case(Variant::Type::VECTOR3): (*static_cast<Vector3*>(ptr)).~Vector3(); break;
	case(Variant::Type::VECTOR3I): (*static_cast<Vector3i*>(ptr)).~Vector3i(); break;
	case(Variant::Type::TRANSFORM2D): (*static_cast<Transform2D*>(ptr)).~Transform2D(); break;
	case(Variant::Type::VECTOR4): (*static_cast<Vector4*>(ptr)).~Vector4(); break;
	case(Variant::Type::VECTOR4I): (*static_cast<Vector4i*>(ptr)).~Vector4i(); break;
	case(Variant::Type::PLANE): (*static_cast<Plane*>(ptr)).~Plane(); break;
	case(Variant::Type::QUATERNION): (*static_cast<Quaternion*>(ptr)).~Quaternion(); break;
	case(Variant::Type::AABB): (*static_cast<AABB*>(ptr)).~AABB(); break;
	case(Variant::Type::BASIS): (*static_cast<Basis*>(ptr)).~Basis(); break;
	case(Variant::Type::TRANSFORM3D): (*static_cast<Transform3D*>(ptr)).~Transform3D(); break;
	case(Variant::Type::PROJECTION): (*static_cast<Projection*>(ptr)).~Projection(); break;
	case(Variant::Type::COLOR): (*static_cast<Color*>(ptr)).~Color(); break;
	case(Variant::Type::STRING_NAME): (*static_cast<StringName*>(ptr)).~StringName(); break;
	case(Variant::Type::NODE_PATH): (*static_cast<NodePath*>(ptr)).~NodePath(); break;
	case(Variant::Type::RID): (*static_cast<RID*>(ptr)).~RID(); break;
	case(Variant::Type::OBJECT): (*static_cast<Variant*>(ptr)).~Variant() ; break;
	case(Variant::Type::CALLABLE): (*static_cast<Callable*>(ptr)).~Callable(); break;
	case(Variant::Type::SIGNAL): (*static_cast<Signal*>(ptr)).~Signal(); break;
	case(Variant::Type::DICTIONARY): (*static_cast<Dictionary*>(ptr)).~Dictionary(); break;
	case(Variant::Type::ARRAY): (*static_cast<Array*>(ptr)).~Array(); break;
	case(Variant::Type::PACKED_BYTE_ARRAY): (*static_cast<PackedByteArray*>(ptr)).~PackedByteArray(); break;
	case(Variant::Type::PACKED_INT32_ARRAY): (*static_cast<PackedInt32Array*>(ptr)).~PackedInt32Array(); break;
	case(Variant::Type::PACKED_INT64_ARRAY): (*static_cast<PackedInt64Array*>(ptr)).~PackedInt64Array(); break;
	case(Variant::Type::PACKED_FLOAT32_ARRAY): (*static_cast<PackedFloat32Array*>(ptr)).~PackedFloat32Array(); break;
	case(Variant::Type::PACKED_FLOAT64_ARRAY): (*static_cast<PackedFloat64Array*>(ptr)).~PackedFloat64Array(); break;
	case(Variant::Type::PACKED_STRING_ARRAY): (*static_cast<PackedStringArray*>(ptr)).~PackedStringArray(); break;
	case(Variant::Type::PACKED_VECTOR2_ARRAY): (*static_cast<PackedVector2Array*>(ptr)).~PackedVector2Array(); break;
	case(Variant::Type::PACKED_VECTOR3_ARRAY): (*static_cast<PackedVector3Array*>(ptr)).~PackedVector3Array(); break;
	case(Variant::Type::PACKED_COLOR_ARRAY): (*static_cast<PackedColorArray*>(ptr)).~PackedColorArray(); break;
	case(Variant::Type::PACKED_VECTOR4_ARRAY): (*static_cast<PackedVector4Array*>(ptr)).~PackedVector4Array(); break;
	case(Variant::Type::VARIANT_MAX): throw "VARIANT_MAX can't be deinitialized";
	}
}

void GFWorld::init_component_ptr(
	void* ptr,
	ecs_entity_t component,
	Variant args
) const {
	const EcsStruct* c_struct = ecs_get(_raw, component, EcsStruct);
	if (c_struct == nullptr) {
		return;
	}
	for (int i=0; i != ecs_vec_count(&c_struct->members); i++) {
		const ecs_member_t* member = ecs_vec_get_t(&c_struct->members, ecs_member_t, i);
		auto member_value = static_cast<void*>(static_cast<int8_t*>(ptr) + member->offset);
		init_gd_type_ptr(member_value, member->type);
	}
}

/// If the type is a Variant, then initializes the pointer as that type
void GFWorld::init_gd_type_ptr(
	void* ptr,
	ecs_entity_t type
) const {
	Variant::Type vari_type = id_as_variant_type(type);

	switch (vari_type) {
	case(Variant::Type::NIL): if (ecs_has(_raw, type, EcsStruct)) {init_component_ptr(ptr, type, Variant());}; break;
	case(Variant::Type::BOOL): *static_cast<bool*>(ptr) = false; break;
	case(Variant::Type::INT): *static_cast<int64_t*>(ptr) = 0; break;
	case(Variant::Type::FLOAT): *static_cast<float*>(ptr) = 0.0; break;
	case(Variant::Type::STRING): new(ptr) String(); break;
	case(Variant::Type::VECTOR2): new(ptr) Vector2(); break;
	case(Variant::Type::VECTOR2I): new(ptr) Vector2i(); break;
	case(Variant::Type::RECT2): new(ptr) Rect2(); break;
	case(Variant::Type::RECT2I): new(ptr) Rect2i(); break;
	case(Variant::Type::VECTOR3): new(ptr) Vector3(); break;
	case(Variant::Type::VECTOR3I): new(ptr) Vector3i(); break;
	case(Variant::Type::TRANSFORM2D): new(ptr) Transform2D(); break;
	case(Variant::Type::VECTOR4): new(ptr) Vector4(); break;
	case(Variant::Type::VECTOR4I): new(ptr) Vector4i(); break;
	case(Variant::Type::PLANE): new(ptr) Plane(); break;
	case(Variant::Type::QUATERNION): new(ptr) Quaternion(); break;
	case(Variant::Type::AABB): new(ptr) AABB(); break;
	case(Variant::Type::BASIS): new(ptr) Basis(); break;
	case(Variant::Type::TRANSFORM3D): new(ptr) Transform3D(); break;
	case(Variant::Type::PROJECTION): new(ptr) Projection(); break;
	case(Variant::Type::COLOR): new(ptr) Color(); break;
	case(Variant::Type::STRING_NAME): new(ptr) StringName(); break;
	case(Variant::Type::NODE_PATH): new(ptr) NodePath(); break;
	case(Variant::Type::RID): new(ptr) RID(); break;
	case(Variant::Type::OBJECT): new(ptr) Variant(nullptr) ; break;
	case(Variant::Type::CALLABLE): new(ptr) Callable(); break;
	case(Variant::Type::SIGNAL): new(ptr) Signal(); break;
	case(Variant::Type::DICTIONARY): new(ptr) Dictionary(); break;
	case(Variant::Type::ARRAY): new(ptr) Array(); break;
	case(Variant::Type::PACKED_BYTE_ARRAY): new(ptr) PackedByteArray(); break;
	case(Variant::Type::PACKED_INT32_ARRAY): new(ptr) PackedInt32Array(); break;
	case(Variant::Type::PACKED_INT64_ARRAY): new(ptr) PackedInt64Array(); break;
	case(Variant::Type::PACKED_FLOAT32_ARRAY): new(ptr) PackedFloat32Array(); break;
	case(Variant::Type::PACKED_FLOAT64_ARRAY): new(ptr) PackedFloat64Array(); break;
	case(Variant::Type::PACKED_STRING_ARRAY): new(ptr) PackedStringArray(); break;
	case(Variant::Type::PACKED_VECTOR2_ARRAY): new(ptr) PackedVector2Array(); break;
	case(Variant::Type::PACKED_VECTOR3_ARRAY): new(ptr) PackedVector3Array(); break;
	case(Variant::Type::PACKED_COLOR_ARRAY): new(ptr) PackedColorArray(); break;
	case(Variant::Type::PACKED_VECTOR4_ARRAY): new(ptr) PackedVector4Array(); break;
	case(Variant::Type::VARIANT_MAX): throw "VARIANT_MAX can't be initialized";
	}
}

bool GFWorld::id_has_child(ecs_entity_t parent, const char* child_name) const {
	return ecs_lookup_path_w_sep(
		raw(),
		parent,
		child_name,
		"/",
		"/root/",
		false
	) != 0;
}

bool GFWorld::id_set_parent(ecs_entity_t id, ecs_entity_t parent) const {
	CHECK_ENTITY_ALIVE(id, this, false,
		"Failed to set parent\n	Child is not alive\n"
	);
	CHECK_ENTITY_ALIVE(parent, this, false,
		"Failed to set parent\n	Parent is not alive\n"
	);

	String new_name = String();
	if (id_has_child(parent, ecs_get_name(raw(), id))) {
		// Entity needs a unique name in new parent
		new_name = entity_unique_name(parent, ecs_get_name(raw(), id));
		ecs_remove_pair(raw(), id, ecs_id(EcsIdentifier), EcsName);
	}

	ecs_add_id(raw(), id, ecs_childof(parent));

	if (!new_name.is_empty()) {
		// Set new name
		CharString char_new_name = new_name.utf8();
		ecs_set_name(raw(), id, char_new_name);
	}

	return true;
}

bool GFWorld::is_id_alive(ecs_entity_t id) const {
	if (ECS_IS_PAIR(id)) {
		if (!ecs_is_alive(raw(), ECS_PAIR_FIRST(id))) {
			return false;
		}
		if (!ecs_is_alive(raw(), ECS_PAIR_SECOND(id))) {
			return false;
		}
	} else {
		if (!ecs_is_alive(raw(), id)) {
			return false;
		}
	}
	return true;
}

ecs_world_t * GFWorld::raw() const {
	return _raw;
}

void* GFWorld::_comp_get_member_ptr_mut_at(ecs_entity_t entity, ecs_entity_t comp, int offset) const {
	int8_t* bytes = static_cast<int8_t*>(
		ecs_get_mut_id(raw(), entity, comp)
	);
	return static_cast<void*>(&bytes[offset]);
}

Variant GFWorld::_variant_from_member_ptr(
	const void* ptr,
	ecs_entity_t member_type
) const {
	Variant::Type vari_type = id_as_variant_type(member_type);
	if (vari_type == Variant::NIL) {
		// Member is not a godot type--maybe primitive?
		const EcsPrimitive* primi_c = ecs_get(raw(), member_type, EcsPrimitive);
		if (primi_c != nullptr) {
			// Member is a primitive, convert primitive to Godot type
			return _variant_from_member_ptr_primitive(ptr, primi_c->kind);
		}

		// Member was not a primitive, and can't be converted to a Godot type
		return nullptr;
	}

	switch (vari_type) {
	case(Variant::Type::NIL): return nullptr;
	case(Variant::Type::BOOL): return *static_cast<const bool*>(ptr);
	case(Variant::Type::INT): return *static_cast<const int64_t*>(ptr);
	case(Variant::Type::FLOAT): return *static_cast<const double*>(ptr);
	case(Variant::Type::STRING): return *static_cast<const String*>(ptr);
	case(Variant::Type::VECTOR2): return *static_cast<const Vector2*>(ptr);
	case(Variant::Type::VECTOR2I): return *static_cast<const Vector2i*>(ptr);
	case(Variant::Type::RECT2): return *static_cast<const Rect2*>(ptr);
	case(Variant::Type::RECT2I): return *static_cast<const Rect2i*>(ptr);
	case(Variant::Type::VECTOR3): return *static_cast<const Vector3*>(ptr);
	case(Variant::Type::VECTOR3I): return *static_cast<const Vector3i*>(ptr);
	case(Variant::Type::TRANSFORM2D): return *static_cast<const Transform2D*>(ptr);
	case(Variant::Type::VECTOR4): return *static_cast<const Vector4*>(ptr);
	case(Variant::Type::VECTOR4I): return *static_cast<const Vector4i*>(ptr);
	case(Variant::Type::PLANE): return *static_cast<const Plane*>(ptr);
	case(Variant::Type::QUATERNION): return *static_cast<const Quaternion*>(ptr);
	case(Variant::Type::AABB): return *static_cast<const AABB*>(ptr);
	case(Variant::Type::BASIS): return *static_cast<const Basis*>(ptr);
	case(Variant::Type::TRANSFORM3D): return *static_cast<const Transform3D*>(ptr);
	case(Variant::Type::PROJECTION): return *static_cast<const Projection*>(ptr);
	case(Variant::Type::COLOR): return *static_cast<const Color*>(ptr);
	case(Variant::Type::STRING_NAME): return *static_cast<const StringName*>(ptr);
	case(Variant::Type::NODE_PATH): return *static_cast<const NodePath*>(ptr);
	case(Variant::Type::RID): return *static_cast<const RID*>(ptr);
	case(Variant::Type::OBJECT): return *static_cast<const Variant*>(ptr);
	case(Variant::Type::CALLABLE): return *static_cast<const Callable*>(ptr);
	case(Variant::Type::SIGNAL): return *static_cast<const Signal*>(ptr);
	case(Variant::Type::DICTIONARY): return *static_cast<const Dictionary*>(ptr);
	case(Variant::Type::ARRAY): return *static_cast<const Array*>(ptr);
	case(Variant::Type::PACKED_BYTE_ARRAY): return *static_cast<const PackedByteArray*>(ptr);
	case(Variant::Type::PACKED_INT32_ARRAY): return *static_cast<const PackedInt32Array*>(ptr);
	case(Variant::Type::PACKED_INT64_ARRAY): return *static_cast<const PackedInt64Array*>(ptr);
	case(Variant::Type::PACKED_FLOAT32_ARRAY): return *static_cast<const PackedFloat32Array*>(ptr);
	case(Variant::Type::PACKED_FLOAT64_ARRAY): return *static_cast<const PackedFloat64Array*>(ptr);
	case(Variant::Type::PACKED_STRING_ARRAY): return *static_cast<const PackedStringArray*>(ptr);
	case(Variant::Type::PACKED_VECTOR2_ARRAY): return *static_cast<const PackedVector2Array*>(ptr);
	case(Variant::Type::PACKED_VECTOR3_ARRAY): return *static_cast<const PackedVector3Array*>(ptr);
	case(Variant::Type::PACKED_COLOR_ARRAY): return *static_cast<const PackedColorArray*>(ptr);
	case(Variant::Type::PACKED_VECTOR4_ARRAY): return *static_cast<const PackedVector4Array*>(ptr);
	case(Variant::Type::VARIANT_MAX): ERR(nullptr, "Failed to get member\n	Member type VARIANT_MAX is invalid");
	}

	ERR(nullptr, "Unreachable");
}

Variant GFWorld::_variant_from_member_ptr_primitive(
	const void* ptr,
	ecs_primitive_kind_t primitive
) {
	switch (primitive) {
		case ecs_primitive_kind_t::EcsBool: return *static_cast<const bool*>(ptr);
		case ecs_primitive_kind_t::EcsChar: return *static_cast<const char*>(ptr);
		case ecs_primitive_kind_t::EcsByte: return *static_cast<const uint8_t*>(ptr);
		case ecs_primitive_kind_t::EcsU8: return *static_cast<const uint8_t*>(ptr);
		case ecs_primitive_kind_t::EcsU16: return *static_cast<const uint16_t*>(ptr);
		case ecs_primitive_kind_t::EcsU32: return *static_cast<const uint32_t*>(ptr);
		case ecs_primitive_kind_t::EcsU64: return *static_cast<const uint64_t*>(ptr);
		case ecs_primitive_kind_t::EcsI8: return *static_cast<const int8_t*>(ptr);
		case ecs_primitive_kind_t::EcsI16: return *static_cast<const int16_t*>(ptr);
		case ecs_primitive_kind_t::EcsI32: return *static_cast<const int32_t*>(ptr);
		case ecs_primitive_kind_t::EcsI64: return *static_cast<const int64_t*>(ptr);
		case ecs_primitive_kind_t::EcsF32: return *static_cast<const float*>(ptr);
		case ecs_primitive_kind_t::EcsF64: return *static_cast<const double*>(ptr);
		case ecs_primitive_kind_t::EcsUPtr: ERR(nullptr, "Can't get primitive\n	Can't handle uptr");
		case ecs_primitive_kind_t::EcsIPtr: ERR(nullptr, "Can't get primitive\n	Can't handle iptr");
		case ecs_primitive_kind_t::EcsString: return *static_cast<char* const *>(ptr);
		case ecs_primitive_kind_t::EcsEntity: return *static_cast<const ecs_entity_t*>(ptr);
		case ecs_primitive_kind_t::EcsId: return *static_cast<const ecs_entity_t*>(ptr);
		default: ERR(nullptr, "Can't get primitive\n	Unknown primitive type: ", primitive);
	}
}

// ----------------------------------------------
// --- Protected ---
// ----------------------------------------------

GFWorld* GFWorld::get_global_thread_singleton() {
	if (!UtilityFunctions::is_instance_id_valid(global_thread_singleton)) {
		GFWorld* world = memnew(GFWorld(nullptr));
		global_thread_singleton = world->get_instance_id();
		world->setup_glecs();
	}
	return Object::cast_to<GFWorld>(
		UtilityFunctions::instance_from_id(global_thread_singleton)
	);
}

GFWorld* GFWorld::get_default_world() {
	if (!UtilityFunctions::is_instance_id_valid(local_thread_singleton)) {
		GFWorld* global_world = get_global_thread_singleton();
		set_default_world(global_world);
		return global_world;
	}
	return Object::cast_to<GFWorld>(
		UtilityFunctions::instance_from_id(local_thread_singleton)
	);
}

void GFWorld::set_default_world(const GFWorld* world) {
	if (world == nullptr) {
		local_thread_singleton = 0;
	}
	local_thread_singleton = world->get_instance_id();
}

void GFWorld::_bind_methods() {
	godot::ClassDB::bind_static_method(get_class_static(), D_METHOD("get_default_world"), &GFWorld::get_default_world);
	godot::ClassDB::bind_static_method(get_class_static(), D_METHOD("set_default_world", "world"), &GFWorld::set_default_world);
	godot::ClassDB::bind_static_method(get_class_static(), D_METHOD("get_singleton"), &GFWorld::get_singleton);

	godot::ClassDB::bind_method(D_METHOD("register_script", "script"), &GFWorld::register_script);

	godot::ClassDB::bind_method(D_METHOD("coerce_id", "entity"), &GFWorld::coerce_id);
	godot::ClassDB::bind_method(D_METHOD("get_raw"), &GFWorld::get_raw);
	godot::ClassDB::bind_method(D_METHOD("start_rest_api"), &GFWorld::start_rest_api);
	godot::ClassDB::bind_method(D_METHOD("lookup", "path"), &GFWorld::lookup);
	godot::ClassDB::bind_method(D_METHOD("pair", "first", "second"), &GFWorld::pair);
	godot::ClassDB::bind_method(D_METHOD("pair_ids", "first", "second"), &GFWorld::pair_ids);
	godot::ClassDB::bind_method(D_METHOD("progress", "delta"), &GFWorld::progress);

	godot::ClassDB::bind_method(D_METHOD("_register_modules_from_scripts", "depth"), &GFWorld::_register_modules_from_scripts);
}

// ----------------------------------------------
// --- Private ---
// ----------------------------------------------

void GFWorld::define_gd_literal(
	const char* name,
	ecs_primitive_kind_t primitive,
	ecs_entity_t* id_storage
) const {
	ecs_primitive_desc_t desc = {
		.entity = *id_storage,
		.kind = primitive
	}; ecs_primitive_init(_raw, &desc);
	ecs_add_path_w_sep(
		_raw,
		*id_storage,
		glecs_meta,
		name,
		"/",
		"/root/"
	);
}
