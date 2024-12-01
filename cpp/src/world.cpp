
#include "world.h"
#include "entity.h"
#include "component_builder.h"
#include "godot_cpp/classes/resource.hpp"
#include "godot_cpp/classes/script.hpp"
#include "godot_cpp/classes/text_server_manager.hpp"
#include "godot_cpp/classes/wrapped.hpp"
#include "godot_cpp/variant/packed_string_array.hpp"
#include "godot_cpp/variant/utility_functions.hpp"
#include "observer_builder.h"
#include "pair.h"
#include "query_builder.h"
#include "registerable_entity.h"
#include "system_builder.h"
#include "utils.h"

#include <cassert>
#include <cctype>
#include <flecs.h>
#include "godot_cpp/core/memory.hpp"
#include "godot_cpp/variant/dictionary.hpp"
#include "godot_cpp/variant/variant.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/variant/string_name.hpp>

using namespace godot;

const char* GFWorld::SINGLETON_NAME = "GFGlobalWorld";

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

GFWorld::GFWorld() {
	_raw = ecs_init();
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
		ecs_entity_t old_scope = ecs_get_scope(_raw);
		ecs_set_scope(_raw, glecs);

		ecs_component_desc_t comp_desc = {
			.entity = ecs_new_from_path(_raw, glecs, "meta"),
		};
		glecs_meta = ecs_module_init(
			_raw,
			"meta",
			&comp_desc
		);

		ecs_set_scope(_raw, old_scope);
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

GFWorld::~GFWorld() {
	ecs_fini(_raw);
}

ecs_entity_t GFWorld::coerce_id(Variant value) {
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
				return (static_cast<GFEntity*>(obj)->get_id());
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
					// 	"Failed to coerce Script to ID\n",
					// 	"The script ", script, " has not been registered with world ", this
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

Ref<GFEntity> GFWorld::lookup(String path) {
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

Ref<GFPair> GFWorld::pair(Variant first, Variant second) {
	return GFPair::from_ids(coerce_id(first), coerce_id(second), this);
}

ecs_entity_t GFWorld::pair_ids(ecs_entity_t first, ecs_entity_t second) {
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

void GFWorld::progress(double delta) {
	ecs_progress(raw(), delta);
}

Ref<GFComponentBuilder> GFWorld::component_builder() {
	Ref<GFComponentBuilder> builder = memnew(GFComponentBuilder);
	builder->set_world(this);
	return builder;
}

Ref<GFObserverBuilder> GFWorld::observer_builder_varargs(
	const Variant** args,
	int64_t arg_count,
	GDExtensionCallError& error
) {
	if (arg_count > FLECS_EVENT_DESC_MAX) {
		// TODO: utilize call error
		ERR(Ref<GFObserverBuilder>(),
			"Failed to set terms in observer builder",
			"Max term count is ", FLECS_EVENT_DESC_MAX, ", but ",
			arg_count, " terms were passed"
		);
	}

	Ref<GFObserverBuilder> builder = memnew(GFObserverBuilder(this));
	builder->set_events_varargs(args, arg_count, error);
	return builder;
}

Variant observer_builder_varargs(
	const Variant **args,
	GDExtensionInt arg_count,
	GDExtensionCallError &error
) {
	return arg_count;
}

Ref<GFQueryBuilder> GFWorld::query_builder() {
	Ref<GFQueryBuilder> builder = memnew(GFQueryBuilder(this));
	return builder;
}

Ref<GFSystemBuilder> GFWorld::system_builder() {
	Ref<GFSystemBuilder> builder = memnew(GFSystemBuilder(this));
	return builder;
}

Ref<GFRegisterableEntity> GFWorld::register_script(Ref<Script> script) {
	Ref<GFRegisterableEntity> ett = register_script_id_no_user_call(script);
	if (ett == nullptr) {
		return nullptr;
	}
	ett->call_user_register();
	return ett;
}

bool is_valid_data(char c) {
	return (c <= '9' && c >= '0') || c == ',';
}

ecs_entity_t GFWorld::register_script_id(Ref<Script> script) {
	Ref<GFRegisterableEntity> ett = register_script_id_no_user_call(script);
	ett->call_user_register();
	return ett->get_id();
}

Ref<GFRegisterableEntity> GFWorld::register_script_id_no_user_call(Ref<Script> script) {
	if (*script == nullptr) {
		ERR(nullptr,
			"Could not register script\n",
			"Script is null."
		);
	}
	if (!godot::ClassDB::is_parent_class(
		script->get_instance_base_type(),
		GFRegisterableEntity::get_class_static()
	)) {
		ERR(nullptr,
			"Could not register script\n",
			"Script, ", script, ", does not inherit from ",
			GFRegisterableEntity::get_class_static()
		);
	}

	if (registered_entity_ids.has(script)) {
		Ref<GFRegisterableEntity> reg_ett
			= GFRegisterableEntity::from_script(script, this);
		ERR(reg_ett,
			"Could not register script\n",
			"Script ", script, " is already registered"
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
		ecs_entity_t prev_scope = ecs_get_scope(raw());
		ecs_set_scope(raw(), glecs);

		Object* glecs_modules = engine->get_singleton(MODULES);
		glecs_modules->call("register_modules", this);

		ecs_set_scope(raw(), prev_scope);
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

void GFWorld::start_rest_api() {
	ecs_entity_t rest_id = ecs_lookup_path_w_sep(raw(), 0, "flecs.rest.Rest", ".", "", false);
	EcsRest rest = (EcsRest)EcsRest();
	ecs_set_id(raw(), rest_id, rest_id, sizeof(EcsRest), &rest);
}

ecs_entity_t GFWorld::variant_type_to_id(Variant::Type type) {
	if (type == Variant::Type::VARIANT_MAX) {
		throw "No ID exists for VARIANT_MAX";
	}
	return GFWorld::glecs_meta_nil + type;
}

String GFWorld::id_to_text(ecs_entity_t id) {
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

Variant::Type GFWorld::id_to_variant_type(ecs_entity_t id) {
	if (id < GFWorld::glecs_meta_nil) {
		return godot::Variant::NIL;
	}
	Variant::Type type = Variant::Type(id - GFWorld::glecs_meta_nil);
	if (type >= Variant::Type::VARIANT_MAX) {
		return godot::Variant::NIL;
	}
	return type;
}

// ----------------------------------------------
// --- Unexposed ---
// ----------------------------------------------

/// If id is a pair then returns the ID that is a component.
/// Id id is not a pair, then just returns id.
ecs_entity_t GFWorld::get_main_id(ecs_entity_t id) {
	if (ECS_IS_PAIR(id)) {
		ecs_entity_t first = ECS_PAIR_FIRST(id);
		if (ecs_has_id(raw(), first, FLECS_IDEcsStructID_)) {
			return first;
		}
		return ECS_PAIR_SECOND(id);
	}
	return id;
}

ecs_entity_t GFWorld::get_registered_id(Ref<Script> script) {
	return registered_entity_ids.get(script, 0);
}

Ref<Script> GFWorld::get_registered_script(ecs_entity_t id) {
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
		return GFWorld::singleton();
	}
	return world;
}

GFWorld* GFWorld::singleton() {
	Object* singleton = Engine::get_singleton()
		->get_singleton(GFWorld::SINGLETON_NAME);
	return Object::cast_to<GFWorld>(singleton);
}

void GFWorld::copy_component_ptr(
	const void* src_ptr,
	void* dst_ptr,
	ecs_entity_t component
) {
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
) {
	Variant::Type vari_type = id_to_variant_type(type);

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
) {
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
) {
	Variant::Type vari_type = id_to_variant_type(type);

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
) {
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
) {
	Variant::Type vari_type = id_to_variant_type(type);

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

ecs_world_t * GFWorld::raw() {
	return _raw;
}

// ----------------------------------------------
// --- Protected ---
// ----------------------------------------------

void GFWorld::_bind_methods() {
	godot::ClassDB::bind_method(D_METHOD("component_builder"), &GFWorld::component_builder);
	ClassDB::bind_vararg_method(METHOD_FLAGS_DEFAULT, "observer_builder", &GFWorld::observer_builder_varargs);
	godot::ClassDB::bind_method(D_METHOD("query_builder"), &GFWorld::query_builder);
	godot::ClassDB::bind_method(D_METHOD("register_script", "script"), &GFWorld::register_script);
	godot::ClassDB::bind_method(D_METHOD("system_builder"), &GFWorld::system_builder);
	godot::ClassDB::bind_method(D_METHOD("coerce_id", "entity"), &GFWorld::coerce_id);
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
) {
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
