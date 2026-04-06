# Spec: Verschiebbare Zeilen im Konfigurator

**Datum:** 2026-04-06
**Status:** Draft

## Context

Im Statusline-Konfigurator (`statusline-configurator.html`) können Zeilen derzeit nur in der Reihenfolge ihrer Erstellung verwendet werden. Wer eine Zeile nachträglich an eine andere Position verschieben möchte, muss sie löschen und neu anlegen — inklusive aller Felder. Dieses Feature fügt Drag & Drop für Zeilen hinzu, konsistent mit dem bestehenden Feld-Drag&Drop.

## Design

### Ansatz

Neue `Sortable.create()`-Instanz auf `#lines-container`, analog zu den bestehenden Feld-Drop-Zones. Sortable.js v1.15.6 ist bereits inline eingebunden (ab Zeile 302).

### Änderungen in `statusline-configurator.html`

#### 1. CSS — Drag-Handle Styling

Neue Klasse `.line-drag-handle`:
- Angezeigt als `⠿`-Icon (oder vergleichbar) links im Zeilen-Header
- `cursor: grab` / `cursor: grabbing` (beim Ziehen)
- Dezentes Styling, konsistent mit dem bestehenden Theme

#### 2. `renderLines()` — Handle ins DOM

Jeder Zeilen-Header bekommt ein Drag-Handle-Element:
```
[⠿] Zeile 1                              [Entfernen]
```
- HTML-Element: `<span class="line-drag-handle">⠿</span>`
- Positioniert vor dem Zeilen-Titel

#### 3. `initSortable()` — Neue Sortable-Instanz auf `#lines-container`

```js
Sortable.create(document.getElementById('lines-container'), {
  handle: '.line-drag-handle',
  animation: 150,
  onEnd(evt) {
    // DOM-Reihenfolge auslesen und state.lines umsortieren
    const lineElements = [...document.getElementById('lines-container').children];
    const newOrder = lineElements.map(el => el.dataset.lineId);
    state.lines = newOrder.map(id => state.lines.find(l => l.id === id)).filter(Boolean);
    render();
  }
});
```

- `handle: '.line-drag-handle'` — nur am Handle ziehbar, nicht am ganzen Block
- `animation: 150` — konsistent mit Feld-Sortables
- `onEnd`: State-Array neu ordnen → `render()` aktualisiert Nummerierung, Preview, Export

#### 4. `renderLines()` — `data-line-id` auf Zeilen-Container

Jedes Zeilen-Element braucht ein `data-line-id` Attribut, damit `onEnd` die neue Reihenfolge auslesen kann.

### Was sich automatisch ergibt

- **Zeilen-Nummerierung** passt sich an (`lineIndex + 1` in `renderLines()`)
- **Preview** aktualisiert sich (`render()` → `renderPreview()`)
- **Export-JSON** aktualisiert sich (`render()` → `updateExportTextarea()`)
- **Feld-Sortables** werden in `initSortable()` bei jedem `render()` neu initialisiert

### Was NICHT geändert wird

- Feld-Drag&Drop (bestehende Sortable-Instanzen)
- Import/Export-Format (JSON-Struktur bleibt identisch)
- Keine neuen Dependencies

## Verification

1. **Manuell im Browser testen:**
   - Zeile 1 mit Feldern anlegen, Zeile 2 anlegen
   - Zeile 1 am Handle hinter Zeile 2 ziehen
   - Prüfen: Nummerierung aktualisiert, Preview korrekt, Export-JSON Reihenfolge stimmt
2. **Edge Cases:**
   - Nur eine Zeile → Handle sichtbar, aber kein Verschieben möglich
   - 10 Zeilen → alle verschiebbar
   - Nach Verschieben: Felder innerhalb der Zeilen bleiben intakt
   - Nach Verschieben: Feld-Drag&Drop zwischen Zeilen funktioniert weiterhin
3. **Bestehende Tests:** `tests/statusline.Tests.ps1` laufen lassen (PowerShell-Script, nicht Konfigurator — sollte nicht betroffen sein)
