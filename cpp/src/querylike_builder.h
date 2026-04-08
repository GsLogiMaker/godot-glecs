
#ifndef QUERYLike_BUILDER_H
#define QUERYLike_BUILDER_H

#include "entity_builder.h"
#include "godot_cpp/variant/callable.hpp"
#include "godot_cpp/variant/packed_int32_array.hpp"
#include "godot_cpp/variant/packed_string_array.hpp"
#include "godot_cpp/variant/variant.hpp"
#include <query.h>

#include <flecs.h>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>

#define OVERRIDE_QUERYLIKE_SELF_METHODS(Self)	\
	OVERRIDE_ENTITY_BUILDER_SELF_METHODS(Self)	\
	Ref<Self> with(const Variant v0, const Variant v1)	{ return GFQuerylikeBuilder::with(v0, v1); }	\
	Ref<Self> with_maybe(const Variant v0, const Variant v1)	{ return GFQuerylikeBuilder::with_maybe(v0, v1); }	\
	Ref<Self> without(const Variant v0, const Variant v1)	{ return GFQuerylikeBuilder::without(v0, v1); }	\
	Ref<Self> or_with(const Variant v0, const Variant v1)	{ return GFQuerylikeBuilder::or_with(v0, v1); }	\
	Ref<Self> up(const Variant v0)	{ return GFQuerylikeBuilder::up(v0); }	\
	Ref<Self> descend(const Variant v0)	{ return GFQuerylikeBuilder::descend(v0); }	\
	Ref<Self> cascade(const Variant v0)	{ return GFQuerylikeBuilder::cascade(v0); }	\
	Ref<Self> io_default()	{ return GFQuerylikeBuilder::io_default(); }	\
	Ref<Self> io_filter()	{ return GFQuerylikeBuilder::io_filter(); }	\
	Ref<Self> io_in()	{ return GFQuerylikeBuilder::io_in(); }	\
	Ref<Self> io_inout()	{ return GFQuerylikeBuilder::io_inout(); }	\
	Ref<Self> io_none()	{ return GFQuerylikeBuilder::io_none(); }	\
	Ref<Self> io_out()	{ return GFQuerylikeBuilder::io_out(); }	\
	Ref<Self> src(const Variant v0)	{ return GFQuerylikeBuilder::src(v0); }	\
	Ref<Self> from(const Variant v0)	{ return GFQuerylikeBuilder::from(v0); }	\
;

#define REGISTER_QUERYLIKE_SELF_METHODS(Self)	\
	REGISTER_ENTITY_BUILDER_SELF_METHODS(Self)	\
	godot::ClassDB::bind_method(D_METHOD("with", "term", "second"), &Self::with, nullptr);	\
	godot::ClassDB::bind_method(D_METHOD("with_maybe", "term", "second"), &Self::with_maybe, nullptr);	\
	godot::ClassDB::bind_method(D_METHOD("without", "term", "second"), &Self::without, nullptr);	\
	godot::ClassDB::bind_method(D_METHOD("or_with", "term", "second"), &Self::or_with, nullptr);	\
	godot::ClassDB::bind_method(D_METHOD("up", "traversal"), &Self::up, 0);	\
	godot::ClassDB::bind_method(D_METHOD("descend", "traversal"), &Self::descend, 0);	\
	godot::ClassDB::bind_method(D_METHOD("cascade", "traversal"), &Self::cascade, 0);	\
	godot::ClassDB::bind_method(D_METHOD("io_default"), &Self::io_default);	\
	godot::ClassDB::bind_method(D_METHOD("io_filter"), &Self::io_filter);	\
	godot::ClassDB::bind_method(D_METHOD("io_in"), &Self::io_in);	\
	godot::ClassDB::bind_method(D_METHOD("io_inout"), &Self::io_inout);	\
	godot::ClassDB::bind_method(D_METHOD("io_none"), &Self::io_none);	\
	godot::ClassDB::bind_method(D_METHOD("io_out"), &Self::io_out);	\
	godot::ClassDB::bind_method(D_METHOD("src", "source"), &Self::src);	\
	godot::ClassDB::bind_method(D_METHOD("from", "entity"), &Self::from);	\
;

#define QUERYLIKE_BUILD_START	\
	CharString* __char_strings = new CharString[get_term_count()*3];	\
	for (int i = 0; i != get_term_count(); i++) {	\
		ecs_term_t *term = &query_desc.terms[i];	\
		CharString source_var_char = source_names[i].utf8();	\
		CharString first_var_char = first_names[i].utf8();	\
		CharString second_var_char = second_names[i].utf8();	\
		__char_strings[i+get_term_count()*0] = source_var_char;	\
		__char_strings[i+get_term_count()*1] = first_var_char;	\
		__char_strings[i+get_term_count()*2] = second_var_char;	\
		term->src.name = (source_var_char.length() == 0) ? nullptr : source_var_char.ptr();	\
		term->first.name = (first_var_char.length() == 0) ? nullptr : first_var_char.ptr();	\
		term->second.name = (second_var_char.length() == 0) ? nullptr : second_var_char.ptr();	\
	}	\
;

#define QUERYLIKE_BUILD_END	\
	for (int i=0; i != get_term_count(); i++) {	\
		ecs_term_t* term = &query_desc.terms[i];	\
		term->src.name = nullptr;	\
		term->first.name = nullptr;	\
		term->second.name = nullptr;	\
	}	\
	delete[] __char_strings;	\
;

namespace godot {

	// Predefine instead of include to avoid cyclic dependencies
	class GFWorld;
	class QueryIterationContext;

	class GFQuerylikeBuilder : public GFEntityBuilder {
		GDCLASS(GFQuerylikeBuilder, GFEntityBuilder)

		friend QueryIterationContext;

	public:
		GFQuerylikeBuilder():
			GFQuerylikeBuilder(nullptr)
		{}
		GFQuerylikeBuilder(GFWorld* world):
			GFEntityBuilder(world),
			query_desc( {0} ),
			built(false),
			term_count(0)
		{}
		~GFQuerylikeBuilder();

		OVERRIDE_ENTITY_BUILDER_SELF_METHODS(GFQuerylikeBuilder);

		// **************************************
		// *** Exposed ***
		// **************************************

		int get_term_count() const;
		bool is_built() const;
		Ref<GFQuerylikeBuilder> io_default();
		Ref<GFQuerylikeBuilder> io_filter();
		Ref<GFQuerylikeBuilder> io_in();
		Ref<GFQuerylikeBuilder> io_inout();
		Ref<GFQuerylikeBuilder> io_none();
		Ref<GFQuerylikeBuilder> io_out();
		Ref<GFQuerylikeBuilder> src(const Variant source);
		Ref<GFQuerylikeBuilder> with(const Variant, const Variant);
		Ref<GFQuerylikeBuilder> with_maybe(const Variant, const Variant);
		Ref<GFQuerylikeBuilder> without(const Variant, const Variant);
		Ref<GFQuerylikeBuilder> or_with(const Variant, const Variant);
		Ref<GFQuerylikeBuilder> up(const Variant component);
		Ref<GFQuerylikeBuilder> descend(const Variant component);
		Ref<GFQuerylikeBuilder> cascade(const Variant component);
		Ref<GFQuerylikeBuilder> from(const Variant component);

		// **************************************
		// *** Unexposed ***
		// **************************************

		bool handle_id_or_variable(
			GFWorld* world,
			Variant entity,
			ecs_entity_t* ref_out,
			String* var_out
		);
		Ref<GFQuerylikeBuilder> _add_term(
			const Variant term,
			const Variant second,
			ecs_oper_kind_t oper
		);

	protected:
		/// The Flecs description of the building query.
		ecs_query_desc_t query_desc{0};
		/// Is true if this builder has alio_iny been built
		bool built{false};
		PackedStringArray source_names = PackedStringArray();
		PackedStringArray first_names = PackedStringArray();
		PackedStringArray second_names = PackedStringArray();

		QueryIterationContext* setup_ctx(const Callable callable);
		static void _bind_methods();

	private:
		/// The number of terms added to the query so far.
		int term_count{0};

	};
}

#endif
