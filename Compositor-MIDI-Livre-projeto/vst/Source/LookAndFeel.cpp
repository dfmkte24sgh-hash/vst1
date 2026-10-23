#include "LookAndFeel.h"
#include <map>

juce::Colour Pal::instrumentColour(const juce::String& id)
{
    static const std::map<juce::String, juce::uint32> m = {
        { "drums", 0xffe0584c }, { "bass", 0xff5b84e6 }, { "keys", 0xffecbd48 }, { "strings", 0xffaa78d2 },
        { "arp", 0xff4cd0c4 }, { "guitar", 0xffe8924a }, { "lead", 0xfff2679f }, { "counter", 0xffc57ac2 },
        { "brass", 0xffefd13c }, { "winds", 0xff7ed67e }, { "mallets", 0xff74c5ee }, { "texture", 0xff8e91a6 } };
    auto it = m.find(id);
    return juce::Colour(it != m.end() ? it->second : 0xff9a9ca3);
}

juce::Colour Pal::philoColour(int philo)
{
    switch (philo) { case 1: return amber; case 2: return teal; default: return magenta; }
}

ToonLook::ToonLook()
{
    setColour(juce::ResizableWindow::backgroundColourId, Pal::bg1);
    setColour(juce::Label::textColourId, Pal::text);
    setColour(juce::TextButton::buttonColourId, Pal::panel2);
    setColour(juce::TextButton::textColourOffId, Pal::text);
    setColour(juce::TextButton::textColourOnId, Pal::bg0);
    setColour(juce::ComboBox::backgroundColourId, Pal::bg0);
    setColour(juce::ComboBox::textColourId, Pal::text);
    setColour(juce::ComboBox::outlineColourId, Pal::line);
    setColour(juce::ComboBox::arrowColourId, Pal::amber);
    setColour(juce::PopupMenu::backgroundColourId, Pal::panel);
    setColour(juce::PopupMenu::textColourId, Pal::text);
    setColour(juce::PopupMenu::highlightedBackgroundColourId, Pal::amber);
    setColour(juce::PopupMenu::highlightedTextColourId, Pal::bg0);
    setColour(juce::Slider::textBoxTextColourId, Pal::text);
    setColour(juce::Slider::textBoxOutlineColourId, juce::Colours::transparentBlack);
    setColour(juce::Slider::textBoxBackgroundColourId, juce::Colours::transparentBlack);
    setColour(juce::TextEditor::backgroundColourId, Pal::bg0);
    setColour(juce::TextEditor::textColourId, Pal::text);
    setColour(juce::TextEditor::outlineColourId, Pal::line);
    setColour(juce::TextEditor::focusedOutlineColourId, Pal::amber);
    setColour(juce::TextEditor::highlightColourId, Pal::amber.withAlpha(0.4f));
    setColour(juce::CaretComponent::caretColourId, Pal::amber);
    setColour(juce::ScrollBar::thumbColourId, Pal::line);
}

void ToonLook::drawRotarySlider(juce::Graphics& g, int x, int y, int w, int h, float pos, float a0, float a1, juce::Slider& s)
{
    auto b = juce::Rectangle<float>((float) x, (float) y, (float) w, (float) h).reduced(3.0f);
    const float d = juce::jmin(b.getWidth(), b.getHeight());
    auto c = b.withSizeKeepingCentre(d, d);
    const float ang = a0 + pos * (a1 - a0);
    const auto accent = s.findColour(juce::Slider::rotarySliderFillColourId, true);
    const juce::Colour col = s.isColourSpecified(juce::Slider::rotarySliderFillColourId) ? accent : Pal::amber;

    g.setColour(Pal::bg0);
    g.fillEllipse(c);
    juce::Path track;
    track.addCentredArc(c.getCentreX(), c.getCentreY(), d * 0.5f - 1.5f, d * 0.5f - 1.5f, 0.0f, a0, a1, true);
    g.setColour(Pal::line);
    g.strokePath(track, juce::PathStrokeType(2.5f));
    juce::Path val;
    val.addCentredArc(c.getCentreX(), c.getCentreY(), d * 0.5f - 1.5f, d * 0.5f - 1.5f, 0.0f, a0, ang, true);
    g.setColour(s.isEnabled() ? col : Pal::dim);
    g.strokePath(val, juce::PathStrokeType(2.5f, juce::PathStrokeType::curved, juce::PathStrokeType::rounded));

    auto cap = c.reduced(d * 0.2f);
    g.setGradientFill(juce::ColourGradient(Pal::panel2.brighter(0.15f), cap.getX(), cap.getY(), Pal::panel, cap.getRight(), cap.getBottom(), false));
    g.fillEllipse(cap);
    g.setColour(Pal::line);
    g.drawEllipse(cap, 1.0f);
    juce::Path p;
    const float r = cap.getWidth() * 0.5f;
    p.addRoundedRectangle(-1.2f, -r + 1.5f, 2.4f, r * 0.55f, 1.0f);
    g.setColour(Pal::text);
    g.fillPath(p, juce::AffineTransform::rotation(ang).translated(cap.getCentreX(), cap.getCentreY()));
}

void ToonLook::drawLinearSlider(juce::Graphics& g, int x, int y, int w, int h, float pos, float, float,
                                juce::Slider::SliderStyle style, juce::Slider& s)
{
    if (style != juce::Slider::LinearHorizontal && style != juce::Slider::LinearBar)
        return LookAndFeel_V4::drawLinearSlider(g, x, y, w, h, pos, 0, 0, style, s);
    const float cy = y + h * 0.5f;
    auto groove = juce::Rectangle<float>((float) x, cy - 2.5f, (float) w, 5.0f);
    g.setColour(Pal::bg0);
    g.fillRoundedRectangle(groove, 2.5f);
    g.setColour(Pal::line);
    g.drawRoundedRectangle(groove, 2.5f, 1.0f);
    auto fill = groove.withRight(juce::jlimit((float) x, (float) (x + w), pos));
    g.setGradientFill(juce::ColourGradient(Pal::amberHi, fill.getX(), 0, Pal::amber, fill.getRight(), 0, false));
    g.fillRoundedRectangle(fill, 2.5f);
    g.setColour(Pal::text);
    g.fillEllipse(pos - 6.0f, cy - 6.0f, 12.0f, 12.0f);
    g.setColour(Pal::amber);
    g.drawEllipse(pos - 6.0f, cy - 6.0f, 12.0f, 12.0f, 1.5f);
}

void ToonLook::drawButtonBackground(juce::Graphics& g, juce::Button& b, const juce::Colour& bg, bool hover, bool down)
{
    auto r = b.getLocalBounds().toFloat().reduced(0.5f);
    const bool isTab = (bool) b.getProperties()["tab"];
    const bool isAccent = (bool) b.getProperties()["accent"];
    if (isTab)
    {
        if (b.getToggleState())
        {
            g.setColour(Pal::panel);
            g.fillRoundedRectangle(r.withTrimmedBottom(-6.0f), 6.0f);
            g.setColour(Pal::amber);
            g.fillRect(r.getX() + 8.0f, r.getBottom() - 3.0f, r.getWidth() - 16.0f, 3.0f);
        }
        else if (hover) { g.setColour(Pal::panel.withAlpha(0.6f)); g.fillRoundedRectangle(r, 6.0f); }
        return;
    }
    juce::Colour c = isAccent ? Pal::amber : bg;
    if (b.getToggleState() && ! isAccent) c = Pal::amber.withAlpha(0.9f);
    if (hover) c = c.brighter(0.12f);
    if (down) c = c.darker(0.15f);
    g.setColour(c);
    g.fillRoundedRectangle(r, 5.0f);
    g.setColour(isAccent ? Pal::amberHi : Pal::line);
    g.drawRoundedRectangle(r, 5.0f, 1.0f);
}

void ToonLook::drawButtonText(juce::Graphics& g, juce::TextButton& b, bool, bool)
{
    const bool isTab = (bool) b.getProperties()["tab"];
    const bool isAccent = (bool) b.getProperties()["accent"];
    juce::Colour c = Pal::text;
    if (isTab) c = b.getToggleState() ? Pal::amber : Pal::dim;
    else if (isAccent || b.getToggleState()) c = Pal::bg0;
    g.setColour(c);
    g.setFont(juce::FontOptions(isTab ? 14.0f : 13.0f, juce::Font::bold));
    g.drawFittedText(b.getButtonText(), b.getLocalBounds().reduced(4, 1), juce::Justification::centred, 1);
}

void ToonLook::drawToggleButton(juce::Graphics& g, juce::ToggleButton& b, bool hover, bool)
{
    auto r = b.getLocalBounds().toFloat();
    const float led = juce::jmin(14.0f, r.getHeight() - 4.0f);
    auto l = juce::Rectangle<float>(r.getX() + 2.0f, r.getCentreY() - led * 0.5f, led, led);
    const bool on = b.getToggleState();
    const juce::Colour col = b.findColour(juce::ToggleButton::tickColourId);
    const juce::Colour c = b.isColourSpecified(juce::ToggleButton::tickColourId) ? col : Pal::amber;
    g.setColour(Pal::bg0);
    g.fillRoundedRectangle(l.expanded(1.5f), 4.0f);
    g.setColour(on ? c : Pal::line);
    g.fillRoundedRectangle(l, 3.0f);
    if (on) { g.setColour(c.withAlpha(0.25f)); g.fillRoundedRectangle(l.expanded(3.0f), 5.0f); }
    if (hover) { g.setColour(juce::Colours::white.withAlpha(0.08f)); g.fillRoundedRectangle(l, 3.0f); }
    if (b.getButtonText().isNotEmpty())
    {
        g.setColour(on ? Pal::text : Pal::dim);
        g.setFont(juce::FontOptions(13.0f));
        g.drawFittedText(b.getButtonText(), b.getLocalBounds().withTrimmedLeft((int) led + 8), juce::Justification::centredLeft, 1);
    }
}

void ToonLook::drawComboBox(juce::Graphics& g, int w, int h, bool, int, int, int, int, juce::ComboBox& box)
{
    auto r = juce::Rectangle<float>(0.5f, 0.5f, w - 1.0f, h - 1.0f);
    g.setColour(Pal::bg0);
    g.fillRoundedRectangle(r, 4.0f);
    g.setColour(box.hasKeyboardFocus(true) ? Pal::amber : Pal::line);
    g.drawRoundedRectangle(r, 4.0f, 1.0f);
    juce::Path tri;
    const float cx = w - 12.0f, cy = h * 0.5f;
    tri.addTriangle(cx - 4.0f, cy - 2.0f, cx + 4.0f, cy - 2.0f, cx, cy + 3.0f);
    g.setColour(Pal::amber);
    g.fillPath(tri);
}

void ToonLook::positionComboBoxText(juce::ComboBox& box, juce::Label& l)
{
    l.setBounds(6, 1, box.getWidth() - 24, box.getHeight() - 2);
    l.setFont(getComboBoxFont(box));
}

void ToonLook::drawPopupMenuBackground(juce::Graphics& g, int w, int h)
{
    g.fillAll(Pal::panel);
    g.setColour(Pal::line);
    g.drawRect(0, 0, w, h, 1);
}

void ToonLook::fillTextEditorBackground(juce::Graphics& g, int w, int h, juce::TextEditor& e)
{
    g.setColour(e.findColour(juce::TextEditor::backgroundColourId));
    g.fillRoundedRectangle(0.0f, 0.0f, (float) w, (float) h, 4.0f);
}
void ToonLook::drawTextEditorOutline(juce::Graphics& g, int w, int h, juce::TextEditor& e)
{
    g.setColour(e.hasKeyboardFocus(true) ? Pal::amber : Pal::line);
    g.drawRoundedRectangle(0.5f, 0.5f, w - 1.0f, h - 1.0f, 4.0f, 1.0f);
}
