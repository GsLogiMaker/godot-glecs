
#include "entity.h"
#include "entity_iterator.h"
#include "godot_cpp/classes/global_constants.hpp"
#include "godot_cpp/classes/reg_ex.hpp"
#include "godot_cpp/classes/reg_ex_match.hpp"
#include "godot_cpp/classes/script.hpp"
#include "godot_cpp/core/memory.hpp"
#include "godot_cpp/core/property_info.hpp"
#include "godot_cpp/variant/array.hpp"
#include "godot_cpp/variant/packed_string_array.hpp"
#include "godot_cpp/variant/string_name.hpp"
#include "godot_cpp/variant/typed_array.hpp"
#include "utils.h"
// needed here because entity.h does not include
// component.h, but uses forward declaration instead
#include "component.h"
#include "pair.h"

#include <flecs.h>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include "godot_cpp/variant/variant.hpp"
#include "world.h"

using namespace godot;

Ref<GFEntity> GFEntity::new_in_world(GFWorld* world) {
	return memnew(GFEntity(world));
}
Ref<GFEntity> GFEntity::from(const Variant entity, GFWorld* world) {
	world = GFWorld::world_or_singleton(world);
	return memnew(GFEntity(world->coerce_id(entity), world));
}
Ref<GFEntity> GFEntity::from_id(ecs_entity_t id, GFWorld* world) {
	return setup_template<GFEntity>(memnew(GFEntity(id, world)));
}

const RegEx* GFEntity::get_entity_id_regex() {
	static RegEx* regex = memnew(RegEx());
	if (!regex->is_valid()) {
		regex->compile("#([-]?[0-9]+)");
	}
	return regex;
}

Variant GFEntity::__get(const StringName property) {
	Variant result = Variant();
	_get(property, result);
	return result;
}

bool GFEntity::_get(StringName property, Variant& out) {
	if (is_class(property)) {
		// Property is an inhereted class, return true
		return true;
	}
	if (property.contains(".")) {
		// Property is an inhereted script, return true
		return true;
	}
	if (property == StringName("script")) {
		// Property is `script` from RefCounted, return script
		out = get_script();
		return true;
	}

	GFWorld* w = get_world();

	PackedStringArray prop_parts = property.split("/");
	if (prop_parts.size() < 1) {
		return false;
	}
	TypedArray<RegExMatch> matches = get_entity_id_regex()->search_all(prop_parts[0]);
	if (matches.size() == 0 || matches.size() > 2) {
		return false;
	}

	Ref<RegExMatch> match0 = matches[0];
	ecs_entity_t comp_id = match0->get_strings()[1].to_int();
	if (matches.size() > 1) {
		// Component is a pair
		Ref<RegExMatch> match1 = matches[1];
		comp_id = ecs_pair(
			comp_id,
			match1->get_strings()[1].to_int()
		);
	}

	if (!w->is_id_alive(comp_id)) {
		// Component is not alive, abort
		return false;
	}
	if (prop_parts.size() < 2) {
		// Found tag, return null
		return true;
	}
	if (!ecs_has(w->raw(), comp_id, EcsStruct)) {
		// Component is not a struct, abort
		return false;
	}

	const EcsMember* member_c = w->_comp_get_member_data(comp_id, prop_parts[1]);
	if (member_c == nullptr) {
		// Member is does not exist, abort
		return false;
	}

	out = w->_comp_getm(get_id(), comp_id, prop_parts[1]);
	return true;
}

void GFEntity::_get_property_list(List<PropertyInfo>* p_list) {
	GFWorld* w = get_world();
	const ecs_type_t* type = ecs_get_type(w->raw(), get_id());

	for (int i=0; i != type->count; i++) {
		ecs_entity_t main_id = w->get_main_id(type->array[i]);
		if (!w->is_id_alive(main_id)) {
			continue;
		}

		String comp_name = w->id_to_text(type->array[i]);

		if (!ecs_has(w->raw(), main_id, EcsStruct)) {
			p_list->push_back(PropertyInfo(
				Variant::NIL,
				comp_name,
				PROPERTY_HINT_NONE,
				"",
				PROPERTY_USAGE_EDITOR,
				""
			));
			continue;
		}

		w->_comp_get_property_list(
			get_id(),
			type->array[i],
			p_list,
			comp_name + "/"
		);
	}
}

bool GFEntity::_set(StringName property, Variant value) {
	if (is_class(property)) {
		// Property is an inhereted class, return true
		return true;
	}
	if (property.contains(".")) {
		// Property is an inhereted script, return true
		return true;
	}
	if (property == StringName("script")) {
		// Property is `script` from RefCounted, return script
		set_script(value);
		return true;
	}

	GFWorld* w = get_world();

	PackedStringArray prop_parts = property.split("/");
	if (prop_parts.size() < 1) {
		return false;
	}
	TypedArray<RegExMatch> matches = get_entity_id_regex()->search_all(prop_parts[0]);
	if (matches.size() == 0 || matches.size() > 2) {
		return false;
	}

	Ref<RegExMatch> match0 = matches[0];
	ecs_entity_t comp_id = match0->get_strings()[1].to_int();
	if (matches.size() > 1) {
		// Component is a pair
		Ref<RegExMatch> match1 = matches[1];
		comp_id = ecs_pair(
			comp_id,
			match1->get_strings()[1].to_int()
		);
	}

	if (!w->is_id_alive(comp_id)) {
		// Component is not alive, abort
		return false;
	}
	if (prop_parts.size() < 2) {
		// Found tag, return null
		return true;
	}
	if (!ecs_has(w->raw(), comp_id, EcsStruct)) {
		// Component is not a struct, abort
		return false;
	}

	const EcsMember* member_c = w->_comp_get_member_data(comp_id, prop_parts[1]);
	if (member_c == nullptr) {
		// Member is does not exist, abort
		return false;
	}

	w->_comp_setm(get_id(), comp_id, prop_parts[1], value);
	return true;
}

Ref<GFEntity> GFEntity::add_child(const Variant entity) {
	ecs_entity_t id = get_world()->coerce_id(entity);
	get_world()->id_set_parent(id, get_id());
	return Ref(this);
}

Ref<GFEntity> GFEntity::add_component(
	const Variant** args, GDExtensionInt arg_count, GDExtensionCallError &error
) {
	if (arg_count < 1) {
		// Too few arguments, return with error.
		error.error = GDExtensionCallErrorType::GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
		error.argument = arg_count;
		error.expected = 1;
		return Ref(this);
	}

	// Parse arguments
	Array members = Array();
	members.resize(arg_count);
	for (int i=0; i != arg_count; i++) {
		members[i] = *args[i];
	}
	Variant comopnent = members.pop_front();

	add_componentv(comopnent, members);

	return Ref(this);
}

Ref<GFEntity> GFEntity::add_componentv(const Variant component, const Array members) {
	GFWorld* w = get_world();

	ecs_entity_t c_id = w->coerce_id(component);
	CHECK_ENTITY_ALIVE(c_id, w, nullptr,
		"Failed to add to component\n"
	);

	ecs_add_id(w->raw(), get_id(), c_id);

	if (members.size() != 0) {
		return set_componentv(c_id, members);
	}

	return Ref(this);
}

Ref<GFEntity> GFEntity::add_pair(
	const Variant** args, GDExtensionInt arg_count, GDExtensionCallError &error
) {
	if (arg_count < 2) {
		// Too few arguments, return with error.
		error.error = GDExtensionCallErrorType::GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
		error.argument = arg_count;
		error.expected = 2;
		return Ref(this);
	}

	// Parse arguments
	Array members = Array();
	members.resize(arg_count);
	for (int i=0; i != arg_count; i++) {
		members[i] = *args[i];
	}
	Variant first = members.pop_front();
	Variant sec = members.pop_front();

	return add_pairv(first, sec, members);
}
Ref<GFEntity> GFEntity::add_pairv(
	const Variant first,
	const Variant second,
	const Array members
) {
	GFWorld* w = get_world();

	ecs_entity_t first_id = w->coerce_id(first);
	ecs_entity_t second_id = w->coerce_id(second);
	ecs_entity_t pair_id = w->pair_ids(first_id, second_id);
	if (
		members.size() != 0
		|| ecs_has_id(w->raw(), pair_id, FLECS_IDEcsComponentID_)
	) {
		// Add pair as a component
		return add_componentv(pair_id, members);
	} else {
		// Add pair as a dataless tag
		return add_tag(pair_id);
	}

	return Ref(this);
}

Ref<GFEntity> GFEntity::add_sibling(const Variant sib) {
	GFWorld* w = get_world();

	ecs_entity_t sib_id = get_world()->coerce_id(sib);
	CHECK_ENTITY_ALIVE(sib_id, w, nullptr,
		"Failed to add sibling\n"
	);

	ecs_entity_t parent = ecs_get_parent(
		w->raw(),
		get_id()
	);
	ecs_add_pair(w->raw(), sib_id, EcsChildOf, parent);

	return this;
}


Ref<GFEntity> GFEntity::add_tag(const Variant tag) {
	GFWorld* w = get_world();

	ecs_entity_t tag_id = w->coerce_id(tag);

	if (ecs_has(w->raw(), tag_id, EcsComponent)) {
		ERR(nullptr,
			"Failed to add tag to entity\n",
			"	ID, ", tag_id, " is a component, not a tag\n"
			"	(Tags are any entity with no data)"
		);
	}

	ecs_add_id(w->raw(), get_id(), tag_id);

	return Ref(this);
}

Ref<GFEntity> GFEntity::emit(
	const Variant target_entity,
	const Array event_members
) {
	GFWorld* w = get_world();

	// Setup parameter
	ecs_entity_t componet_id = 0;
	const EcsComponent* comp_data = nullptr;
	int8_t* event_data = nullptr;
	if (comp_data != nullptr) {
		event_data = new int8_t[comp_data->size];
		GFComponent::build_data_from_members(
			event_members,
			event_data,
			get_id(),
			w
		);
	}

	ecs_entity_t target_id = w->coerce_id(target_entity);

	auto type = ecs_get_type(w->raw(), target_id);

	// Emit
	ecs_event_desc_t desc = {
		.event = get_id(),
		.ids = ecs_get_type(w->raw(), target_id),
		.entity = target_id,
		.param = static_cast<void*>(event_data)
	};

	ecs_emit(w->raw(), &desc );

	// Cleanup
	if (event_data != nullptr) {
		delete [] event_data;
	}

	return Ref(this);
}

Variant GFEntity::get_component(const Variant entity, const Variant second, const Variant default_value) const {
	GFWorld* w = get_world();

	ecs_entity_t comp_id = w->coerce_id(entity);
	CHECK_ENTITY_ALIVE(comp_id, w, default_value,
		"Failed to get component\n"
	);

	if (second.booleanize()) {
		ecs_entity_t second_id = w->coerce_id(second);
		CHECK_ENTITY_ALIVE(second_id, w, default_value,
			"Failed to get component\n"
		);

		comp_id = ecs_pair(comp_id, second_id);
	}

	if (!ecs_has_id(get_world()->raw(), get_id(), comp_id)) {
		ERR(default_value,
			"Failed to get component\n	Could not find attached component ID: ",
			w->id_to_text(comp_id),
			" on entity: ",
			this
		);
	}

	ecs_entity_t comp_id_main = w->get_main_id(comp_id);

	const EcsStruct* struct_c = ecs_get(w->raw(), comp_id_main, EcsStruct);
	if (struct_c != nullptr) {
		// Component is a struct
		if (ecs_vec_count(&struct_c->members) == 1) {
			// Struct only has one member--return just the member instead of
			// the whole component reference
			ecs_member_t* member = ecs_vec_get_t(&struct_c->members, ecs_member_t, 0);
			return w->_variant_from_member_ptr(
				w->_comp_get_member_ptr_mut_at(get_id(), comp_id, 0),
				member->type
			);
		}
	} else {
		// Component is not a struct--maybe primitive
		const EcsPrimitive* primitive_c = ecs_get(w->raw(), comp_id_main, EcsPrimitive);
		if (primitive_c != nullptr) {
			// Component is a primitive--return just the primitive instead
			// of the whole component reference
			return w->_variant_from_member_ptr_primitive(
				w->_comp_get_member_ptr_mut_at(get_id(), comp_id, 0),
				primitive_c->kind
			);
		}
	}

	Ref<GFComponent> c_reference = GFComponent::from_id(
		comp_id,
		get_id(),
		get_world()
	);
	return c_reference;
}

bool GFEntity::has_entity(const Variant entity, const Variant second) const {
	GFWorld* w = get_world();

	ecs_entity_t id = w->coerce_id(entity);
	CHECK_ENTITY_ALIVE(id, w, false,
		"Failed to check for entity\n"
	);

	if (second.booleanize()) {
		ecs_entity_t second_id = w->coerce_id(second);
		CHECK_ENTITY_ALIVE(second_id, w, false,
			"Failed to check for entity\n"
		);

		id = ecs_pair(id, second_id);
	}

	return ecs_has_id(get_world()->raw(), get_id(), id);
}


bool GFEntity::has_child(const String path) const {
	return ecs_lookup_path_w_sep(
		get_world()->raw(),
		get_id(),
		path.utf8(),
		"/",
		"/root/",
		false
	) != 0;
}

Ref<GFEntity> GFEntity::set_component(
	const Variant** args, GDExtensionInt arg_count, GDExtensionCallError &error
) {
	if (arg_count < 1) {
		// Too few arguments, return with error.
		error.error = GDExtensionCallErrorType::GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
		error.argument = arg_count;
		error.expected = 1;
		return Ref(this);
	}

	// Parse arguments
	Array members = Array();
	members.resize(arg_count);
	for (int i=0; i != arg_count; i++) {
		members[i] = *args[i];
	}
	Variant comopnent = members.pop_front();

	return set_componentv(comopnent, members);
}

Ref<GFEntity> GFEntity::set_componentv(
	const Variant component,
	const Array members
) {
	GFWorld* w = get_world();

	ecs_entity_t c_id = w->coerce_id(component);

	if (!ecs_has_id(w->raw(), get_id(), c_id)) {
		// Component is not present in entity, add it

		if (ECS_IS_PAIR(c_id)) {
			// ID is a pair, perform pair specific checks
			ecs_entity_t first_id = ECS_PAIR_FIRST(c_id);
			ecs_entity_t second_id = ECS_PAIR_SECOND(c_id);
			if (
				!ecs_has_id(w->raw(), first_id, ecs_id(EcsComponent))
				&& !ecs_has_id(w->raw(), second_id, ecs_id(EcsComponent))
			) {
				// ID is not a component, error
				ERR(nullptr,
					"Failed to set data in pair\n",
					"	Neither ", w->id_to_text(first_id),
					" nor ", w->id_to_text(second_id), "are components"
				);
			}

		} else if (!ecs_has_id(w->raw(), c_id, ecs_id(EcsComponent))) {
			// Passed ID is not a component, handle
			if (members.size() != 0) {
				ERR(nullptr, "Failed to set data in component\n",
					"	Entity ", w->id_to_text(c_id), " is not a component"
				);
			}

			// Add as tag and return
			ecs_add_id(w->raw(), get_id(), c_id);
			return this;
		}

		ecs_add_id(w->raw(), get_id(), c_id);
	}

	GFComponent::build_data_from_members(
		members,
		ecs_get_mut_id(w->raw(), get_id(), c_id),
		c_id,
		get_world()
	);
	ecs_modified_id(w->raw(), get_id(), c_id);

	return Ref(this);
}

Ref<GFEntity> GFEntity::set_pair(
	const Variant** args, GDExtensionInt arg_count, GDExtensionCallError &error
) {
	if (arg_count < 1) {
		// Too few arguments, return with error.
		error.error = GDExtensionCallErrorType::GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
		error.argument = arg_count;
		error.expected = 1;
		return Ref(this);
	}

	// Parse arguments
	Array members = Array();
	members.resize(arg_count);
	for (int i=0; i != arg_count; i++) {
		members[i] = *args[i];
	}
	Variant first = members.pop_front();
	Variant sec = members.pop_front();

	return set_pairv(first, sec, members);
}

Ref<GFEntity> GFEntity::set_pairv (
	const Variant first,
	const Variant second,
	const Array members
) {
	ecs_entity_t first_id = get_world()->coerce_id(first);
	ecs_entity_t second_id = get_world()->coerce_id(second);
	set_componentv(ecs_pair(first_id, second_id), members);

	return Ref(this);
}

Ref<GFEntity> GFEntity::clear() {
	ecs_clear(get_world()->raw(), get_id());
	return this;
}

void GFEntity::delete_() const {
	ecs_delete(get_world()->raw(), get_id());
}

ecs_entity_t GFEntity::get_id() const { return id; }
String GFEntity::get_path() const {
	return String(ecs_get_path_w_sep(
		get_world()->raw(),
		0,
		get_id(),
		"/",
		"/root/"
	));
}
GFWorld* GFEntity::get_world() const { return Object::cast_to<GFWorld>(
	UtilityFunctions::instance_from_id(world_instance_id)
); }

Ref<GFEntity> GFEntity::inherit(Variant entity) {
	return add_pairv(EcsIsA, entity, {});
}

bool GFEntity::is_alive() const {
	if (!UtilityFunctions::is_instance_id_valid(world_instance_id)) {
		return false;
	}

	return get_world()->is_id_alive(get_id());
}

bool GFEntity::is_inheriting(Variant entity) const {
	GFWorld* w = get_world();
	ecs_entity_t id = w->coerce_id(entity);
	CHECK_ENTITY_ALIVE(id, w, false,
		"Failed to check inheritance\n"
	);
	return has_entity(EcsIsA, id);
}

bool GFEntity::is_owner_of(const Variant entity) const {
	GFWorld* w = get_world();
	ecs_entity_t id = w->coerce_id(entity);
	CHECK_ENTITY_ALIVE(id, w, false,
		"Failed to check ownership\n"
	);
	return ecs_owns_id(w->raw(), get_id(), id);
}

bool GFEntity::is_pair() const {
	return ecs_id_is_pair(get_id());
}

Ref<GFEntityIterator> GFEntity::iter_children() const {
	GFWorld* w = get_world();
	ecs_iter_t iter = ecs_children(w->raw(), get_id());
	return Ref(memnew(GFEntityIterator(iter, w)));
}

Ref<GFEntity> GFEntity::get_child(const String name) const {
	ecs_entity_t id = ecs_lookup_path_w_sep(
		get_world()->raw(),
		get_id(),
		name.utf8(),
		"/",
		"/root/",
		false
	);
	if (id == 0) {
		return nullptr;
	}
	return GFEntity::from_id(id, get_world());
}

TypedArray<GFEntity> GFEntity::get_children() const {
	// Entity iterator should only ever iterate over
	// entities, so we can safely cast it to a typed array.
	Array arr = iter_children()->into_array();
	return arr;
}

String GFEntity::get_name() const {
	CHECK_ENTITY_ALIVE(get_id(), get_world(), "",
		"Failed to get name of entity\n"
	);
	return String(ecs_get_name(get_world()->raw(), get_id()));
}

Ref<GFEntity> GFEntity::get_parent() const {
	ecs_entity_t parent = ecs_get_parent(
		get_world()->raw(),
		get_id()
	);

	if (parent == 0) {
		return nullptr;
	}

	return GFEntity::from_id(parent, get_world());
}

/// Returns the target for a pair added to an entity.
Ref<GFEntity> GFEntity::get_target_for(const Variant rel, int index) const {
	GFWorld* w = get_world();

	ecs_entity_t rel_id = w->coerce_id(rel);
	CHECK_ENTITY_ALIVE(rel_id, w, nullptr,
		"Failed to get target for added relationship\n"
	);

	ecs_entity_t target_id = ecs_get_target(
		get_world()->raw(),
		get_id(),
		rel_id,
		index
	);
	CHECK_ENTITY_ALIVE(target_id, w, nullptr,
		"Failed to get target for added relationship\n"
	);

	return GFEntity::from_id(target_id, w);
}

Ref<GFEntity> GFEntity::set_name(const String name) {
	GFWorld* w = get_world();
	ecs_entity_t parent = ecs_get_parent(
		w->raw(),
		get_id()
	);

	String unique_name = w->entity_unique_name(parent, name);

	CharString char_name = unique_name.utf8();
	ecs_set_name(get_world()->raw(), get_id(), char_name);
	return Ref(this);
}

Ref<GFEntity> GFEntity::set_parent(const Variant entity) {
	ecs_entity_t id = get_world()->coerce_id(entity);
	if (!get_world()->id_set_parent(get_id(), id)) {
		return nullptr;
	}
	return Ref(this);
}

Ref<GFPair> GFEntity::pair(const Variant second) const {
	return GFPair::from_id(pair_id(get_world()->coerce_id(second)), get_world());
}
ecs_entity_t GFEntity::pair_id(const ecs_entity_t second) const {
	return get_world()->pair_ids(get_id(), second);
}

Ref<GFEntity> GFEntity::remove_component(const Variant entity, const Variant second) {
	GFWorld* w = get_world();

	ecs_entity_t id = w->coerce_id(entity);
	CHECK_ENTITY_ALIVE(id, w, nullptr,
		"Failed to remove component\n"
	);

	if (second.booleanize()) {
		ecs_entity_t second_id = w->coerce_id(second);
		CHECK_ENTITY_ALIVE(second_id, w, nullptr,
			"Failed to remove component\n"
		);
		id = ecs_pair(id, second_id);
	}

	if (!ecs_has_id(w->raw(), get_id(), id)) {
		ERR(nullptr,
			"Failed to remove component\n",
			"	Component ID ", id, " is not attached to entity"
		);
	}

	ecs_remove_id(get_world()->raw(), get_id(), id);

	return Ref(this);
}

String GFEntity::_to_string() const {
	return get_world()->id_to_text(get_id());
}

// ----------------------------------------------
// --- Unexposed ---
// ----------------------------------------------

void GFEntity::set_id(const ecs_entity_t value) { id = value; }
void GFEntity::set_world(const GFWorld* value) { world_instance_id = value->get_instance_id(); }

void GFEntity::_bind_methods() {
	REGISTER_ENTITY_SELF_METHODS(GFEntity);

	godot::ClassDB::bind_static_method(GFEntity::get_class_static(), D_METHOD("new_in_world", "world"), &GFEntity::new_in_world);
	godot::ClassDB::bind_static_method(GFEntity::get_class_static(), D_METHOD("from", "entity", "world"), &GFEntity::from, nullptr);
	godot::ClassDB::bind_static_method(GFEntity::get_class_static(), D_METHOD("from_id", "id", "world"), &GFEntity::from_id, nullptr);

	godot::ClassDB::bind_method(D_METHOD("_get", "property"), &GFEntity::__get);
	godot::ClassDB::bind_method(D_METHOD("get", "component", "second", "default_value"), &GFEntity::get_component, nullptr, nullptr);

	godot::ClassDB::bind_method(D_METHOD("delete"), &GFEntity::delete_);

	godot::ClassDB::bind_method(D_METHOD("get_child", "path"), &GFEntity::get_child);
	godot::ClassDB::bind_method(D_METHOD("get_children"), &GFEntity::get_children);
	godot::ClassDB::bind_method(D_METHOD("get_id"), &GFEntity::get_id);
	godot::ClassDB::bind_method(D_METHOD("get_name"), &GFEntity::get_name);
	godot::ClassDB::bind_method(D_METHOD("get_parent"), &GFEntity::get_parent);
	godot::ClassDB::bind_method(D_METHOD("get_path"), &GFEntity::get_path);
	godot::ClassDB::bind_method(D_METHOD("get_world"), &GFEntity::get_world);
	godot::ClassDB::bind_method(D_METHOD("get_target_for", "relationship", "index"), &GFEntity::get_target_for, 0);

	godot::ClassDB::bind_method(D_METHOD("has", "entity", "second"), &GFEntity::has_entity, nullptr);
	godot::ClassDB::bind_method(D_METHOD("has_child", "path"), &GFEntity::has_child);

	godot::ClassDB::bind_method(D_METHOD("is_alive"), &GFEntity::is_alive);
	godot::ClassDB::bind_method(D_METHOD("is_inheriting", "entity"),	&GFEntity::is_inheriting);
	godot::ClassDB::bind_method(D_METHOD("is_owner_of"), &GFEntity::is_owner_of);
	godot::ClassDB::bind_method(D_METHOD("is_pair"), &GFEntity::is_pair);

	godot::ClassDB::bind_method(D_METHOD("iter_children"), &GFEntity::iter_children);

	godot::ClassDB::bind_method(D_METHOD("pair", "second"), &GFEntity::pair);
	godot::ClassDB::bind_method(D_METHOD("pair_id", "second_id"), &GFEntity::pair_id);
}
