

#include "entity_builder.h"
#include "entity.h"
#include "godot_cpp/variant/utility_functions.hpp"
#include "querylike_builder.h"
#include <godot_cpp/core/class_db.hpp>
#include "godot_cpp/variant/callable.hpp"
#include "godot_cpp/variant/variant.hpp"
#include "utils.h"
#include "world.h"

#include <stdlib.h>
#include <flecs.h>

using namespace godot;


// **************************************
// *** Exposed ***
// **************************************

Ref<GFEntityBuilder> GFEntityBuilder::new_in_world(GFWorld* world) {
	return Ref(memnew(GFEntityBuilder(world)));
}

Ref<GFEntityBuilder> GFEntityBuilder::add(const Variant entity, const Variant second) {
	GFWorld* w = get_world();
	ecs_entity_t id = w->coerce_id(entity);
	CHECK_ENTITY_ALIVE(id, w, this,
		"Failed to entity in builder\n"
	);

	if (second.booleanize()) {
		ecs_entity_t second_id = w->coerce_id(second);
		CHECK_ENTITY_ALIVE(second_id, w, this,
			"Failed to entity in builder\n"
		);
		id = ecs_pair(id, second_id);
	}

	ids.append(id);

	return this;
}

Ref<GFEntity> GFEntityBuilder::build() {
	GFWorld* w = get_world();
	return GFEntity::from_id(GFEntityBuilder::build_id(), w);
}

ecs_entity_t GFEntityBuilder::build_id() {
	GFWorld* w = get_world();
	CharString name_utf8 = name.utf8();
	desc.name = name_utf8.get_data();

	ids.append(0); // Add null terminator (required by ecs_entity_desc_t)
	desc.add = reinterpret_cast<const ecs_id_t*>(ids.ptr());

	ecs_entity_t id = ecs_entity_init(
		w->raw(),
		&desc
	);

	// Reset volatile pointers/data
	desc.name = nullptr;
	desc.add = nullptr;
	ids.remove_at(ids.size()-1); // Remove null terminator

	built_count += 1;

	return id;
}

GFWorld* GFEntityBuilder::get_world() const { return Object::cast_to<GFWorld>(
	UtilityFunctions::instance_from_id(world_instance_id)
); }

Ref<GFEntityBuilder> GFEntityBuilder::set_target_entity(const Variant entity) {
	GFWorld* w = get_world();
	ecs_entity_t id = w->coerce_id(entity);

	CHECK_ENTITY_ALIVE(id, w, this,
		"Failed to set entity in builder\n"
	);

	desc.id = id;
	return this;
}

Ref<GFEntityBuilder> GFEntityBuilder::set_name(const String name_) {
	name = name_;
	return this;
}

Ref<GFEntityBuilder> GFEntityBuilder::set_parent(const Variant parent) {
	GFWorld* w = get_world();
	ecs_entity_t parent_id = w->coerce_id(parent);
	CHECK_ENTITY_ALIVE(parent_id, w, this,
		"Failed to set parent in builder\n"
	);
	desc.parent = parent_id;
	return this;
}

// **************************************
// *** Unexposed ***
// **************************************

void GFEntityBuilder::set_world(const GFWorld* world_) {
	world_instance_id = world_->get_instance_id();
}

// **********************************************
// *** PROTECTED ***
// **********************************************

void GFEntityBuilder::_bind_methods() {
	REGISTER_ENTITY_BUILDER_SELF_METHODS(GFEntityBuilder);

	godot::ClassDB::bind_static_method(GFEntityBuilder::get_class_static(), D_METHOD("new_in_world", "world"), &GFEntityBuilder::new_in_world);

	godot::ClassDB::bind_method(D_METHOD("build"), &GFEntityBuilder::build);
	godot::ClassDB::bind_method(D_METHOD("build_id"), &GFEntityBuilder::build_id);
	godot::ClassDB::bind_method(D_METHOD("get_world"), &GFEntityBuilder::get_world);
}

// **********************************************
// *** PRIVATE ***
// **********************************************
