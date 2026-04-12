
#ifndef WORLD_H
#define WORLD_H

#include "godot_cpp/classes/script.hpp"
#include "godot_cpp/core/property_info.hpp"
#include "godot_cpp/templates/list.hpp"
#include "godot_cpp/variant/dictionary.hpp"
#include <flecs.h>
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <sys/types.h>

namespace godot {

	// Predefine instead of include to avoid cyclic dependencies
	class GFComponentBuilder;
	class GFObserverBuilder;
	class GFQueryBuilder;
	class GFSystemBuilder;
	class GFEntity;
	class GFRegisterableEntity;
	class GFPair;

	class GFWorld : public Object {
		GDCLASS(GFWorld, Object)

	public:
		GFWorld(): GFWorld(nullptr) {
			setup_glecs();
		};
		GFWorld(void*) {}; // Construct without setup (Used when registering singleton)
		~GFWorld();

		void setup_glecs();

		// **************************************
		// *** Exposed ***
		// **************************************

		void _register_modules_from_scripts(int);
		String _to_string() const;

		ecs_entity_t coerce_id(const Variant);

		static GFWorld* get_default_world();
		int64_t get_raw() const;
		static GFWorld* get_singleton();

		Ref<GFEntity> lookup(const String);

		Ref<GFPair> pair(const Variant, Variant);
		ecs_entity_t pair_ids(ecs_entity_t, ecs_entity_t) const;
		void progress(double delta) const;

		Ref<GFRegisterableEntity> register_script(const Ref<Script>);
		ecs_entity_t register_script_id(const Ref<Script>);
		ecs_entity_t register_new_script_id(const Ref<Script> script);
		Ref<GFRegisterableEntity> register_script_id_no_user_call(const Ref<Script> script);

		bool id_has_child(ecs_entity_t parent, const char* child_name) const;
		bool id_set_parent(ecs_entity_t id, ecs_entity_t parent) const;
		String id_to_text(ecs_entity_t) const;
		Variant::Type id_as_variant_type(ecs_entity_t) const;
		Variant::Type id_into_variant_type(ecs_entity_t) const;

		static void set_default_world(const GFWorld*);
		void set_gd_struct_from_variant(const Variant, const ecs_entity_t, void*) const;

		void start_rest_api() const;
		static ecs_entity_t variant_type_to_id(const Variant::Type);
		static GFWorld* world_or_singleton(GFWorld* world);

		// **************************************
		// *** Maybe expose later ***
		// **************************************

		PropertyInfo _comp_get_property_info(
			ecs_entity_t e,
			ecs_entity_t c,
			const Variant,
			String=String()
		) const;
		void _comp_get_property_list(
			ecs_entity_t e,
			ecs_entity_t c,
			List<PropertyInfo>*,
			String=String()
		) const;
		Variant _comp_getm(ecs_entity_t e, ecs_entity_t c, String) const;
		const EcsMember* _comp_get_member_data(ecs_entity_t comp, const String member) const;
		bool _comp_setm(ecs_entity_t e, ecs_entity_t c, String, Variant) const;
		bool _comp_setm_no_notify(ecs_entity_t e, ecs_entity_t c, String, Variant) const;
		String entity_unique_name(ecs_entity_t parent, String) const;

		// **************************************
		// *** Unexposed ***
		// **************************************

		// *** Glecs entities ***
		static ecs_entity_t glecs;
		static ecs_entity_t glecs_meta;
		static ecs_entity_t glecs_meta_real;
		static ecs_entity_t glecs_meta_nil;
		static ecs_entity_t glecs_meta_bool;
		static ecs_entity_t glecs_meta_int;
		static ecs_entity_t glecs_meta_float;
		static ecs_entity_t glecs_meta_string;
		static ecs_entity_t glecs_meta_vector2;
		static ecs_entity_t glecs_meta_vector2i;
		static ecs_entity_t glecs_meta_rect2;
		static ecs_entity_t glecs_meta_rect2i;
		static ecs_entity_t glecs_meta_vector3;
		static ecs_entity_t glecs_meta_vector3i;
		static ecs_entity_t glecs_meta_transform2d;
		static ecs_entity_t glecs_meta_vector4;
		static ecs_entity_t glecs_meta_vector4i;
		static ecs_entity_t glecs_meta_plane;
		static ecs_entity_t glecs_meta_quaternion;
		static ecs_entity_t glecs_meta_aabb;
		static ecs_entity_t glecs_meta_basis;
		static ecs_entity_t glecs_meta_transform3d;
		static ecs_entity_t glecs_meta_projection;
		static ecs_entity_t glecs_meta_color;
		static ecs_entity_t glecs_meta_string_name;
		static ecs_entity_t glecs_meta_node_path;
		static ecs_entity_t glecs_meta_rid;
		static ecs_entity_t glecs_meta_object;
		static ecs_entity_t glecs_meta_callable;
		static ecs_entity_t glecs_meta_signal;
		static ecs_entity_t glecs_meta_dictionary;
		static ecs_entity_t glecs_meta_array;
		static ecs_entity_t glecs_meta_packed_byte_array;
		static ecs_entity_t glecs_meta_packed_int32_array;
		static ecs_entity_t glecs_meta_packed_int64_array;
		static ecs_entity_t glecs_meta_packed_float32_array;
		static ecs_entity_t glecs_meta_packed_float64_array;
		static ecs_entity_t glecs_meta_packed_string_array;
		static ecs_entity_t glecs_meta_packed_vector2_array;
		static ecs_entity_t glecs_meta_packed_vector3_array;
		static ecs_entity_t glecs_meta_packed_color_array;
		static ecs_entity_t glecs_meta_packed_vector4_array;

		ecs_entity_t get_main_id(ecs_entity_t) const;
		/// Returns the ID which was registered with the given Script.
		/// Returns 0 if the entity has no registered script.
		ecs_entity_t get_registered_id(const Ref<Script> script) const;
		/// Returns the script which was registered with the given ID.
		/// Returns null if the entity has no registered script.
		Ref<Script> get_registered_script(ecs_entity_t id) const;

		void copy_component_ptr(const void*, void*, ecs_entity_t) const;
		void copy_gd_type_ptr(const void*, void*, ecs_entity_t) const;
		void deinit_component_ptr(void*, ecs_entity_t) const;
		void deinit_gd_type_ptr(void*, ecs_entity_t) const;
		void init_component_ptr(void*, ecs_entity_t, Variant) const;
		void init_gd_type_ptr(void*, ecs_entity_t) const;

		bool is_id_alive(const ecs_entity_t id) const;
		ecs_world_t* raw() const;

		void* _comp_get_member_ptr_mut_at(ecs_entity_t e, ecs_entity_t c, int) const;
		Variant _variant_from_member_ptr(
			const void* ptr,
			ecs_entity_t member_type
		) const;
		static Variant _variant_from_member_ptr_primitive(
			const void* ptr,
			ecs_primitive_kind_t primitive
		);

	protected:
		static GDObjectInstanceID global_thread_singleton;
		static thread_local GDObjectInstanceID local_thread_singleton;

		static GFWorld* get_global_thread_singleton();

		static void _bind_methods();

	private:
		ecs_world_t* _raw {nullptr};
		/// Maps registered scripts to entity IDs
		Dictionary registered_entity_ids {Dictionary()};
		/// Maps entity IDs to their registered scripts
		Dictionary registered_entity_scripts {Dictionary()};

		template<typename T>
		static void gd_type_ctor(
			void* ptr,
			int32_t count,
			const ecs_type_info_t* type_info
		) {
			T* list = static_cast<T*>(ptr);
			for (int i=0; i != count; i++) {
				new(&list[i]) T();
			}
		}

		template<typename T>
		static void gd_type_dtor(
			void* ptr,
			int32_t count,
			const ecs_type_info_t* type_info
		) {
			T* list = static_cast<T*>(ptr);
			for (int i=0; i != count; i++) {
				list[i].~T();
			}
		}

		template<typename T>
		static void gd_type_copy(
			void* dst_ptr,
			const void* src_ptr,
			int32_t count,
			const ecs_type_info_t* type_info
		) {
			T* dst_list = static_cast<T*>(dst_ptr);
			const T* src_list = static_cast<const T*>(src_ptr);
			for (int i=0; i != count; i++) {
				dst_list[i] = T(src_list[i]);
			}
		}

		template<typename T>
		static void gd_type_move(
			void* dst_ptr,
			void* src_ptr,
			int32_t count,
			const ecs_type_info_t* type_info
		) {
			T* dst_list = static_cast<T*>(dst_ptr);
			T* src_list = static_cast<T*>(src_ptr);
			for (int i=0; i != count; i++) {
				dst_list[i] = T(src_list[i]);
			}
		}

		template<typename T>
		void define_gd_component(
			const char* name,
			const ecs_entity_t* static_id
		) {
			EcsType type = {
				.kind = ecs_type_kind_t::EcsOpaqueType,
				.existing = true,
				.partial = false
			};
			ecs_component_desc_t desc = {
				.entity = *static_id,
				.type = {
					.size = sizeof(T),
					.alignment = 8
				}
			}; ecs_component_init(_raw, &desc);
			ecs_type_hooks_t hooks = {
				.ctor = GFWorld::gd_type_ctor<T>,
				.dtor = GFWorld::gd_type_dtor<T>,
				.copy = GFWorld::gd_type_copy<T>,
				.move = GFWorld::gd_type_move<T>
			}; ecs_set_hooks_id(_raw, *static_id, &hooks);
			ecs_set_id(raw(), *static_id, ecs_id(EcsType), sizeof(EcsType), &type);
			ecs_add_path_w_sep(
				_raw,
				*static_id,
				glecs_meta,
				name,
				"/",
				"/root/"
			);
		}

		void define_gd_literal(const char*, ecs_primitive_kind_t, ecs_entity_t* id_storage) const;
	};
}

#endif
