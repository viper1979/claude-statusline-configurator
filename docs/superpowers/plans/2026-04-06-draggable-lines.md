# Draggable Lines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zeilen im Konfigurator per Drag & Drop verschiebbar machen, sodass die Reihenfolge nachträglich geändert werden kann.

**Architecture:** Neue Sortable.js-Instanz auf `#lines-container` mit Drag-Handle pro Zeile. State-Synchronisation über `onEnd`-Callback. Keine neuen Dependencies — Sortable.js v1.15.6 ist bereits inline eingebunden.

**Tech Stack:** Sortable.js (inline), Vanilla JS/HTML/CSS

**Spec:** `docs/superpowers/specs/2026-04-06-draggable-lines-design.md`

---

### Task 1: CSS — Drag-Handle Klasse hinzufügen

**Files:**
- Modify: `statusline-configurator.html:201` (nach `.btn-icon:hover` Regel)

- [ ] **Step 1: CSS-Regel einfügen**

Nach Zeile 201 (`.btn-icon:hover { ... }`) und vor Zeile 202 (`.sortable-ghost {`) folgende CSS-Regel einfügen:

```css
    .line-drag-handle {
      cursor: grab;
      color: var(--color-text-muted);
      font-size: 16px;
      padding: 2px 4px;
      user-select: none;
      border-radius: 3px;
      transition: color 0.15s;
    }
    .line-drag-handle:hover {
      color: var(--color-text);
      background: var(--color-surface-2);
    }
    .line-drag-handle:active {
      cursor: grabbing;
    }
    .sortable-line-ghost {
      opacity: 0.4;
      background: var(--color-surface-2) !important;
      border-radius: var(--radius);
    }
```

- [ ] **Step 2: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): add CSS classes for line drag handle"
```

---

### Task 2: `renderLines()` — Drag-Handle und `data-line-id` hinzufügen

**Files:**
- Modify: `statusline-configurator.html:1165-1189` (`renderLines()` Funktion)

- [ ] **Step 1: `renderLines()` anpassen**

Die Funktion `renderLines()` (Zeile 1165-1189) ersetzen durch:

```js
function renderLines() {
  const container = document.getElementById('lines-container');
  container.innerHTML = '';

  state.lines.forEach((line, lineIndex) => {
    const lineEl = document.createElement('div');
    lineEl.dataset.lineId = line.id;
    lineEl.style.cssText = 'margin-bottom:12px;';
    lineEl.innerHTML = `
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:6px;">
        <span class="line-drag-handle" title="Zeile verschieben">⠿</span>
        <span style="font-size:11px;color:var(--color-text-muted);">Zeile ${lineIndex + 1}</span>
        <button class="btn btn-danger" style="padding:2px 8px;font-size:11px;" onclick="removeLine('${line.id}')">✕ Entfernen</button>
      </div>
      <div class="line-drop-zone" data-line-id="${line.id}"
           style="min-height:44px;background:var(--color-surface);border:1.5px dashed var(--color-border);
                  border-radius:var(--radius);padding:6px 8px;display:flex;flex-wrap:wrap;gap:6px;align-items:center;">
        ${line.fields.length === 0
          ? '<span style="color:var(--color-text-muted);font-size:12px;pointer-events:none;">Felder hier hineinziehen…</span>'
          : line.fields.map(f => renderFieldChip(f, line.id)).join('')
        }
      </div>
    `;
    container.appendChild(lineEl);
  });
}
```

Änderungen gegenüber dem Original:
1. `lineEl.dataset.lineId = line.id;` — ermöglicht Reihenfolge-Auslesen im `onEnd`-Callback
2. `<span class="line-drag-handle" title="Zeile verschieben">⠿</span>` — Drag-Handle vor dem Zeilen-Titel

- [ ] **Step 2: Im Browser prüfen**

`statusline-configurator.html` im Browser öffnen, 2-3 Zeilen anlegen. Prüfen:
- Jede Zeile zeigt links ein `⠿` Icon
- Hover über das Icon ändert die Farbe
- Cursor wird zu `grab` auf dem Handle

- [ ] **Step 3: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): add drag handle and data-line-id to line elements"
```

---

### Task 3: `initSortable()` — Sortable-Instanz für `#lines-container`

**Files:**
- Modify: `statusline-configurator.html:1223` (`initSortable()` Funktion)

- [ ] **Step 1: Lines-Container Sortable-Instanz hinzufügen**

Am Anfang von `initSortable()` (nach Zeile 1223, vor dem Kommentar "Destroy old per-group Sortable instances" auf Zeile 1224), folgenden Block einfügen:

```js
  // ── Sortable for line reordering ──
  const linesContainer = document.getElementById('lines-container');
  if (linesContainer._sortable) { linesContainer._sortable.destroy(); linesContainer._sortable = null; }
  linesContainer._sortable = Sortable.create(linesContainer, {
    handle: '.line-drag-handle',
    animation: 150,
    ghostClass: 'sortable-line-ghost',
    onEnd() {
      const lineElements = [...linesContainer.children];
      const newOrder = lineElements.map(el => el.dataset.lineId);
      state.lines = newOrder.map(id => state.lines.find(l => l.id === id)).filter(Boolean);
      render();
    }
  });

```

Der vollständige Anfang von `initSortable()` sieht dann so aus:

```js
function initSortable() {
  // ── Sortable for line reordering ──
  const linesContainer = document.getElementById('lines-container');
  if (linesContainer._sortable) { linesContainer._sortable.destroy(); linesContainer._sortable = null; }
  linesContainer._sortable = Sortable.create(linesContainer, {
    handle: '.line-drag-handle',
    animation: 150,
    ghostClass: 'sortable-line-ghost',
    onEnd() {
      const lineElements = [...linesContainer.children];
      const newOrder = lineElements.map(el => el.dataset.lineId);
      state.lines = newOrder.map(id => state.lines.find(l => l.id === id)).filter(Boolean);
      render();
    }
  });

  // Destroy old per-group Sortable instances
  document.querySelectorAll('.field-group-list').forEach(list => {
    ...
```

- [ ] **Step 2: Im Browser testen**

`statusline-configurator.html` im Browser öffnen. Teste folgende Szenarien:

1. **Grundfunktion:** 3 Zeilen anlegen, jeweils mit unterschiedlichen Feldern. Zeile 1 am Handle hinter Zeile 3 ziehen.
   - Erwartung: Nummerierung aktualisiert ("Zeile 1/2/3"), Felder bleiben in ihren Zeilen.

2. **Preview:** Nach Verschieben die Vorschau prüfen.
   - Erwartung: Reihenfolge der Zeilen in der Vorschau entspricht der neuen Anordnung.

3. **Export-JSON:** Nach Verschieben das Export-JSON prüfen.
   - Erwartung: `lines`-Array im JSON spiegelt die neue Reihenfolge wider.

4. **Feld-Drag&Drop:** Nach Zeilen-Verschiebung ein Feld aus der Palette in eine Zeile ziehen, ein Feld zwischen Zeilen verschieben.
   - Erwartung: Funktioniert wie vorher.

5. **Edge Case — 1 Zeile:** Nur eine Zeile → Handle sichtbar, kein Verschieben möglich.

6. **Edge Case — 10 Zeilen:** Maximum-Anzahl Zeilen → alle verschiebbar.

- [ ] **Step 3: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): enable line reordering via drag and drop"
```

---

## Verification

Nach Abschluss aller Tasks im Browser prüfen:

1. Zeilen anlegen, mit Feldern füllen, Reihenfolge per Drag & Drop ändern
2. Nummerierung, Preview und Export-JSON aktualisieren sich korrekt
3. Feld-Drag&Drop (innerhalb Zeile, zwischen Zeilen, aus Palette) funktioniert weiterhin
4. Import einer bestehenden `statusline-config.json` → Zeilen erscheinen, sind verschiebbar
5. `tests/statusline.Tests.ps1` laufen lassen — sollte nicht betroffen sein, da nur PowerShell-Script getestet wird
