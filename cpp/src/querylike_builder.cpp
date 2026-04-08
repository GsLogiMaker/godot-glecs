

#include "querylike_builder.h"
#include "godot_cpp/variant/callable.hpp"
#include "godot_cpp/variant/packed_string_array.hpp"
#include "godot_cpp/variant/variant.hpp"
#include "query_builder.h"
#include "query_iteration_context.h"
#include "utils.h"
#include "world.h"

#include <stdlib.h>
#include <flecs.h>

using namespace godot;

#define CHECK_HAS_A_TERM(return_value, err) \
	if (get_term_count() == 0) { \
		ERR(return_value, \
			err, \
			"	Query has no terms" \
		); \
	}

GFQuerylikeBuilder::~GFQuerylikeBuilder() {
}

// **************************************
// *** Exposed ***
// **************************************

int GFQuerylikeBuilder::get_term_count() const {
	return term_count;
}

bool GFQuerylikeBuilder::is_built() const {
	return built;
}

Ref<GFQuerylikeBuilder> GFQuerylikeBuilder::io_default() {
	CHECK_HAS_A_TERM(Ref(this),
		"Failed to set term's access mode to `default`\n"
	);
	query_desc.terms[get_term_count()-1].inout = ecs_inout_kind_t::EcsInOutDefault;
	return Ref(this);
}
Ref<GFQuerylikeBuilder> GFQuerylikeBuilder::io_filter() {
	CHECK_HAS_A_TERM(Ref(this),
		"Failed to set term's access mode to `filter`\n"
	);
	query_desc.terms[get_term_count()-1].inout = ecs_inout_kind_t::EcsInOutFilter;
	return Ref(this);
}
Ref<GFQuerylikeBuilder> GFQuerylikeBuilder::io_in() {
	CHECK_HAS_A_TERM(Ref(this),
		"Failed to set term's access mode to `in`\n"
	);
	query_desc.terms[get_term_count()-1].inout = ecs_inout_kind_t::EcsIn;
	return Ref(this);
}
Ref<GFQuerylikeBuilder> GFQuerylikeBuilder::io_inout() {
	CHECK_HAS_A_TERM(Ref(this),
		"Failed to set term's access mode to `inout`\n"
	);
	query_desc.terms[get_term_count()-1].inout = ecs_inout_kind_t::EcsInOut;
	return Ref(this);
}
Ref<GFQuerylikeBuilder> GFQuerylikeBuilder::io_none() {
	CHECK_HAS_A_TERM(Ref(this),
		"Failed to set term's access mode to `none`\n"
	);
	query_desc.terms[get_term_count()-1].inout = ecs_inout_kind_t::EcsInOutNone;
	return Ref(this);
}
Ref<GFQuerylikeBuilder> GFQuerylikeBuilder::io_out() {
	CHECK_HAS_A_TERM(Ref(this),
		"Failed to set term's access mode to `out`\n"
	);
	query_desc.terms[get_term_count()-1].inout = ecs_inout_kind_t::EcsOut;
	return Ref(this);
}

Ref<GFQuerylikeBuilder> GFQuerylikeBuilder::src(const Variant source) {
	CHECK_HAS_A_TERM(Ref(this),
		"Failed to set source in term\n"
	);

	GFWorld* w = get_world();
	ecs_term_t* term = &query_desc.terms[get_term_count()-1];

	handle_id_or_variable(
		w,
		source,
		&term->first.id,
		&source_names[get_term_count()-1]
	);

	return Ref(this);
}

Ref<GFQuerylikeBuilder> GFQuerylikeBuilder::with(const Variant term_v, const Variant second) {
	return _add_term(term_v, second, ecs_oper_kind_t::EcsAnd);
}
Ref<GFQuerylikeBuilder> GFQuerylikeBuilder::with_maybe(const Variant term_v, const Variant second) {
	return _add_term(term_v, second, ecs_oper_kind_t::EcsOptional);
}
Ref<GFQuerylikeBuilder> GFQuerylikeBuilder::or_with(const Variant term_v, const Variant second) {
	CHECK_HAS_A_TERM(Ref(this),
		"Failed to add `or` term to query\n"
	);
	if (query_desc.terms[get_term_count()-1].oper != ecs_oper_kind_t::EcsAnd) {
		ERR(Ref(this),
			"Could not add term to query\n",
			"OR terms can only be added after AND terms; use \"with\" for previous term instead"
		);
	}
	query_desc.terms[get_term_count()-1].oper = ecs_oper_kind_t::EcsOr;

	return _add_term(term_v, second, ecs_oper_kind_t::EcsAnd);
}
Ref<GFQuerylikeBuilder> GFQuerylikeBuilder::without(const Variant term_v, const Variant second) {
	return _add_term(term_v, second, ecs_oper_kind_t::EcsNot);
}

Ref<GFQuerylikeBuilder> GFQuerylikeBuilder::up(const Variant entity) {
	GFWorld* w = get_world();
	ecs_entity_t entity_id = 0;
	if (!entity) {
		// Passed variant is null, use the default ChildOf tag
		entity_id = ecs_lookup(w->raw(), "flecs.core.ChildOf");
	} else {
		// Passed variant is not null, coerce it to an entity ID
		entity_id = w->coerce_id(entity);
	}

	CHECK_ENTITY_ALIVE(entity_id, w,
		Ref(this),
		"Failed to add `up` traversal to query\n"
	);

	query_desc.terms[get_term_count()-1].src.id = EcsUp;
	query_desc.terms[get_term_count()-1].trav = entity_id;

	return Ref(this);
}
Ref<GFQuerylikeBuilder> GFQuerylikeBuilder::descend(const Variant entity) {
	GFWorld* w = get_world();
	ecs_entity_t entity_id = w->coerce_id(entity);

	CHECK_ENTITY_ALIVE(entity_id, w,
		Ref(this),
		"Failed to add `descend` traversal to query\n"
	);

	query_desc.terms[get_term_count()-1].src.id = EcsDesc;
	query_desc.terms[get_term_count()-1].trav = entity_id;

	return Ref(this);
}
Ref<GFQuerylikeBuilder> GFQuerylikeBuilder::cascade(const Variant entity) {
	GFWorld* w = get_world();
	ecs_entity_t entity_id = w->coerce_id(entity);

	CHECK_ENTITY_ALIVE(entity_id, w,
		Ref(this),
		"Failed to add `cascade` traversal to query\n"
	);

	query_desc.terms[get_term_count()-1].src.id = EcsCascade;
	query_desc.terms[get_term_count()-1].trav = entity_id;

	return Ref(this);
}

Ref<GFQuerylikeBuilder> GFQuerylikeBuilder::from(const Variant entity) {
	GFWorld* w = get_world();
	ecs_entity_t entity_id = w->coerce_id(entity);

	ecs_term_t* term = &query_desc.terms[get_term_count()-1];
	handle_id_or_variable(
		w,
		entity,
		&term->src.id,
		&source_names[get_term_count()-1]
	);

	return Ref(this);
}

// **************************************
// *** Unexposed ***
// **************************************

bool GFQuerylikeBuilder::handle_id_or_variable(
	GFWorld* world,
	Variant entity,
	ecs_entity_t* ref_out,
	String* var_out
) {
	switch (entity.get_type()) {
		case Variant::STRING:
		case Variant::STRING_NAME: {
			String string = entity;
			if (!string.begins_with("$")) {
				break;
			}
			*var_out = string;
			return true;
		}
		default: {}
	}

	*ref_out = world->coerce_id(entity);
	CHECK_ENTITY_ALIVE(*ref_out, world,
		false,
		"Failed to add term in to query\n"
	);
	CHECK_NOT_PAIR(*ref_out, world,
		false,
		"Failed to add term in to query\n"
	);

	return true;
}

Ref<GFQuerylikeBuilder> GFQuerylikeBuilder::_add_term(
	const Variant term_v,
	const Variant second,
	ecs_oper_kind_t oper
) {
	GFWorld* w = get_world();

	const char* oper_name = "";
	switch (oper) {
		case EcsAnd: oper_name = "and"; break;
		case EcsOr: oper_name = "or"; break;
		case EcsNot: oper_name = "not"; break;
		case EcsOptional: oper_name = "optional"; break;
		case EcsAndFrom: oper_name = "and_from"; break;
		case EcsOrFrom: oper_name = "or_from"; break;
		case EcsNotFrom: oper_name = "not_from"; break;
	}

	source_names.resize(get_term_count()+1);
	first_names.resize(get_term_count()+1);
	second_names.resize(get_term_count()+1);

	ecs_term_t* term = &query_desc.terms[get_term_count()];
	term->oper = static_cast<int16_t>(oper);

	handle_id_or_variable(
		w,
		term_v,
		&term->first.id,
		&first_names[get_term_count()]
	);

	if (second.booleanize()) {
		handle_id_or_variable(
			w,
			second,
			&term->second.id,
			&second_names[get_term_count()]
		);
	} else {
		term->id = term->first.id;
		term->first.id = 0;
	}

	term_count += 1;

	return this;
}

// **********************************************
// *** PROTECTED ***
// **********************************************

QueryIterationContext* GFQuerylikeBuilder::setup_ctx(const Callable callable) {
	QueryIterationContext* ctx =  new QueryIterationContext(
		Ref(this),
		callable
	);
	if (query_desc.binding_ctx != nullptr) {
		// Delete old context
		delete static_cast<QueryIterationContext*>(query_desc.binding_ctx);
	}
	query_desc.binding_ctx = ctx;
	query_desc.binding_ctx_free = [](void* ptr) {
		delete static_cast<QueryIterationContext*>(ptr);
	};

	if (callable.get_argument_count() != ctx->comp_ref_args.size()) {
		if (get_class() != GFQueryBuilder::get_class_static()) {
			ERR(ctx,
				"Failed to setup query context\n",
				"	Query expected a callable with ",
				ctx->comp_ref_args.size(),
				" arguments, but got callable with ",
				callable.get_argument_count(),
				" arguments."
			);
		}
	}

	return ctx;
}

void GFQuerylikeBuilder::_bind_methods() {
	REGISTER_QUERYLIKE_SELF_METHODS(GFQuerylikeBuilder);
}

// **********************************************
// *** PRIVATE ***
// **********************************************
