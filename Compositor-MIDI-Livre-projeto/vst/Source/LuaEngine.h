#pragma once
#include <juce_core/juce_core.h>
#include <vector>

struct lua_State;

// Envolve o motor de composicao (Lua 5.4 embutido). Thread-safe: toda chamada usa um lock.
class LuaEngine
{
public:
    struct Arg
    {
        enum Kind { Str, Int, Num, Bool } kind;
        juce::String s; juce::int64 i = 0; double d = 0; bool b = false;
        Arg(const juce::String& v) : kind(Str), s(v) {}
        Arg(const char* v) : kind(Str), s(v) {}
        Arg(int v) : kind(Int), i(v) {}
        Arg(juce::int64 v) : kind(Int), i(v) {}
        Arg(double v) : kind(Num), d(v) {}
        Arg(bool v) : kind(Bool), b(v) {}
    };

    LuaEngine();
    ~LuaEngine();

    bool isOk() const { return L != nullptr && error.isEmpty(); }
    juce::String getError() const { return error; }

    // chama B.fn(args...) e devolve o resultado como texto (JSON ou texto simples)
    juce::String call(const char* fn, const std::vector<Arg>& args = {});
    juce::var callJson(const char* fn, const std::vector<Arg>& args = {});

    // atalhos
    void set(const juce::String& scope, const juce::String& key, const juce::var& value, bool isInteger);
    juce::String save();
    bool load(const juce::String& s);

private:
    lua_State* L = nullptr;
    int bridgeRef = -1;
    juce::String error;
    juce::CriticalSection lock;
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(LuaEngine)
};
