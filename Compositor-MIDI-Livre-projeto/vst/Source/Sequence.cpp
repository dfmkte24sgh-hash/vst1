#include "Sequence.h"
#include <algorithm>

Sequence Sequence::fromJson(const juce::var& v, const juce::StringArray& ids)
{
    Sequence s;
    if (! v.isObject()) return s;
    s.total = juce::jmax(0.25, (double) v.getProperty("total", 16.0));
    s.bpm   = (double) v.getProperty("bpm", 100.0);
    s.tsNum = (int) v.getProperty("tsNum", 4);
    s.tsDen = (int) v.getProperty("tsDen", 4);

    if (auto* arr = v.getProperty("tracks", {}).getArray())
    {
        for (auto& tv : *arr)
        {
            TrackInfo t;
            t.id = tv.getProperty("id", "").toString();
            t.label = tv.getProperty("label", "").toString();
            t.style = tv.getProperty("style", "").toString();
            t.defaultChannel = juce::jlimit(0, 15, (int) tv.getProperty("ch", 0));
            t.program = juce::jlimit(0, 127, (int) tv.getProperty("prog", 0));
            const int inst = juce::jmax(0, ids.indexOf(t.id));
            if (auto* na = tv.getProperty("notes", {}).getArray())
                for (auto& x : *na) t.notes.push_back((float) (double) x);

            const double endCap = s.total - 1.0e-4;
            for (size_t i = 0; i + 3 < t.notes.size(); i += 4)
            {
                const double tn = t.notes[i], len = t.notes[i + 1];
                const int p = juce::jlimit(0, 127, (int) t.notes[i + 2]);
                const int vel = juce::jlimit(1, 127, (int) t.notes[i + 3]);
                const double on = juce::jlimit(0.0, endCap - 1.0e-3, tn);
                const double off = juce::jlimit(on + 1.0e-3, endCap, on + juce::jmax(0.01, len));
                SeqEvent a; a.qn = on;  a.type = 2; a.inst = (juce::uint8) inst; a.d1 = (juce::uint8) p; a.d2 = (juce::uint8) vel;
                SeqEvent b; b.qn = off; b.type = 0; b.inst = (juce::uint8) inst; b.d1 = (juce::uint8) p;
                s.events.push_back(a); s.events.push_back(b);
            }
            if (auto* ca = tv.getProperty("cc", {}).getArray())
            {
                for (size_t i = 0; i + 2 < (size_t) ca->size(); i += 3)
                {
                    SeqEvent c; c.qn = juce::jlimit(0.0, endCap, (double) (*ca)[(int) i]); c.type = 1; c.inst = (juce::uint8) inst;
                    c.d1 = (juce::uint8) juce::jlimit(0, 127, (int) (*ca)[(int) i + 1]);
                    c.d2 = (juce::uint8) juce::jlimit(0, 127, (int) (*ca)[(int) i + 2]);
                    s.events.push_back(c);
                }
            }
            s.tracks.push_back(std::move(t));
            s.trackInstrument.push_back(inst);
        }
    }
    if (auto* ca = v.getProperty("chords", {}).getArray())
        for (auto& c : *ca)
        {
            ChordInfo ci;
            ci.t0 = c.getProperty("t0", 0.0); ci.len = c.getProperty("len", 1.0);
            ci.name = c.getProperty("name", "").toString(); ci.scale = c.getProperty("scale", "").toString();
            ci.label = c.getProperty("label", "").toString(); ci.philo = (int) c.getProperty("philo", 1);
            s.chords.push_back(ci);
        }
    if (auto* ba = v.getProperty("bars", {}).getArray())
        for (auto& b : *ba)
        {
            BarInfo bi;
            bi.t0 = b.getProperty("t0", 0.0); bi.len = b.getProperty("len", 4.0);
            bi.name = b.getProperty("name", "").toString(); bi.energy = b.getProperty("energy", 1.0);
            s.bars.push_back(bi);
        }
    if (auto* pa = v.getProperty("plan", {}).getArray())
        for (auto& l : *pa) s.planLines.add(l.toString());

    std::stable_sort(s.events.begin(), s.events.end(), [](const SeqEvent& a, const SeqEvent& b) {
        if (a.qn != b.qn) return a.qn < b.qn;
        return a.type < b.type; // offs, depois CCs, depois note ons
    });
    return s;
}
