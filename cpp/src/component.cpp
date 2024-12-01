
#include "component.h"
#include "component_builder.h"
#include "entity.h"
#include "godot_cpp/classes/wrapped.hpp"
#include "godot_cpp/variant/array.hpp"
#include "godot_cpp/variant/dictionary.hpp"
#include "godot_cpp/variant/packed_int64_array.hpp"
#include "godot_cpp/variant/variant.hpp"
#include "registerable_entity.h"
#include "utils.h"

#include <cstddef>
#include <cstdint>
#include <stdint.h>
#include <flecs.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

GFComponent::GFComponent() {
}
GFComponent::~GFComponent() {
}

Ref<GFComponent> GFComponent::spawn(GFWorld* world_) {
	ERR(NULL,
		"Could not instantiate ", get_class_static(), "\n",
		"Use ", get_class_static(), ".from or ",
		get_class_static(), ".from_id instead."
	);
}
Ref<GFComponent> GFComponent::from(Variant comp, Variant entity, GFWorld* world) {
	return from_id(world->coerce_id(comp), world->coerce_id(entity), world);
}
Ref<GFComponent> GFComponent::from_id(ecs_entity_t comp, ecs_entity_t entity, GFWorld* world) {
	const EcsComponent* comp_ptr = GFComponent::get_component_ptr(world, comp);
	if (comp_ptr == nullptr) {
		ERR(nullptr,
			"Could not instantiate ", get_class_static(), "\n",
			"	Entity ", world->id_to_text(comp), " is not a component"
		);
	}
	Ref<GFComponent> component = from_id_template<GFComponent>(comp, world);
	component->set_source_id(entity);
	return component;
}

void GFComponent::_register_internal() {
	// Build component
	Ref<GFComponentBuilder> b = get_world()->component_builder();
	if (GDVIRTUAL_IS_OVERRIDDEN(_build)) {
		b->set_entity(get_id());
		GDVIRTUAL_CALL(_build, b);
		if (!b->is_built()) {
			b->build();
		}
	}

	// Call super method
	GFRegisterableEntity::_register_internal();
}

void GFComponent::setm(String member, Variant value) {
	ecs_world_t* raw = get_world()->raw();

	// Get member data
	const EcsMember* member_data = get_member_data(member);
	if (member_data == nullptr) {
		// Member data is null. This should never happen.
		ERR(/**/,
			"Member metadata is null"
		);
	}
	void* member_ptr = get_member_ptr_mut_at(member_data->offset);
	if (member_ptr == nullptr) {
		ERR(/**/,
			"Member pointer is null"
		);
	}

	// Return member
	Utils::set_type_from_variant(value, member_data->type, raw, member_ptr);
	ecs_modified_id(get_world()->raw(), get_source_id(), get_id());
}

Variant GFComponent::getm(String member) {
	ecs_world_t* raw = get_world()->raw();

	// Get member data
	const EcsMember* member_data = get_member_data(member);
	if (member_data == nullptr) {
		// Member data is null. This should never happen.
		ERR(nullptr,
			"Member metadata is null"
		);
	}
	void* member_value_ptr = get_member_ptr_mut_at(member_data->offset);
	if (member_value_ptr == nullptr) {
		ERR(nullptr,
			"Member value is null"
		);
	}

	return member_value_as_type(member_value_ptr, member_data->type);
}

void* GFComponent::get_member_ptr_mut_at(int offset) {
	ecs_world_t* raw = get_world()->raw();
	int8_t* bytes = static_cast<int8_t*>(
		ecs_get_mut_id(raw, get_source_id(), get_id())
	);
	return static_cast<void*>(&bytes[offset]);
}

const EcsMember* GFComponent::get_member_data(String member) {
	ecs_world_t* raw = get_world()->raw();
	const char* c_str = member.utf8().get_data();

	ecs_entity_t main_id = get_world()->get_main_id(get_id());

	// Get member ID
	ecs_entity_t member_id = ecs_lookup_child(raw, main_id, c_str);

	if (member_id == 0) {
		ERR(nullptr,
			"No member named \"",
			member,
			"\" found in component \"",
			get_world()->id_to_text(get_id()),
			"\""
		);
	}

	// Get member data
	const EcsMember* member_data = ecs_get(raw, member_id, EcsMember);

	return member_data;
}

Variant GFComponent::member_value_as_primitive(
	void* ptr,
	ecs_primitive_kind_t primitive
) {
	switch (primitive) {
		case ecs_primitive_kind_t::EcsBool: return *static_cast<bool*>(ptr);
		case ecs_primitive_kind_t::EcsChar: return *static_cast<char*>(ptr);
		case ecs_primitive_kind_t::EcsByte: return *static_cast<uint8_t*>(ptr);
		case ecs_primitive_kind_t::EcsU8: return *static_cast<uint8_t*>(ptr);
		case ecs_primitive_kind_t::EcsU16: return *static_cast<uint16_t*>(ptr);
		case ecs_primitive_kind_t::EcsU32: return *static_cast<uint32_t*>(ptr);
		case ecs_primitive_kind_t::EcsU64: return *static_cast<uint64_t*>(ptr);
		case ecs_primitive_kind_t::EcsI8: return *static_cast<int8_t*>(ptr);
		case ecs_primitive_kind_t::EcsI16: return *static_cast<int16_t*>(ptr);
		case ecs_primitive_kind_t::EcsI32: return *static_cast<int32_t*>(ptr);
		case ecs_primitive_kind_t::EcsI64: return *static_cast<int64_t*>(ptr);
		case ecs_primitive_kind_t::EcsF32: return *static_cast<float*>(ptr);
		case ecs_primitive_kind_t::EcsF64: return *static_cast<double*>(ptr);
		case ecs_primitive_kind_t::EcsUPtr: ERR(nullptr, "Can't get primitive\nCan't handle uptr");
		case ecs_primitive_kind_t::EcsIPtr: ERR(nullptr, "Can't get primitive\nCan't handle iptr");
		case ecs_primitive_kind_t::EcsString: return *static_cast<char**>(ptr);
		case ecs_primitive_kind_t::EcsEntity: return *static_cast<ecs_entity_t*>(ptr);
		case ecs_primitive_kind_t::EcsId: return *static_cast<ecs_entity_t*>(ptr);
		default: ERR(nullptr, "Can't get primitive\nUnknown primitive type");
	}
}

Variant GFComponent::member_value_as_type(
	void* ptr,
	ecs_entity_t type
) {
	ecs_world_t* raw = get_world()->raw();
	Variant::Type vari_type = get_world()->id_to_variant_type(type);

	switch (vari_type) {
	case(Variant::Type::NIL): {
		// Member is not a Godot type. Try to get from Flecs primitive
		if (ecs_has_id(raw, type, ecs_id(EcsPrimitive))) {
			return member_value_as_primitive(
				ptr,
				ecs_get(raw, type, EcsPrimitive)->kind
			);
		}

		ERR(nullptr,
			"Can't convert type ", get_world()->id_to_text(type), " to Variant"
		);
	}
	case(Variant::Type::BOOL): return Variant( *static_cast<bool*>(ptr) );
	case(Variant::Type::INT): return Variant( *static_cast<int64_t*>(ptr) );
	case(Variant::Type::FLOAT): return Variant( *static_cast<double*>(ptr) );
	case(Variant::Type::STRING): return Variant( *static_cast<String*>(ptr) );
	case(Variant::Type::VECTOR2): return Variant( *static_cast<Vector2*>(ptr) );
	case(Variant::Type::VECTOR2I): return Variant( *static_cast<Vector2i*>(ptr) );
	case(Variant::Type::RECT2): return Variant( *static_cast<Rect2*>(ptr) );
	case(Variant::Type::RECT2I): return Variant( *static_cast<Rect2i*>(ptr) );
	case(Variant::Type::VECTOR3): return Variant( *static_cast<Vector3*>(ptr) );
	case(Variant::Type::VECTOR3I): return Variant( *static_cast<Vector3i*>(ptr) );
	case(Variant::Type::TRANSFORM2D): return Variant( *static_cast<Transform2D*>(ptr) );
	case(Variant::Type::VECTOR4): return Variant( *static_cast<Vector4*>(ptr) );
	case(Variant::Type::VECTOR4I): return Variant( *static_cast<Vector4i*>(ptr) );
	case(Variant::Type::PLANE): return Variant( *static_cast<Plane*>(ptr) );
	case(Variant::Type::QUATERNION): return Variant( *static_cast<Quaternion*>(ptr) );
	case(Variant::Type::AABB): return Variant( *static_cast<AABB*>(ptr) );
	case(Variant::Type::BASIS): return Variant( *static_cast<Basis*>(ptr) );
	case(Variant::Type::TRANSFORM3D): return Variant( *static_cast<Transform3D*>(ptr) );
	case(Variant::Type::PROJECTION): return Variant( *static_cast<Projection*>(ptr) );
	case(Variant::Type::COLOR): return Variant( *static_cast<Color*>(ptr) );
	case(Variant::Type::STRING_NAME): return Variant( *static_cast<StringName*>(ptr) );
	case(Variant::Type::NODE_PATH): return Variant( *static_cast<NodePath*>(ptr) );
	case(Variant::Type::RID): return Variant( *static_cast<RID*>(ptr) );
	case(Variant::Type::OBJECT): return Variant( *static_cast<Variant*>(ptr) );
	case(Variant::Type::CALLABLE): return Variant( *static_cast<Callable*>(ptr) );
	case(Variant::Type::SIGNAL): return Variant( *static_cast<Signal*>(ptr) );
	case(Variant::Type::DICTIONARY): return *static_cast<Dictionary*>(ptr);
	case(Variant::Type::ARRAY): return *static_cast<Array*>(ptr);
	case(Variant::Type::PACKED_BYTE_ARRAY): return Variant( *static_cast<PackedByteArray*>(ptr) );
	case(Variant::Type::PACKED_INT32_ARRAY): return Variant( *static_cast<PackedInt32Array*>(ptr) );
	case(Variant::Type::PACKED_INT64_ARRAY): return Variant( *static_cast<PackedInt64Array*>(ptr) );
	case(Variant::Type::PACKED_FLOAT32_ARRAY): return Variant( *static_cast<PackedFloat32Array*>(ptr) );
	case(Variant::Type::PACKED_FLOAT64_ARRAY): return Variant( *static_cast<PackedFloat64Array*>(ptr) );
	case(Variant::Type::PACKED_STRING_ARRAY): return Variant( *static_cast<PackedStringArray*>(ptr) );
	case(Variant::Type::PACKED_VECTOR2_ARRAY): return Variant( *static_cast<PackedVector2Array*>(ptr) );
	case(Variant::Type::PACKED_VECTOR3_ARRAY): return Variant( *static_cast<PackedVector3Array*>(ptr) );
	case(Variant::Type::PACKED_COLOR_ARRAY): return Variant( *static_cast<PackedColorArray*>(ptr) );
	case(Variant::Type::PACKED_VECTOR4_ARRAY): return Variant( *static_cast<PackedVector4Array*>(ptr) );
	case(Variant::Type::VARIANT_MAX): throw "Can't get type VARIANT_MAX";
	}

	throw "Unreachable";
}

Ref<GFEntity> GFComponent::get_source_entity() {
	return GFEntity::from(get_source_id(), get_world());
}

ecs_entity_t GFComponent::get_source_id() {
	return source_entity_id;
}

int GFComponent::get_data_size() {
	return ecs_get(get_world()->raw(), get_id(), EcsComponent)->size;
}
int GFComponent::get_data_alignment() {
	return ecs_get(get_world()->raw(), get_id(), EcsComponent)->alignment;
}

bool GFComponent::is_alive() {
	GFEntity* entity = this;
	return entity->is_alive()
		&& ecs_has_id(get_world()->raw(), get_source_id(), get_id());
}

void GFComponent::build_data_from_variant(
	Variant vari,
	void* output
) {
	ecs_world_t* raw = get_world()->raw();

	const EcsStruct* struct_data = ecs_get(raw, get_id(), EcsStruct);
	if (struct_data == nullptr) {
		ERR(/**/,
			"Could not build data from Variant\n",
			"Component is not a struct."
		);
	}

	switch (vari.get_type()) {
		case Variant::DICTIONARY: {
			Dictionary dict = vari;
			Array keys = dict.keys();
			for (int i=0; i != keys.size(); i++) {
				String member_name = keys[i];
				Variant value = dict[member_name];
				const EcsMember* member_data = get_member_data(member_name);
				if (member_data == nullptr) {
					// No member with that name exists, skip
					continue;
				}
				void* member_ptr = static_cast<void*>(
					static_cast<uint8_t*>(output) + member_data->offset
				);
				// Set member from dictionary
				Utils::set_type_from_variant(value, member_data->type, raw, member_ptr);
			}
			break;
		}
		case Variant::ARRAY: {
			Array arr = vari;
			for (int i=0; i != arr.size() && i != ecs_vec_size(&struct_data->members); i++) {
				// Iterate the combined sizes of the passed array and the members vector
				Variant value = arr[i];

				ecs_member_t* member_data = ecs_vec_get_t(&struct_data->members, ecs_member_t, i);
				void* member_ptr = static_cast<void*>(
					static_cast<uint8_t*>(output) + member_data->offset
				);
				// Set member from array
				Utils::set_type_from_variant(value, member_data->type, raw, member_ptr);
			}
			break;
		}
		default: ERR(/**/,
			"Could not build data from Variant\n",
			"Variant type ", Variant::get_type_name(vari.get_type()),
			" can't be built into component data."
		);
	}
}

const EcsComponent* GFComponent::get_component_ptr(GFWorld* world, ecs_entity_t id) {
	return ecs_get(world->raw(), world->get_main_id(id), EcsComponent);
}

const EcsStruct* GFComponent::get_struct_ptr(GFWorld* world, ecs_entity_t id) {
	return ecs_get(world->raw(), world->get_main_id(id), EcsStruct);
}

void GFComponent::build_data_from_members(
	Array members,
	void* output,
	ecs_entity_t component_id,
	GFWorld* world
) {
	ecs_world_t* w_raw = world->raw();

	const EcsStruct* struct_data = GFComponent::get_struct_ptr(world, component_id);
	if (struct_data == nullptr) {
		ERR(/**/,
			"Could not build data from Array\n",
			"	Entity ", world->id_to_text(component_id), " is not a struct."
		);
	}

	for (int i=0; i != members.size() && i != ecs_vec_size(&struct_data->members); i++) {
		// Iterate the combined sizes of the passed array and the members vector
		Variant value = members[i];

		ecs_member_t* member_data = /* Get member metadata */ ecs_vec_get_t(
			&struct_data->members,
			ecs_member_t,
			i
		);
		void* member_ptr = /* Get member pointer */ static_cast<void*>(
			static_cast<uint8_t*>(output) + member_data->offset
		);
		// Set member value
		Utils::set_type_from_variant(value, member_data->type, w_raw, member_ptr);
	}
}

void GFComponent::set_source_id(ecs_entity_t id) {
	source_entity_id = id;
}

Ref<GFRegisterableEntity> GFComponent::new_internal() {
	return Ref(memnew(GFComponent));
}

void GFComponent::_bind_methods() {
	GDVIRTUAL_BIND(_build, "b");
	godot::ClassDB::bind_method(D_METHOD("_register_internal"), &GFComponent::_register_internal);

	godot::ClassDB::bind_static_method(GFComponent::get_class_static(), D_METHOD("spawn", "world"), &GFComponent::spawn, nullptr);
	godot::ClassDB::bind_static_method(GFComponent::get_class_static(), D_METHOD("from", "component", "world"), &GFComponent::from, nullptr);
	godot::ClassDB::bind_static_method(GFComponent::get_class_static(), D_METHOD("from_id", "id", "world"), &GFComponent::from_id, nullptr);

	godot::ClassDB::bind_method(D_METHOD("getm", "member"), &GFComponent::getm);
	godot::ClassDB::bind_method(D_METHOD("setm", "member", "value"), &GFComponent::setm);

	godot::ClassDB::bind_method(D_METHOD("get_source_entity"), &GFComponent::get_source_entity);
	godot::ClassDB::bind_method(D_METHOD("get_source_id"), &GFComponent::get_source_id);
	godot::ClassDB::bind_method(D_METHOD("get_data_size"), &GFComponent::get_data_size);
	godot::ClassDB::bind_method(D_METHOD("get_data_alignment"), &GFComponent::get_data_alignment);
	godot::ClassDB::bind_method(D_METHOD("is_alive"), &GFComponent::is_alive);

	godot::ClassDB::bind_static_method(get_class_static(), D_METHOD("_new_internal"), &GFComponent::new_internal);
}
