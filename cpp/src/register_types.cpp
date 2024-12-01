
#include "component.h"
#include "component_builder.h"
#include "doc_data.gen.h"
#include "entity.h"
#include "gdextension_interface.h"
#include "godot_cpp/classes/engine.hpp"
#include "godot_cpp/classes/resource_loader.hpp"
#include "godot_cpp/variant/utility_functions.hpp"
#include "module.h"
#include "observer_builder.h"
#include "pair.h"
#include "query.h"
#include "query_builder.h"
#include "query_iterator.h"
#include "querylike_builder.h"
#include "register_types.h"
#include "registerable_entity.h"
#include "system_builder.h"
#include "world.h"

using namespace godot;

void initialize_module(ModuleInitializationLevel p_level) {
	switch (p_level) {
        case MODULE_INITIALIZATION_LEVEL_CORE:
        case MODULE_INITIALIZATION_LEVEL_SERVERS:
        case MODULE_INITIALIZATION_LEVEL_MAX:
			break;
        case MODULE_INITIALIZATION_LEVEL_SCENE:
			godot::ClassDB::register_class<GFWorld>();

			godot::ClassDB::register_abstract_class<GFEntity>();
			godot::ClassDB::register_abstract_class<GFPair>();
			godot::ClassDB::register_class<GFRegisterableEntity>();
			godot::ClassDB::register_class<GFComponent>();
			godot::ClassDB::register_class<GFModule>();

			godot::ClassDB::register_abstract_class<GFComponentBuilder>();
			godot::ClassDB::register_abstract_class<GFQuery>();
			godot::ClassDB::register_abstract_class<GFQueryIterator>();

			godot::ClassDB::register_abstract_class<GFQuerylikeBuilder>();
			godot::ClassDB::register_abstract_class<GFObserverBuilder>();
			godot::ClassDB::register_abstract_class<GFQueryBuilder>();
			godot::ClassDB::register_abstract_class<GFSystemBuilder>();
     	   	Engine::get_singleton()->register_singleton(GFWorld::SINGLETON_NAME, memnew(GFWorld));
			break;
        case MODULE_INITIALIZATION_LEVEL_EDITOR:
			GDExtensionsInterfaceEditorHelpLoadXmlFromUtf8CharsAndLen
				editor_help_load_xml_from_utf8_chars_and_len
				= (GDExtensionsInterfaceEditorHelpLoadXmlFromUtf8CharsAndLen)
				internal::gdextension_interface_get_proc_address(
					"editor_help_load_xml_from_utf8_chars_and_len"
				);
			editor_help_load_xml_from_utf8_chars_and_len(_doc_data, _doc_data_size);
			break;
	}
}

void uninitialize_module(ModuleInitializationLevel p_level) {
	switch (p_level) {
        case MODULE_INITIALIZATION_LEVEL_CORE:
        case MODULE_INITIALIZATION_LEVEL_SERVERS:
        case MODULE_INITIALIZATION_LEVEL_EDITOR:
        case MODULE_INITIALIZATION_LEVEL_MAX:
          break;
        case MODULE_INITIALIZATION_LEVEL_SCENE:
     	   Engine::get_singleton()->unregister_singleton(GFWorld::SINGLETON_NAME);
		   break;
	}
}

extern "C" {
// Initialization.
GDExtensionBool GDE_EXPORT library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_module);
	init_obj.register_terminator(uninitialize_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}
