#include "LuaEngine.h"
#include "BinaryData.h"

extern "C" {
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
}

LuaEngine::LuaEngine()
{
    L = luaL_newstate();
    if (L == nullptr) { error = "Nao foi possivel criar o interpretador Lua"; return; }
    luaL_openlibs(L);
    lua_pushboolean(L, 1); lua_setglobal(L, "COMPOSER_TEST");
    lua_newtable(L);       lua_setglobal(L, "reaper");

    auto fail = [this](const char* what) {
        error = juce::String(what) + ": " + juce::String::fromUTF8(lua_tostring(L, -1));
        lua_pop(L, 1);
    };

    if (luaL_loadbuffer(L, BinaryData::engine_lua, (size_t) BinaryData::engine_luaSize, "=engine") != LUA_OK)
        { fail("engine (sintaxe)"); return; }
    if (lua_pcall(L, 0, 1, 0) != LUA_OK) { fail("engine (execucao)"); return; }
    // pilha: M
    if (luaL_loadbuffer(L, BinaryData::bridge_lua, (size_t) BinaryData::bridge_luaSize, "=bridge") != LUA_OK)
    { lua_pop(L, 1); { fail("bridge (sintaxe)"); return; } }
    lua_pushvalue(L, -2);                       // M como argumento "..."
    if (lua_pcall(L, 1, 1, 0) != LUA_OK) { fail("bridge (execucao)"); return; }
    bridgeRef = luaL_ref(L, LUA_REGISTRYINDEX); // guarda B
    lua_pop(L, 1);                              // remove M
}

LuaEngine::~LuaEngine()
{
    if (L != nullptr) lua_close(L);
}

juce::String LuaEngine::call(const char* fn, const std::vector<Arg>& args)
{
    const juce::ScopedLock sl(lock);
    if (L == nullptr || bridgeRef < 0) return {};
    const int top = lua_gettop(L);
    lua_rawgeti(L, LUA_REGISTRYINDEX, bridgeRef);
    lua_getfield(L, -1, fn);
    for (auto& a : args)
    {
        switch (a.kind)
        {
            case Arg::Str:  lua_pushstring(L, a.s.toRawUTF8()); break;
            case Arg::Int:  lua_pushinteger(L, (lua_Integer) a.i); break;
            case Arg::Num:  lua_pushnumber(L, a.d); break;
            case Arg::Bool: lua_pushboolean(L, a.b ? 1 : 0); break;
        }
    }
    juce::String out;
    if (lua_pcall(L, (int) args.size(), 1, 0) != LUA_OK)
    {
        error = juce::String(fn) + ": " + juce::String::fromUTF8(lua_tostring(L, -1));
        DBG(error);
    }
    else
    {
        size_t len = 0;
        const char* s = lua_tolstring(L, -1, &len);
        if (s != nullptr) out = juce::String::fromUTF8(s, (int) len);
    }
    lua_settop(L, top);
    return out;
}

juce::var LuaEngine::callJson(const char* fn, const std::vector<Arg>& args)
{
    auto txt = call(fn, args);
    if (txt.isEmpty()) return {};
    return juce::JSON::parse(txt);
}

void LuaEngine::set(const juce::String& scope, const juce::String& key, const juce::var& value, bool isInteger)
{
    if (value.isBool())         call("set", { scope, key, (bool) value });
    else if (value.isString())  call("set", { scope, key, value.toString() });
    else if (isInteger)         call("set", { scope, key, (juce::int64) value });
    else                        call("set", { scope, key, (double) value });
}

juce::String LuaEngine::save() { return call("save"); }
bool LuaEngine::load(const juce::String& s) { return call("load", { s }) == "true"; }
