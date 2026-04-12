

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

// **********************************************
// *** PUBLIC ***
// **********************************************

ecs_entity_t get_compmonent_of_term(const ecs_term_t* term) {
	if (term->id == 0) {
		return ecs_pair(term->first.id, term->second.id);
	}
	return term->id;
}

Ref<GFEntity> instance_from(ecs_entity_t id, GFWorld* world) {
	ecs_entity_t main_id = world->get_main_id(id); // Get main ID, if pair, for checking if ID is component
	if (ecs_has(world->raw(), main_id, EcsComponent)) {
		return GFComponent::from_id_no_source(
			id,
			world
		);
	} else {
		return GFTag::from_id(id, world);
	}
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

		Ref<GFEntity> added_entity = comp_ref_args[comp_i];
		if (added_entity == nullptr) {
			// Object is null, skip
			continue;
		}


		if (!added_entity->is_class(GFComponent::get_class_static())) {
			// Added ID is not a component, skip
			continue;
		}

		ecs_entity_t source = 0;
		if (it->entities) {
			source = ecs_field_src(it, term_i);
		}
		if (!get_world()->is_id_alive(source)) {
			source = it->entities[entity_index];
		}

		// Set source of added ID
		Ref<GFComponent> comp = added_entity;
		comp->set_source_id(source);
	}
}

void QueryIterationContext::update_component_terms(ecs_iter_t* it) {
	const ecs_term_t* terms = it->query->terms;

	int i_arg = 0;
	for (int term_i=0; term_i != it->query->term_count; term_i++) {
		ecs_entity_t entity_id = ecs_field_src(it, term_i);
		if (entity_id == 0) {
			entity_id = it->entities[0];
		}

		const ecs_term_t* term = &terms[term_i];
		Ref<GFEntity> comp_ref = comp_ref_per_term[term_i];
		ecs_entity_t comp_ref_id = it->ids[i_arg];
		comp_ref->set_id(comp_ref_id);

		switch (term->oper) {
			case ecs_oper_kind_t::EcsAnd:
				comp_ref_args[i_arg] = comp_ref;
				comp_ref_term_ids[i_arg] = term_i;
				i_arg += 1;
				break;

			case ecs_oper_kind_t::EcsOptional:
				if (!ecs_has_id(world->raw(), entity_id, term->id)) {
					// Term is null due to being optional
					comp_ref_args[i_arg] = Variant();
					comp_ref_term_ids[i_arg] = term_i;
				} else {
					comp_ref_args[i_arg] = comp_ref;
					comp_ref_term_ids[i_arg] = term_i;
				}
				i_arg += 1;
				break;

			case ecs_oper_kind_t::EcsOr:
				if (term->id == it->ids[i_arg]) {
					// Term matches OR chain, set arg to term
					comp_ref_args[i_arg] = comp_ref;
					comp_ref_term_ids[i_arg] = term_i;
					i_arg += 1;
					// Skip terms till OR chain is exited.
					// There is guaranteed to be another none OR term at the
					// end of the chain, so we don't need to check for the end of
					// the terms list.
					while (terms[term_i].oper == ecs_oper_kind_t::EcsOr) {
						term_i++;
					}
					// Final term in OR chain is skipped by for loop.
				} else {
					// Term does not match arg, set arg to null until
					// matching term is found in OR chain.
					// Arg may remain null if the final term is
					// optional or negative.
					comp_ref_args[i_arg] = Variant();
					comp_ref_term_ids[i_arg] = term_i;
				}

				break;

			case ecs_oper_kind_t::EcsNot:
				// NOT terms don't add arguments, do nothing
				break;
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
