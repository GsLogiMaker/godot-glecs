
#ifndef SYSTEM_BUILDER_H
#define SYSTEM_BUILDER_H

#include <querylike_builder.h>

#include <flecs.h>
#include "godot_cpp/variant/callable.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

	// Predefine instead of include to avoid cyclic dependencies
	class GFWorld;

	class GFSystemBuilder : public GFQuerylikeBuilder {
		GDCLASS(GFSystemBuilder, GFQuerylikeBuilder)

	public:
		GFSystemBuilder(GFWorld* world):
			GFQuerylikeBuilder(world),
			callable(Callable())
		{}
		GFSystemBuilder():
			GFSystemBuilder(nullptr)
		{}
		~GFSystemBuilder();

		// **************************************
		// *** Exposed ***
		// **************************************

		OVERRIDE_QUERYLIKE_SELF_METHODS(GFSystemBuilder);

		static Ref<GFSystemBuilder> new_in_world(GFWorld*);
		Ref<GFEntity> for_each(const Callable callable);

		// **************************************
		// *** Unexposed ***
		// **************************************

	protected:
		static void _bind_methods();

	private:
		Callable callable;
	};

}

#endif
