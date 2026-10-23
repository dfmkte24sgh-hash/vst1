cmake_minimum_required(VERSION 3.22)
set(CMAKE_OSX_DEPLOYMENT_TARGET "10.13" CACHE STRING "")
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "")
project(CompositorMIDI VERSION 1.0.0 LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 99)

include(FetchContent)
FetchContent_Declare(JUCE GIT_REPOSITORY https://github.com/juce-framework/JUCE.git GIT_TAG 8.0.6 GIT_SHALLOW TRUE)
FetchContent_Declare(lua GIT_REPOSITORY https://github.com/lua/lua.git GIT_TAG v5.4.7 GIT_SHALLOW TRUE)
FetchContent_MakeAvailable(JUCE lua)

# ---- Lua 5.4 embutido (motor de composicao) --------------------------------
file(GLOB LUA_SRC "${lua_SOURCE_DIR}/*.c")
list(FILTER LUA_SRC EXCLUDE REGEX "/(lua|luac|onelua|ltests|testes)\\.c$")
add_library(lua_embedded STATIC ${LUA_SRC})
target_include_directories(lua_embedded PUBLIC ${lua_SOURCE_DIR})
set_target_properties(lua_embedded PROPERTIES POSITION_INDEPENDENT_CODE ON)

# ---- scripts do motor viram dados binarios dentro do plugin -----------------
juce_add_binary_data(CompositorData SOURCES engine/engine.lua engine/bridge.lua)
set_target_properties(CompositorData PROPERTIES POSITION_INDEPENDENT_CODE ON)

set(COMPOSITOR_SOURCES
  Source/LuaEngine.cpp Source/Sequence.cpp Source/PluginProcessor.cpp
  Source/PluginEditor.cpp Source/LookAndFeel.cpp)

set(COMPOSITOR_DEFS
  JUCE_WEB_BROWSER=0 JUCE_USE_CURL=0 JUCE_VST3_CAN_REPLACE_VST2=0
  JUCE_DISPLAY_SPLASH_SCREEN=0 JUCE_REPORT_APP_USAGE=0)
# Linux sem bibliotecas opcionais (so para compilar em maquinas minimas)
option(COMPOSITOR_MINIMAL_LINUX "Desliga ALSA/JACK/Xrandr etc." OFF)
if(COMPOSITOR_MINIMAL_LINUX)
  list(APPEND COMPOSITOR_DEFS JUCE_ALSA=0 JUCE_JACK=0 JUCE_USE_XRANDR=0 JUCE_USE_XINERAMA=0
       JUCE_USE_XCURSOR=0 JUCE_USE_XSHM=0 JUCE_USE_XRENDER=0)
endif()

juce_add_plugin(CompositorMIDI
  COMPANY_NAME "Compositor"
  PLUGIN_MANUFACTURER_CODE Cmpl
  PLUGIN_CODE Cmlv
  FORMATS VST3
  PRODUCT_NAME "Compositor MIDI Livre"
  IS_SYNTH TRUE
  NEEDS_MIDI_INPUT TRUE
  NEEDS_MIDI_OUTPUT TRUE
  IS_MIDI_EFFECT FALSE
  EDITOR_WANTS_KEYBOARD_FOCUS TRUE
  COPY_PLUGIN_AFTER_BUILD FALSE
  VST3_CATEGORIES Instrument)
target_sources(CompositorMIDI PRIVATE ${COMPOSITOR_SOURCES})
target_compile_definitions(CompositorMIDI PUBLIC ${COMPOSITOR_DEFS})
target_link_libraries(CompositorMIDI
  PRIVATE CompositorData lua_embedded
          juce::juce_audio_utils juce::juce_gui_extra
  PUBLIC  juce::juce_recommended_config_flags juce::juce_recommended_warning_flags)

# ---- teste automatico do processador (sem host) -----------------------------
juce_add_console_app(ProcessorTest PRODUCT_NAME "ProcessorTest")
target_sources(ProcessorTest PRIVATE Source/ProcessorTest.cpp ${COMPOSITOR_SOURCES})
target_compile_definitions(ProcessorTest PUBLIC ${COMPOSITOR_DEFS} JUCE_USE_CUSTOM_PLUGIN_STANDALONE_APP=0
  JucePlugin_Name="Compositor MIDI Livre" JucePlugin_Manufacturer="Compositor"
  JucePlugin_ProducesMidiOutput=1 JucePlugin_WantsMidiInput=1 JucePlugin_IsSynth=1 JucePlugin_IsMidiEffect=0
  JucePlugin_PreferredChannelConfigurations={2,2} JucePlugin_EditorRequiresKeyboardFocus=1)
target_link_libraries(ProcessorTest PRIVATE CompositorData lua_embedded
  juce::juce_audio_utils juce::juce_gui_extra juce::juce_recommended_config_flags)
