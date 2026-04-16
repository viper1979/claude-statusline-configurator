# Statusline Anpassungen 011 C — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preview-Font auf MesloLGS NF aktualisieren, Merge-Chips visuell verbinden und fehlende Tooltip ergänzen.

**Architecture:** Drei unabhängige Änderungen in einer einzigen Datei (`statusline-configurator.html`): (1) CSS-Variable für Font, (2) CSS + JS-Rendering für verbundene Merge-Chips, (3) fehlendes `title`-Attribut. Keine neuen Dateien, keine PS-Skript-Änderungen, keine automatisierten Tests (rein visuell).

**Tech Stack:** Vanilla JS, HTML/CSS (Single-File-Konfigurator)

**Spec:** `docs/superpowers/specs/2026-04-16-statusline-anpassungen-011-c-design.md`

---

## Datei-Übersicht

| Datei | Änderungen |
|-------|------------|
| `statusline-configurator.html` | Zeile 21 (Font), CSS-Block (`.chip-connector`), `renderFieldChip` (Zeilen 1241–1269), `renderLines` (Zeile 1229), Zeile 1222 (title) |

---

## Task 1: Feature-Branch erstellen

**Files:** —

- [ ] **Step 1: Branch anlegen und wechseln**

```bash
git checkout -b feature/statusline-011-c-ux
```

Expected: Prompt zeigt `feature/statusline-011-c-ux`.

---

## Task 2: C1 — Preview-Font

**Files:**
- Modify: `statusline-configurator.html:21`

- [ ] **Step 1: CSS-Variable anpassen**

In `statusline-configurator.html` Zeile 21 (im `:root`-Block) ersetzen:

```css
/* Vorher: */
--font-mono: 'Cascadia Code', 'Consolas', monospace;

/* Nachher: */
--font-mono: 'MesloLGS NF', 'Cascadia Code', 'Consolas', monospace;
```

- [ ] **Step 2: Manuell verifizieren**

1. `statusline-configurator.html` im Browser öffnen
2. DevTools → Element `#preview-output` auswählen → Computed → `font-family` prüfen
3. Wenn `MesloLGS NF` lokal installiert ist: erster Font in der Liste
4. Wenn nicht installiert: `Cascadia Code` oder `Consolas` — kein Fehler, nur Fallback

- [ ] **Step 3: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): add MesloLGS NF as primary preview font"
```

---

## Task 3: C2 — Merge-Chip-Visualisierung

**Files:**
- Modify: `statusline-configurator.html` — CSS-Block, `renderFieldChip` (Zeilen 1241–1269), `renderLines` (Zeile 1229)

### Hintergrund

Aktuell ruft `renderLines` die Chip-Funktion so auf (Zeile 1229):

```javascript
line.fields.map(f => renderFieldChip(f, line.id)).join('')
```

`renderFieldChip` (Zeilen 1241–1269) rendert jeden Chip mit fix `border-radius:4px` und `border:1px solid var(--color-border)`, unabhängig davon ob `mergeWithNext` gesetzt ist. Es gibt keine visuelle Verbindung zwischen Chips.

### Ziel

Chips mit `mergeWithNext: true` und ihr Folge-Chip sehen zusammengehörig aus:
- Abgeflachte innere Seiten (kein Border-Radius, kein Border zwischen Chips)
- Ein `.chip-connector`-Span als nahtlose Brücke

- [ ] **Step 1: CSS für `.chip-connector` ergänzen**

Im `<style>`-Block (irgendwo nach den bestehenden Regeln, z.B. nach `.btn-icon:hover`) einfügen:

```css
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

- [ ] **Step 2: `renderFieldChip`-Signatur und Inline-Styles anpassen**

Die Funktion `renderFieldChip` (Zeile 1241) bekommt zwei neue Parameter mit Defaults.
Außerdem werden drei neue lokale Variablen berechnet, die `border-radius` und die
linke/rechte Border steuern. Ersetze die gesamte Funktion (Zeilen 1241–1269):

```javascript
function renderFieldChip(field, lineId, mergedLeft = false, mergedRight = false) {
  // Apply the same priority chain as renderFieldHtml so the chip reflects
  // the effective color (Override > Field-Theme > Global Theme > Standard).
  const fieldThemeId = field.themeId ?? state.activeTheme;
  const activeTheme  = state.themes.find(t => t.id === fieldThemeId) ?? null;
  const fgIsOverride = field.fgOverride ?? (field.fg !== null && field.fg !== undefined);
  const bgIsOverride = field.bgOverride ?? (field.bg !== null && field.bg !== undefined);
  const effectiveFg  = fgIsOverride ? field.fg : (activeTheme?.fieldFg ?? null);
  const effectiveBg  = bgIsOverride ? field.bg : (activeTheme?.fieldBg ?? null);
  const bg = effectiveBg ? `background:${effectiveBg};` : '';
  const fg = effectiveFg ? `color:${effectiveFg};` : '';
  const label = fieldLabel(field);
  const mergeActive = !!field.mergeWithNext;
  const mergeColor  = mergeActive ? 'var(--color-accent)' : 'var(--color-text-muted)';
  const mergeIcon   = mergeActive ? '→' : '↝';
  // Border-radius and border adapt to merge context so connected chips appear joined.
  const borderRadius = (mergedLeft && mergedRight) ? '0'
                     : mergedLeft                  ? '0 4px 4px 0'
                     : mergedRight                 ? '4px 0 0 4px'
                     :                              '4px';
  const borderLeft   = mergedLeft  ? 'none' : '1px solid var(--color-border)';
  const borderRight  = mergedRight ? 'none' : '1px solid var(--color-border)';
  return `
    <span class="field-chip" data-field-id="${field.id}" data-line-id="${lineId}"
          style="display:inline-flex;align-items:center;gap:4px;padding:3px 8px;
                 border-radius:${borderRadius};font-size:12px;background:var(--color-surface-2);
                 border-top:1px solid var(--color-border);border-bottom:1px solid var(--color-border);
                 border-left:${borderLeft};border-right:${borderRight};${bg}${fg}cursor:default;">
      <span>${label}</span>
      <button class="btn-icon" title="Mit nächstem Feld gruppieren (Tab-Ausrichtung)"
              onclick="toggleMergeNext('${lineId}','${field.id}')"
              style="color:${mergeColor};font-size:11px;padding:0 2px;">${mergeIcon}</button>
      <button class="btn-icon" title="Bearbeiten" onclick="openEditDialog('line','${lineId}','${field.id}')">✏️</button>
      <button class="btn-icon" title="Entfernen" onclick="removeFieldFromLine('${lineId}','${field.id}')">✕</button>
    </span>
  `;
}
```

- [ ] **Step 3: `renderLines`-Iteration auf `reduce` umstellen**

In `renderLines()` (Zeile 1229) die Field-Iteration ersetzen. Aktuell:

```javascript
: line.fields.map(f => renderFieldChip(f, line.id)).join('')
```

Nachher:

```javascript
: line.fields.reduce((html, f, idx) => {
    const prevField  = line.fields[idx - 1];
    const mergedLeft  = !!(prevField?.mergeWithNext);
    const mergedRight = !!f.mergeWithNext;
    if (mergedLeft) html += '<span class="chip-connector"></span>';
    return html + renderFieldChip(f, line.id, mergedLeft, mergedRight);
  }, '')
```

- [ ] **Step 4: Manuell verifizieren**

1. `statusline-configurator.html` im Browser öffnen
2. Eine Config mit mehreren Feldern pro Zeile laden (oder manuell Felder hinzufügen)
3. Merge-Button (`↝`) eines Feldes klicken → Chip sollte optisch mit dem nächsten verbunden erscheinen (abgeflachte innere Kanten, Connector-Brücke)
4. Erneut klicken → Chips trennen sich wieder (voller Border-Radius, normaler Border)
5. Drei Felder hintereinander mergen → mittlerer Chip hat beidseitig abgeflachte Kanten

- [ ] **Step 5: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): visually connect merged field chips with flattened borders and connector span"
```

---

## Task 4: C3 — Zeilen-Delete-Button Tooltip

**Files:**
- Modify: `statusline-configurator.html:1222`

### Hintergrund

Der Delete-Button der Zeile (Zeile 1222) hat kein `title`-Attribut. Alle anderen Buttons
haben bereits Tooltips. Aktuell:

```html
<button class="btn btn-danger" style="padding:2px 8px;font-size:11px;" onclick="removeLine('${line.id}')">✕ Entfernen</button>
```

(Hinweis: Edit- und Delete-Buttons in `renderFieldChip` haben bereits `title` — die sind fertig.)

- [ ] **Step 1: `title` ergänzen**

Zeile 1222 ersetzen:

```javascript
// Vorher:
<button class="btn btn-danger" style="padding:2px 8px;font-size:11px;" onclick="removeLine('${line.id}')">✕ Entfernen</button>

// Nachher:
<button class="btn btn-danger" title="Zeile entfernen" style="padding:2px 8px;font-size:11px;" onclick="removeLine('${line.id}')">✕ Entfernen</button>
```

- [ ] **Step 2: Manuell verifizieren**

1. `statusline-configurator.html` im Browser öffnen
2. Maus über den roten „✕ Entfernen"-Button einer Zeile halten
3. Tooltip „Zeile entfernen" erscheint

- [ ] **Step 3: Commit**

```bash
git add statusline-configurator.html
git commit -m "fix(configurator): add missing title tooltip to line delete button"
```

---

## Abschluss

Nach Task 4 sind alle C-Punkte implementiert. Anschließend `superpowers:finishing-a-development-branch` aufrufen.
