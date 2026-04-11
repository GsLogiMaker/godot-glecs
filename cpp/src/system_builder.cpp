

#include "system_builder.h"
#include "query_iteration_context.h"
#include "godot_cpp/classes/object.hpp"
#include "godot_cpp/variant/variant.hpp"
#include "querylike_builder.h"
#include "world.h"

#include <stdlib.h>
#include <flecs.h>

using namespace godot;

GFSystemBuilder::~GFSystemBuilder() {
}

Ref<GFSystemBuilder> GFSystemBuilder::new_in_world(GFWorld* world) {
	return memnew(GFSystemBuilder(world));
}

Ref<GFEntity> GFSystemBuilder::for_each(const Callable callable) {
	QUERYLIKE_BUILD_START

	ecs_entity_t sys_id = GFEntityBuilder::build_id();
	// Prevent creating new entity if builder is rebuilt
	set_target_entity(sys_id);
	if (!ecs_has_id(get_world()->raw(), sys_id, EcsSystem)) {
		setup_ctx(callable);
		ecs_add_id(get_world()->raw(), sys_id, ecs_dependson(EcsOnUpdate));
		ecs_system_desc_t desc = {
			.entity = sys_id,
			.query = query_desc,
			.callback = QueryIterationContext::iterator_callback
		};
		ecs_system_init(get_world()->raw(), &desc);
	}

	QUERYLIKE_BUILD_END

	return GFEntity::from_id(
		sys_id,
		get_world()
	);
}

// **********************************************
// *** PROTECTED ***
// **********************************************



void GFSystemBuilder::_bind_methods() {
	REGISTER_QUERYLIKE_SELF_METHODS(GFSystemBuilder);

	godot::ClassDB::bind_static_method(get_class_static(), D_METHOD("new_in_world", "world"), &GFSystemBuilder::new_in_world);
	godot::ClassDB::bind_method(D_METHOD("for_each", "callback"), &GFSystemBuilder::for_each);
}

// **********************************************
// *** PRIVATE ***
// **********************************************
