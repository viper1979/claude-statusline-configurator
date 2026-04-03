# Spec: Anpassungen 003 — Emoji-Picker, Bugfixes & Progressbar Preview-Wert

**Datum:** 2026-04-03  
**Branch:** feature/statusline-enhancements  
**Scope:** `statusline-configurator.html` (Single-File Web-App)

---

## Übersicht

Diese Spec beschreibt vier Änderungen am Statusline-Konfigurator:

1. **Bugfix:** Doppelte IDs bei Custom Fields nach `loadConfig()`
2. **Bugfix:** Theme Foreground Color überschreibt Progressbar-Threshold-Farben
3. **Feature:** Emoji-Picker im Edit-Dialog für Custom Fields
4. **Feature:** Konfigurierbarer Preview-Wert für Progressbars im Formatierungsdialog

---

## 1. Bugfix — Doppelte IDs bei Custom Fields

### Problem

`_idCounter` startet nach `loadConfig()` bei 0 und wird beim Einlesen von Lines/Fields hochgezählt. Custom Fields behalten ihre gespeicherte `id` aus der JSON (z.B. `id-36`). Der Counter kennt nach dem Laden nicht den höchsten bereits vergebenen Wert aus den Custom Fields. Wenn der Counter beim nächsten `generateId()`-Aufruf denselben Wert erreicht, kommt es zu einer ID-Kollision — das falsche Field wird in die Oberfläche gezogen.

### Fix

Neue Hilfsfunktion `syncIdCounter(state)`:

- Durchläuft alle IDs in `state.lines[].id`, `state.lines[].fields[].id` und `state.customFields[].id`
- Parst das numerische Suffix aus `id-N`-Strings
- Setzt `_idCounter = max(N)` über alle gefundenen Werte

Aufruf von `syncIdCounter(state)` am Ende von `loadConfig()`, nachdem alle Lines, Fields und Custom Fields eingelesen wurden.

### Betroffene Stellen

| Funktion | Zeile (ca.) | Änderung |
|---|---|---|
| `generateId()` | 409 | Keine Änderung |
| `loadConfig()` | 1165 | Aufruf `syncIdCounter(state)` am Ende |
| — | neu | Neue Funktion `syncIdCounter(state)` |

---

## 2. Bugfix — Theme Foreground Color überschreibt Progressbar-Threshold-Farben

### Problem

`applyTheme()` schreibt `theme.fieldFg` auf `field.fg` **aller** Felder, einschließlich Progressbars. In `renderFieldHtml()` wird `barFgOverride = field.fg ?? null` gesetzt — da das Feld jetzt einen expliziten Wert hat, werden die Threshold-Farben ignoriert.

### Fix

In `applyTheme()`: `fieldFg` wird nur auf Felder angewendet, deren `type !== 'progressbar'`. Progressbar-Felder werden von `applyTheme()` grundsätzlich nicht angefasst.

- Progressbars mit einer **vom User explizit gesetzten** `field.fg`-Farbe (über den Farben-Tab) bleiben erhalten.
- Progressbars **ohne** explizit gesetzte `field.fg` nutzen weiterhin die Threshold-Farben.

### Betroffene Stellen

| Funktion | Zeile (ca.) | Änderung |
|---|---|---|
| `applyTheme()` | 845 | Guard: `if (field.type === 'progressbar') continue;` |

---

## 3. Feature — Emoji-Picker im Edit-Dialog

### Ziel

Im Edit-Dialog für Custom Fields (Tab "Allgemein") kann der User Emojis bequem in das "Text"-Feld einfügen, ohne den genauen Codepoint zu kennen.

### UI

- Neben dem Text-Input erscheint ein Button `😊`
- Klick öffnet ein positioniertes Popup direkt unter dem Button (z-index konsistent mit bestehenden Modals)
- Popup schließt sich bei: Klick außerhalb, Escape, oder nach Emoji-Auswahl
- Das gewählte Emoji wird an der aktuellen Cursor-Position in das Text-Input eingefügt

### Popup-Aufbau

```
┌─────────────────────────────┐
│ [🔍 Suche: Name oder U+XXXX]│
├─────────────────────────────┤
│ Symbole & Zeichen           │
│  ✓  ✗  ★  ♦  ©  ™  …      │
│ Pfeile                      │
│  →  ←  ↑  ↓  ⇒  …         │
│ Technik & Tools             │
│  ⚙  🔧  💻  🖥  📡  …      │
│ Energie & Wetter            │
│  ⚡  🔋  🌡  ☀  ❄  …       │
│ Smileys & Gesten            │
│  😊  👍  ⚠  💡  …          │
│ Natur                       │
│  🌿  🐍  🦊  …             │
└─────────────────────────────┘
```

### Emoji-Liste (~150 Emojis, kuriert für Windows Terminal)

| Kategorie | Beispiele |
|---|---|
| Symbole & Zeichen | ✓ ✗ ★ ☆ ♦ ♠ ♣ ♥ © ® ™ ℃ ℉ № µ § ¶ |
| Pfeile | → ← ↑ ↓ ↔ ↕ ⇒ ⇐ ⇑ ⇓ ➜ ➔ |
| Technik & Tools | ⚙ 🔧 🔨 💻 🖥 🖨 📡 🔌 💾 📁 📂 |
| Energie & Wetter | ⚡ 🔋 🌡 ☀ 🌤 ❄ 🌧 🌊 💧 🔥 |
| Smileys & Gesten | 😊 😀 😎 👍 👎 ✋ 🤝 ⚠ 💡 ❓ ❗ |
| Natur | 🌿 🌱 🍀 🌲 🐍 🦊 🐧 🐳 |

### Suchverhalten

- Suche nach Name (case-insensitiv, Teilstring): `"fire"` → 🔥
- Suche nach Hex-Codepoint: `"1F525"` oder `"U+1F525"` → 🔥
- Codepoint-Eingabe rendert das Emoji über `String.fromCodePoint()` auch wenn es nicht in der kuratierten Liste ist

### State

- Kein persistierter State — Suchfeld und Scroll-Position werden nicht gespeichert
- Der Picker ist nur für Custom Fields (source `palette-new` oder `palette-edit`) sichtbar, nicht für eingebaute Felder

### Betroffene Stellen

| Funktion | Zeile (ca.) | Änderung |
|---|---|---|
| `renderEditTabGeneral()` | 1260 | Button `😊` neben Text-Input; Emoji-Picker-HTML |
| — | neu | `EMOJI_LIST` Konstante mit kuratierten Emojis |
| — | neu | `openEmojiPicker()` / `closeEmojiPicker()` |
| — | neu | `filterEmojis(query)` für Suchlogik |
| — | neu | `insertEmojiIntoText(emoji)` für Cursor-Einfügung |

---

## 4. Feature — Konfigurierbarer Progressbar Preview-Wert

### Ziel

Im Edit-Dialog, Tab "Allgemein", für Progressbar-Felder soll ein Zahlenfeld "Vorschau-Wert (%)" angeboten werden. Damit können alle Threshold-Farben einfach durch Eingabe verschiedener Werte getestet werden.

### UI

- Zahlenfeld "Vorschau-Wert (%)" mit `min=0`, `max=100`, `step=1`
- Platzierung: Am Anfang des Progressbar-Abschnitts im Allgemein-Tab, vor den bestehenden Optionen (Farbe, Klammern, Zeichen)
- Standardwert beim Öffnen: Wert aus `SAMPLE_DATA` für das jeweilige Feld, Fallback 50
- Eingaben außerhalb von 0–100 werden auf den nächstliegenden Grenzwert geclamped

### State

- Wert wird in `_editDraft.previewValue` gespeichert — **nur temporärer UI-State**
- Wird **nicht** in die Konfiguration exportiert (`saveEditDialog()` ignoriert `previewValue`)
- Wird **nicht** in `statusline-config.json` gespeichert

### Vorschau-Rendering

- Die Dialog-Vorschau rendert das Feld direkt aus `_editDraft`. Wenn `_editDraft.previewValue` gesetzt ist, wird dieser Wert als Rohwert für die Progressbar-Berechnung verwendet (anstelle des Werts aus `SAMPLE_DATA`).
- Die Hauptvorschau (außerhalb des Edit-Dialogs) rendert Felder aus `state` und hat keinen Zugriff auf `_editDraft.previewValue` — hier bleibt `SAMPLE_DATA` unverändert.
- Konkret: `renderFieldHtml()` erhält einen optionalen Parameter `previewOverride` (Zahlenwert 0–100). Ist er gesetzt, wird er als Rohwert für die Progressbar genutzt. Die Dialog-Vorschau übergibt `_editDraft.previewValue`, alle anderen Aufrufer übergeben nichts.

### Betroffene Stellen

| Funktion | Zeile (ca.) | Änderung |
|---|---|---|
| `renderEditTabGeneral()` | 1290 | Zahlenfeld für `previewValue` im Progressbar-Branch |
| `renderFieldHtml()` | 1683 | `previewValue` aus `_editDraft` nutzen wenn Dialog offen |
| `saveEditDialog()` | 1505 | `previewValue` explizit aus dem gespeicherten State ausschließen |

---

## Nicht im Scope

- Persistierung des Emoji-Picker-Zustands (Suchbegriff, Scroll)
- Emoji-Picker für Label-Felder (nur Text-Input)
- Persistierung des Progressbar-Preview-Werts in der Konfiguration
- Änderungen am PowerShell-Script `statusline.ps1`
- Änderungen am Test-Setup

---

## Reihenfolge der Implementierung

1. Bugfix: Doppelte IDs (isoliert, kein UI-Impact)
2. Bugfix: Theme FG / Progressbar (eine Zeile Guard)
3. Feature: Progressbar Preview-Wert (im bestehenden Dialog-Branch)
4. Feature: Emoji-Picker (größte Änderung, eigene Hilfsfunktionen)
