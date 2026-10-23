#pragma once
#include <juce_audio_processors/juce_audio_processors.h>
#include <atomic>
#include <memory>
#include "LuaEngine.h"
#include "Sequence.h"

class CompositorProcessor : public juce::AudioProcessor
{
public:
    CompositorProcessor();
    ~CompositorProcessor() override;

    // ---- AudioProcessor
    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void releaseResources() override {}
    bool isBusesLayoutSupported(const BusesLayout& layouts) const override;
    void processBlock(juce::AudioBuffer<float>&, juce::MidiBuffer&) override;
    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override { return true; }
    const juce::String getName() const override { return "Compositor MIDI Livre"; }
    bool acceptsMidi() const override { return true; }
    bool producesMidi() const override { return true; }
    bool isMidiEffect() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String&) override {}
    void getStateInformation(juce::MemoryBlock&) override;
    void setStateInformation(const void*, int) override;

    // ---- motor
    LuaEngine& getEngine() { return engine; }
    const juce::var& getMeta() const { return meta; }
    int getInstrumentCount() const { return instrumentIds.size(); }
    const juce::StringArray& getInstrumentIds() const { return instrumentIds; }
    void regenerate();                                  // thread de mensagens (ou setState)
    std::shared_ptr<const Sequence> getSequence() const;
    int getGeneration() const { return generation.load(); }

    // ---- reproducao
    std::atomic<bool> repeatOn { true }, previewOn { false }, sendProgramChange { false };
    std::atomic<double> offsetQn { 0.0 };
    std::atomic<juce::uint32> muteMask { 0 }, soloMask { 0 };
    std::atomic<int> channelOf[16];
    std::atomic<double> uiRelQn { 0.0 };
    std::atomic<bool> uiPlaying { false };
    std::atomic<double> uiHostBpm { 0.0 };

    // ---- exportacao (instrument = -1 -> todas as trilhas)
    bool exportMidiFile(const juce::File& file, int instrument = -1) const;
    static juce::File getExportFolder();
    static juce::File getTempFolder();

private:
    void flushNotes(juce::MidiBuffer&, int samplePos);
    bool audible(int inst) const
    {
        const auto m = muteMask.load(), s = soloMask.load();
        const juce::uint32 bit = 1u << inst;
        if (m & bit) return false;
        return s == 0 || (s & bit) != 0;
    }

    LuaEngine engine;
    juce::var meta;
    juce::StringArray instrumentIds;

    mutable juce::SpinLock seqSpin;
    std::shared_ptr<const Sequence> current;
    std::vector<std::shared_ptr<const Sequence>> retired;
    std::shared_ptr<const Sequence> audioSeq;
    juce::CriticalSection regenLock;
    std::atomic<int> generation { 0 };

    // estado do audio
    bool wasActive = false;
    double expectedPpq = 0.0, internalPpq = 0.0;
    int activeCount[16][128] = {};
    bool channelUsed[16] = {};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(CompositorProcessor)
};
