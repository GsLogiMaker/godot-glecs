

#include "observer_builder.h"
#include "querylike_builder.h"
#include "query_iteration_context.h"
#include "world.h"
#include "utils.h"
#include <flecs.h>

using namespace godot;

GFObserverBuilder::~GFObserverBuilder() {
}

Ref<GFObserverBuilder> GFObserverBuilder::new_in_world(GFWorld* world) {
	return memnew(GFObserverBuilder(world));
}

Ref<GFEntity> GFObserverBuilder::for_each(const Callable callable) {
	QUERYLIKE_BUILD_START

	ecs_entity_t obs_id = GFEntityBuilder::build_id();
	// Prevent creating new entity if builder is rebuilt
	set_target_entity(obs_id);

	if (!ecs_has_id(get_world()->raw(), obs_id, EcsObserver)) {
		setup_ctx(callable);
		ecs_observer_desc_t desc = {
			.entity = obs_id,
			.query = query_desc,
			.events = {*events},
			.callback = QueryIterationContext::iterator_callback
		};
		ecs_observer_init(get_world()->raw(), &desc);
	}

	QUERYLIKE_BUILD_END

	return GFEntity::from_id(
		obs_id,
		get_world()
	);
}

Ref<GFObserverBuilder> GFObserverBuilder::set_event(int index, const Variant event) {
	events[index] = get_world()->coerce_id(event);
	return Ref(this);
}

Ref<GFObserverBuilder> GFObserverBuilder::set_events_varargs(
	const Variant** args,
	int64_t arg_count,
	GDExtensionCallError& error
) {
	if (arg_count > FLECS_EVENT_DESC_MAX) {
		// TODO: utilize call error
		ERR(Ref(this),
			"Failed to set terms in observer builder",
			"Max term count is ", FLECS_EVENT_DESC_MAX, ", but ",
			arg_count, " terms were passed"
		);
	}
	for (int i=0; i != FLECS_EVENT_DESC_MAX; i++) {
		if (i < arg_count) {
			events[i] = get_world()->coerce_id(*args[i]);
		} else {
			events[i] = 0;
		}
	}
	return Ref(this);
}

// **********************************************
// *** PROTECTED ***
// **********************************************



void GFObserverBuilder::_bind_methods() {
	REGISTER_QUERYLIKE_SELF_METHODS(GFObserverBuilder);

	godot::ClassDB::bind_static_method(get_class_static(), D_METHOD("new_in_world", "world"), &GFObserverBuilder::new_in_world);
	godot::ClassDB::bind_method(D_METHOD("for_each", "callback"), &GFObserverBuilder::for_each);
	godot::ClassDB::bind_method(D_METHOD("set_event", "index", "event"), &GFObserverBuilder::set_event);
	ClassDB::bind_vararg_method(METHOD_FLAGS_DEFAULT, "set_events", &GFObserverBuilder::set_events_varargs);
}

// **********************************************
// *** PRIVATE ***
// **********************************************
