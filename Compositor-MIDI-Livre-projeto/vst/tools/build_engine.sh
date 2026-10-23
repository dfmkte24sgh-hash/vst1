#!/bin/bash
# Regenera engine/engine.lua a partir de engine/parts/*.lua (motor de composicao, sem a interface do REAPER).
set -e
cd "$(dirname "$0")/.."
cat $(ls engine/parts/*.lua | sort) > engine/engine.lua
echo "engine.lua: $(wc -l < engine/engine.lua) linhas"
