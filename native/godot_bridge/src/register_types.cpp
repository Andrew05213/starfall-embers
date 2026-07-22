#include "starfall/godot_bridge/simulation_host_node.hpp"

#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

namespace {

void initialize_starfall_sim(godot::ModuleInitializationLevel level) {
    if (level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    GDREGISTER_CLASS(starfall::godot_bridge::StarfallSimulationHost);
}

void uninitialize_starfall_sim(godot::ModuleInitializationLevel level) {
    if (level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}

} // namespace

extern "C" GDExtensionBool GDE_EXPORT starfall_sim_library_init(
    GDExtensionInterfaceGetProcAddress get_proc_address,
    GDExtensionClassLibraryPtr library,
    GDExtensionInitialization* initialization
) {
    godot::GDExtensionBinding::InitObject init_object(
        get_proc_address,
        library,
        initialization
    );
    init_object.register_initializer(initialize_starfall_sim);
    init_object.register_terminator(uninitialize_starfall_sim);
    init_object.set_minimum_library_initialization_level(
        godot::MODULE_INITIALIZATION_LEVEL_SCENE
    );
    return init_object.init();
}
