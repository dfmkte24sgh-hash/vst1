#include "PluginEditor.h"

using juce::String;

static juce::StringArray listOf(const juce::var& meta, const String& name)
{
    juce::StringArray out;
    if (auto* a = meta.getProperty("lists", {}).getProperty(name, {}).getArray())
        for (auto& v : *a) out.add(v.toString());
    return out;
}

// ===========================================================================
// ParamPanel
// ===========================================================================
ParamPanel::ParamPanel(CompositorEditor& o, const String& tab) : owner(o)
{
    auto meta = owner.getMeta();
    auto* controls = meta.getProperty("controls", {}).getArray();
    if (controls == nullptr) return;
    for (auto& c : *controls)
    {
        if (c.getProperty("tab", "").toString() != tab) continue;
        auto r = std::make_unique<Row>();
        r->desc = c;
        r->key = c.getProperty("key", "").toString();
        r->kind = c.getProperty("kind", "").toString();
        r->showKey = c.getProperty("showKey", "").toString();
        r->showEq = (int) c.getProperty("showEq", 0);
        const String text = c.getProperty("label", "").toString();
        const String key = r->key;
        Row* rp = r.get();

        if (r->kind == "float" || r->kind == "int")
        {
            auto s = std::make_unique<juce::Slider>(juce::Slider::LinearHorizontal, juce::Slider::TextBoxRight);
            const bool isInt = (r->kind == "int");
            r->isInt = isInt;
            s->setRange((double) c.getProperty("min", 0), (double) c.getProperty("max", 1), isInt ? 1.0 : 0.01);
            s->setTextBoxStyle(juce::Slider::TextBoxRight, false, 56, 20);
            if (isInt) s->setNumDecimalPlacesToDisplay(0);
            auto* sp = s.get();
            s->onValueChange = [this, key, isInt, sp] {
                if (syncing) return;
                owner.setGlobal(key, isInt ? juce::var((juce::int64) sp->getValue()) : juce::var(sp->getValue()), isInt);
            };
            r->widget = std::move(s);
        }
        else if (r->kind == "combo")
        {
            auto cb = std::make_unique<juce::ComboBox>();
            auto items = listOf(meta, c.getProperty("items", "").toString());
            for (int i = 0; i < items.size(); ++i) cb->addItem(items[i], i + 1);
            if (auto* va = c.getProperty("values", {}).getArray())
                for (auto& v : *va) r->values.push_back((int) v);
            r->isInt = true;
            auto* cp = cb.get();
            cb->onChange = [this, key, rp, cp] {
                if (syncing) return;
                const int idx = cp->getSelectedId() - 1;
                if (idx < 0) return;
                const int v = rp->values.empty() ? idx + 1 : rp->values[(size_t) juce::jmin(idx, (int) rp->values.size() - 1)];
                owner.setGlobal(key, v, true);
            };
            r->widget = std::move(cb);
        }
        else if (r->kind == "check")
        {
            auto t = std::make_unique<juce::ToggleButton>(text);
            auto* tp = t.get();
            t->onClick = [this, key, tp] { if (! syncing) owner.setGlobal(key, tp->getToggleState(), false); };
            r->widget = std::move(t);
        }
        else // text
        {
            auto te = std::make_unique<juce::TextEditor>();
            auto* tp = te.get();
            te->setText("", false);
            te->setTextToShowWhenEmpty("ex.: 4/4 4/4 3/4 7/8  (vazio = usa o compasso escolhido)", Pal::dim);
            auto commit = [this, key, tp] { if (! syncing) owner.setGlobal(key, tp->getText(), false); };
            te->onReturnKey = commit;
            te->onFocusLost = commit;
            r->widget = std::move(te);
        }
        if (r->kind != "check")
        {
            r->label = std::make_unique<juce::Label>(juce::String(), text);
            r->label->setColour(juce::Label::textColourId, Pal::dim);
            r->label->setFont(juce::FontOptions(13.0f));
            addAndMakeVisible(*r->label);
        }
        addAndMakeVisible(*r->widget);
        rows.push_back(std::move(r));
    }
}

void ParamPanel::applyVisibility(const juce::var& G)
{
    for (auto& r : rows)
    {
        r->visible = r->showKey.isEmpty() || (int) G.getProperty(r->showKey, 0) == r->showEq;
        r->widget->setVisible(r->visible);
        if (r->label) r->label->setVisible(r->visible);
    }
    resized();
}

void ParamPanel::sync(const juce::var& G)
{
    const juce::ScopedValueSetter<bool> guard(syncing, true);
    for (auto& r : rows)
    {
        auto v = G.getProperty(r->key, {});
        if (auto* s = dynamic_cast<juce::Slider*>(r->widget.get())) s->setValue((double) v, juce::dontSendNotification);
        else if (auto* cb = dynamic_cast<juce::ComboBox*>(r->widget.get()))
        {
            int idx = (int) v - 1;
            if (! r->values.empty())
            {
                idx = 0;
                for (size_t i = 0; i < r->values.size(); ++i) if (r->values[i] == (int) v) idx = (int) i;
            }
            cb->setSelectedId(idx + 1, juce::dontSendNotification);
        }
        else if (auto* t = dynamic_cast<juce::ToggleButton*>(r->widget.get())) t->setToggleState((bool) v, juce::dontSendNotification);
        else if (auto* te = dynamic_cast<juce::TextEditor*>(r->widget.get()))
        {
            if (! te->hasKeyboardFocus(true)) te->setText(v.toString(), false);
        }
    }
    applyVisibility(G);
}

void ParamPanel::resized()
{
    const int colW = (getWidth() - 40) / 2;
    int col = 0, y[2] = { 10, 10 };
    for (auto& r : rows)
    {
        if (! r->visible) continue;
        const int x = 10 + col * (colW + 20);
        const bool wide = (r->kind == "text");
        const int h = 34;
        if (wide) { col = 0; y[0] = y[1] = juce::jmax(y[0], y[1]); }
        const int xx = wide ? 10 : x;
        const int ww = wide ? getWidth() - 20 : colW;
        int& yy = wide ? y[0] : y[col];
        if (r->label)
        {
            r->label->setBounds(xx, yy, 210, h);
            r->widget->setBounds(xx + 215, yy + 4, ww - 220, h - 8);
        }
        else r->widget->setBounds(xx + 4, yy + 4, ww - 8, h - 8);
        yy += h + 4;
        if (wide) y[1] = y[0];
        else col = 1 - col;
    }
}

// ===========================================================================
// InstrumentsPanel
// ===========================================================================
static const char* knobKeys[5]  = { "density", "variation", "complexity", "gate", "vel" };
static const char* knobNames[5] = { "DENS", "VAR", "COMPL", "LEG", "VOL" };

InstrumentsPanel::Row::Row(CompositorEditor& o, int idx, const juce::var& ins)
    : owner(o), index(idx)
{
    id = ins.getProperty("id", "").toString();
    label = ins.getProperty("label", "").toString();
    colour = Pal::instrumentColour(id);

    on.setColour(juce::ToggleButton::tickColourId, colour);
    on.onClick = [this] { if (! syncing) { owner.setInstr(id, "on", on.getToggleState(), false); } };
    addAndMakeVisible(on);

    if (auto* st = ins.getProperty("styles", {}).getArray())
        for (int i = 0; i < st->size(); ++i) style.addItem((*st)[i].toString(), i + 1);
    style.onChange = [this] { if (! syncing && style.getSelectedId() > 0) owner.setInstr(id, "style", style.getSelectedId(), true); };
    addAndMakeVisible(style);

    for (int i = 0; i < 5; ++i)
    {
        auto& k = knobs[i];
        k.setSliderStyle(juce::Slider::RotaryHorizontalVerticalDrag);
        k.setTextBoxStyle(juce::Slider::NoTextBox, false, 0, 0);
        k.setColour(juce::Slider::rotarySliderFillColourId, colour);
        k.setRotaryParameters(juce::MathConstants<float>::pi * 1.2f, juce::MathConstants<float>::pi * 2.8f, true);
        if (i == 3) k.setRange(0.2, 1.4, 0.01); else if (i == 4) k.setRange(0.2, 1.0, 0.01); else k.setRange(0.0, 1.0, 0.01);
        const juce::String key = knobKeys[i];
        k.onValueChange = [this, key, i] { if (! syncing) owner.setInstr(id, key, knobs[i].getValue(), false); };
        addAndMakeVisible(k);
    }
    for (int o2 = -2; o2 <= 2; ++o2) octave.addItem(o2 > 0 ? "+" + juce::String(o2) : juce::String(o2), o2 + 3);
    octave.onChange = [this] { if (! syncing && octave.getSelectedId() > 0) owner.setInstr(id, "octave", octave.getSelectedId() - 3, true); };
    addAndMakeVisible(octave);
    for (int c = 1; c <= 16; ++c) channel.addItem("Ch " + juce::String(c), c);
    channel.onChange = [this] {
        if (! syncing && channel.getSelectedId() > 0 && index < 16)
        { owner.proc.channelOf[index].store(channel.getSelectedId() - 1); owner.markDirty(); }
    };
    addAndMakeVisible(channel);
    vary.onClick = [this] {
        auto p = owner.getState().getProperty("P", {}).getProperty(id, {});
        owner.setInstr(id, "seedOff", (juce::int64) ((int) p.getProperty("seedOff", 0) + 1), true);
        owner.regenerateNow();
    };
    addAndMakeVisible(vary);
}

void InstrumentsPanel::Row::sync(const juce::var& p)
{
    const juce::ScopedValueSetter<bool> guard(syncing, true);
    on.setToggleState((bool) p.getProperty("on", true), juce::dontSendNotification);
    style.setSelectedId((int) p.getProperty("style", 1), juce::dontSendNotification);
    for (int i = 0; i < 5; ++i) knobs[i].setValue((double) p.getProperty(knobKeys[i], 0.5), juce::dontSendNotification);
    octave.setSelectedId((int) p.getProperty("octave", 0) + 3, juce::dontSendNotification);
    if (index < 16) channel.setSelectedId(owner.proc.channelOf[index].load() + 1, juce::dontSendNotification);
    repaint();
}

void InstrumentsPanel::Row::resized()
{
    on.setBounds(8, 10, 24, 24);
    style.setBounds(226, 10, 220, 24);
    for (int i = 0; i < 5; ++i) knobs[i].setBounds(454 + i * 58 + 11, 2, 34, 34);
    octave.setBounds(454 + 5 * 58 + 10, 10, 58, 24);
    channel.setBounds(454 + 5 * 58 + 76, 10, 68, 24);
    vary.setBounds(454 + 5 * 58 + 156, 9, 84, 26);
}

void InstrumentsPanel::Row::paint(juce::Graphics& g)
{
    auto r = getLocalBounds().toFloat().reduced(2.0f, 1.0f);
    g.setColour(Pal::panel);
    g.fillRoundedRectangle(r, 6.0f);
    g.setColour(colour);
    g.fillRoundedRectangle(r.withWidth(4.0f), 2.0f);
    g.setColour(on.getToggleState() ? Pal::text : Pal::dim);
    g.setFont(juce::FontOptions(14.0f, juce::Font::bold));
    g.drawText(label, 38, 0, 184, getHeight(), juce::Justification::centredLeft, true);
    g.setColour(Pal::dim);
    g.setFont(juce::FontOptions(9.5f));
    for (int i = 0; i < 5; ++i)
        g.drawText(knobNames[i], knobs[i].getX() - 8, 34, knobs[i].getWidth() + 16, 10, juce::Justification::centred);
}

InstrumentsPanel::InstrumentsPanel(CompositorEditor& o) : owner(o)
{
    if (auto* a = owner.getMeta().getProperty("instruments", {}).getArray())
    {
        int i = 0;
        for (auto& ins : *a)
        {
            rows.push_back(std::make_unique<Row>(owner, i++, ins));
            addAndMakeVisible(*rows.back());
        }
    }
}

void InstrumentsPanel::sync(const juce::var& P)
{
    for (auto& r : rows) r->sync(P.getProperty(r->id, {}));
}

void InstrumentsPanel::resized()
{
    int y = 20;
    for (auto& r : rows) { r->setBounds(0, y, getWidth(), 44); y += 44; }
}

void InstrumentsPanel::paint(juce::Graphics& g)
{
    g.setColour(Pal::dim);
    g.setFont(juce::FontOptions(10.5f, juce::Font::bold));
    g.drawText("INSTRUMENTO", 38, 2, 180, 16, juce::Justification::centredLeft);
    g.drawText("ESTILO", 226, 2, 200, 16, juce::Justification::centredLeft);
    g.drawText("CONTROLES", 454, 2, 290, 16, juce::Justification::centredLeft);
    g.drawText("OITAVA", 454 + 5 * 58 + 10, 2, 58, 16, juce::Justification::centred);
    g.drawText("CANAL MIDI", 454 + 5 * 58 + 76, 2, 68, 16, juce::Justification::centred);
}

// ===========================================================================
// TapPad, RhythmView, TapPanel
// ===========================================================================
void TapPad::paint(juce::Graphics& g)
{
    auto r = getLocalBounds().toFloat().reduced(8.0f);
    const float d = juce::jmin(r.getWidth(), r.getHeight());
    auto c = r.withSizeKeepingCentre(d, d);
    if (flash > 0.01f)
    {
        g.setColour(Pal::amber.withAlpha(0.35f * flash));
        g.fillEllipse(c.expanded(6.0f * flash));
    }
    g.setGradientFill(juce::ColourGradient(Pal::panel2.brighter(0.1f), c.getX(), c.getY(), Pal::bg0, c.getRight(), c.getBottom(), false));
    g.fillEllipse(c);
    g.setColour(Pal::amber.interpolatedWith(Pal::amberHi, flash));
    g.drawEllipse(c.reduced(3.0f), 4.0f);
    g.setColour(Pal::text);
    g.setFont(juce::FontOptions(34.0f, juce::Font::bold));
    g.drawText("TAP", c.toNearestInt(), juce::Justification::centred);
    g.setColour(Pal::dim);
    g.setFont(juce::FontOptions(11.0f));
    g.drawText("clique ou tecla T / espaco", c.toNearestInt().withTrimmedTop((int) (d * 0.65f)), juce::Justification::centred);
}

bool TapPad::keyPressed(const juce::KeyPress& k)
{
    if (k.getTextCharacter() == 't' || k.getTextCharacter() == 'T' || k.isKeyCode(juce::KeyPress::spaceKey)) { hit(); return true; }
    return false;
}

void RhythmView::paint(juce::Graphics& g)
{
    auto r = getLocalBounds().toFloat();
    g.setColour(Pal::bg0);
    g.fillRoundedRectangle(r, 5.0f);
    g.setColour(Pal::line);
    g.drawRoundedRectangle(r.reduced(0.5f), 5.0f, 1.0f);
    if (weights.empty())
    {
        g.setColour(Pal::dim);
        g.setFont(juce::FontOptions(12.0f));
        g.drawText("nenhum ritmo aprendido ainda", getLocalBounds(), juce::Justification::centred);
        return;
    }
    const float n = (float) weights.size();
    const float cw = (r.getWidth() - 8.0f) / n;
    for (size_t i = 0; i < weights.size(); ++i)
    {
        const float h = juce::jmax(2.0f, weights[i] * (r.getHeight() - 12.0f));
        g.setColour(((int) i % 4 == 0 ? Pal::amberHi : Pal::amber).withAlpha(0.25f + 0.75f * weights[i]));
        g.fillRoundedRectangle(4.0f + (float) i * cw + 1.0f, r.getBottom() - 4.0f - h, cw - 2.0f, h, 2.0f);
    }
}

TapPanel::TapPanel(CompositorEditor& o) : owner(o)
{
    pad.onTap = [this] { doTap(); };
    addAndMakeVisible(pad);
    addAndMakeVisible(rhythm);
    auto modes = listOf(owner.getMeta(), "tapmodes");
    for (int i = 0; i < modes.size(); ++i) mode.addItem(modes[i], i + 1);
    mode.setSelectedId(1, juce::dontSendNotification);
    addAndMakeVisible(mode);
    for (auto* b : { &apply, &clear, &x2, &half, &forget, &interpret }) addAndMakeVisible(*b);
    apply.getProperties().set("accent", true);
    interpret.getProperties().set("accent", true);
    tapInfo.setFont(juce::FontOptions(15.0f, juce::Font::bold));
    tapInfo.setText("Toques: 0\nBPM: --", juce::dontSendNotification);
    addAndMakeVisible(tapInfo);

    inflLabel.setText("Influencia do ritmo tocado", juce::dontSendNotification);
    inflLabel.setColour(juce::Label::textColourId, Pal::dim);
    addAndMakeVisible(inflLabel);
    influence.setSliderStyle(juce::Slider::LinearHorizontal);
    influence.setRange(0.0, 1.0, 0.01);
    influence.setTextBoxStyle(juce::Slider::TextBoxRight, false, 50, 20);
    influence.onValueChange = [this] { if (! syncing) owner.setGlobal("tapInfluence", influence.getValue(), false); };
    addAndMakeVisible(influence);

    log.setMultiLine(true); log.setReadOnly(true); log.setScrollbarsShown(true);
    log.setText("Toque o andamento ou um ritmo e clique em APLICAR TOQUES.\nO primeiro toque e o tempo 1 do compasso.", false);
    addAndMakeVisible(log);
    intent.setMultiLine(true); intent.setReturnKeyStartsNewLine(false);
    intent.setTextToShowWhenEmpty("Ex.: tenso e sombrio, jazz em re dorico, 7/8, 90 bpm, sem bateria", Pal::dim);
    addAndMakeVisible(intent);

    clear.onClick = [this] { taps.clear(); tapInfo.setText("Toques: 0\nBPM: --", juce::dontSendNotification); };
    apply.onClick = [this] { applyTaps(); };
    x2.onClick = [this] { owner.setGlobal("bpm", juce::jlimit(40, 220, (int) owner.getState().getProperty("G", {}).getProperty("bpm", 100) * 2), true); owner.refreshAll(); };
    half.onClick = [this] { owner.setGlobal("bpm", juce::jlimit(40, 220, (int) owner.getState().getProperty("G", {}).getProperty("bpm", 100) / 2), true); owner.refreshAll(); };
    forget.onClick = [this] { owner.proc.getEngine().call("forgetRhythm"); owner.refreshAll(); owner.markDirty(); };
    interpret.onClick = [this] {
        auto r = owner.proc.getEngine().callJson("intent", { intent.getText() });
        juce::StringArray lines;
        if (auto* a = r.getArray()) for (auto& v : *a) lines.add("- " + v.toString());
        log.setText(lines.joinIntoString("\n"), false);
        owner.refreshAll();
        owner.regenerateNow();
    };

    if (auto* a = owner.getMeta().getProperty("presets", {}).getArray())
        for (auto& p : *a)
        {
            auto b = std::make_unique<juce::TextButton>(p.getProperty("name", "").toString());
            const String text = p.getProperty("text", "").toString();
            b->onClick = [this, text] { intent.setText(text, false); interpret.onClick(); };
            addAndMakeVisible(*b);
            presetButtons.push_back(std::move(b));
        }
}

juce::String TapPanel::csv() const
{
    juce::StringArray s;
    for (auto t : taps) s.add(juce::String(t - taps.front(), 4));
    return s.joinIntoString(",");
}

void TapPanel::doTap()
{
    const double now = juce::Time::getMillisecondCounterHiRes() / 1000.0;
    if (! taps.empty() && now - taps.back() > 3.0) taps.clear();
    taps.push_back(now);
    double bpm = 0.0;
    if (taps.size() >= 2) bpm = owner.proc.getEngine().call("liveBpm", { csv() }).getDoubleValue();
    tapInfo.setText("Toques: " + juce::String((int) taps.size()) + "\nBPM: " + (bpm > 0 ? juce::String(bpm, 1) : juce::String("--")),
                    juce::dontSendNotification);
}

void TapPanel::applyTaps()
{
    if (taps.size() < 4) { log.setText("Faca pelo menos 4 toques (o primeiro e o tempo 1).", false); return; }
    auto r = owner.proc.getEngine().callJson("tap", { csv(), mode.getSelectedId() });
    juce::StringArray lines;
    if (auto* a = r.getProperty("log", {}).getArray()) for (auto& v : *a) lines.add(v.toString());
    log.setText(lines.joinIntoString("\n"), false);
    owner.refreshAll();
    if ((bool) r.getProperty("ok", false)) owner.regenerateNow();
}

void TapPanel::sync(const juce::var& state)
{
    const juce::ScopedValueSetter<bool> guard(syncing, true);
    auto G = state.getProperty("G", {});
    influence.setValue((double) G.getProperty("tapInfluence", 0.5), juce::dontSendNotification);
    if (! intent.hasKeyboardFocus(true)) intent.setText(G.getProperty("intent", "").toString(), false);
    rhythm.weights.clear();
    if (auto* w = state.getProperty("tapProfile", {}).getProperty("w", {}).getArray())
        for (auto& v : *w) rhythm.weights.push_back((float) (double) v);
    rhythm.repaint();
}

void TapPanel::tickFlash()
{
    if (pad.flash > 0.0f) { pad.flash = juce::jmax(0.0f, pad.flash - 0.12f); pad.repaint(); }
}

void TapPanel::paint(juce::Graphics& g)
{
    g.setColour(Pal::dim);
    g.setFont(juce::FontOptions(11.0f, juce::Font::bold));
    g.drawText("TAP  -  toque o andamento ou um ritmo", 20, 10, 500, 18, juce::Justification::centredLeft);
    g.drawText("INTENCAO MUSICAL  -  descreva em texto (portugues ou ingles)", 10, 242, 600, 18, juce::Justification::centredLeft);
    g.drawText("ATMOSFERAS PRONTAS", 10, 368, 300, 18, juce::Justification::centredLeft);
    g.setColour(Pal::line);
    g.drawHorizontalLine(236, 10.0f, (float) getWidth() - 10.0f);
}

void TapPanel::resized()
{
    pad.setBounds(20, 36, 190, 190);
    tapInfo.setBounds(225, 36, 120, 40);
    mode.setBounds(350, 40, 280, 26);
    apply.setBounds(225, 84, 150, 28); clear.setBounds(381, 84, 80, 28);
    x2.setBounds(467, 84, 70, 28); half.setBounds(543, 84, 70, 28); forget.setBounds(619, 84, 150, 28);
    inflLabel.setBounds(225, 120, 200, 24); influence.setBounds(430, 120, 340, 24);
    rhythm.setBounds(225, 152, 545, 74);
    log.setBounds(790, 36, getWidth() - 800, 190);
    intent.setBounds(10, 264, 800, 84);
    interpret.setBounds(824, 264, 220, 34);
    for (size_t i = 0; i < presetButtons.size(); ++i)
        presetButtons[i]->setBounds(10 + (int) (i % 5) * 232, 390 + (int) (i / 5) * 38, 226, 32);
}

// ===========================================================================
// OptionsPanel
// ===========================================================================
OptionsPanel::OptionsPanel(CompositorEditor& o) : owner(o)
{
    for (auto* t : { &repeat, &preview, &sendPc }) addAndMakeVisible(*t);
    repeat.onClick = [this] { if (! syncing) owner.proc.repeatOn = repeat.getToggleState(); };
    preview.onClick = [this] { if (! syncing) owner.proc.previewOn = preview.getToggleState(); };
    sendPc.onClick = [this] { if (! syncing) owner.proc.sendProgramChange = sendPc.getToggleState(); };
    offsetLabel.setText("Deslocar o inicio da peca (em tempos)", juce::dontSendNotification);
    offsetLabel.setColour(juce::Label::textColourId, Pal::dim);
    addAndMakeVisible(offsetLabel);
    offset.setSliderStyle(juce::Slider::LinearHorizontal);
    offset.setRange(0.0, 64.0, 0.25);
    offset.setTextBoxStyle(juce::Slider::TextBoxRight, false, 56, 20);
    offset.onValueChange = [this] { if (! syncing) owner.proc.offsetQn = offset.getValue(); };
    addAndMakeVisible(offset);
    for (auto* b : { &exportAll, &openFolder, &reset }) addAndMakeVisible(*b);
    exportAll.getProperties().set("accent", true);
    exportAll.onClick = [this] {
        auto f = CompositorProcessor::getExportFolder().getChildFile(
            "Compositor_" + juce::Time::getCurrentTime().formatted("%Y%m%d_%H%M%S") + ".mid");
        if (owner.proc.exportMidiFile(f, -1)) owner.setStatus("Exportado: " + f.getFullPathName());
        else owner.setStatus("Nao foi possivel exportar o MIDI.");
    };
    openFolder.onClick = [] { CompositorProcessor::getExportFolder().startAsProcess(); };
    reset.onClick = [this] {
        owner.proc.getEngine().call("reset");
        owner.refreshAll();
        owner.regenerateNow();
    };
    help.setJustificationType(juce::Justification::topLeft);
    help.setFont(juce::FontOptions(13.0f));
    help.setColour(juce::Label::textColourId, Pal::dim);
    help.setText(
        "COMO USAR NO REAPER\n"
        "1. Coloque este plugin numa faixa e, depois dele, um instrumento (VSTi) na mesma faixa. O MIDI gerado passa para o proximo plugin.\n"
        "2. Aperte play: a peca toca sincronizada ao projeto e repete em loop (desligue 'Repetir' para tocar uma vez).\n"
        "3. Para usar um sintetizador diferente em cada instrumento, deixe cada instrumento em um canal MIDI proprio e crie faixas com\n"
        "    envio de MIDI (send) filtrando o canal, ou arraste o .mid (botao 'MID' de cada linha na faixa de baixo) para novas faixas.\n"
        "4. Para gravar o MIDI na faixa: arraste o .mid para o arranjo, ou exporte e importe (Insert > Media file).\n"
        "5. O BPM e o compasso do projeto mandam na reproducao; o campo BPM do plugin e so referencia para o .mid exportado.", juce::dontSendNotification);
    addAndMakeVisible(help);
}

void OptionsPanel::sync()
{
    const juce::ScopedValueSetter<bool> guard(syncing, true);
    repeat.setToggleState(owner.proc.repeatOn.load(), juce::dontSendNotification);
    preview.setToggleState(owner.proc.previewOn.load(), juce::dontSendNotification);
    sendPc.setToggleState(owner.proc.sendProgramChange.load(), juce::dontSendNotification);
    offset.setValue(owner.proc.offsetQn.load(), juce::dontSendNotification);
}

void OptionsPanel::resized()
{
    repeat.setBounds(14, 14, 340, 26);
    preview.setBounds(14, 46, 340, 26);
    sendPc.setBounds(14, 78, 340, 26);
    offsetLabel.setBounds(14, 112, 300, 24);
    offset.setBounds(320, 114, 420, 24);
    exportAll.setBounds(14, 152, 300, 34);
    openFolder.setBounds(322, 152, 150, 34);
    reset.setBounds(480, 152, 190, 34);
    help.setBounds(14, 206, getWidth() - 28, 300);
}

// ===========================================================================
// SongStrip: regua de compassos + acordes (cor = filosofia) + uma pista por instrumento
// ===========================================================================
juce::Rectangle<int> SongStrip::laneRect(int lane) const
{
    const int top = rulerH + chordH + 4;
    const int n = seq ? (int) seq->tracks.size() : 1;
    const int h = juce::jmin(18, (getHeight() - top - 4) / juce::jmax(1, n));
    return { 0, top + lane * h, getWidth(), h };
}

void SongStrip::paint(juce::Graphics& g)
{
    g.fillAll(Pal::bg0);
    g.setColour(Pal::line);
    g.drawHorizontalLine(0, 0.0f, (float) getWidth());
    if (! seq || seq->tracks.empty())
    {
        g.setColour(Pal::dim);
        g.setFont(juce::FontOptions(13.0f));
        g.drawText("Nenhum instrumento ligado. Ligue um na aba INSTRUMENTOS.", getLocalBounds(), juce::Justification::centred);
        return;
    }
    const int tx = labelW, tw = getWidth() - labelW - 8;
    const double total = seq->total;
    auto X = [&](double qn) { return tx + (float) (qn / total * tw); };

    // canto: arrastar o arranjo inteiro
    auto corner = juce::Rectangle<int>(6, 3, labelW - 12, rulerH + chordH - 4);
    g.setColour(Pal::panel2);
    g.fillRoundedRectangle(corner.toFloat(), 5.0f);
    g.setColour(Pal::amber);
    g.drawRoundedRectangle(corner.toFloat(), 5.0f, 1.0f);
    g.setFont(juce::FontOptions(11.0f, juce::Font::bold));
    g.drawText("ARRASTE O MIDI (TUDO)", corner, juce::Justification::centred);

    // compassos
    g.setFont(juce::FontOptions(10.0f));
    for (size_t i = 0; i < seq->bars.size(); ++i)
    {
        auto& b = seq->bars[i];
        const float x0 = X(b.t0), x1 = X(b.t0 + b.len);
        g.setColour(((i % 2) ? Pal::panel : Pal::panel2).withAlpha(0.6f));
        g.fillRect(x0, 1.0f, x1 - x0, (float) rulerH - 2.0f);
        g.setColour(Pal::dim);
        g.drawText(String((int) i + 1), (int) x0 + 3, 0, 40, rulerH, juce::Justification::centredLeft);
    }
    // acordes
    g.setFont(juce::FontOptions(11.0f, juce::Font::bold));
    for (auto& c : seq->chords)
    {
        auto r = juce::Rectangle<float>(X(c.t0) + 1.0f, (float) rulerH + 2.0f, X(c.t0 + c.len) - X(c.t0) - 2.0f, (float) chordH - 3.0f);
        g.setColour(Pal::philoColour(c.philo).withAlpha(0.85f));
        g.fillRoundedRectangle(r, 4.0f);
        g.setColour(Pal::bg0);
        g.drawFittedText(c.name, r.toNearestInt().reduced(3, 0), juce::Justification::centredLeft, 1, 0.8f);
    }
    // pistas
    const auto mute = owner.proc.muteMask.load(), solo = owner.proc.soloMask.load();
    for (size_t t = 0; t < seq->tracks.size(); ++t)
    {
        auto lr = laneRect((int) t);
        auto& tr = seq->tracks[t];
        const int inst = seq->trackInstrument[t];
        const auto col = Pal::instrumentColour(tr.id);
        g.setColour(t % 2 ? Pal::bg1 : Pal::bg0.brighter(0.04f));
        g.fillRect(lr);
        const bool audible = ! (mute & (1u << inst)) && (solo == 0 || (solo & (1u << inst)));
        g.setColour(audible ? col : col.withAlpha(0.3f));
        g.fillEllipse(8.0f, (float) lr.getCentreY() - 3.0f, 6.0f, 6.0f);
        g.setColour(audible ? Pal::text : Pal::dim);
        g.setFont(juce::FontOptions(11.0f));
        g.drawText(tr.label, 20, lr.getY(), labelW - 100, lr.getHeight(), juce::Justification::centredLeft, true);
        // M / S / grip
        auto mR = juce::Rectangle<int>(labelW - 76, lr.getY() + 1, 18, lr.getHeight() - 2);
        auto sR = mR.translated(21, 0), gR = juce::Rectangle<int>(labelW - 31, lr.getY() + 1, 26, lr.getHeight() - 2);
        g.setColour((mute & (1u << inst)) ? Pal::red : Pal::panel2); g.fillRoundedRectangle(mR.toFloat(), 3.0f);
        g.setColour((solo & (1u << inst)) ? Pal::amber : Pal::panel2); g.fillRoundedRectangle(sR.toFloat(), 3.0f);
        g.setColour(Pal::panel2); g.fillRoundedRectangle(gR.toFloat(), 3.0f);
        g.setFont(juce::FontOptions(9.5f, juce::Font::bold));
        g.setColour((mute & (1u << inst)) ? Pal::bg0 : Pal::dim); g.drawText("M", mR, juce::Justification::centred);
        g.setColour((solo & (1u << inst)) ? Pal::bg0 : Pal::dim); g.drawText("S", sR, juce::Justification::centred);
        g.setColour(Pal::amber); g.drawText("MID", gR, juce::Justification::centred);

        int lo = 127, hi = 0;
        for (size_t i = 0; i + 3 < tr.notes.size(); i += 4) { lo = juce::jmin(lo, (int) tr.notes[i + 2]); hi = juce::jmax(hi, (int) tr.notes[i + 2]); }
        hi = juce::jmax(hi, lo + 7);
        g.setColour(audible ? col : col.withAlpha(0.25f));
        for (size_t i = 0; i + 3 < tr.notes.size(); i += 4)
        {
            const float x0 = X(tr.notes[i]);
            const float w = juce::jmax(1.5f, X(tr.notes[i] + tr.notes[i + 1]) - x0);
            const float y = lr.getBottom() - 2.0f - (tr.notes[i + 2] - lo) / (float) (hi - lo) * (float) (lr.getHeight() - 5);
            g.fillRect(x0, y - 1.0f, w, 2.0f);
        }
    }
    // linhas de compasso e cabeca de reproducao
    const int bottom = laneRect((int) seq->tracks.size() - 1).getBottom();
    g.setColour(Pal::line.withAlpha(0.7f));
    for (auto& b : seq->bars) g.drawVerticalLine((int) X(b.t0), (float) rulerH, (float) bottom);
    if (owner.proc.uiPlaying.load())
    {
        const float x = X(owner.proc.uiRelQn.load());
        g.setColour(Pal::amberHi);
        g.fillRect(x - 1.0f, 0.0f, 2.0f, (float) bottom);
        juce::Path tri; tri.addTriangle(x - 5.0f, 0.0f, x + 5.0f, 0.0f, x, 7.0f);
        g.fillPath(tri);
    }
}

void SongStrip::mouseDown(const juce::MouseEvent& e)
{
    dragInst = -2;
    if (! seq) return;
    auto p = e.getPosition();
    if (p.y < rulerH + chordH && p.x < labelW) { dragInst = -1; return; }
    for (size_t t = 0; t < seq->tracks.size(); ++t)
    {
        auto lr = laneRect((int) t);
        if (! lr.contains(p)) continue;
        const int inst = seq->trackInstrument[t];
        const juce::uint32 bit = 1u << inst;
        if (p.x >= labelW - 76 && p.x < labelW - 58) { owner.proc.muteMask ^= bit; repaint(); }
        else if (p.x >= labelW - 55 && p.x < labelW - 37) { owner.proc.soloMask ^= bit; repaint(); }
        else if (p.x >= labelW - 31 && p.x < labelW - 5) dragInst = (int) t;
        return;
    }
}

void SongStrip::mouseDrag(const juce::MouseEvent& e)
{
    if (dragInst == -2 || e.getDistanceFromDragStart() < 6 || ! seq) return;
    const int which = dragInst;
    dragInst = -2;
    String name = "Compositor_arranjo";
    int inst = -1;
    if (which >= 0)
    {
        name = "Compositor_" + seq->tracks[(size_t) which].id;
        inst = seq->trackInstrument[(size_t) which];
    }
    auto file = CompositorProcessor::getTempFolder().getChildFile(name + ".mid");
    if (! owner.proc.exportMidiFile(file, inst)) { owner.setStatus("Nao foi possivel criar o MIDI para arrastar."); return; }
    if (auto* dc = juce::DragAndDropContainer::findParentDragContainerFor(this))
        dc->performExternalDragDropOfFiles(juce::StringArray(file.getFullPathName()), false, this);
}

// ===========================================================================
// CompositorEditor
// ===========================================================================
CompositorEditor::CompositorEditor(CompositorProcessor& p)
    : AudioProcessorEditor(&p), proc(p),
      geral(*this, "geral"), harmonia(*this, "harmonia"), instruments(*this), tap(*this), options(*this), strip(*this)
{
    setLookAndFeel(&look);
    setSize(1200, 880);

    static const char* names[5] = { "GERAL", "HARMONIA", "INSTRUMENTOS", "TAP E INTENCAO", "OPCOES" };
    for (int i = 0; i < 5; ++i)
    {
        tabButtons[i].setButtonText(names[i]);
        tabButtons[i].getProperties().set("tab", true);
        tabButtons[i].onClick = [this, i] { showTab(i); };
        addAndMakeVisible(tabButtons[i]);
    }
    generate.getProperties().set("accent", true);
    generate.onClick = [this] { regenerateNow(); };
    newVersion.onClick = [this] {
        setGlobal("seed", juce::Random::getSystemRandom().nextInt(juce::Range<int>(1, 999999)), true);
        refreshAll();
        regenerateNow();
    };
    autoToggle.setToggleState(true, juce::dontSendNotification);
    autoToggle.onClick = [this] { autoGen = autoToggle.getToggleState(); };
    seedLabel.setColour(juce::Label::textColourId, Pal::dim);
    seedLabel.setJustificationType(juce::Justification::centredRight);
    seedLabel.setFont(juce::FontOptions(12.5f));
    for (auto* c : std::initializer_list<juce::Component*>{ &generate, &newVersion, &autoToggle, &seedLabel, &geral, &harmonia,
                                                             &instruments, &tap, &options, &planView, &strip })
        addAndMakeVisible(*c);

    planView.setMultiLine(true);
    planView.setReadOnly(true);
    planView.setScrollbarsShown(true);
    planView.setFont(juce::FontOptions(juce::Font::getDefaultMonospacedFontName(), 13.0f, juce::Font::plain));

    refreshAll();
    lastGeneration = proc.getGeneration();
    strip.setSequence(proc.getSequence());
    updateHarmonyView();
    status = "Pronto. Aperte play no REAPER: a musica toca sincronizada ao projeto.";
    showTab(0);
    startTimerHz(30);
}

CompositorEditor::~CompositorEditor()
{
    stopTimer();
    setLookAndFeel(nullptr);
}

void CompositorEditor::showTab(int i)
{
    currentTab = i;
    for (int k = 0; k < 5; ++k) tabButtons[k].setToggleState(k == i, juce::dontSendNotification);
    geral.setVisible(i == 0);
    harmonia.setVisible(i == 1);
    planView.setVisible(i == 1);
    instruments.setVisible(i == 2);
    tap.setVisible(i == 3);
    options.setVisible(i == 4);
    repaint();
}

void CompositorEditor::refreshAll()
{
    state = proc.getEngine().callJson("state");
    auto G = state.getProperty("G", {});
    geral.sync(G);
    harmonia.sync(G);
    instruments.sync(state.getProperty("P", {}));
    tap.sync(state);
    options.sync();
    seedLabel.setText("Semente " + juce::String((int) G.getProperty("seed", 0)), juce::dontSendNotification);
}

void CompositorEditor::setGlobal(const juce::String& key, const juce::var& v, bool isInt)
{
    proc.getEngine().set("G", key, v, isInt);
    if (auto* o = state.getProperty("G", {}).getDynamicObject()) o->setProperty(key, v);
    auto G = state.getProperty("G", {});
    if (key == "meterIdx" || key == "philo") { geral.sync(G); harmonia.sync(G); }
    if (key == "seed") seedLabel.setText("Semente " + juce::String((int) v), juce::dontSendNotification);
    markDirty();
}

void CompositorEditor::setInstr(const juce::String& id, const juce::String& key, const juce::var& v, bool isInt)
{
    proc.getEngine().set(id, key, v, isInt);
    if (auto* o = state.getProperty("P", {}).getProperty(id, {}).getDynamicObject()) o->setProperty(key, v);
    markDirty();
}

void CompositorEditor::markDirty()
{
    if (autoGen) dirtyCountdown = 12;
    else setStatus("Alteracoes pendentes: clique em GERAR.");
}

void CompositorEditor::regenerateNow()
{
    proc.regenerate();
    lastGeneration = proc.getGeneration();
    auto seq = proc.getSequence();
    strip.setSequence(seq);
    updateHarmonyView();
    dirtyCountdown = 0;
    if (seq)
    {
        int notes = 0;
        for (auto& t : seq->tracks) notes += (int) t.notes.size() / 4;
        status = juce::String((int) seq->tracks.size()) + " trilhas, " + juce::String(notes) + " notas, "
               + juce::String((int) seq->bars.size()) + " compassos (" + juce::String(seq->tsNum) + "/" + juce::String(seq->tsDen) + ")";
    }
    repaint();
}

void CompositorEditor::updateHarmonyView()
{
    auto seq = proc.getSequence();
    if (! seq) return;
    juce::String t = "Progressao (A, B... = frases; Ton/Mod/Exp = filosofia):\n";
    for (auto& l : seq->planLines) t << "  " << l << "\n";
    t << "\nEscala local de cada acorde:\n";
    int n = 0;
    for (auto& c : seq->chords)
    {
        int bar = 1;
        for (size_t i = 0; i < seq->bars.size(); ++i) if (c.t0 >= seq->bars[i].t0 - 1.0e-6) bar = (int) i + 1;
        t << "  comp. " << juce::String(bar).paddedLeft(' ', 2) << ": " << c.name.paddedRight(' ', 14) << " -> " << c.scale << "\n";
        if (++n >= 40) { t << "  ...\n"; break; }
    }
    planView.setText(t, false);
}

void CompositorEditor::timerCallback()
{
    tap.tickFlash();
    if (dirtyCountdown > 0 && --dirtyCountdown == 0) regenerateNow();
    if (proc.getGeneration() != lastGeneration)
    {
        lastGeneration = proc.getGeneration();
        strip.setSequence(proc.getSequence());
        updateHarmonyView();
    }
    static bool wasPlaying = false;
    const bool playing = proc.uiPlaying.load();
    if (playing || wasPlaying) strip.repaint();
    wasPlaying = playing;
}

void CompositorEditor::paint(juce::Graphics& g)
{
    g.fillAll(Pal::bg1);
    auto top = getLocalBounds().removeFromTop(56);
    g.setGradientFill(juce::ColourGradient(Pal::bg0.brighter(0.05f), 0, 0, Pal::bg0, 0, 56, false));
    g.fillRect(top);
    g.setColour(Pal::amber);
    g.fillRect(0, 55, getWidth(), 2);
    g.setFont(juce::FontOptions(24.0f, juce::Font::bold));
    g.setColour(Pal::amber);
    g.drawText("COMPOSITOR", 18, 6, 220, 30, juce::Justification::centredLeft);
    g.setFont(juce::FontOptions(11.0f, juce::Font::bold));
    g.setColour(Pal::dim);
    g.drawText("MIDI LIVRE  -  HARMONIA POR ESCALAS", 20, 34, 260, 16, juce::Justification::centredLeft);

    auto content = juce::Rectangle<int>(8, 62, getWidth() - 16, getHeight() - 62 - 230 - 30);
    g.setColour(Pal::panel);
    g.fillRoundedRectangle(content.toFloat(), 8.0f);

    auto bar = getLocalBounds().removeFromBottom(26);
    g.setColour(Pal::bg0);
    g.fillRect(bar);
    g.setColour(Pal::text);
    g.setFont(juce::FontOptions(12.5f));
    g.drawText(status, bar.reduced(12, 0).withTrimmedRight(520), juce::Justification::centredLeft, true);
    g.setColour(Pal::dim);
    g.drawText("BPM do host: " + juce::String(proc.uiHostBpm.load(), 1) + "   |   " + (proc.uiPlaying.load() ? "tocando" : "parado"),
               bar.reduced(12, 0), juce::Justification::centredRight);
}

void CompositorEditor::resized()
{
    const int w = getWidth(), h = getHeight();
    static const int tabW[5] = { 88, 104, 130, 150, 80 };
    int x = 236;
    for (int i = 0; i < 5; ++i) { tabButtons[i].setBounds(x, 12, tabW[i], 44); x += tabW[i] + 4; }
    generate.setBounds(w - 160, 12, 144, 32);
    newVersion.setBounds(w - 322, 12, 152, 32);
    autoToggle.setBounds(w - 392, 15, 66, 26);
    seedLabel.setBounds(w - 480, h - 26, 190, 26);

    auto content = juce::Rectangle<int>(8, 62, w - 16, h - 62 - 230 - 30).reduced(6);
    geral.setBounds(content);
    harmonia.setBounds(content.withHeight(250));
    planView.setBounds(content.withTrimmedTop(256).reduced(4));
    instruments.setBounds(content);
    tap.setBounds(content);
    options.setBounds(content);
    strip.setBounds(0, h - 26 - 230, w, 230);
}
