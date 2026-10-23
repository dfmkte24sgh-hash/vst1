#pragma once
#include <juce_gui_extra/juce_gui_extra.h>
#include <functional>
#include "PluginProcessor.h"
#include "LookAndFeel.h"

class CompositorEditor;

// ---------------------------------------------------------------------------
// painel generico de controles (Geral / Harmonia) montado a partir dos metadados do motor
class ParamPanel : public juce::Component
{
public:
    ParamPanel(CompositorEditor& owner, const juce::String& tab);
    void sync(const juce::var& G);
    void resized() override;

private:
    struct Row
    {
        juce::var desc;
        juce::String key, kind;
        bool isInt = false;
        std::vector<int> values;
        std::unique_ptr<juce::Label> label;
        std::unique_ptr<juce::Component> widget;
        juce::String showKey; int showEq = 0; bool visible = true;
    };
    CompositorEditor& owner;
    std::vector<std::unique_ptr<Row>> rows;
    bool syncing = false;
    void applyVisibility(const juce::var& G);
};

// ---------------------------------------------------------------------------
class InstrumentsPanel : public juce::Component
{
public:
    explicit InstrumentsPanel(CompositorEditor& owner);
    void sync(const juce::var& P);
    void resized() override;
    void paint(juce::Graphics&) override;

private:
    struct Row : public juce::Component
    {
        Row(CompositorEditor& o, int index, const juce::var& insMeta);
        void paint(juce::Graphics&) override;
        void resized() override;
        void sync(const juce::var& p);
        CompositorEditor& owner;
        int index; juce::String id, label; juce::Colour colour;
        juce::ToggleButton on;
        juce::ComboBox style, octave, channel;
        juce::Slider knobs[5];
        juce::TextButton vary { "VARIAR" };
        bool syncing = false;
    };
    CompositorEditor& owner;
    std::vector<std::unique_ptr<Row>> rows;
};

// ---------------------------------------------------------------------------
class TapPad : public juce::Component
{
public:
    std::function<void()> onTap;
    void paint(juce::Graphics&) override;
    void mouseDown(const juce::MouseEvent&) override { grabKeyboardFocus(); hit(); }
    bool keyPressed(const juce::KeyPress&) override;
    TapPad() { setWantsKeyboardFocus(true); }
    void hit() { flash = 1.0f; repaint(); if (onTap) onTap(); }
    float flash = 0.0f;
};

class RhythmView : public juce::Component
{
public:
    std::vector<float> weights;
    void paint(juce::Graphics&) override;
};

class TapPanel : public juce::Component
{
public:
    explicit TapPanel(CompositorEditor& owner);
    void sync(const juce::var& state);
    void resized() override;
    void tickFlash();
    void paint(juce::Graphics&) override;

private:
    void doTap();
    void applyTaps();
    CompositorEditor& owner;
    TapPad pad;
    RhythmView rhythm;
    juce::ComboBox mode;
    juce::TextButton apply { "APLICAR TOQUES" }, clear { "LIMPAR" }, x2 { "BPM x2" }, half { "BPM /2" }, forget { "ESQUECER RITMO" };
    juce::Label tapInfo, inflLabel;
    juce::Slider influence;
    juce::TextEditor log, intent;
    juce::TextButton interpret { "INTERPRETAR E APLICAR" };
    std::vector<std::unique_ptr<juce::TextButton>> presetButtons;
    std::vector<double> taps;
    bool syncing = false;
    juce::String csv() const;
};

// ---------------------------------------------------------------------------
class OptionsPanel : public juce::Component
{
public:
    explicit OptionsPanel(CompositorEditor& owner);
    void sync();
    void resized() override;

private:
    CompositorEditor& owner;
    juce::ToggleButton repeat { "Repetir a peca em loop" }, preview { "Previa: tocar sem o transporte" },
        sendPc { "Enviar Program Change (GM) ao iniciar" };
    juce::Slider offset;
    juce::Label offsetLabel, help;
    juce::TextButton exportAll { "EXPORTAR .MID (TODAS AS TRILHAS)" }, openFolder { "ABRIR PASTA" }, reset { "RESTAURAR PADROES" };
    bool syncing = false;
};

// ---------------------------------------------------------------------------
class SongStrip : public juce::Component
{
public:
    explicit SongStrip(CompositorEditor& owner) : owner(owner) {}
    void setSequence(std::shared_ptr<const Sequence> s) { seq = std::move(s); repaint(); }
    void paint(juce::Graphics&) override;
    void mouseDown(const juce::MouseEvent&) override;
    void mouseDrag(const juce::MouseEvent&) override;
    void mouseUp(const juce::MouseEvent&) override { dragInst = -2; }

private:
    juce::Rectangle<int> laneRect(int lane) const;
    CompositorEditor& owner;
    std::shared_ptr<const Sequence> seq;
    int dragInst = -2;   // -2 nada, -1 todas, >=0 indice de trilha
    static constexpr int labelW = 190, rulerH = 18, chordH = 24;
};

// ---------------------------------------------------------------------------
class CompositorEditor : public juce::AudioProcessorEditor,
                         public juce::DragAndDropContainer,
                         private juce::Timer
{
public:
    explicit CompositorEditor(CompositorProcessor&);
    ~CompositorEditor() override;

    void paint(juce::Graphics&) override;
    void resized() override;

    // chamados pelos paineis
    CompositorProcessor& proc;
    void setGlobal(const juce::String& key, const juce::var& v, bool isInt);
    void setInstr(const juce::String& id, const juce::String& key, const juce::var& v, bool isInt);
    void markDirty();
    void refreshAll();
    void regenerateNow();
    void setStatus(const juce::String& s) { status = s; repaint(); }
    juce::var getState() const { return state; }
    juce::var getMeta() const { return proc.getMeta(); }
    void showTab(int i);

private:
    void timerCallback() override;
    void updateHarmonyView();
    ToonLook look;
    juce::var state;
    juce::String status;
    int dirtyCountdown = 0;
    int lastGeneration = -1;
    bool autoGen = true;

    juce::TextButton tabButtons[5];
    juce::TextButton generate { "GERAR" }, newVersion { "NOVA VERSAO" };
    juce::ToggleButton autoToggle { "AUTO" };
    juce::Label seedLabel;

    ParamPanel geral, harmonia;
    InstrumentsPanel instruments;
    TapPanel tap;
    OptionsPanel options;
    juce::TextEditor planView;
    SongStrip strip;
    int currentTab = 0;
};
