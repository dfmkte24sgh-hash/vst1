#pragma once
#include <juce_core/juce_core.h>
#include <juce_audio_basics/juce_audio_basics.h>
#include <vector>

// Evento de reproducao: tempo em tempos (seminimas) relativos ao inicio da peca.
struct SeqEvent
{
    double qn = 0;
    juce::uint8 type = 0;   // 0 = note off, 1 = control change / program change, 2 = note on  (ordem de envio)
    juce::uint8 inst = 0;   // indice do instrumento (para mute/solo e canal)
    juce::uint8 d1 = 0, d2 = 0;
    bool program = false;   // type 1 com program = true -> program change
};

struct TrackInfo
{
    juce::String id, label, style;
    int defaultChannel = 0;   // 0..15
    int program = 0;
    std::vector<float> notes; // t, l, p, v  (para desenhar e exportar)
};

struct ChordInfo { double t0 = 0, len = 0; juce::String name, scale, label; int philo = 1; };
struct BarInfo   { double t0 = 0, len = 0; juce::String name; double energy = 1; };

struct Sequence
{
    double total = 16.0;
    double bpm = 100.0;
    int tsNum = 4, tsDen = 4;
    std::vector<TrackInfo> tracks;         // so os instrumentos ligados
    std::vector<int> trackInstrument;      // indice global do instrumento de cada trilha
    std::vector<ChordInfo> chords;
    std::vector<BarInfo> bars;
    juce::StringArray planLines;
    std::vector<SeqEvent> events;          // ordenados por tempo

    // constroi a partir do JSON devolvido por B.generate(); instrumentIds = ids na ordem global
    static Sequence fromJson(const juce::var& v, const juce::StringArray& instrumentIds);
};
