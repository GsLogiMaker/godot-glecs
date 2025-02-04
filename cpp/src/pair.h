
#ifndef PAIR_H
#define PAIR_H

#include "component_builder.h"
#include "entity.h"

#include <cassert>
#include <flecs.h>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

	class GFPair : public GFEntity {
		GDCLASS(GFPair, GFEntity)

	public:
		GFPair(ecs_entity_t first, ecs_entity_t second, GFWorld* world):
			GFEntity(ecs_make_pair(first, second), world)
		{}
		GFPair(ecs_entity_t pair_id, GFWorld* world):
			GFEntity(pair_id, world)
		{}
		GFPair():
			GFPair(0, nullptr)
		{}
		~GFPair();

		// --------------------------------------
		// --- Exposed
		// --------------------------------------

		OVERRIDE_ENTITY_SELF_METHODS(GFPair);

		static Ref<GFPair> from(const Variant first, const Variant second, GFWorld*);
		static Ref<GFPair> from_id(ecs_entity_t, GFWorld*);
		static Ref<GFPair> from_ids(ecs_entity_t, ecs_entity_t, GFWorld*);

		Ref<GFEntity> first() const;
		ecs_entity_t first_id() const;
		Ref<GFEntity> second() const;
		ecs_entity_t second_id() const;

		// --------------------------------------
		// --- Unexposed
		// --------------------------------------

	protected:
		static void _bind_methods();


	private:
	};

}

#endif
