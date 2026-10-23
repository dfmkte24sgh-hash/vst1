# Compositor MIDI Livre (VST3)

Plugin VST3 que gera linhas MIDI para 12 instrumentos (bateria, baixo, teclas, cordas, arpejo, violão, lead, contracanto, metais, sopros, percussão melódica, textura). Harmonia híbrida (tonal / modal / experimental), compassos livres, Tap de BPM e ritmo, edição por parâmetros e por texto. Só gera MIDI: o som vem do instrumento (VSTi) que você colocar depois dele.

## Como obter o plugin (Windows / macOS / Linux)
1. Crie um repositório no GitHub e envie esta pasta inteira (`git init`, `git add .`, `git commit`, `git push`).
2. Abra a aba **Actions**. O fluxo "Compilar VST3" roda sozinho (leva ~10-20 min na primeira vez).
3. Ao terminar, baixe o artefato do seu sistema (Windows, macOS ou Linux) e extraia o zip.
4. Siga o `INSTALAR.txt` que vem dentro do zip.

Para gerar uma release com os zips anexados, crie uma tag: `git tag v1.0.0 && git push --tags`.

## Compilar localmente
Requer CMake 3.22+ e um compilador C++17 (Visual Studio 2022, Xcode ou GCC/Clang). JUCE e Lua são baixados automaticamente.

    cmake -B build -DCMAKE_BUILD_TYPE=Release
    cmake --build build --config Release --target CompositorMIDI_VST3

O plugin sai em `build/CompositorMIDI_artefacts/Release/VST3/`.
No Linux instale antes: `libasound2-dev libx11-dev libxrandr-dev libxinerama-dev libxcursor-dev libfreetype-dev libfontconfig1-dev libgl1-mesa-dev`.

## Uso no REAPER
1. Nova faixa > FX > **VST3i: Compositor MIDI Livre**.
2. Adicione logo depois o seu instrumento (VSTi) na mesma cadeia. O MIDI gerado passa para ele.
3. Dê play: o plugin acompanha o transporte e repete em loop. Sem transporte, use o modo de pré-escuta (aba OPÇÕES).
4. Cada instrumento sai em um canal MIDI próprio (bateria no 10). Para sintetizadores separados, crie faixas com *send* de MIDI filtrando o canal.
5. Para ter o MIDI como itens editáveis, arraste o `.mid` (canto "ARRASTE O MIDI", ou o botão MID de cada pista) para o arranjo.

## Abas
- **GERAL**: tonalidade, compasso, andamento, tamanho, energia, semente.
- **HARMONIA**: filosofia (tonal / modal / experimental / híbrida), escalas, cromatismo, tensão.
- **INSTRUMENTOS**: liga/desliga, estilo, densidade e registro de cada um.
- **TAP E INTENÇÃO**: toque no pad para detectar BPM e ritmo; escreva em texto o que quer ("mais sombrio, lento, jazz, 6/8").
- **OPÇÕES**: repetição, deslocamento, Program Change, canais.

## Motor
O motor de composição é Lua 5.4 embutido (`engine/parts/*.lua`). Para alterar, edite as partes e rode `tools/build_engine.sh`.

## Estado de teste
Testado de forma automática no Linux (testes do processador, exportação MIDI, estado, renderização da interface). Não testado dentro de um REAPER real; se algo falhar, anote a versão do REAPER e a mensagem de erro.
