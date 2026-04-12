# Design: Statusline Anpassungen 006

**Date:** 2026-04-12
**Branch:** feature/statusline-enhancements

---

## Overview

Two independent enhancements to `statusline-configurator.html`:

1. **Theme/Color Priority System** — non-destructive theme application with three explicit color states per field (Standard → Theme → Field Override), live preview on all color changes
2. **Drag-and-Drop Bug Fix** — field chip stays in source line on first cross-line drag; root cause is SortableJS event ordering (`onAdd` fires before `onRemove`)

---

## 1. Theme/Color Priority System

### Goal

Replace the current destructive `applyTheme()` (which bakes theme colors directly into field objects) with a non-destructive model. Each field tracks whether its own color is active (Override) or deferred to the theme or terminal default. All color changes are immediately reflected in the preview.

### Priority Chain

```
effectiveFg = fgOverride ? field.fg : (theme?.fieldFg ?? null)
effectiveBg = bgOverride ? field.bg : (theme?.fieldBg ?? null)
```

Three states per color channel (FG and BG independently):

| State | Condition | Effective color |
|---|---|---|
| Standard | No active theme, `fgOverride` false/absent | `null` → terminal default |
| Theme | Active theme set, `fgOverride` false/absent | `theme.fieldFg` |
| Override | `fgOverride: true` | `field.fg` |

### Data Model

Each field object gains two optional boolean flags:

```json
{
  "type": "field",
  "key": "model.display_name",
  "fg": "#ff0000",
  "fgOverride": true,
  "bg": null,
  "bgOverride": false
}
```

- `fgOverride: true` → `field.fg` is used regardless of active theme
- `fgOverride: false` or absent → theme or standard applies
- Same semantics for `bgOverride` / `field.bg`

### Backwards Compatibility

Existing configs that have baked-in theme colors (written by the old `applyTheme()`) are treated as active overrides. No migration code is needed. The read logic derives the effective override state as:

```javascript
const fgIsOverride = field.fgOverride ?? (field.fg !== null);
const bgIsOverride = field.bgOverride ?? (field.bg !== null);
```

This means: if `fgOverride` is absent but `fg` is set, the color is interpreted as an active override (Option B — existing baked colors are preserved as overrides).

### `applyTheme()` — Simplified

```javascript
function applyTheme(id) {
  saveThresholdInputs(id);
  state.activeTheme = id;
  _themePreviewId = null;
  render();
}
```

No longer writes into field objects. Idempotent — applying the same theme multiple times has no side effect.

### `renderFieldHtml` — Priority Chain

Replace the current `field.fg ?? previewTheme?.fieldFg ?? null` pattern with the explicit override check:

```javascript
const fgIsOverride = field.fgOverride ?? (field.fg !== null);
const bgIsOverride = field.bgOverride ?? (field.bg !== null);
const fg = fgIsOverride ? field.fg : (previewTheme?.fieldFg ?? null);
const bg = bgIsOverride ? field.bg : (previewTheme?.fieldBg ?? null);
```

Progressbar fields: the existing exclusion (`field.type === 'progressbar'`) continues to apply — theme `fieldFg` must not suppress threshold colors.

### Export (`buildExportJson`)

`fgOverride`/`bgOverride` are written only when `true`. Fields without an active override export no flag, keeping the config file compact.

```javascript
if (f.fgOverride) base.fgOverride = true;
if (f.bgOverride) base.bgOverride = true;
```

### Edit Dialog — "Farben" Tab

The existing two-input layout (FG color picker + "Keine Farbe" checkbox) is replaced with a badge + toggle design per color channel.

**Badge logic:**

| State | Badge text | Color picker visible |
|---|---|---|
| No theme, no override | `Standard` | No |
| Theme active, no override | `Theme: #xxxxxx` | No |
| Override active | `Override aktiv` | Yes |

**Layout per channel (FG shown, BG identical):**

```
Vordergrundfarbe
[Standard]  [Override aktivieren]

Vordergrundfarbe
[Theme: #686868]  [Override aktivieren]

Vordergrundfarbe
[Override aktiv]  [Override deaktivieren]
████  #ff0000
```

**Interactions:**

- **"Override aktivieren"** → sets `fgOverride = true` on `_editDraft`, shows color picker. Initial picker value: last saved `field.fg`, or active theme's `fieldFg` if present, or `#e0e0e0`
- **"Override deaktivieren"** → sets `fgOverride = false` on `_editDraft`, hides color picker. `field.fg` is retained in state (not deleted) — it is simply ignored by the priority chain until re-activated
- Color picker `oninput` → updates `_editDraft.fg` and calls `renderPreview()` immediately

The "Keine Farbe" checkbox is removed. Override deactivation replaces its function.

### Live Preview — Theme Tab

`updateThemeColor()` gains a `renderPreview()` call at the end so that FG/BG changes in the Theme tab appear in the preview without clicking "Anwenden":

```javascript
function updateThemeColor(id, prop, value) {
  const theme = state.themes.find(t => t.id === id);
  if (!theme) return;
  theme[prop] = value;
  renderPreview(); // live update
}
```

Progress threshold inputs also update live: `saveThresholdInputs()` is called on `oninput` of threshold color/value fields, followed by `renderPreview()`.

---

## 2. Drag-and-Drop Bug Fix

### Root Cause

When a field chip is dragged from drop-zone A to drop-zone B, SortableJS fires events in this order:

1. `onAdd` on zone B
2. `onRemove` on zone A

The current code sets `_draggedField` inside `onRemove`. Because `onAdd` fires first, `_draggedField` is still `null` at that point. `onAdd` reads `null`, returns early without adding the field to the target, and does not call `render()`. `onRemove` then fires, removes the field from source state, sets `_draggedField` — but nothing triggers a re-render. The DOM (managed by Sortable) shows the chip briefly in transit; when a subsequent interaction triggers `render()`, the chip appears in neither line.

The user observes the chip as staying in the source line (because no re-render occurs immediately after the failed drop).

### Fix

**New globals:**

```javascript
let _draggedField        = null; // set in onStart, consumed in onAdd
let _draggedSourceLineId = null; // set in onStart, consumed in onAdd
```

**`onStart` — added to each drop-zone Sortable:**

```javascript
onStart(evt) {
  const fieldId = evt.item.dataset.fieldId;
  const srcLine = state.lines.find(l => l.id === lineId);
  _draggedField        = srcLine?.fields.find(f => f.id === fieldId) ?? null;
  _draggedSourceLineId = lineId;
},
```

**`onAdd` — zone-to-zone branch extended:**

```javascript
} else {
  // Zone-to-zone chip move: field was stored in onStart, not onRemove
  newField = _draggedField;
  _draggedField = null;
  if (!newField) return;

  // Remove from source line here — onRemove fires after onAdd and is now a no-op
  const srcLine = state.lines.find(l => l.id === _draggedSourceLineId);
  if (srcLine && _draggedSourceLineId !== lineId) {
    srcLine.fields = srcLine.fields.filter(f => f.id !== newField.id);
  }
  _draggedSourceLineId = null;
}
```

**`onRemove` — becomes a no-op:**

```javascript
onRemove(_evt) {
  // onAdd handles full state management for cross-list moves.
  // onRemove is retained as a Sortable handler but takes no action.
},
```

**Intra-line reordering** continues to be handled by `onUpdate` — no changes there.

### Affected Files

- `statusline-configurator.html` — `initSortable()` function only

---

## Affected Files Summary

| File | Changes |
|---|---|
| `statusline-configurator.html` | `applyTheme()`, `renderFieldHtml()`, `renderEditTabColors()`, `buildExportJson()`, `updateThemeColor()`, threshold `oninput` handlers, `initSortable()` |
| `statusline-config.json` | No structural change; existing `fg`/`bg` values on fields are treated as active overrides on load |
| `statusline.ps1` | No changes — color resolution happens in the configurator only |
| `tests/statusline.Tests.ps1` | No new tests required (PS1 unchanged) |
