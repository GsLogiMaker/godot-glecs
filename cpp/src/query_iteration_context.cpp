

#include "query_iteration_context.h"
#include "godot_cpp/variant/utility_functions.hpp"
#include "querylike_builder.h"
#include "component.h"
#include "godot_cpp/variant/callable.hpp"
#include "godot_cpp/variant/variant.hpp"
#include "tag.h"
#include "world.h"

#include <stdlib.h>
#include <flecs.h>

using namespace godot;

ecs_entity_t deref_entity(const ecs_iter_t* it, const ecs_term_ref_t* ref) {
	if (ref->name == nullptr) {
		return 0;
	}
	int var_index = ecs_query_find_var(it->query, ref->name);
	if (!ecs_query_var_is_entity(it->query, var_index)) {
		return 0;
	}
	if (it->variables->entity == 0) {
		return 0;
	}
	return it->variables->entity;
}

ecs_entity_t deref_component(
	const ecs_iter_t* it,
	const ecs_term_ref_t* first_ref,
	const ecs_term_ref_t* second_ref,
	ecs_entity_t arg_index
) {
	ecs_entity_t first = deref_entity(it, first_ref);
	ecs_entity_t second = deref_entity(it, first_ref);

	if (second) {
		return ecs_pair(first, second);
	}
	if (first) {
		return first;
	}

	return it->ids[arg_index];
}

ecs_entity_t deref_source(const ecs_iter_t* it, const ecs_term_ref_t* source_ref, int arg_index, int entity_index) {
	ecs_entity_t source = deref_entity(it, source_ref);
	source = source ? source : ecs_field_src(it, arg_index);
	source = source ? source : it->entities[entity_index];
	return source;
}

// **********************************************
// *** PUBLIC ***
// **********************************************

ecs_entity_t get_compmonent_of_term(const ecs_term_t* term) {
	if (term->id == 0) {
		return ecs_pair(term->first.id, term->second.id);
	}
	return term->id;
}

Ref<GFEntity> QueryIterationContext::instance_from(ecs_entity_t id, GFWorld* world) {
	return GFComponent::from_id_no_source(
		id,
		world
	);
}

QueryIterationContext::QueryIterationContext(
	const Ref<GFQuerylikeBuilder> query_b,
	const Callable callable_
) {
	callable = callable_;
	world = query_b->get_world();

	for (int i=0; i != query_b->get_term_count(); i++) {
		auto terms = query_b->query_desc.terms;
		switch (terms[i].oper) {
			case ecs_oper_kind_t::EcsAnd:
			case ecs_oper_kind_t::EcsOptional:
				comp_ref_per_term.append(
					instance_from(
						get_compmonent_of_term(&terms[i]),
						get_world()
					)
				);
				comp_ref_args.append(Variant());
				comp_ref_term_ids.append(i);
				break;
			case ecs_oper_kind_t::EcsOr:
				comp_ref_per_term.append(
					instance_from(
						get_compmonent_of_term(&terms[i]),
						get_world()
					)
				);
				// OR terms must always be followed by another term, so
				// there's guaranteed to be another term after this one
				if (terms[i+1].oper == ecs_oper_kind_t::EcsNot) {
					// NOT terms don't add args for term, so add
					// it here instead
					comp_ref_args.append(Variant());
					comp_ref_term_ids.append(i);
				}
				break;
			case ecs_oper_kind_t::EcsNot:
				comp_ref_per_term.append(Variant());
				// TODO: If previous term was OR, then an argument will never
				//		be added for the OR chain. This needs addressing.
				break;
		}
	}
}
QueryIterationContext::~QueryIterationContext() {}

Callable QueryIterationContext::get_callable() const {
	return callable;
}
GFWorld* QueryIterationContext::get_world() const {
	return world;
}

void QueryIterationContext::update_component_entities(ecs_iter_t* it, int entity_index) const {
	for (int comp_i=0; comp_i != comp_ref_args.size(); comp_i++) {
		int term_i = comp_ref_term_ids[comp_i];
		const ecs_term_t* term = &it->query->terms[term_i];

		Ref<GFEntity> added_entity = comp_ref_args[comp_i];
		if (added_entity == nullptr) {
			// Object is null, skip
			continue;
		}


		if (!added_entity->is_class(GFComponent::get_class_static())) {
			// Added ID is not a component, skip
			continue;
		}

		ecs_entity_t source = deref_source(it, &term->src, comp_i, entity_index);;

		// Set source of added ID
		Ref<GFComponent> comp = added_entity;
		comp->set_source_id(source);
	}
}

void QueryIterationContext::update_component_terms(ecs_iter_t* it) {
	const ecs_term_t* terms = it->query->terms;

	int arg_index = 0;
	for (int term_index=0; term_index != it->query->term_count; term_index++) {
		const ecs_term_t* term = &terms[term_index];
		ecs_entity_t source_id = deref_source(it, &term->src, arg_index, 0);
		Ref<GFEntity> term_comp_ref = comp_ref_per_term[term_index];
		Ref<GFEntity> setting_arg_ref = nullptr;

		switch (term->oper) {
			case ecs_oper_kind_t::EcsAnd:
				setting_arg_ref = term_comp_ref;
				comp_ref_term_ids[arg_index] = term_index;
				break;

			case ecs_oper_kind_t::EcsOptional:
				if (ecs_has_id(world->raw(), source_id, term_comp_ref->get_id())) {
					setting_arg_ref = term_comp_ref;
				} else {
					setting_arg_ref = Variant();
				}
				comp_ref_term_ids[arg_index] = term_index;
				break;

			case ecs_oper_kind_t::EcsOr:
				if (ecs_has_id(get_world()->raw(), source_id, term_comp_ref->get_id())) {
					// Term matches OR chain, set arg to term
					setting_arg_ref = term_comp_ref;
					comp_ref_term_ids[arg_index] = term_index;
					while (terms[term_index].oper == ecs_oper_kind_t::EcsOr) {
						// Skip terms till OR chain is exited.
						// There is guaranteed to be another none OR term at the
						// end of the chain, so we don't need to check for the end of
						// the terms list.
						term_index++;
					}
					// Final term in OR chain is skipped by for loop.
				} else {
					// Term does not match arg, set arg to null until
					// matching term is found in OR chain.
					// Arg may remain null if the final term is
					// optional or negative.
					setting_arg_ref = Variant();
					comp_ref_term_ids[arg_index] = term_index;
				}
				break;

			case ecs_oper_kind_t::EcsNot:
				// NOT terms don't add arguments -- do nothing
				break;
		}

		if (setting_arg_ref != nullptr) {
			ecs_entity_t term_comp_id = deref_component(it, &terms->first, &terms->second, arg_index);
			setting_arg_ref->set_id(term_comp_id);

			comp_ref_args[arg_index] = setting_arg_ref;
			arg_index += 1;
		} else {
			comp_ref_args[arg_index] = Variant();
			if (term->oper == ecs_oper_kind_t::EcsOptional) {
				arg_index += 1;
			}
		}
	}
}

void QueryIterationContext::iterator_callback(ecs_iter_t* it) {
	QueryIterationContext* ctx = static_cast<QueryIterationContext*>(it->query->binding_ctx);
	ctx->update_component_terms(it);
	for (int i=0; i != it->count; i++) {
		ctx->update_component_entities(it, i);
		ctx->get_callable().callv(ctx->comp_ref_args);
	}
}
