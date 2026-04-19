
#ifndef QUERY_ITERATION_CONTEXT_BUILDER_H
#define QUERY_ITERATION_CONTEXT_BUILDER_H

#include "component.h"
#include "entity.h"
#include "godot_cpp/variant/callable.hpp"
#include "godot_cpp/variant/packed_int32_array.hpp"
#include "godot_cpp/variant/typed_array.hpp"
#include <query.h>

#include <flecs.h>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>


namespace godot {

	class GFComponent;
	class GFQuerylikeBuilder;

	// Predefine instead of include to avoid cyclic dependencies
	class GFWorld;
	class QueryIterationContext;

	class QueryIterationContext {
	public:
		TypedArray<GFEntity> comp_ref_per_term {TypedArray<GFEntity>()};
		TypedArray<GFEntity> comp_ref_args {TypedArray<GFEntity>()};
		PackedInt32Array comp_ref_term_ids {PackedInt32Array()};

		QueryIterationContext(
			const Ref<GFQuerylikeBuilder> query_b,
			const Callable callable
		);
		QueryIterationContext(GFWorld* world):
			callable(Callable()),
			world(world)
		{};
		~QueryIterationContext();

		Callable get_callable() const;
		GFWorld* get_world() const;

		static Ref<GFEntity> instance_from(ecs_entity_t id, GFWorld* world);

		void update_component_entities(ecs_iter_t* it, int entity_index) const;
		void update_component_terms(ecs_iter_t* it);
		static void iterator_callback(ecs_iter_t* it);

	private:
		Callable callable;
		GFWorld* world;
	};

}

#endif
