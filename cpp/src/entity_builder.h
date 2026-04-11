
#ifndef ENTITY_BUILDER_H
#define ENTITY_BUILDER_H

#include "gdextension_interface.h"
#include "godot_cpp/variant/callable.hpp"
#include "godot_cpp/variant/packed_int64_array.hpp"
#include "world.h"

#include <flecs.h>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>

#define OVERRIDE_ENTITY_BUILDER_SELF_METHODS(Self)	\
	Ref<Self> add(const Variant v0, const Variant v1)	{ return GFEntityBuilder::add(v0, v1); }	\
	Ref<Self> set_target_entity(const Variant v0)	{ return GFEntityBuilder::set_target_entity(v0); }	\
	Ref<Self> set_name(const Variant v0)	{ return GFEntityBuilder::set_name(v0); }	\
	Ref<Self> set_parent(const Variant v0)	{ return GFEntityBuilder::set_parent(v0); }	\
;

#define REGISTER_ENTITY_BUILDER_SELF_METHODS(Self)	\
	godot::ClassDB::bind_method(D_METHOD("add", "entity", "second"),	&Self::add, nullptr);	\
	godot::ClassDB::bind_method(D_METHOD("set_target_entity", "entity"),	&Self::set_target_entity);	\
	godot::ClassDB::bind_method(D_METHOD("set_name", "name"),	&Self::set_name);	\
	godot::ClassDB::bind_method(D_METHOD("set_parent", "entity"),	&Self::set_parent, 0);	\
;

namespace godot {

	class GFEntityBuilder : public RefCounted {
		GDCLASS(GFEntityBuilder, RefCounted)

	public:
		GFEntityBuilder(): GFEntityBuilder(nullptr) {}
		GFEntityBuilder(GFWorld* world):
			world_instance_id(
				GFWorld::world_or_singleton(world)->get_instance_id()
			),
			ids(PackedInt64Array()),
			desc({
				.sep="/",
				.root_sep="/root/",
			}),
			name(String("")),
			built_count(0)
		{}
		~GFEntityBuilder() {}

		// **************************************
		// *** Exposed ***
		// **************************************

		static Ref<GFEntityBuilder> new_in_world(GFWorld*);

		Ref<GFEntityBuilder> add(const Variant entity, const Variant second);
		Ref<GFEntityBuilder> set_target_entity(const Variant entity);
		Ref<GFEntityBuilder> set_name(const String);
		Ref<GFEntityBuilder> set_parent(const Variant entity);

		Ref<GFEntity> build();
		ecs_entity_t build_id();
		GFWorld* get_world() const;

		// **************************************
		// *** Unexposed ***
		// **************************************

		void set_world(const GFWorld*);


	protected:
		ecs_entity_desc_t desc;
		/// Owned copy of the IDs to add to the entity.
		PackedInt64Array ids;
		/// Owned copy of the entity's name.
		String name;
		/// The world to query in.
		GDObjectInstanceID world_instance_id;
		int built_count;

		static void _bind_methods();

	private:
	};

}

#endif
