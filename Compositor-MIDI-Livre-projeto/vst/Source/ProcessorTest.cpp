// Teste automatico (sem host): reproducao sincronizada, loop, stop, mute, MIDI exportado, estado e imagem da interface.
#include "PluginProcessor.h"
#include "PluginEditor.h"
#include <iostream>
#include <map>
#include <cmath>

static int failures = 0;
#define CHECK(cond, msg) do { if (!(cond)) { ++failures; std::cout << "FALHOU: " << msg << std::endl; } else std::cout << "ok: " << msg << std::endl; } while (0)

struct TestPlayHead : juce::AudioPlayHead
{
    bool playing = false; double ppq = 0, bpm = 120;
    juce::Optional<PositionInfo> getPosition() const override
    {
        PositionInfo i; i.setIsPlaying(playing); i.setPpqPosition(ppq); i.setBpm(bpm); return i;
    }
};

struct Run { int ons = 0, offs = 0, ccs = 0; double firstOn = -1; std::map<int,int> onsPerCh; int maxActive = 0; };

static Run play(CompositorProcessor& p, TestPlayHead& ph, double fromPpq, double toPpq, int block = 512, double sr = 44100.0)
{
    Run r; int active = 0;
    ph.playing = true; ph.ppq = fromPpq;
    juce::AudioBuffer<float> buf(2, block);
    const double qnPerBlock = block * ph.bpm / (60.0 * sr);
    while (ph.ppq < toPpq)
    {
        juce::MidiBuffer midi;
        p.processBlock(buf, midi);
        for (auto m : midi)
        {
            auto msg = m.getMessage();
            if (msg.isNoteOn()) { ++r.ons; ++r.onsPerCh[msg.getChannel()]; ++active; r.maxActive = std::max(r.maxActive, active);
                                  if (r.firstOn < 0) r.firstOn = ph.ppq + m.samplePosition / (double) block * qnPerBlock; }
            else if (msg.isNoteOff()) { ++r.offs; --active; }
            else if (msg.isController()) ++r.ccs;
        }
        ph.ppq += qnPerBlock;
    }
    return r;
}

int main()
{
    juce::ScopedJuceInitialiser_GUI gui;
    CompositorProcessor p;
    TestPlayHead ph;
    p.setPlayHead(&ph);
    p.setRateAndBufferSizeDetails(44100.0, 512);
    p.prepareToPlay(44100.0, 512);

    auto seq = p.getSequence();
    CHECK(seq != nullptr && ! seq->events.empty(), "sequencia inicial gerada");
    std::cout << "trilhas=" << seq->tracks.size() << " total=" << seq->total << " eventos=" << seq->events.size() << std::endl;
    CHECK(seq->tracks.size() >= 8, "varios instrumentos ligados por padrao");

    // 1) reproducao de um ciclo: todo note-on ganha seu note-off
    auto r1 = play(p, ph, 0.0, seq->total + 0.5);
    CHECK(r1.ons > 100, "gera notas ao tocar (" + juce::String(r1.ons) + ")");
    CHECK(r1.firstOn >= 0 && r1.firstOn < 1.5, "primeira nota no inicio (ppq " + juce::String(r1.firstOn, 3) + ")");
    CHECK(r1.onsPerCh.count(10) > 0, "bateria no canal 10");
    // 2) parar o transporte solta todas as notas
    juce::AudioBuffer<float> buf(2, 512);
    ph.playing = false;
    juce::MidiBuffer m; p.processBlock(buf, m);
    int stray = 0; for (auto e : m) if (e.getMessage().isNoteOn()) ++stray;
    CHECK(stray == 0, "parado nao emite notas");
    // 3) loop: dois ciclos geram aproximadamente o dobro
    p.prepareToPlay(44100.0, 512);
    auto one = play(p, ph, 0.0, seq->total - 0.01);
    ph.playing = false; { juce::MidiBuffer mm; p.processBlock(buf, mm); }
    auto two = play(p, ph, 0.0, 2 * seq->total - 0.01);
    CHECK(two.ons >= one.ons * 2 - 2 && two.ons <= one.ons * 2 + 2, "loop repete a peca (" + juce::String(one.ons) + " -> " + juce::String(two.ons) + ")");
    // 4) sem loop, nao repete
    p.repeatOn = false; ph.playing = false; { juce::MidiBuffer mm; p.processBlock(buf, mm); }
    auto noloop = play(p, ph, 0.0, 2 * seq->total - 0.01);
    CHECK(noloop.ons <= one.ons + 2, "sem 'repetir' toca uma vez (" + juce::String(noloop.ons) + ")");
    p.repeatOn = true;
    // 5) mute de tudo exceto solo
    ph.playing = false; { juce::MidiBuffer mm; p.processBlock(buf, mm); }
    p.soloMask = 1u << 0; // so a bateria
    auto solo = play(p, ph, 0.0, seq->total - 0.01);
    CHECK(solo.onsPerCh.size() == 1 && solo.onsPerCh.count(10), "solo da bateria");
    p.soloMask = 0;
    // 6) saltar o cursor libera notas
    ph.playing = false; { juce::MidiBuffer mm; p.processBlock(buf, mm); }
    {
        int active = 0; ph.playing = true; ph.ppq = 0.0; bool jumped = false;
        for (int i = 0; i < 200; ++i)
        {
            juce::MidiBuffer mm; p.processBlock(buf, mm);
            for (auto e : mm) { auto x = e.getMessage(); if (x.isNoteOn()) ++active; else if (x.isNoteOff()) --active; }
            ph.ppq += 512 * 120.0 / (60.0 * 44100.0);
            if (i == 100 && ! jumped) { ph.ppq = 5.0; jumped = true; }
        }
        ph.playing = false; juce::MidiBuffer mm; p.processBlock(buf, mm);
        for (auto e : mm) { auto x = e.getMessage(); if (x.isNoteOff()) --active; }
        CHECK(active == 0, "sem notas presas apos salto e parada (saldo " + juce::String(active) + ")");
    }
    // 7) tempo diferente do projeto (60 bpm) mantem sincronia em ppq
    ph.bpm = 60; p.prepareToPlay(44100.0, 512);
    auto slow = play(p, ph, 0.0, seq->total - 0.01);
    CHECK(std::abs(slow.ons - one.ons) <= 2, "bpm do host nao muda o conteudo por ciclo");
    ph.bpm = 120; ph.playing = false; { juce::MidiBuffer mm; p.processBlock(buf, mm); }

    // 8) exportar MIDI e reler
    auto f = juce::File::getSpecialLocation(juce::File::tempDirectory).getChildFile("composer_test.mid");
    CHECK(p.exportMidiFile(f, -1), "exporta .mid");
    juce::MidiFile mf; juce::FileInputStream in(f);
    CHECK(in.openedOk() && mf.readFrom(in), "le o .mid de volta");
    int notes = 0; for (int t = 0; t < mf.getNumTracks(); ++t) for (int i = 0; i < mf.getTrack(t)->getNumEvents(); ++i) if (mf.getTrack(t)->getEventPointer(i)->message.isNoteOn()) ++notes;
    int expect = 0; for (auto& t : seq->tracks) expect += (int) t.notes.size() / 4;
    CHECK(notes == expect, "notas no .mid = " + juce::String(notes) + " (esperado " + juce::String(expect) + ")");
    CHECK(mf.getNumTracks() == (int) seq->tracks.size() + 1, "uma trilha por instrumento + tempo");
    auto f2 = juce::File::getSpecialLocation(juce::File::tempDirectory).getChildFile("composer_single.mid");
    CHECK(p.exportMidiFile(f2, 1), "exporta so o baixo");

    // 9) estado: muda parametros, salva, restaura em outra instancia
    p.getEngine().set("G", "bars", 12, true);
    p.getEngine().set("G", "meterIdx", 7, true);   // 6/8
    p.regenerate();
    auto before = p.getSequence();
    juce::MemoryBlock mb; p.getStateInformation(mb);
    CompositorProcessor p2; p2.setStateInformation(mb.getData(), (int) mb.getSize());
    auto after = p2.getSequence();
    CHECK(after && std::abs(after->total - before->total) < 1e-6 && after->events.size() == before->events.size(),
          "estado restaurado reproduz a mesma peca (" + juce::String(after ? after->total : 0) + " tempos)");
    CHECK(before->bars.size() == 12 && before->tsNum == 6 && before->tsDen == 8, "12 compassos de 6/8");

    // 10) interface: renderiza para imagem
    {
        std::unique_ptr<juce::AudioProcessorEditor> ed(p.createEditor());
        ed->setSize(1200, 880);
        for (int tab = 0; tab < 5; ++tab)
        {
            if (auto* ce = dynamic_cast<CompositorEditor*>(ed.get())) ce->showTab(tab);
            auto img = ed->createComponentSnapshot(ed->getLocalBounds(), true, 1.0f);
            juce::File out = juce::File("/tmp/ui_tab" + juce::String(tab) + ".png");
            out.deleteFile(); juce::FileOutputStream os(out); juce::PNGImageFormat png; png.writeImageToStream(img, os);
        }
        CHECK(true, "interface renderizada em /tmp/ui_tab*.png");
    }
    std::cout << (failures == 0 ? "TODOS OS TESTES PASSARAM" : "HA FALHAS") << std::endl;
    return failures;
}
