
#include "component.h"
#include "component_builder.h"
#include "entity.h"
#include "godot_cpp/classes/wrapped.hpp"
#include "godot_cpp/core/error_macros.hpp"
#include "godot_cpp/variant/array.hpp"
#include "godot_cpp/variant/dictionary.hpp"
#include "godot_cpp/variant/packed_int64_array.hpp"
#include "godot_cpp/variant/variant.hpp"
#include "registerable_entity.h"
#include "utils.h"
#include "world.h"

#include <cstdint>
#include <stdint.h>
#include <flecs.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

Ref<GFComponent> GFComponent::from(
	const Variant comp,
	const Variant entity,
	GFWorld* world
) {
	world = GFWorld::world_or_singleton(world);
	return from_id(world->coerce_id(comp), world->coerce_id(entity), world);
}
Ref<GFComponent> GFComponent::from_id(
	ecs_entity_t comp,
	ecs_entity_t entity,
	GFWorld* world
) {
	world = GFWorld::world_or_singleton(world);

	Ref<GFComponent> comp_ref = memnew(GFComponent(entity, comp, world));
	return setup_template<GFComponent>(comp_ref);
}

Ref<GFComponent> GFComponent::from_id_no_source(
	ecs_entity_t comp,
	GFWorld* world
) {
	world = GFWorld::world_or_singleton(world);

	Ref<GFComponent> comp_ref = Ref(memnew(GFComponent(0, comp, world)));
	comp_ref->update_script();
	return comp_ref;
}

bool GFComponent::_get(StringName property, Variant& out) {
	out = getm(property);
	return out != Variant();
}

void GFComponent::_get_property_list(List<PropertyInfo>* p_list) {
	return get_world()->_comp_get_property_list(get_source_id(), get_id(), p_list);
}

bool GFComponent::_set(StringName property, Variant value) {
	return setm(property, value);
}

void GFComponent::_register_internal() {
	// Build component
	Ref<GFComponentBuilder> b = memnew(GFComponentBuilder(get_world()));
	if (GDVIRTUAL_IS_OVERRIDDEN(_build)) {
		b->set_target_entity(get_id());
		GDVIRTUAL_CALL(_build, b);
		if (!b->is_built()) {
			b->build();
		}
	}

	// Call super method
	GFRegisterableEntity::_register_internal();
}

bool GFComponent::setm(const String member, const Variant value) const {
	return get_world()->_comp_setm(
		get_source_id(),
		get_id(),
		member,
		value
	);
}

bool GFComponent::setm_no_notify(const String member, const Variant value) const {
	return get_world()->_comp_setm_no_notify(
		get_source_id(),
		get_id(),
		member,
		value
	);
}

Variant GFComponent::getm(const String member) const {
	return get_world()->_comp_getm(
		get_source_id(),
		get_id(),
		member
	);
}

String GFComponent::_to_string() const {
	return get_world()->id_to_text(get_source_id())
		+ "." + get_world()->id_to_text(get_id());
}

Ref<GFEntity> GFComponent::get_source_entity() const {
	return GFEntity::from(get_source_id(), get_world());
}

ecs_entity_t GFComponent::get_source_id() const {
	return source_entity_id;
}

int GFComponent::get_data_size() const {
	const EcsComponent* component_data = ecs_get(
		get_world()->raw(),
		get_id(),
		EcsComponent
	);
	if (component_data == nullptr) {
		return 0;
	}
	return component_data->size;
}
int GFComponent::get_data_alignment() const {
	const EcsComponent* component_data = ecs_get(
		get_world()->raw(),
		get_id(),
		EcsComponent
	);
	if (component_data == nullptr) {
		return 0;
	}
	return component_data->alignment;
}

bool GFComponent::is_alive() const {
	const GFEntity* entity = this;
	return entity->is_alive()
		&& ecs_has_id(get_world()->raw(), get_source_id(), get_id());
}

void GFComponent::build_data_from_variant(
	Variant vari,
	void* output
) const {
	GFWorld* w = get_world();

	const EcsStruct* struct_data = ecs_get(w->raw(), get_id(), EcsStruct);
	if (struct_data == nullptr) {
		ERR(/**/,
			"Could not build data from Variant\n",
			"	Component is not a struct."
		);
	}

	switch (vari.get_type()) {
		case Variant::DICTIONARY: {
			Dictionary dict = vari;
			Array keys = dict.keys();
			for (int i=0; i != keys.size(); i++) {
				String member_name = keys[i];
				Variant value = dict[member_name];
				const EcsMember* member_data = w->_comp_get_member_data(
					get_id(),
					member_name
				);
				if (member_data == nullptr) {
					// No member with that name exists, skip
					continue;
				}
				void* member_ptr = static_cast<void*>(
					static_cast<uint8_t*>(output) + member_data->offset
				);
				// Set member from dictionary
				Utils::set_type_from_variant(
					value,
					member_data->type,
					w,
					member_ptr
				);
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
				Utils::set_type_from_variant(value, member_data->type, w, member_ptr);
			}
			break;
		}
		default: ERR(/**/,
			"Could not build data from Variant\n",
			"	Variant type ", Variant::get_type_name(vari.get_type()),
			" can't be built into component data."
		);
	}
}

const EcsComponent* GFComponent::get_component_ptr(
	const GFWorld* world,
	ecs_entity_t id
) {
	return ecs_get(world->raw(), world->get_main_id(id), EcsComponent);
}

const EcsStruct* GFComponent::get_struct_ptr(
	const GFWorld* world,
	ecs_entity_t id
) {
	return ecs_get(world->raw(), world->get_main_id(id), EcsStruct);
}

void GFComponent::build_data_from_members(
	const Array members,
	void* output,
	ecs_entity_t component_id,
	const GFWorld* world
) {
	if (members.size() == 0) {
		ERR(/**/,
			"Could not set component's data\n",
			"	No values were provided."
		);
	}

	const EcsStruct* struct_data = GFComponent::get_struct_ptr(
		world,
		component_id
	);
	if (struct_data == nullptr) {
		// Component is not a struct--maybe a primitive
		if (!ecs_has_id(world->raw(), component_id, ecs_id(EcsPrimitive))) {
			ERR(/**/,
				"Could not set component's data\n",
				"	Component ", world->id_to_text(component_id), " is not a struct or primitive."
			);
		}
		if (members.size() > 1) {
			ERR(/**/,
				"Could not set component's data\n",
				"	Component ", world->id_to_text(component_id),
				" is a primitive, but more than value was provided."
			);
		}

		// Component is a primitive, and exactly one value was provided
		// Set primitive from value
		Utils::set_type_from_variant(members[0], component_id, world, output);
		return;
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
		Utils::set_type_from_variant(value, member_data->type, world, member_ptr);
	}
}

void GFComponent::set_source_id(ecs_entity_t id) {
	source_entity_id = id;
}

void GFComponent::_bind_methods() {
	REGISTER_ENTITY_SELF_METHODS(GFComponent);

	GDVIRTUAL_BIND(_build, "b");
	godot::ClassDB::bind_method(D_METHOD("_register_internal"), &GFComponent::_register_internal);

	godot::ClassDB::bind_static_method(get_class_static(), D_METHOD("from", "component", "entity", "world"), &GFComponent::from, nullptr);
	godot::ClassDB::bind_static_method(get_class_static(), D_METHOD("from_id", "component_id", "entity_id","world"), &GFComponent::from_id, nullptr);

	godot::ClassDB::bind_method(D_METHOD("getm", "member"), &GFComponent::getm);
	godot::ClassDB::bind_method(D_METHOD("setm", "member", "value"), &GFComponent::setm);
	godot::ClassDB::bind_method(D_METHOD("setm_no_notify", "member", "value"), &GFComponent::setm_no_notify);

	godot::ClassDB::bind_method(D_METHOD("get_source_entity"), &GFComponent::get_source_entity);
	godot::ClassDB::bind_method(D_METHOD("get_source_id"), &GFComponent::get_source_id);
	godot::ClassDB::bind_method(D_METHOD("get_data_size"), &GFComponent::get_data_size);
	godot::ClassDB::bind_method(D_METHOD("get_data_alignment"), &GFComponent::get_data_alignment);
	godot::ClassDB::bind_method(D_METHOD("is_alive"), &GFComponent::is_alive);
	godot::ClassDB::bind_method(D_METHOD("_to_string"), &GFComponent::_to_string);
}
