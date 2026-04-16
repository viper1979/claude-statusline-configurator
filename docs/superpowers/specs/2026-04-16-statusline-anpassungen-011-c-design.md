# Spec: Statusline Anpassungen 011 — C

**Datum:** 2026-04-16  
**Branch:** feature/statusline-011-c-ux  
**Scope:** Preview-Font, Merge-Visualisierung, Clarity-Polish

---

## Kontext

Aus dem Anpassungsdokument `Anpasungen_011.md` werden die Punkte C (Preview-Font und
UX-Verbesserungen) in diesem Spec behandelt. Die Punkte A+B sind bereits implementiert
(Branch `master`, Commits `05e70a4`–`c1e266d`).

Scope: Ansatz 1 (gezielt) — Font-Update, Merge-Chip-Visualisierung, minimales Clarity-Polish.
Keine strukturellen Umbauten, keine JS-Logik-Änderungen außer Rendering.

---

## C1 — Preview-Font

### Problem

Der Preview-Bereich (`#preview-output`) nutzt `--font-mono: 'Cascadia Code', 'Consolas', monospace`.
Unicode-Zeichen und NerdFont-Glyphen werden bei fehlenden Glyphen als Fallback-Boxen dargestellt.
Das macht das Preview unrealistisch.

### Fix

In `:root` CSS (ca. Zeile 10) die Variable `--font-mono` um `'MesloLGS NF'` als erste Wahl erweitern:

```css
/* Vorher: */
--font-mono: 'Cascadia Code', 'Consolas', monospace;

/* Nachher: */
--font-mono: 'MesloLGS NF', 'Cascadia Code', 'Consolas', monospace;
```

**Verhalten:** Wenn `MesloLGS NF` lokal installiert ist, wird er sofort genutzt. Andernfalls
greift der Browser automatisch auf die bestehenden Fallbacks zurück. Keine UI-Änderung nötig.

---

## C2 — Merge-Chip-Visualisierung

### Problem

Wenn `field.mergeWithNext = true`, ändert sich aktuell nur das Icon (`→` vs `↝`) und die
Farbe des Merge-Buttons am Chip. Am Chip selbst ist keine visuelle Verbindung erkennbar.
Es ist nicht intuitiv, dass zwei Felder zu einer Einheit zusammengeführt werden.

### Design

Chips, die per `mergeWithNext` verbunden sind, sehen optisch zusammengehörig aus:

```
Vorher (getrennte Chips):
  [Token ✏✕→]   [Separator ✏✕→]   [Model ✏✕]

Nachher (verbundene Chips):
  [Token ✏✕ ─── Separator ✏✕ ─── Model ✏✕]
```

- **Chip mit `mergeWithNext: true`** (`chip-merged-left`): rechter Border-Radius = 0, rechter Border entfällt
- **Folge-Chip nach einem Merge-Chip** (`chip-merged-right`): linker Border-Radius = 0, linker Border entfällt
- **Connector-Span** zwischen verbundenen Chips: gleiche Hintergrundfarbe wie Chip, kein Border, kein Radius — wirkt als nahtlose Brücke

### CSS (neu, in `<style>`):

```css
.chip-merged-left {
  border-radius: 4px 0 0 4px !important;
  border-right: none !important;
}

.chip-merged-right {
  border-radius: 0 4px 4px 0 !important;
  border-left: none !important;
}

.chip-connector {
  display: inline-block;
  width: 4px;
  height: 22px;
  background: var(--color-surface-2);
  border-top: 1px solid var(--color-border);
  border-bottom: 1px solid var(--color-border);
  vertical-align: middle;
}
```

### Implementierung

`renderFieldChip(field, lineId)` bekommt zwei neue Parameter:

```javascript
/**
 * Renders a single field chip.
 * @param {object} field
 * @param {string} lineId
 * @param {boolean} mergedLeft  - this chip follows a chip with mergeWithNext=true
 * @param {boolean} mergedRight - this chip has mergeWithNext=true
 */
function renderFieldChip(field, lineId, mergedLeft = false, mergedRight = false) {
```

Die CSS-Klassen werden als `extraClasses` in den `class`-String des Chip-Spans eingebaut:

```javascript
const mergeClasses = [
  mergedLeft  ? 'chip-merged-left'  : '',
  mergedRight ? 'chip-merged-right' : '',
].filter(Boolean).join(' ');
```

`renderLines()` berechnet beim Iterieren über `line.fields`, ob der aktuelle Chip
`mergedLeft` oder `mergedRight` ist:

```javascript
line.fields.forEach((field, idx) => {
  const prevField   = line.fields[idx - 1];
  const mergedLeft  = !!(prevField?.mergeWithNext);
  const mergedRight = !!field.mergeWithNext;

  if (mergedLeft) {
    html += `<span class="chip-connector"></span>`;
  }
  html += renderFieldChip(field, line.id, mergedLeft, mergedRight);
});
```

**Wichtig:** Der Merge-Button (`→` / `↝`) und sein Event-Handler `toggleMergeNext()` bleiben
unverändert. Nur das visuelle Rendering ändert sich.

---

## C3 — Clarity-Polish (Tooltips)

### Problem

Icon-Buttons ohne `title`-Attribut sind für neue Nutzer nicht selbsterklärend.

### Fix

In `renderFieldChip()` bekommen Edit- und Delete-Button `title`-Attribute:

```javascript
// Edit-Button (vorher kein title):
<button class="btn-icon" title="Feld bearbeiten" onclick="openEditDialog(...)">✏️</button>

// Delete-Button (vorher kein title):
<button class="btn-icon" title="Feld entfernen" onclick="removeFieldFromLine(...)">✕</button>
```

Für Zeilen-Level-Buttons in `renderLines()`: falls `title`-Attribute fehlen, werden sie
analog ergänzt (z.B. `"Zeile entfernen"`, `"Spaltenausrichtung umschalten"`).

---

## Nicht im Scope

- Font-Auswahl-UI (Dropdown) — kein Bedarf, eine Schrift reicht
- Vollständiges CSS-Redesign (Farben, Spacing, Typografie-System) — Ansatz 2, separate Session
- Neue JS-Features oder Datentypen

---

## Testing

- **C1:** `statusline-configurator.html` im Browser öffnen → Preview-Bereich prüfen ob `MesloLGS NF` genutzt wird (DevTools → Computed Styles → `font-family`)
- **C2:** Config mit Merge-Felder laden → Chips müssen optisch verbunden erscheinen; Toggle → Chips trennen sich wieder
- **C3:** Hover über Edit/Delete-Icons → Tooltip erscheint
