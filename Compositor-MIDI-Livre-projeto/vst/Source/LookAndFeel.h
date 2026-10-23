#pragma once
#include <juce_gui_extra/juce_gui_extra.h>

// Paleta e estetica funcional (carvao + ambar, botoes tipo knob e LED), em estilo de plugins de producao.
namespace Pal
{
    const juce::Colour bg0     (0xff0f1012);
    const juce::Colour bg1     (0xff17181b);
    const juce::Colour panel   (0xff202226);
    const juce::Colour panel2  (0xff2a2c31);
    const juce::Colour line    (0xff3a3d44);
    const juce::Colour text    (0xffe9e9ec);
    const juce::Colour dim     (0xff8d9097);
    const juce::Colour amber   (0xfff5a020);
    const juce::Colour amberHi (0xffffc361);
    const juce::Colour teal    (0xff35c5b5);
    const juce::Colour magenta (0xffd4557e);
    const juce::Colour red     (0xffd9534f);

    juce::Colour instrumentColour(const juce::String& id);
    juce::Colour philoColour(int philo);
}

class ToonLook : public juce::LookAndFeel_V4
{
public:
    ToonLook();

    void drawRotarySlider(juce::Graphics&, int x, int y, int w, int h, float pos, float startAngle,
                          float endAngle, juce::Slider&) override;
    void drawLinearSlider(juce::Graphics&, int x, int y, int w, int h, float pos, float minPos, float maxPos,
                          juce::Slider::SliderStyle, juce::Slider&) override;
    void drawButtonBackground(juce::Graphics&, juce::Button&, const juce::Colour&, bool hover, bool down) override;
    void drawButtonText(juce::Graphics&, juce::TextButton&, bool hover, bool down) override;
    void drawToggleButton(juce::Graphics&, juce::ToggleButton&, bool hover, bool down) override;
    void drawComboBox(juce::Graphics&, int w, int h, bool down, int bx, int by, int bw, int bh, juce::ComboBox&) override;
    void positionComboBoxText(juce::ComboBox&, juce::Label&) override;
    juce::Font getComboBoxFont(juce::ComboBox&) override { return juce::FontOptions(13.0f); }
    juce::Font getTextButtonFont(juce::TextButton&, int) override { return juce::FontOptions(13.0f, juce::Font::bold); }
    void drawPopupMenuBackground(juce::Graphics&, int w, int h) override;
    void drawTextEditorOutline(juce::Graphics&, int w, int h, juce::TextEditor&) override;
    void fillTextEditorBackground(juce::Graphics&, int w, int h, juce::TextEditor&) override;
};
