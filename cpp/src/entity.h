
#ifndef GL_ENTITY_H
#define GL_ENTITY_H

#include "entity_iterator.h"
#include "godot_cpp/classes/reg_ex.hpp"
#include "godot_cpp/core/class_db.hpp"
#include "godot_cpp/variant/dictionary.hpp"
#include "godot_cpp/variant/string_name.hpp"
#include "godot_cpp/variant/typed_array.hpp"
#include "godot_cpp/variant/variant.hpp"
#include "utils.h"
#include "world.h"

#include <cassert>
#include <cstdint>
#include <flecs.h>
#include <godot_cpp/classes/ref_counted.hpp>

#define OVERRIDE_ENTITY_SELF_METHODS(Self)	\
	Ref<Self> add_child(const Variant v0)	{ return GFEntity::add_child(v0); }	\
	Ref<Self> add_sibling(const Variant v0)	{ return GFEntity::add_sibling(v0); }	\
	Ref<Self> add_componentv(const Variant v0, const Variant v1)	{ return GFEntity::add_componentv(v0, v1); }	\
	Ref<Self> clear()	{ return GFEntity::clear(); }	\
	Ref<Self> set_componentv(const Variant v0, const Variant v1)	{ return GFEntity::set_componentv(v0, v1); }	\
	Ref<Self> set_pairv(const Variant v0, const Variant v1, const Variant v2)	{ return GFEntity::set_pairv(v0, v1, v2); }	\
	Ref<Self> add_pairv(const Variant v0, const Variant v1, const Variant v2)	{ return GFEntity::add_pairv(v0, v1, v2); }	\
	Ref<Self> add_tag(const Variant v0)	{ return GFEntity::add_tag(v0); }	\
	Ref<Self> emit(const Variant v0, const Array v1)	{ return GFEntity::emit(v0, v1); }	\
	Ref<Self> inherit(const Variant v0)	{ return GFEntity::inherit(v0); }	\
	Ref<Self> set_name(const String v0)	{ return GFEntity::set_name(v0); }	\
	Ref<Self> set_parent(const Variant v0)	{ return GFEntity::set_parent(v0); }	\
	Ref<Self> add_component(const Variant** v0, GDExtensionInt v1, GDExtensionCallError& v2)	{ return GFEntity::add_component(v0, v1, v2); }	\
	Ref<Self> set_component(const Variant** v0, GDExtensionInt v1, GDExtensionCallError& v2)	{ return GFEntity::set_component(v0, v1, v2); }	\
	Ref<Self> add_pair(const Variant** v0, GDExtensionInt v1, GDExtensionCallError& v2)	{ return GFEntity::add_pair(v0, v1, v2); }	\
	Ref<Self> set_pair(const Variant** v0, GDExtensionInt v1, GDExtensionCallError& v2)	{ return GFEntity::set_pair(v0, v1, v2); }	\
	Ref<Self> remove_component(const Variant v0, const Variant v1)	{ return GFEntity::remove_component(v0, v1); }	\
;

#define REGISTER_ENTITY_SELF_METHODS(Self)	\
	godot::ClassDB::bind_method(D_METHOD("add_child", "entity"),	&Self::add_child);	\
	godot::ClassDB::bind_method(D_METHOD("add_sibling", "entity"),	&Self::add_sibling);	\
	godot::ClassDB::bind_method(D_METHOD("addv", "component", "members"),	&Self::add_componentv, Array());	\
	godot::ClassDB::bind_method(D_METHOD("clear"),	&Self::clear);	\
	godot::ClassDB::bind_method(D_METHOD("setv", "component", "members"),	&Self::set_componentv);	\
	godot::ClassDB::bind_method(D_METHOD("add_pairv", "first", "second", "members"),	&Self::add_pairv, Array());	\
	godot::ClassDB::bind_method(D_METHOD("set_pairv", "first", "second", "members"),	&Self::set_pairv);	\
	godot::ClassDB::bind_method(D_METHOD("add_tag", "tag"),	&Self::add_tag);	\
	godot::ClassDB::bind_method(D_METHOD("emit", "entity", "event_members"),	&Self::emit, Array());	\
	godot::ClassDB::bind_method(D_METHOD("inherit", "entity"),	&Self::inherit);	\
	godot::ClassDB::bind_method(D_METHOD("remove", "entity", "second"),	&Self::remove_component, nullptr);	\
	godot::ClassDB::bind_method(D_METHOD("set_name", "name"),	&Self::set_name);	\
	godot::ClassDB::bind_method(D_METHOD("set_parent", "entity"),	&Self::set_parent);	\
	{	\
		MethodInfo mi;	\
		mi.arguments.push_back(PropertyInfo(Variant::NIL, "component"));	\
		mi.name = "add";	\
		mi.flags = METHOD_FLAGS_DEFAULT;	\
		godot::ClassDB::bind_vararg_method(METHOD_FLAGS_DEFAULT, StringName(mi.name), &Self::add_component, mi);	\
	}	\
	{	\
		MethodInfo mi;	\
		mi.arguments.push_back(PropertyInfo(Variant::NIL, "component"));	\
		mi.name = "set";	\
		godot::ClassDB::bind_vararg_method(METHOD_FLAGS_DEFAULT, StringName(mi.name), &Self::set_component, mi);	\
	}	\
	{	\
		MethodInfo mi;	\
		mi.arguments.push_back(PropertyInfo(Variant::NIL, "first"));	\
		mi.arguments.push_back(PropertyInfo(Variant::NIL, "second"));	\
		mi.name = "add_pair";	\
		godot::ClassDB::bind_vararg_method(METHOD_FLAGS_DEFAULT, StringName(mi.name), &Self::add_pair, mi);	\
	}	\
	{	\
		MethodInfo mi;	\
		mi.arguments.push_back(PropertyInfo(Variant::NIL, "first"));	\
		mi.arguments.push_back(PropertyInfo(Variant::NIL, "second"));	\
		mi.name = "set_pair";	\
		godot::ClassDB::bind_vararg_method(METHOD_FLAGS_DEFAULT, StringName(mi.name), &Self::set_pair, mi);	\
	}	\
;

namespace godot {

	// Predefine instead of include to avoid cyclic dependencies
	class GFComponent;
	class GFPair;

	class GFEntity : public RefCounted {
		GDCLASS(GFEntity, RefCounted)

	public:
		// New entity in global world
		GFEntity(): GFEntity(nullptr) {};
		// New entity in specific world
		GFEntity(GFWorld* world) {
			GFWorld* w = GFWorld::world_or_singleton(world);
			id = ecs_new(w->raw());
			world_instance_id = w->get_instance_id();
		};
		// Reference an entity
		GFEntity(ecs_entity_t id_, GFWorld* world):
			id(id_)
		{
			GFWorld* w = GFWorld::world_or_singleton(world);
			world_instance_id = w->get_instance_id();
		}
		// Copy an entity reference
		GFEntity(GFEntity& ett): GFEntity(ett.get_id(), ett.get_world()) {}
		~GFEntity() {};

		// --------------------------------------
		// --- Exposed ---
		// --------------------------------------

		static Ref<GFEntity> new_in_world(GFWorld*);
		static Ref<GFEntity> from(const Variant, GFWorld*);
		static Ref<GFEntity> from_id(ecs_entity_t, GFWorld*);

		Variant __get(const StringName property);
		bool _get(StringName, Variant&);
		void _get_property_list(List<PropertyInfo> *p_list);
		bool _set(StringName, Variant);

		Ref<GFEntity> add_child(const Variant entity);
		Ref<GFEntity> add_component(const Variant**, GDExtensionInt, GDExtensionCallError&);
		Ref<GFEntity> add_componentv(const Variant, const Array);
		Ref<GFEntity> set_component(const Variant**, GDExtensionInt, GDExtensionCallError&);
		Ref<GFEntity> set_componentv(const Variant, const Array);

		Ref<GFEntity> add_pair(const Variant**, GDExtensionInt, GDExtensionCallError&);
		Ref<GFEntity> add_pairv(const Variant, const Variant, const Array);
		Ref<GFEntity> set_pair(const Variant**, GDExtensionInt, GDExtensionCallError&);
		Ref<GFEntity> set_pairv(const Variant, const Variant, const Array);

		Ref<GFEntity> add_sibling(const Variant);

		Ref<GFEntity> add_tag(const Variant);
		Ref<GFEntity> emit(const Variant, const Array);
		Ref<GFEntity> set_name(const String);
		Ref<GFEntity> set_parent(const Variant entity);

		Ref<GFEntity> clear();
		void delete_() const;

		Ref<GFEntity> get_child(const String) const;
		TypedArray<GFEntity> get_children() const;
		Variant get_component(const Variant, const Variant) const;
		static const RegEx* get_entity_id_regex();
		ecs_entity_t get_id() const;
		String get_name() const;
		Ref<GFEntity> get_parent() const;
		String get_path() const;
		Ref<GFEntity> get_target_for(const Variant, int) const;
		GFWorld* get_world() const;

		bool has_entity(const Variant, const Variant) const;
		bool has_child(const String) const;

		Ref<GFEntity> inherit(Variant);

		bool is_alive() const;
		bool is_inheriting(const Variant) const;
		bool is_owner_of(const Variant) const;
		bool is_pair() const;
		Ref<GFEntityIterator> iter_children() const;


		Ref<GFPair> pair(const Variant second) const;
		ecs_entity_t pair_id(const ecs_entity_t second_id) const;

		Ref<GFEntity> remove_component(const Variant entity, const Variant second);

		String _to_string() const;

		// --------------------------------------
		// --- Unexposed ---
		// --------------------------------------

		/// Assigns the correct script to this entity according to its ID.
		void update_script() {
			Ref<Script> script = get_world()->get_registered_script(get_id());
			if (script == nullptr) {
				return;
			}
			if (!ClassDB::is_parent_class(
				get_class(),
				script->get_instance_base_type()
			)) {
				return;
			}
			set_script(script);
		}

		template<typename T>
		static Ref<T> setup_template(const Ref<T> e) {
			e->update_script();

			if (!e->is_alive()) {
				ERR(nullptr,
					"Could not instantiate ", T::get_class_static(), " from ID\n",
					"	ID ", e->get_id(), " is not alive in world ", e->get_world()
				);
			}

			return e;
		}


		void set_id(const ecs_entity_t);
		void set_world(const GFWorld*);

	protected:
		static void _bind_methods();

	private:
		ecs_entity_t id {0};
		uint64_t world_instance_id {0};
	};

}

#endif
