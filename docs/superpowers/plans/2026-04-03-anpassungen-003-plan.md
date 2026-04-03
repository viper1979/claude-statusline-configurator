# Anpassungen 003 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vier Änderungen am Statusline-Konfigurator: zwei Bugfixes (doppelte IDs, Theme-FG/Progressbar) und zwei Features (Emoji-Picker, konfigurierbarer Progressbar-Preview-Wert).

**Architecture:** Alle Änderungen in `statusline-configurator.html` (Single-File, kein Build-Schritt). JS-Logik ist inline im `<script>`-Tag. Kein Test-Framework für den JS-Teil — Verifikation erfolgt manuell im Browser durch Öffnen der HTML-Datei.

**Tech Stack:** Vanilla JS, HTML, CSS (kein Framework, kein Build). Pester für PS-Tests (nicht betroffen).

---

## File Structure

Nur eine Datei wird modifiziert:

- **Modify:** `statusline-configurator.html`
  - Task 1: `syncIdCounter()` nach `generateId()` einfügen; Aufruf in `loadConfig()`
  - Task 2: Guard in `applyTheme()` für Progressbar-Felder
  - Task 3: `renderFieldHtml()` um `previewOverride`-Parameter erweitern; neue Hilfsfunktionen `renderProgressbarPreview()` / `updateProgressbarPreview()`; Zahlenfeld + Preview im Progressbar-Branch von `renderEditTabGeneral()`; `delete _editDraft.previewValue` in `saveEditDialog()`
  - Task 4: `EMOJI_LIST`-Konstante; Emoji-Picker-HTML-Div; Picker-Hilfsfunktionen; Button in `renderEditTabGeneral()` Palette-Branch

---

## Task 1: Bugfix — Doppelte IDs nach loadConfig()

**Files:**
- Modify: `statusline-configurator.html` (~Zeile 411 und ~Zeile 1185)

### Problem verstehen

Nach `loadConfig()` werden Lines und Fields mit `generateId()` neu-ID'd (zählt `_idCounter` hoch). Custom Fields behalten ihre gespeicherte `id` aus der JSON (z.B. `id-36`). `_idCounter` kennt den höchsten vorhandenen Wert danach nicht — beim nächsten `generateId()`-Aufruf kann dieselbe ID vergeben werden.

- [ ] **Schritt 1: `syncIdCounter()` direkt nach `generateId()` einfügen (~Zeile 411)**

Suche die Stelle:
```javascript
let _idCounter = 0;
function generateId() { return 'id-' + (++_idCounter); }
```

Füge direkt danach ein:
```javascript
/**
 * Synchronises _idCounter to the highest numeric suffix found across all IDs
 * in the loaded state. Call after loadConfig() to prevent ID collisions when
 * new fields are added after loading a saved configuration.
 * @param {object} state
 */
function syncIdCounter(state) {
  const allIds = [
    ...state.lines.map(l => l.id),
    ...state.lines.flatMap(l => l.fields.map(f => f.id)),
    ...state.customFields.map(cf => cf.id),
    ...state.themes.map(t => t.id),
  ];
  let max = _idCounter;
  for (const id of allIds) {
    const match = id && id.match(/^id-(\d+)$/);
    if (match) max = Math.max(max, parseInt(match[1], 10));
  }
  _idCounter = max;
}
```

- [ ] **Schritt 2: `syncIdCounter(state)` in `loadConfig()` aufrufen (~Zeile 1185)**

Suche am Ende von `loadConfig()`:
```javascript
  // knownKeys: not stored in state — rebuilt on every export from AVAILABLE_FIELDS

  render();
}
```

Ändere zu:
```javascript
  // knownKeys: not stored in state — rebuilt on every export from AVAILABLE_FIELDS

  syncIdCounter(state);
  render();
}
```

- [ ] **Schritt 3: Manuell im Browser verifizieren**

1. `statusline-configurator.html` im Browser öffnen
2. Eine Konfiguration laden die viele Custom Fields enthält (z.B. `statusline-config(1).json`)
3. Ein neues Custom Field über "+ Feld" anlegen
4. Prüfen dass das neue Feld korrekt in die Palette erscheint und beim Drag auf eine Zeile das richtige Feld gezogen wird (kein Alias-Effekt mehr)
5. Konsole öffnen — keine `id-XX`-Kollision-Warnungen

- [ ] **Schritt 4: Committen**

```bash
git add statusline-configurator.html
git commit -m "fix(configurator): sync _idCounter after loadConfig to prevent duplicate field IDs"
```

---

## Task 2: Bugfix — Theme Foreground Color überschreibt Progressbar-Threshold-Farben

**Files:**
- Modify: `statusline-configurator.html` (~Zeile 849)

### Problem verstehen

`applyTheme()` schreibt `theme.fieldFg` auf `field.fg` aller Felder inkl. Progressbars. `renderFieldHtml()` liest `barFgOverride = field.fg ?? null` — ist das gesetzt, werden Threshold-Farben ignoriert.

- [ ] **Schritt 1: Guard in `applyTheme()` einfügen (~Zeile 849)**

Suche:
```javascript
  state.lines.forEach(line => {
    line.fields.forEach(field => {
      if (theme.fieldFg !== null) field.fg = theme.fieldFg;
      if (theme.fieldBg !== null) field.bg = theme.fieldBg;
    });
  });
```

Ändere zu:
```javascript
  state.lines.forEach(line => {
    line.fields.forEach(field => {
      if (field.type === 'progressbar') return; // Theme fieldFg must not suppress threshold colors
      if (theme.fieldFg !== null) field.fg = theme.fieldFg;
      if (theme.fieldBg !== null) field.bg = theme.fieldBg;
    });
  });
```

- [ ] **Schritt 2: Manuell im Browser verifizieren**

1. Konfiguration mit einer Progressbar (z.B. `context_window.used_percentage`) laden
2. Ein Theme mit einer Foreground Color (z.B. Blau `#3b82f6`) anlegen und "Anwenden" klicken
3. Prüfen dass andere Felder blau werden, die Progressbar aber weiterhin grün/gelb/rot (Threshold-Farben) zeigt
4. In den Farben-Tab der Progressbar wechseln: `fg` ist weiterhin leer (nicht überschrieben)

- [ ] **Schritt 3: Committen**

```bash
git add statusline-configurator.html
git commit -m "fix(configurator): applyTheme must not override progressbar threshold colors"
```

---

## Task 3: Feature — Konfigurierbarer Progressbar Preview-Wert

**Files:**
- Modify: `statusline-configurator.html` (Zeilen ~1683, ~1290, ~1574, nach ~1574)

### Überblick

- `renderFieldHtml()` erhält optionalen Parameter `previewOverride` (Zahl 0–100)
- Im Progressbar-Branch von `renderEditTabGeneral()`: Zahlenfeld + Inline-Preview-Span
- `updateProgressbarPreview(value)`: Aktualisiert `_editDraft.previewValue` + Preview-Span
- `renderProgressbarPreview(value)`: Rendert Progressbar mit given value via `renderFieldHtml()`
- `saveEditDialog()`: Löscht `_editDraft.previewValue` vor dem Speichern (nicht persistiert)

- [ ] **Schritt 1: `renderFieldHtml()` um `previewOverride` erweitern (~Zeile 1683)**

Suche:
```javascript
function renderFieldHtml(field, data, previewTheme = null) {
  const fg = field.fg ?? previewTheme?.fieldFg ?? null;
  const bg = field.bg ?? previewTheme?.fieldBg ?? null;
  const style = [fg ? `color:${fg};` : '', bg ? `background:${bg};padding:1px 3px;` : ''].join('');

  if (field.type === 'static') {
    return `<span style="${style}">${escapeHtml(field.text || '')}</span>`;
  }

  if (field.type === 'new_fields_indicator') {
    return `<span style="${style}">● Neue Felder (Indikator)</span>`;
  }

  const raw = getNestedValue(data, field.key);
```

Ändere zu:
```javascript
function renderFieldHtml(field, data, previewTheme = null, previewOverride = null) {
  const fg = field.fg ?? previewTheme?.fieldFg ?? null;
  const bg = field.bg ?? previewTheme?.fieldBg ?? null;
  const style = [fg ? `color:${fg};` : '', bg ? `background:${bg};padding:1px 3px;` : ''].join('');

  if (field.type === 'static') {
    return `<span style="${style}">${escapeHtml(field.text || '')}</span>`;
  }

  if (field.type === 'new_fields_indicator') {
    return `<span style="${style}">● Neue Felder (Indikator)</span>`;
  }

  // Use previewOverride as raw value for progressbar when set (e.g. from edit dialog preview)
  const raw = (field.type === 'progressbar' && previewOverride !== null)
    ? previewOverride
    : getNestedValue(data, field.key);
```

- [ ] **Schritt 2: Hilfsfunktionen `renderProgressbarPreview()` und `updateProgressbarPreview()` nach `saveEditDialog()` einfügen (~nach Zeile 1574)**

Suche:
```javascript
  closeEditDialog();
  render();
}

// ─── Progress bar rendering ───────────────────────────────────────────────
```

Füge zwischen den beiden Blöcken ein:
```javascript
  closeEditDialog();
  render();
}

/**
 * Renders the edit draft field as a progressbar HTML snippet using the given
 * preview value. Used by the dialog's inline preview. Returns an empty string
 * if no draft is active.
 * @param {number} value - 0 to 100
 * @returns {string} HTML snippet
 */
function renderProgressbarPreview(value) {
  if (!_editDraft) return '';
  const activeThemeObj = (() => {
    const id = _themePreviewId ?? state.activeTheme;
    return id ? state.themes.find(t => t.id === id) || null : null;
  })();
  return renderFieldHtml(_editDraft, SAMPLE_DATA, activeThemeObj, value);
}

/**
 * Called by the preview-value number input in the progressbar edit dialog.
 * Clamps the value to [0, 100], stores it in _editDraft.previewValue, and
 * updates the inline preview span.
 * @param {string|number} rawValue - value from the input element
 */
function updateProgressbarPreview(rawValue) {
  const v = Math.min(100, Math.max(0, parseInt(rawValue, 10) || 0));
  if (_editDraft) _editDraft.previewValue = v;
  const displayEl = document.getElementById('edit-pb-preview-display');
  if (displayEl) displayEl.innerHTML = renderProgressbarPreview(v);
}

// ─── Progress bar rendering ───────────────────────────────────────────────
```

- [ ] **Schritt 3: Zahlenfeld + Preview im Progressbar-Branch von `renderEditTabGeneral()` einfügen (~Zeile 1303)**

Suche den Beginn des Template-Literals im Progressbar-Branch:
```javascript
    el.innerHTML = `
      <div style="margin-bottom:10px;">
        <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:6px;">Farbe</div>
```

Ändere zu:
```javascript
    const initialPreviewValue = f.previewValue ?? Math.round(getNestedValue(SAMPLE_DATA, f.key) ?? 50);
    el.innerHTML = `
      <div style="margin-bottom:12px;display:flex;align-items:center;gap:10px;">
        <div>
          <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:4px;">Vorschau-Wert (%)</div>
          <input type="number" id="edit-pb-preview-value" min="0" max="100" step="1"
            value="${initialPreviewValue}"
            oninput="updateProgressbarPreview(this.value)"
            style="width:72px;padding:4px 6px;border-radius:4px;border:1px solid var(--color-border);
              background:var(--color-surface-2);color:var(--color-text);font-size:12px;">
        </div>
        <div>
          <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:4px;">Vorschau</div>
          <span id="edit-pb-preview-display" style="font-family:monospace;font-size:12px;">
            ${renderProgressbarPreview(initialPreviewValue)}
          </span>
        </div>
      </div>
      <div style="margin-bottom:10px;">
        <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:6px;">Farbe</div>
```

**Hinweis:** `renderProgressbarPreview()` ruft `renderFieldHtml()` auf, das wiederum `_editDraft` als Feld nutzt. Da `_editDraft` beim Rendern des Tabs bereits gesetzt ist, funktioniert das korrekt. `renderFieldHtml()` muss vor `renderEditTabGeneral()` im Skript stehen — das ist aktuell der Fall (Zeile ~1683 vs. ~1256), aber nach der Refaktorierung stehen die neuen Hilfsfunktionen _nach_ `saveEditDialog()`. Da alle Funktionen per Hoisting im gleichen `<script>`-Block verfügbar sind, ist das kein Problem.

- [ ] **Schritt 4: `previewValue` in `saveEditDialog()` löschen (~Zeile 1505)**

Suche:
```javascript
function saveEditDialog() {
  if (!_editCtx || !_editDraft) return;
  const { source, lineId } = _editCtx;
```

Ändere zu:
```javascript
function saveEditDialog() {
  if (!_editCtx || !_editDraft) return;
  // previewValue is ephemeral UI state — never persisted to the real field objects
  delete _editDraft.previewValue;
  const { source, lineId } = _editCtx;
```

- [ ] **Schritt 5: Manuell im Browser verifizieren**

1. HTML im Browser öffnen
2. Eine Progressbar-Field (z.B. `context_window.used_percentage`) auf eine Zeile ziehen
3. Bleistift-Icon klicken → Edit-Dialog öffnet sich
4. Im Tab "Allgemein": Zahlenfeld "Vorschau-Wert (%)" und Vorschau-Span sind sichtbar
5. Wert auf `10` setzen → Progressbar zeigt 10% in Grün
6. Wert auf `60` setzen → Progressbar zeigt 60% in Gelb
7. Wert auf `90` setzen → Progressbar zeigt 90% in Rot
8. Speichern klicken → Hauptvorschau zeigt weiterhin SAMPLE_DATA-Wert (keine Persistenz)
9. Dialog erneut öffnen → Zahlenfeld zeigt wieder SAMPLE_DATA-Wert als Default

- [ ] **Schritt 6: Committen**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): add configurable preview value for progressbar in edit dialog"
```

---

## Task 4: Feature — Emoji-Picker im Edit-Dialog

**Files:**
- Modify: `statusline-configurator.html` (HTML-Bereich nach Edit-Dialog, JS-Bereich nach Picker-Hilfsfunktionen)

### Überblick

- `EMOJI_LIST`: Konstante mit ~150 kuratierten Emojis in 6 Kategorien
- Picker-HTML: verstecktes `<div id="emoji-picker">` nach dem Edit-Dialog-Block
- Picker-Funktionen: `openEmojiPicker()`, `closeEmojiPicker()`, `filterAndRenderEmojis()`, `insertEmojiAtCursor()`
- Button `😊` im Palette-Branch von `renderEditTabGeneral()` neben dem Text-Input

- [ ] **Schritt 1: `EMOJI_LIST`-Konstante nach `SAMPLE_DATA` einfügen (~nach Zeile 405)**

Suche:
```javascript
// ─── ID generation ────────────────────────────────────────────────────────

let _idCounter = 0;
```

Füge davor ein:
```javascript
// ─── Emoji list for the emoji picker (curated for Windows Terminal compatibility) ────

const EMOJI_LIST = [
  { category: 'Symbole & Zeichen', emojis: [
    { emoji: '✓', name: 'check mark done' },
    { emoji: '✗', name: 'cross x error wrong' },
    { emoji: '★', name: 'star filled' },
    { emoji: '☆', name: 'star outline' },
    { emoji: '♦', name: 'diamond' },
    { emoji: '♠', name: 'spade' },
    { emoji: '♣', name: 'club' },
    { emoji: '♥', name: 'heart love' },
    { emoji: '©', name: 'copyright' },
    { emoji: '®', name: 'registered trademark' },
    { emoji: '™', name: 'trademark' },
    { emoji: '℃', name: 'celsius temperature degree' },
    { emoji: '℉', name: 'fahrenheit temperature degree' },
    { emoji: '№', name: 'numero number' },
    { emoji: 'µ', name: 'micro mu unit' },
    { emoji: '§', name: 'section paragraph law' },
    { emoji: '¶', name: 'pilcrow paragraph' },
    { emoji: '∞', name: 'infinity unlimited' },
    { emoji: '≈', name: 'approximately equal similar' },
    { emoji: '≠', name: 'not equal unequal' },
    { emoji: '±', name: 'plus minus' },
    { emoji: '÷', name: 'divide division' },
    { emoji: '×', name: 'multiply multiplication times' },
    { emoji: '•', name: 'bullet dot point' },
    { emoji: '◦', name: 'bullet outline circle' },
    { emoji: '▪', name: 'square small black filled' },
    { emoji: '▫', name: 'square small white outline' },
  ]},
  { category: 'Pfeile', emojis: [
    { emoji: '→', name: 'arrow right' },
    { emoji: '←', name: 'arrow left' },
    { emoji: '↑', name: 'arrow up' },
    { emoji: '↓', name: 'arrow down' },
    { emoji: '↔', name: 'arrow left right horizontal' },
    { emoji: '↕', name: 'arrow up down vertical' },
    { emoji: '⇒', name: 'double arrow right bold' },
    { emoji: '⇐', name: 'double arrow left bold' },
    { emoji: '⇑', name: 'double arrow up bold' },
    { emoji: '⇓', name: 'double arrow down bold' },
    { emoji: '➜', name: 'arrow right curved' },
    { emoji: '➔', name: 'arrow right heavy thick' },
    { emoji: '↩', name: 'arrow return back' },
    { emoji: '↪', name: 'arrow return forward' },
    { emoji: '↖', name: 'arrow upper left diagonal' },
    { emoji: '↗', name: 'arrow upper right diagonal' },
    { emoji: '↘', name: 'arrow lower right diagonal' },
    { emoji: '↙', name: 'arrow lower left diagonal' },
  ]},
  { category: 'Technik & Tools', emojis: [
    { emoji: '⚙', name: 'gear settings config' },
    { emoji: '🔧', name: 'wrench tool fix' },
    { emoji: '🔨', name: 'hammer tool build' },
    { emoji: '💻', name: 'laptop computer coding' },
    { emoji: '🖥', name: 'desktop monitor computer screen' },
    { emoji: '🖨', name: 'printer print' },
    { emoji: '📡', name: 'satellite antenna signal network' },
    { emoji: '🔌', name: 'plug power electric connect' },
    { emoji: '💾', name: 'floppy disk save storage' },
    { emoji: '📁', name: 'folder directory file' },
    { emoji: '📂', name: 'folder open directory file' },
    { emoji: '🔑', name: 'key access login auth' },
    { emoji: '🔒', name: 'lock locked security private' },
    { emoji: '🔓', name: 'lock unlocked security open' },
    { emoji: '📋', name: 'clipboard copy paste' },
    { emoji: '📌', name: 'pin pushpin location mark' },
    { emoji: '🔍', name: 'magnifier search find zoom' },
    { emoji: '📊', name: 'chart bar graph stats' },
    { emoji: '📈', name: 'chart up trending increase' },
    { emoji: '📉', name: 'chart down trending decrease' },
    { emoji: '⌨', name: 'keyboard type input' },
    { emoji: '🖱', name: 'mouse computer cursor' },
    { emoji: '💿', name: 'cd disc optical media' },
    { emoji: '📀', name: 'dvd disc optical media' },
  ]},
  { category: 'Energie & Wetter', emojis: [
    { emoji: '⚡', name: 'lightning bolt electricity energy power' },
    { emoji: '🔋', name: 'battery power charge' },
    { emoji: '🌡', name: 'thermometer temperature hot cold' },
    { emoji: '☀', name: 'sun sunny bright' },
    { emoji: '🌤', name: 'sun cloud partly cloudy' },
    { emoji: '☁', name: 'cloud cloudy overcast' },
    { emoji: '❄', name: 'snowflake cold ice winter freeze' },
    { emoji: '🌧', name: 'rain cloud rainy wet' },
    { emoji: '🌊', name: 'wave ocean water sea' },
    { emoji: '💧', name: 'droplet water rain liquid' },
    { emoji: '🔥', name: 'fire flame hot burn' },
    { emoji: '💨', name: 'wind air blow dash' },
    { emoji: '🌪', name: 'tornado cyclone wind storm' },
    { emoji: '⛅', name: 'sun cloud partly cloudy weather' },
    { emoji: '🌈', name: 'rainbow color spectrum' },
    { emoji: '⭐', name: 'star glowing bright yellow' },
    { emoji: '🌙', name: 'moon night crescent' },
    { emoji: '🌍', name: 'globe earth world' },
  ]},
  { category: 'Smileys & Gesten', emojis: [
    { emoji: '😊', name: 'smile happy smiley blush' },
    { emoji: '😀', name: 'grin happy big smile' },
    { emoji: '😎', name: 'cool sunglasses awesome' },
    { emoji: '😍', name: 'love heart eyes adore' },
    { emoji: '🤔', name: 'thinking hmm wondering' },
    { emoji: '😅', name: 'sweat smile nervous awkward' },
    { emoji: '😂', name: 'laugh crying funny joy' },
    { emoji: '🙁', name: 'sad frown unhappy' },
    { emoji: '👍', name: 'thumbs up like ok good approve' },
    { emoji: '👎', name: 'thumbs down dislike bad reject' },
    { emoji: '✋', name: 'hand stop halt raised' },
    { emoji: '🤝', name: 'handshake agreement deal' },
    { emoji: '👀', name: 'eyes look see watch' },
    { emoji: '💪', name: 'muscle strong flex power' },
    { emoji: '⚠', name: 'warning alert caution danger' },
    { emoji: '💡', name: 'lightbulb idea tip hint' },
    { emoji: '❓', name: 'question mark unknown help' },
    { emoji: '❗', name: 'exclamation mark important urgent' },
    { emoji: '✅', name: 'check mark done ok success green' },
    { emoji: '❌', name: 'cross red error wrong fail' },
    { emoji: '🚀', name: 'rocket launch fast deploy' },
    { emoji: '🎯', name: 'target bullseye goal aim' },
    { emoji: '🏆', name: 'trophy winner champion award' },
    { emoji: '🎉', name: 'party celebration tada' },
    { emoji: '🔔', name: 'bell notification alert ring' },
    { emoji: '🔕', name: 'bell off mute silence' },
  ]},
  { category: 'Natur', emojis: [
    { emoji: '🌿', name: 'herb leaf plant green nature' },
    { emoji: '🌱', name: 'seedling sprout plant grow' },
    { emoji: '🍀', name: 'clover lucky shamrock green' },
    { emoji: '🌲', name: 'tree forest pine evergreen' },
    { emoji: '🌵', name: 'cactus desert dry' },
    { emoji: '🐍', name: 'snake python reptile' },
    { emoji: '🦊', name: 'fox animal cunning' },
    { emoji: '🐧', name: 'penguin linux bird' },
    { emoji: '🐳', name: 'whale docker ocean big' },
    { emoji: '🦁', name: 'lion king animal brave' },
    { emoji: '🐉', name: 'dragon fantasy power' },
    { emoji: '🦋', name: 'butterfly transform change' },
    { emoji: '🌸', name: 'cherry blossom flower spring pink' },
    { emoji: '🍎', name: 'apple mac fruit red' },
    { emoji: '🍕', name: 'pizza food slice' },
    { emoji: '☕', name: 'coffee hot drink morning' },
  ]},
];

// ─── ID generation ────────────────────────────────────────────────────────

let _idCounter = 0;
```

- [ ] **Schritt 2: Emoji-Picker HTML-Div nach dem Edit-Dialog-Block einfügen (~nach Zeile 285)**

Suche (Ende des Edit-Dialog-Blocks):
```html
    </div>
  </div>

<script>
```

Füge zwischen `</div>` und `<script>` ein:
```html
    </div>
  </div>

  <!-- Emoji Picker Popup -->
  <div id="emoji-picker"
       style="display:none;position:fixed;z-index:300;
              background:var(--color-surface);border:1px solid var(--color-border);
              border-radius:var(--radius);padding:8px;width:284px;max-height:320px;
              overflow-y:auto;box-shadow:0 4px 20px rgba(0,0,0,0.5);">
    <input id="emoji-search" type="text" placeholder="🔍 Name oder U+1F525..."
           oninput="filterAndRenderEmojis(this.value)"
           style="width:100%;box-sizing:border-box;padding:5px 8px;margin-bottom:8px;
                  border-radius:4px;border:1px solid var(--color-border);
                  background:var(--color-surface-2);color:var(--color-text);font-size:12px;">
    <div id="emoji-grid"></div>
  </div>

<script>
```

- [ ] **Schritt 3: Emoji-Picker Hilfsfunktionen einfügen (nach `updateProgressbarPreview()`, vor dem Progress-bar-rendering Block)**

Suche:
```javascript
// ─── Progress bar rendering ───────────────────────────────────────────────
```

Füge davor ein:
```javascript
// ─── Emoji Picker ─────────────────────────────────────────────────────────

let _emojiTargetInputId = null; // ID of the text input to insert the emoji into

/**
 * Opens the emoji picker popup, positions it below the trigger button,
 * and focuses the search field.
 * @param {HTMLElement} triggerBtn - the button that was clicked
 * @param {string} targetInputId  - id of the text input to insert emojis into
 */
function openEmojiPicker(triggerBtn, targetInputId) {
  _emojiTargetInputId = targetInputId;
  const picker = document.getElementById('emoji-picker');
  const rect   = triggerBtn.getBoundingClientRect();
  picker.style.top  = (rect.bottom + 4) + 'px';
  picker.style.left = Math.max(4, rect.right - 284) + 'px';
  picker.style.display = '';
  const searchEl = document.getElementById('emoji-search');
  if (searchEl) { searchEl.value = ''; searchEl.focus(); }
  filterAndRenderEmojis('');
}

/**
 * Closes the emoji picker popup.
 */
function closeEmojiPicker() {
  document.getElementById('emoji-picker').style.display = 'none';
  _emojiTargetInputId = null;
}

/**
 * Filters the EMOJI_LIST by name (case-insensitive substring) or by Unicode
 * codepoint (e.g. "1F525" or "U+1F525"), then renders the result into
 * #emoji-grid. A valid codepoint that is not in the curated list is shown
 * as a single result via String.fromCodePoint().
 * @param {string} query - search query from the input field
 */
function filterAndRenderEmojis(query) {
  const grid = document.getElementById('emoji-grid');
  if (!grid) return;

  const q = (query || '').trim();

  // Codepoint search: "1F525" or "U+1F525"
  const cpMatch = q.match(/^(?:U\+)?([0-9A-Fa-f]{4,6})$/);
  if (cpMatch) {
    try {
      const cp   = parseInt(cpMatch[1], 16);
      const ch   = String.fromCodePoint(cp);
      grid.innerHTML = renderEmojiGrid([{ category: 'Codepoint', emojis: [{ emoji: ch, name: q }] }]);
    } catch {
      grid.innerHTML = '<div style="font-size:11px;color:var(--color-text-muted);padding:4px;">Ungültiger Codepoint</div>';
    }
    return;
  }

  // Name search
  const lower = q.toLowerCase();
  const filtered = EMOJI_LIST.map(cat => ({
    category: cat.category,
    emojis: q
      ? cat.emojis.filter(e => e.name.toLowerCase().includes(lower))
      : cat.emojis,
  })).filter(cat => cat.emojis.length > 0);

  grid.innerHTML = filtered.length > 0
    ? renderEmojiGrid(filtered)
    : '<div style="font-size:11px;color:var(--color-text-muted);padding:4px;">Keine Ergebnisse</div>';
}

/**
 * Renders category headers and emoji buttons for the given filtered list.
 * @param {Array} categories - array of { category, emojis } objects
 * @returns {string} HTML string
 */
function renderEmojiGrid(categories) {
  return categories.map(cat => `
    <div style="font-size:10px;color:var(--color-text-muted);margin:6px 0 3px;text-transform:uppercase;
                letter-spacing:0.05em;">${escapeHtml(cat.category)}</div>
    <div style="display:flex;flex-wrap:wrap;gap:2px;">
      ${cat.emojis.map(e => `
        <button type="button"
                title="${escapeHtml(e.name)}"
                onclick="insertEmojiAtCursor('${e.emoji.replace(/'/g, "\\'")}')"
                style="width:28px;height:28px;border:none;background:none;cursor:pointer;
                       font-size:16px;border-radius:3px;line-height:1;
                       transition:background 0.1s;"
                onmouseover="this.style.background='var(--color-surface-2)'"
                onmouseout="this.style.background='none'"
                >${e.emoji}</button>
      `).join('')}
    </div>
  `).join('');
}

/**
 * Inserts the given emoji into the target text input at the current cursor
 * position, then closes the picker.
 * @param {string} emoji - the emoji character to insert
 */
function insertEmojiAtCursor(emoji) {
  const input = _emojiTargetInputId
    ? document.getElementById(_emojiTargetInputId)
    : null;
  if (input) {
    const start = input.selectionStart ?? input.value.length;
    const end   = input.selectionEnd   ?? input.value.length;
    input.value = input.value.slice(0, start) + emoji + input.value.slice(end);
    const newPos = start + emoji.length;
    input.setSelectionRange(newPos, newPos);
    input.focus();
  }
  closeEmojiPicker();
}

// Close picker on outside click
document.addEventListener('click', e => {
  const picker = document.getElementById('emoji-picker');
  if (picker && picker.style.display !== 'none') {
    if (!picker.contains(e.target) && !e.target.closest('[data-emoji-trigger]')) {
      closeEmojiPicker();
    }
  }
});

// Close picker on Escape key
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') {
    const picker = document.getElementById('emoji-picker');
    if (picker && picker.style.display !== 'none') closeEmojiPicker();
  }
});

// ─── Progress bar rendering ───────────────────────────────────────────────
```

- [ ] **Schritt 4: Button `😊` und `data-emoji-trigger` im Palette-Branch von `renderEditTabGeneral()` einfügen (~Zeile 1271)**

Suche im Palette-Branch:
```javascript
      <div>
        <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:4px;">Text</div>
        <input id="edit-text" type="text" value="${escapeHtml(f.text || '')}"
               style="width:100%;box-sizing:border-box;padding:6px 8px;border-radius:4px;
                      border:1px solid var(--color-border);background:var(--color-surface-2);
                      color:var(--color-text);font-size:12px;">
      </div>
```

Ändere zu:
```javascript
      <div>
        <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:4px;">Text</div>
        <div style="display:flex;gap:6px;align-items:center;">
          <input id="edit-text" type="text" value="${escapeHtml(f.text || '')}"
                 style="flex:1;box-sizing:border-box;padding:6px 8px;border-radius:4px;
                        border:1px solid var(--color-border);background:var(--color-surface-2);
                        color:var(--color-text);font-size:12px;">
          <button type="button" data-emoji-trigger
                  onclick="openEmojiPicker(this, 'edit-text')"
                  title="Emoji einfügen"
                  style="padding:5px 8px;border-radius:4px;border:1px solid var(--color-border);
                         background:var(--color-surface-2);color:var(--color-text);
                         cursor:pointer;font-size:14px;line-height:1;flex-shrink:0;">
            😊
          </button>
        </div>
      </div>
```

- [ ] **Schritt 5: Manuell im Browser verifizieren**

1. HTML im Browser öffnen
2. "+ Feld anlegen" klicken → Edit-Dialog öffnet sich (Tab "Allgemein" mit Label + Text)
3. `😊`-Button neben dem Text-Input ist sichtbar
4. Klick auf `😊` → Emoji-Picker öffnet sich unter dem Button
5. Kategorien "Symbole & Zeichen", "Pfeile", "Technik & Tools" etc. sind sichtbar
6. In das Suchfeld `"fire"` tippen → nur 🔥 wird angezeigt
7. In das Suchfeld `"1F525"` tippen → 🔥 wird als Codepoint-Treffer angezeigt
8. In das Suchfeld `"U+2713"` tippen → ✓ wird als Codepoint-Treffer angezeigt
9. Auf ein Emoji klicken → wird in den Text-Input eingefügt, Picker schließt sich
10. Klick außerhalb des Pickers → Picker schließt sich
11. Picker öffnen, Escape drücken → Picker schließt sich
12. Cursors in Text-Input positionieren, dann Emoji einfügen → Emoji erscheint an Cursor-Position

- [ ] **Schritt 6: Committen**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): add emoji picker to custom field edit dialog"
```

---

## Self-Review Checklist

- **Spec coverage:**
  - ✓ Bugfix Doppelte IDs → Task 1
  - ✓ Bugfix Theme FG / Progressbar → Task 2
  - ✓ Progressbar Preview-Wert → Task 3
  - ✓ Emoji-Picker mit Kategorien, Suche, Codepoint-Eingabe → Task 4
  - ✓ `previewValue` nicht persistiert → Task 3 Schritt 4 (`delete _editDraft.previewValue`)
  - ✓ Picker nur für Custom Fields (palette-Branches) → Task 4 Schritt 4 (nur Palette-Branch)
  - ✓ Schließen bei Klick außerhalb + Escape → Task 4 Schritt 3 (Event-Listener)

- **Keine Platzhalter:** Alle Schritte enthalten vollständigen Code.

- **Typ-Konsistenz:**
  - `renderFieldHtml(field, data, previewTheme, previewOverride)` — Signatur in Task 3 Schritt 1 definiert, in `renderProgressbarPreview()` konsistent aufgerufen
  - `updateProgressbarPreview(rawValue)` — in Task 3 Schritt 2 definiert, im Template-Literal in Task 3 Schritt 3 als `oninput="updateProgressbarPreview(this.value)"` referenziert
  - `openEmojiPicker(triggerBtn, targetInputId)` — in Task 4 Schritt 3 definiert, im Template-Literal in Task 4 Schritt 4 als `openEmojiPicker(this, 'edit-text')` aufgerufen
  - `filterAndRenderEmojis(query)` — definiert und im HTML-Input als `oninput="filterAndRenderEmojis(this.value)"` referenziert
  - `insertEmojiAtCursor(emoji)` — definiert, in `renderEmojiGrid()` im `onclick` referenziert
  - `_emojiTargetInputId` — gesetzt in `openEmojiPicker()`, genutzt in `insertEmojiAtCursor()`, gecleart in `closeEmojiPicker()`
  - `data-emoji-trigger` — im Button gesetzt (Task 4 Schritt 4), im außen-click-Listener per `.closest('[data-emoji-trigger]')` geprüft (Task 4 Schritt 3)
