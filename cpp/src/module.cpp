
#include "module.h"
#include "registerable_entity.h"
#include "utils.h"
#include <stdint.h>
#include <flecs.h>
#include "godot_cpp/variant/char_string.hpp"
#include "godot_cpp/classes/wrapped.hpp"
#include "godot_cpp/variant/array.hpp"
#include "world.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

GFModule::~GFModule() {
}

Ref<GFModule> GFModule::new_in_world(GFWorld* world) {
	return memnew(GFModule(world));
}

Ref<GFModule> GFModule::new_named_in_world(const String name, GFWorld* world_) {
	GFWorld* world = GFWorld::world_or_singleton(world_);

	CharString name_utf8 = name.utf8();
	ecs_component_desc_t comp_desc = {0};
	ecs_entity_t module_id = ecs_module_init(
		world->raw(),
		name_utf8,
		&comp_desc

	);
	return from_id(module_id, world);
}

Ref<GFModule> GFModule::from(const Variant module, GFWorld* world_) {
	GFWorld* world = GFWorld::world_or_singleton(world_);

	ecs_entity_t module_id = world->coerce_id(module);
	return from_id(module_id, world);
}

Ref<GFModule> GFModule::from_id(ecs_entity_t module_id, GFWorld* world_) {
	GFWorld* world = GFWorld::world_or_singleton(world_);

	if (!ecs_has_id(world->raw(), module_id, EcsModule)) {
		ERR(nullptr,
			"Could not instantiate module from ID\n",
			"ID is not a module"
		);
	}
	Ref<GFModule> ett = memnew(GFModule(
		module_id,
		world
	));
	if (!ett->is_alive()) {
		ERR(nullptr,
			"Could not instantiate module from ID\n",
			"World/ID is not valid/alive"
		);
	}
	return ett;
}

void GFModule::_register_internal() {
	ecs_component_desc_t desc = {
		.entity = get_id(),
	};
	ecs_module_init(
		get_world()->raw(),
		"TODOSomeName",
		&desc
	);

	GLECS_SCOPE(get_world(), get_id(), {
		Ref<Script> script = get_script();
		Dictionary constants = script->get_script_constant_map();
		Array keys = constants.keys();

		for (int i=0; i != keys.size(); i++) {
			Variant const_val = constants[keys[i]];
			if (!variant_is_registerable_script(const_val)) {
				continue;
			}
			Ref<Script> const_script = const_val;

			// Initialize
			Ref<GFRegisterableEntity> ett = get_world()->register_script_id_no_user_call(const_script);

			// Maybe set name of registered module
			if (ecs_get_name(get_world()->raw(), ett->get_id()) == nullptr) {
				// Entity has no name, give it the name of the constant's key
				String name = keys[i];
				ecs_set_name(get_world()->raw(), ett->get_id(), name.utf8());
			}
		}
	});

	// Call super method
	GFRegisterableEntity::_register_internal();
}

void GFModule::_register_user() {
	GLECS_SCOPE(get_world(), get_id(), {
		// Call super method
		GFRegisterableEntity::_register_user();

		Ref<Script> script = get_script();
		Dictionary constants = script->get_script_constant_map();
		Array keys = constants.keys();

		for (int i=0; i != keys.size(); i++) {
			Variant const_val = constants[keys[i]];
			if (!variant_is_registerable_script(const_val)) {
				continue;
			}

			Ref<Script> const_script = const_val;

			// Initialize sub-item
			Ref<GFRegisterableEntity> ett = ClassDB::instantiate(
				const_script->get_instance_base_type()
			);
			ett->set_id(get_world()->coerce_id(const_script));
			ett->set_world(get_world());
			ett->set_script(const_script);

			ett->call_user_register();
		}
	});
}


void GFModule::_bind_methods() {
	REGISTER_ENTITY_SELF_METHODS(GFModule);

	godot::ClassDB::bind_static_method(get_class_static(), D_METHOD("new_in_world", "world"), &GFModule::new_named_in_world);
	godot::ClassDB::bind_static_method(get_class_static(), D_METHOD("new_named_in_world", "name", "world"), &GFModule::new_named_in_world);
	godot::ClassDB::bind_static_method(get_class_static(), D_METHOD("from", "module", "world"), &GFModule::from, nullptr);
	godot::ClassDB::bind_static_method(get_class_static(), D_METHOD("from_id", "module_id", "world"), &GFModule::from_id, nullptr);
	godot::ClassDB::bind_method(D_METHOD("_register_internal"), &GFModule::_register_internal);
	godot::ClassDB::bind_method(D_METHOD("_register_user"), &GFModule::_register_user);
}
