
#ifndef WORLD_H
#define WORLD_H

#include "godot_cpp/classes/script.hpp"
#include "godot_cpp/variant/dictionary.hpp"
#include <flecs.h>
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/ref_counted.hpp>

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
		GFWorld();
		~GFWorld();

		// **************************************
		// *** Exposed ***
		// **************************************

		Ref<GFComponentBuilder> component_builder();
		Ref<GFObserverBuilder> observer_builder_varargs(const Variant**, int64_t, GDExtensionCallError&);
		Ref<GFQueryBuilder> query_builder();
		Ref<GFSystemBuilder> system_builder();

		ecs_entity_t coerce_id(Variant);
		Ref<GFEntity> lookup(String);
		Ref<GFPair> pair(Variant, Variant);
		ecs_entity_t pair_ids(ecs_entity_t, ecs_entity_t);
		void progress(double delta);

		Ref<GFRegisterableEntity> register_script(Ref<Script>);
		ecs_entity_t register_script_id(Ref<Script>);
		ecs_entity_t register_new_script_id(Ref<Script> script);
		Ref<GFRegisterableEntity> register_script_id_no_user_call(Ref<Script> script);
		void _register_modules_from_scripts(int);

		void start_rest_api();
		static ecs_entity_t variant_type_to_id(Variant::Type);
		String id_to_text(ecs_entity_t);
		static Variant::Type id_to_variant_type(ecs_entity_t);

		// **************************************
		// *** Unexposed ***
		// **************************************

		static const char* SINGLETON_NAME;

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

		ecs_entity_t get_main_id(ecs_entity_t);
		/// Returns the ID which was registered with the given Script.
		/// Returns 0 if the entity has no registered script.
		ecs_entity_t get_registered_id(Ref<Script> script);
		/// Returns the script which was registered with the given ID.
		/// Returns null if the entity has no registered script.
		Ref<Script> get_registered_script(ecs_entity_t id);

		void copy_component_ptr(const void*, void*, ecs_entity_t);
		void copy_gd_type_ptr(const void*, void*, ecs_entity_t);
		void deinit_component_ptr(void*, ecs_entity_t);
		void deinit_gd_type_ptr(void*, ecs_entity_t);
		void init_component_ptr(void*, ecs_entity_t, Variant);
		void init_gd_type_ptr(void*, ecs_entity_t);

		static GFWorld* world_or_singleton(GFWorld* world);
		static GFWorld* singleton();
		ecs_world_t* raw();

	protected:
		static void _bind_methods();

	private:
		ecs_world_t* _raw;
		/// Maps registered scripts to entity IDs
		Dictionary registered_entity_ids;
		/// Maps entity IDs to their registered scripts
		Dictionary registered_entity_scripts;

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
			ecs_entity_t* static_id
		) {
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
			ecs_add_path_w_sep(
				_raw,
				*static_id,
				glecs_meta,
				name,
				"/",
				"/root/"
			);
		}

		void define_gd_literal(const char*, ecs_primitive_kind_t, ecs_entity_t* id_storage);
	};
}

#endif
