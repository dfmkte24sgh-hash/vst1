#include "PluginProcessor.h"
#include <algorithm>
#include <cmath>
#include <cstring>
#include "PluginEditor.h"

CompositorProcessor::CompositorProcessor()
    : AudioProcessor(BusesProperties().withOutput("Output", juce::AudioChannelSet::stereo(), true))
{
    for (auto& c : channelOf) c.store(0);
    meta = engine.callJson("meta");
    if (auto* arr = meta.getProperty("instruments", {}).getArray())
    {
        int i = 0;
        for (auto& ins : *arr)
        {
            instrumentIds.add(ins.getProperty("id", "").toString());
            if (i < 16) channelOf[i].store(juce::jlimit(0, 15, (int) ins.getProperty("ch", 0)));
            ++i;
        }
    }
    regenerate();
}

CompositorProcessor::~CompositorProcessor() {}

void CompositorProcessor::prepareToPlay(double, int)
{
    wasActive = false;
    internalPpq = expectedPpq = 0.0;
    std::memset(activeCount, 0, sizeof(activeCount));
}

bool CompositorProcessor::isBusesLayoutSupported(const BusesLayout& l) const
{
    const auto out = l.getMainOutputChannelSet();
    return out == juce::AudioChannelSet::stereo() || out == juce::AudioChannelSet::mono() || out.isDisabled();
}

juce::AudioProcessorEditor* CompositorProcessor::createEditor() { return new CompositorEditor(*this); }

// ---------------------------------------------------------------------------
void CompositorProcessor::regenerate()
{
    const juce::ScopedLock sl(regenLock);
    auto js = engine.callJson("generate");
    auto seq = std::make_shared<const Sequence>(Sequence::fromJson(js, instrumentIds));
    {
        juce::SpinLock::ScopedLockType l(seqSpin);
        if (current) retired.push_back(current);
        current = seq;
    }
    while (retired.size() > 4) retired.erase(retired.begin()); // o audio nunca segura os 4 mais recentes
    ++generation;
}

std::shared_ptr<const Sequence> CompositorProcessor::getSequence() const
{
    juce::SpinLock::ScopedLockType l(seqSpin);
    return current;
}

// ---------------------------------------------------------------------------
void CompositorProcessor::flushNotes(juce::MidiBuffer& midi, int pos)
{
    for (int ch = 0; ch < 16; ++ch)
    {
        bool any = false;
        for (int p = 0; p < 128; ++p)
            if (activeCount[ch][p] > 0)
            {
                midi.addEvent(juce::MidiMessage::noteOff(ch + 1, p), pos);
                activeCount[ch][p] = 0;
                any = true;
            }
        if (any || channelUsed[ch])
            midi.addEvent(juce::MidiMessage::controllerEvent(ch + 1, 64, 0), pos);
    }
}

void CompositorProcessor::processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midi)
{
    juce::ScopedNoDenormals noDenormals;
    buffer.clear();
    midi.clear();   // gerador: ignora o MIDI de entrada
    const int n = buffer.getNumSamples();
    if (n <= 0) return;

    {   // pega a sequencia mais recente sem travar o audio
        juce::SpinLock::ScopedTryLockType tl(seqSpin);
        if (tl.isLocked()) audioSeq = current;
    }
    if (! audioSeq) return;
    const Sequence& seq = *audioSeq;

    juce::AudioPlayHead::PositionInfo info;
    bool havePos = false;
    if (auto* ph = getPlayHead())
        if (auto p = ph->getPosition()) { info = *p; havePos = true; }

    const bool hostPlaying = havePos && info.getIsPlaying();
    const bool preview = previewOn.load();
    const bool active = hostPlaying || preview;
    const double sr = getSampleRate() > 0 ? getSampleRate() : 44100.0;

    double bpm = seq.bpm;
    if (havePos && info.getBpm().hasValue() && *info.getBpm() > 1.0) bpm = *info.getBpm();
    uiHostBpm.store(bpm);
    const double blockQn = (double) n * bpm / (60.0 * sr);

    if (! active)
    {
        if (wasActive) { flushNotes(midi, 0); wasActive = false; }
        uiPlaying.store(false);
        internalPpq = 0.0;
        return;
    }

    double ppqStart;
    if (hostPlaying)
        ppqStart = (havePos && info.getPpqPosition().hasValue()) ? *info.getPpqPosition()
                                                                 : (wasActive ? expectedPpq : 0.0);
    else
        ppqStart = internalPpq;

    const bool restarted = ! wasActive || std::abs(ppqStart - expectedPpq) > 0.01 + blockQn * 0.02;
    if (restarted)
    {
        const bool fresh = ! wasActive;
        if (wasActive) flushNotes(midi, 0);
        if (fresh && sendProgramChange.load())
            for (size_t t = 0; t < seq.tracks.size(); ++t)
            {
                const int ch = channelOf[juce::jlimit(0, 15, seq.trackInstrument[t])].load();
                midi.addEvent(juce::MidiMessage::programChange(ch + 1, seq.tracks[t].program), 0);
            }
    }

    const double total = seq.total;
    const double offset = offsetQn.load();
    const double a = ppqStart - offset;
    const double b = a + blockQn;
    const bool repeat = repeatOn.load();

    if (b > 0.0)
    {
        const double lo = juce::jmax(a, 0.0);
        const int k0 = (int) std::floor(lo / total);
        const int kEnd = repeat ? (int) std::floor((b - 1.0e-9) / total) : 0;
        uiRelQn.store(repeat ? std::fmod(lo, total) : juce::jmin(lo, total));
        if (repeat || lo < total)
        {
            for (int k = k0; k <= kEnd; ++k)
            {
                const double segStart = juce::jmax(lo, k * total) - k * total;
                const double segEnd = juce::jmin(b, (k + 1) * total) - k * total;
                if (segEnd <= segStart) continue;
                auto it = std::lower_bound(seq.events.begin(), seq.events.end(), segStart,
                                           [](const SeqEvent& e, double v) { return e.qn < v; });
                for (; it != seq.events.end() && it->qn < segEnd; ++it)
                {
                    const int pos = juce::jlimit(0, n - 1, (int) (((k * total + it->qn) - a) / blockQn * n));
                    const int inst = juce::jmin((int) it->inst, 15);
                    const int ch = channelOf[inst].load();
                    channelUsed[ch] = true;
                    if (it->type == 0)
                    {
                        if (activeCount[ch][it->d1] > 0)
                        {
                            midi.addEvent(juce::MidiMessage::noteOff(ch + 1, it->d1), pos);
                            --activeCount[ch][it->d1];
                        }
                    }
                    else if (it->type == 2)
                    {
                        if (! audible(inst)) continue;
                        if (activeCount[ch][it->d1] > 0)
                        {
                            midi.addEvent(juce::MidiMessage::noteOff(ch + 1, it->d1), pos);
                            activeCount[ch][it->d1] = 0;
                        }
                        midi.addEvent(juce::MidiMessage::noteOn(ch + 1, (int) it->d1, (juce::uint8) it->d2), pos);
                        ++activeCount[ch][it->d1];
                    }
                    else if (audible(inst))
                        midi.addEvent(juce::MidiMessage::controllerEvent(ch + 1, it->d1, it->d2), pos);
                }
            }
        }
    }
    else uiRelQn.store(0.0);

    uiPlaying.store(true);
    wasActive = true;
    expectedPpq = ppqStart + blockQn;
    if (! hostPlaying) internalPpq = expectedPpq;
}

// ---------------------------------------------------------------------------
juce::File CompositorProcessor::getExportFolder()
{
    auto f = juce::File::getSpecialLocation(juce::File::userDocumentsDirectory).getChildFile("Compositor MIDI Livre");
    f.createDirectory();
    return f;
}
juce::File CompositorProcessor::getTempFolder()
{
    auto f = juce::File::getSpecialLocation(juce::File::tempDirectory).getChildFile("CompositorMIDI");
    f.createDirectory();
    return f;
}

bool CompositorProcessor::exportMidiFile(const juce::File& file, int instrument) const
{
    auto seq = getSequence();
    if (! seq) return false;
    constexpr int ppq = 960;
    juce::MidiFile mf;
    mf.setTicksPerQuarterNote(ppq);

    juce::MidiMessageSequence conductor;
    conductor.addEvent(juce::MidiMessage::textMetaEvent(3, "Compositor MIDI Livre"), 0);
    conductor.addEvent(juce::MidiMessage::tempoMetaEvent((int) (60000000.0 / juce::jmax(20.0, seq->bpm))), 0);
    conductor.addEvent(juce::MidiMessage::timeSignatureMetaEvent(seq->tsNum, seq->tsDen), 0);
    conductor.addEvent(juce::MidiMessage::endOfTrack(), seq->total * ppq);
    mf.addTrack(conductor);

    for (size_t t = 0; t < seq->tracks.size(); ++t)
    {
        const int inst = seq->trackInstrument[t];
        if (instrument >= 0 && inst != instrument) continue;
        const int ch = channelOf[juce::jlimit(0, 15, inst)].load();
        juce::MidiMessageSequence ts;
        ts.addEvent(juce::MidiMessage::textMetaEvent(3, seq->tracks[t].label), 0);
        if (ch != 9) ts.addEvent(juce::MidiMessage::programChange(ch + 1, seq->tracks[t].program), 0);
        for (auto& e : seq->events)
        {
            if (e.inst != inst) continue;
            const double tick = e.qn * ppq;
            if (e.type == 2) ts.addEvent(juce::MidiMessage::noteOn(ch + 1, (int) e.d1, (juce::uint8) e.d2), tick);
            else if (e.type == 0) ts.addEvent(juce::MidiMessage::noteOff(ch + 1, (int) e.d1), tick);
            else ts.addEvent(juce::MidiMessage::controllerEvent(ch + 1, e.d1, e.d2), tick);
        }
        ts.addEvent(juce::MidiMessage::endOfTrack(), seq->total * ppq);
        ts.updateMatchedPairs();
        mf.addTrack(ts);
    }
    file.deleteFile();
    juce::FileOutputStream out(file);
    if (! out.openedOk()) return false;
    return mf.writeTo(out, 1);
}

// ---------------------------------------------------------------------------
void CompositorProcessor::getStateInformation(juce::MemoryBlock& dest)
{
    juce::XmlElement xml("CompositorMIDI");
    xml.setAttribute("v", 1);
    xml.setAttribute("engine", juce::Base64::toBase64(engine.save()));
    xml.setAttribute("repeat", repeatOn.load());
    xml.setAttribute("pc", sendProgramChange.load());
    xml.setAttribute("offset", offsetQn.load());
    xml.setAttribute("mute", (int) muteMask.load());
    xml.setAttribute("solo", (int) soloMask.load());
    juce::StringArray ch;
    for (int i = 0; i < 16; ++i) ch.add(juce::String(channelOf[i].load()));
    xml.setAttribute("chan", ch.joinIntoString(","));
    copyXmlToBinary(xml, dest);
}

void CompositorProcessor::setStateInformation(const void* data, int size)
{
    auto xml = getXmlFromBinary(data, size);
    if (xml == nullptr || ! xml->hasTagName("CompositorMIDI")) return;
    juce::MemoryOutputStream decoded;
    if (juce::Base64::convertFromBase64(decoded, xml->getStringAttribute("engine")))
        engine.load(decoded.toString());
    repeatOn = xml->getBoolAttribute("repeat", true);
    sendProgramChange = xml->getBoolAttribute("pc", false);
    offsetQn = xml->getDoubleAttribute("offset", 0.0);
    muteMask = (juce::uint32) xml->getIntAttribute("mute", 0);
    soloMask = (juce::uint32) xml->getIntAttribute("solo", 0);
    auto ch = juce::StringArray::fromTokens(xml->getStringAttribute("chan"), ",", "");
    for (int i = 0; i < juce::jmin(16, ch.size()); ++i) channelOf[i] = juce::jlimit(0, 15, ch[i].getIntValue());
    regenerate();
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter() { return new CompositorProcessor(); }
