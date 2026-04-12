# Statusline Anpassungen 006 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a non-destructive theme/color priority system (Standard → Theme → Field Override) with live preview, and fix the cross-line field drag bug.

**Architecture:** All changes are in `statusline-configurator.html` (single-file HTML app with inline JS). No test framework exists — verification is manual via browser. Changes follow the existing patterns: inline event handlers, global state object, re-render on every mutation.

**Tech Stack:** Vanilla JS, HTML, inline CSS, SortableJS 1.15.6 (already inlined)

---

## File Map

| File | Changes |
|---|---|
| `statusline-configurator.html` | All tasks — 7 targeted function edits |

No other files are modified.

---

### Task 1: Fix `renderFieldHtml` priority chain

**Files:**
- Modify: `statusline-configurator.html` lines 2276–2277, 2303

Replace the current `field.fg ?? theme?.fieldFg ?? null` pattern with an explicit override-flag check. This is the core of the new priority system.

- [ ] **Step 1: Edit `renderFieldHtml` — fg/bg resolution (lines 2276–2277)**

Find:
```javascript
  const fg = field.fg ?? previewTheme?.fieldFg ?? null;
  const bg = field.bg ?? previewTheme?.fieldBg ?? null;
```

Replace with:
```javascript
  const fgIsOverride = field.fgOverride ?? (field.fg !== null && field.fg !== undefined);
  const bgIsOverride = field.bgOverride ?? (field.bg !== null && field.bg !== undefined);
  const fg = fgIsOverride ? field.fg : (previewTheme?.fieldFg ?? null);
  const bg = bgIsOverride ? field.bg : (previewTheme?.fieldBg ?? null);
```

- [ ] **Step 2: Edit `renderFieldHtml` — progressbar barFgOverride (line 2303)**

Find:
```javascript
    const barFgOverride = field.fg ?? null;
```

Replace with:
```javascript
    const barFgOverride = fgIsOverride ? (field.fg ?? null) : null;
```

- [ ] **Step 3: Verify in browser**

Open `statusline-configurator.html` in a browser. Check that the preview still renders correctly with the existing config (fields with baked-in `fg` values should still show their colors, since `fgOverride ?? (field.fg !== null)` treats them as active overrides).

- [ ] **Step 4: Commit**

```bash
git add statusline-configurator.html
git commit -m "refactor(configurator): use fgOverride/bgOverride flags in renderFieldHtml priority chain"
```

---

### Task 2: Simplify `applyTheme()`

**Files:**
- Modify: `statusline-configurator.html` lines 1157–1174

Remove the destructive field-color baking. `applyTheme` now only sets `state.activeTheme` and re-renders.

- [ ] **Step 1: Replace `applyTheme` body (lines 1161–1175)**

Find:
```javascript
function applyTheme(id) {
  saveThresholdInputs(id);
  const theme = state.themes.find(t => t.id === id);
  if (!theme) return;
  state.lines.forEach(line => {
    line.fields.forEach(field => {
      if (field.type === 'progressbar') return; // Theme fieldFg must not suppress threshold colors
      if (theme.fieldFg !== null) field.fg = theme.fieldFg;
      if (theme.fieldBg !== null) field.bg = theme.fieldBg;
    });
  });
  state.activeTheme = id;
  _themePreviewId   = null;
  render();
}
```

Replace with:
```javascript
function applyTheme(id) {
  saveThresholdInputs(id);
  if (!state.themes.find(t => t.id === id)) return;
  state.activeTheme = id;
  _themePreviewId   = null;
  render();
}
```

- [ ] **Step 2: Update the JSDoc comment above `applyTheme` (line 1156–1160)**

Find:
```javascript
/**
 * Applies the selected theme: writes fieldFg/fieldBg onto every field object in all lines,
 * sets state.activeTheme, and clears the preview state.
 * @param {string} id
 */
```

Replace with:
```javascript
/**
 * Applies the selected theme: sets state.activeTheme and re-renders.
 * Color resolution happens in renderFieldHtml via the fgOverride/bgOverride priority chain.
 * @param {string} id
 */
```

- [ ] **Step 3: Verify in browser**

1. Open the configurator, go to the Theme tab
2. Click "Anwenden" on a theme
3. Confirm the preview updates to show theme colors
4. Confirm no console errors
5. Click "Anwenden" a second time — verify idempotent (same result, no state corruption)

- [ ] **Step 4: Commit**

```bash
git add statusline-configurator.html
git commit -m "refactor(configurator): make applyTheme non-destructive (no longer writes into field objects)"
```

---

### Task 3: Update `buildExportJson()` — export override flags

**Files:**
- Modify: `statusline-configurator.html` lines 1388–1389

Add `fgOverride` and `bgOverride` to the export allowlist. Only write them when `true` to keep configs compact.

- [ ] **Step 1: Edit `buildExportJson` field mapping (lines 1388–1389)**

Find:
```javascript
      if (f.fg)            base.fg = f.fg;
      if (f.bg)            base.bg = f.bg;
```

Replace with:
```javascript
      if (f.fg)            base.fg = f.fg;
      if (f.fgOverride)    base.fgOverride = true;
      if (f.bg)            base.bg = f.bg;
      if (f.bgOverride)    base.bgOverride = true;
```

- [ ] **Step 2: Verify in browser**

1. Open the configurator, go to the Export tab
2. Confirm fields with `fg` set (baked-in colors from old theme) do NOT have `fgOverride` in the export yet (since `fgOverride` flag is not set on any existing field — the override is implied by presence of `fg`)
3. This is correct — the backwards-compat read logic derives the state from `fg !== null`

- [ ] **Step 3: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): export fgOverride/bgOverride flags in buildExportJson"
```

---

### Task 4: Add live preview to threshold inputs

**Files:**
- Modify: `statusline-configurator.html` lines 970–975 (inside `renderThemeTab`)

Threshold color and value changes should update the preview immediately, without having to click "Anwenden".

- [ ] **Step 1: Add `oninput` to threshold number input (line 970–972)**

Find:
```javascript
          <input type="number" class="theme-threshold-pct" data-index="${i}" min="1" max="100" value="${pt.upTo}"
                 style="width:56px;padding:4px 6px;border-radius:4px;border:1px solid var(--color-border);
                        background:var(--color-surface-2);color:var(--color-text);font-size:12px;">
```

Replace with:
```javascript
          <input type="number" class="theme-threshold-pct" data-index="${i}" min="1" max="100" value="${pt.upTo}"
                 oninput="saveThresholdInputs('${escapeHtml(currentId)}'); renderPreview();"
                 style="width:56px;padding:4px 6px;border-radius:4px;border:1px solid var(--color-border);
                        background:var(--color-surface-2);color:var(--color-text);font-size:12px;">
```

- [ ] **Step 2: Add `oninput` to threshold color input (line 974–975)**

Find:
```javascript
          <input type="color" class="theme-threshold-fg" data-index="${i}" value="${pt.fg || '#ffffff'}"
                 style="width:36px;height:28px;border:1px solid var(--color-border);border-radius:4px;padding:2px;cursor:pointer;">
```

Replace with:
```javascript
          <input type="color" class="theme-threshold-fg" data-index="${i}" value="${pt.fg || '#ffffff'}"
                 oninput="saveThresholdInputs('${escapeHtml(currentId)}'); renderPreview();"
                 style="width:36px;height:28px;border:1px solid var(--color-border);border-radius:4px;padding:2px;cursor:pointer;">
```

- [ ] **Step 3: Verify in browser**

1. Open the configurator, go to the Theme tab, select a theme
2. Change a threshold color — confirm the preview progressbar updates immediately
3. Change a threshold percentage — confirm the preview color changes at the right position

- [ ] **Step 4: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): add live preview to threshold inputs in Theme tab"
```

---

### Task 5: Rewrite `renderEditTabColors()` — badge + toggle UI

**Files:**
- Modify: `statusline-configurator.html` lines 1864–1891

Replace the two color pickers + "Keine Farbe" checkboxes with the new badge + toggle + conditional picker layout. Also add the two helper functions `activateColorOverride` and `deactivateColorOverride`.

- [ ] **Step 1: Replace `renderEditTabColors` function (lines 1864–1892)**

Find:
```javascript
function renderEditTabColors() {
  const el = document.getElementById('edit-tab-colors');
  const f  = _editDraft;
  if (!f) return;

  const fg = f.fg || '';
  const bg = f.bg || '';

  el.innerHTML = `
    <div style="margin-bottom:12px;">
      <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:6px;">Vordergrundfarbe</div>
      <div style="display:flex;align-items:center;gap:8px;">
        <input type="color" id="edit-fg" value="${fg || '#e0e0e0'}" style="cursor:pointer;">
        <label style="font-size:12px;cursor:pointer;display:flex;align-items:center;gap:4px;">
          <input type="checkbox" id="edit-fg-none" ${!fg ? 'checked' : ''}> Keine Farbe
        </label>
      </div>
    </div>
    <div>
      <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:6px;">Hintergrundfarbe</div>
      <div style="display:flex;align-items:center;gap:8px;">
        <input type="color" id="edit-bg" value="${bg || '#333333'}" style="cursor:pointer;">
        <label style="font-size:12px;cursor:pointer;display:flex;align-items:center;gap:4px;">
          <input type="checkbox" id="edit-bg-none" ${!bg ? 'checked' : ''}> Keine Farbe
        </label>
      </div>
    </div>
  `;
}
```

Replace with:
```javascript
/**
 * Renders the colors tab in the edit dialog, showing badge + toggle for each color channel.
 * Three states per channel: Standard (no theme, no override), Theme (theme active, no override),
 * Override active (field.fgOverride/bgOverride is true).
 */
function renderEditTabColors() {
  const el = document.getElementById('edit-tab-colors');
  const f  = _editDraft;
  if (!f) return;

  const activeTheme = state.themes.find(t => t.id === state.activeTheme) ?? null;

  /**
   * Builds the HTML block for one color channel (fg or bg).
   * @param {'fg'|'bg'} channel
   * @param {string} label - display label (e.g. 'Vordergrundfarbe')
   */
  function buildChannel(channel, label) {
    const overrideKey = channel + 'Override';
    const themeColor  = channel === 'fg' ? activeTheme?.fieldFg : activeTheme?.fieldBg;
    const isOverride  = f[overrideKey] ?? (f[channel] !== null && f[channel] !== undefined);
    const pickerVal   = f[channel] || themeColor || '#e0e0e0';

    let badgeText;
    if (isOverride) {
      badgeText = 'Override aktiv';
    } else if (themeColor) {
      badgeText = `Theme: ${themeColor}`;
    } else {
      badgeText = 'Standard';
    }

    const toggleLabel = isOverride ? 'Override deaktivieren' : 'Override aktivieren';
    const toggleFn    = isOverride
      ? `deactivateColorOverride('${channel}')`
      : `activateColorOverride('${channel}')`;

    return `
      <div style="margin-bottom:16px;">
        <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:6px;">${label}</div>
        <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;">
          <span style="font-size:11px;padding:2px 8px;border-radius:10px;
                       background:var(--color-surface-2);color:var(--color-text-muted);">
            ${escapeHtml(badgeText)}
          </span>
          <button class="btn" style="font-size:11px;padding:3px 10px;"
                  onclick="${toggleFn}">${toggleLabel}</button>
        </div>
        ${isOverride ? `
          <div style="margin-top:8px;">
            <input type="color" id="edit-${channel}" value="${escapeHtml(pickerVal)}"
                   style="cursor:pointer;"
                   oninput="_editDraft.${channel} = this.value; renderPreview();">
          </div>
        ` : ''}
      </div>
    `;
  }

  el.innerHTML =
    buildChannel('fg', 'Vordergrundfarbe') +
    buildChannel('bg', 'Hintergrundfarbe');
}

/**
 * Activates the field color override for the given channel.
 * Initialises field.fg/bg to the theme color or a default if not already set.
 * @param {'fg'|'bg'} channel
 */
function activateColorOverride(channel) {
  const overrideKey = channel + 'Override';
  const activeTheme = state.themes.find(t => t.id === state.activeTheme) ?? null;
  const themeColor  = channel === 'fg' ? activeTheme?.fieldFg : activeTheme?.fieldBg;
  if (!_editDraft[channel]) {
    _editDraft[channel] = themeColor ?? '#e0e0e0';
  }
  _editDraft[overrideKey] = true;
  renderEditTabColors();
  renderPreview();
}

/**
 * Deactivates the field color override for the given channel.
 * The stored fg/bg value is retained but ignored by the priority chain.
 * @param {'fg'|'bg'} channel
 */
function deactivateColorOverride(channel) {
  _editDraft[channel + 'Override'] = false;
  renderEditTabColors();
  renderPreview();
}
```

- [ ] **Step 2: Verify in browser**

1. Open the configurator, click the edit (✏️) button on any field
2. Switch to the "Farben" tab
3. Confirm the badge shows the correct state:
   - Field with no theme active and `fg: null` → badge shows `Standard`
   - Field with active theme and `fg: null` → badge shows `Theme: #xxxxxx`
   - Field with `fg` set (baked from old theme) → badge shows `Override aktiv` with color picker visible
4. Click "Override aktivieren" on a Standard field → picker appears, preview updates
5. Change the picker color → preview updates live
6. Click "Override deaktivieren" → picker disappears, preview reverts to theme/standard color

- [ ] **Step 3: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): rewrite colors tab in edit dialog with badge+toggle override UI"
```

---

### Task 6: Update `saveEditDialog()` — read new override flags

**Files:**
- Modify: `statusline-configurator.html` lines 1940–1949

Replace the old "Keine Farbe" checkbox read logic with the new override-aware read. Since `activateColorOverride`/`deactivateColorOverride` already keep `_editDraft` in sync, `saveEditDialog` only needs to capture the final picker value if the picker is rendered.

- [ ] **Step 1: Replace the colors-tab read block in `saveEditDialog` (lines 1940–1949)**

Find:
```javascript
  // Read Farben tab values into draft — only if the tab was actually rendered.
  // If the user never switched to the Colors tab, the DOM elements don't exist and
  // _editDraft retains the fg/bg values copied at dialog-open time.
  const fgNoneEl = document.getElementById('edit-fg-none');
  if (fgNoneEl !== null) {
    _editDraft.fg = fgNoneEl.checked ? null : (document.getElementById('edit-fg')?.value || null);
    _editDraft.bg = document.getElementById('edit-bg-none')?.checked
      ? null
      : (document.getElementById('edit-bg')?.value || null);
  }
```

Replace with:
```javascript
  // Read Farben tab values into draft — only if the tab was actually rendered.
  // fgOverride/bgOverride are already up-to-date (set by activateColorOverride/deactivateColorOverride).
  // Capture the final picker values in case oninput did not fire (e.g. programmatic change).
  const fgInput = document.getElementById('edit-fg');
  if (fgInput) _editDraft.fg = fgInput.value;
  const bgInput = document.getElementById('edit-bg');
  if (bgInput) _editDraft.bg = bgInput.value;
```

- [ ] **Step 2: Verify in browser**

1. Open a field's edit dialog, go to "Farben" tab
2. Activate Override for FG, choose a color, click Speichern
3. Reopen the edit dialog — confirm the "Override aktiv" badge and the saved color are shown
4. Deactivate the override, click Speichern
5. Reopen — confirm badge shows "Standard" or "Theme: ..."
6. Confirm the preview in the main view reflects the correct effective color after save

- [ ] **Step 3: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): update saveEditDialog to read fgOverride/bgOverride from new colors tab"
```

---

### Task 7: Fix cross-line field drag bug

**Files:**
- Modify: `statusline-configurator.html` lines 1289–1352 (inside `initSortable`)

Root cause: SortableJS fires `onAdd` (target) before `onRemove` (source). The current code stores the dragged field in `onRemove`, so `onAdd` sees `_draggedField = null` and returns early. Fix: store the field in `onStart` and let `onAdd` handle removal from source.

- [ ] **Step 1: Add `_draggedSourceLineId` global (near line 1536)**

Find:
```javascript
let _draggedField = null; // buffer for zone-to-zone chip drag
```

Replace with:
```javascript
let _draggedField        = null; // buffer for zone-to-zone chip drag (set in onStart)
let _draggedSourceLineId = null; // source line id for zone-to-zone drag (set in onStart)
```

- [ ] **Step 2: Update the drop-zone Sortable creation in `initSortable` (lines 1289–1351)**

Find:
```javascript
  document.querySelectorAll('.line-drop-zone').forEach(zone => {
    const lineId = zone.dataset.lineId;
    if (zone._sortable) zone._sortable.destroy();
    zone._sortable = Sortable.create(zone, {
      group: { name: 'fields', pull: true, put: true },
      animation: 150,
      ghostClass: 'sortable-ghost',
      draggable: '.field-chip',
      onAdd(evt) {
        const panelFieldType     = evt.item?.dataset?.fieldType;
        const panelCustomFieldId = evt.item?.dataset?.customFieldId;
        const panelFieldKey      = evt.item?.dataset?.fieldKey;
        evt.item.remove();
        let newField;
        if (panelFieldType === 'new_fields_indicator') {
          // Diagnose palette item
          newField = { id: generateId(), type: 'new_fields_indicator', fg: null, bg: null };
          _draggedField = null;
        } else if (panelCustomFieldId) {
          // Custom-field clone from "Eigene Felder" palette → independent static copy
          const cf = state.customFields.find(f => f.id === panelCustomFieldId);
          if (!cf) return;
          newField = { id: generateId(), type: 'static', text: cf.text, fg: cf.fg, bg: cf.bg };
          _draggedField = null;
        } else if (panelFieldKey) {
          // Left-panel known field clone → apply FIELD_TYPE_DEFAULTS automatically
          const isPercentage = PERCENTAGE_KEYS.has(panelFieldKey);
          const defaults = FIELD_TYPE_DEFAULTS[panelFieldKey] || {};
          newField = isPercentage
            ? { id: generateId(), type: 'progressbar', key: panelFieldKey, progressStyle: 'color-coded', barBrackets: true, barCharset: 'block', fg: null, bg: null }
            : { id: generateId(), type: 'field', key: panelFieldKey, ...defaults, fg: null, bg: null };
          _draggedField = null;
        } else {
          // Zone-to-zone chip move → use the field buffered by onRemove
          newField = _draggedField;
          _draggedField = null;
          if (!newField) return;
        }
        const line = state.lines.find(l => l.id === lineId);
        if (!line) return;
        const safeIndex = Math.min(evt.newIndex, line.fields.length);
        line.fields.splice(safeIndex, 0, newField);
        render();
      },
      onUpdate(evt) {
        const zone = evt.to;
        const chips = [...zone.querySelectorAll('.field-chip')];
        const newOrder = chips.map(c => c.dataset.fieldId);
        const line = state.lines.find(l => l.id === lineId);
        if (!line) return;
        line.fields = newOrder.map(id => line.fields.find(f => f.id === id)).filter(Boolean);
        updateExportTextarea();
        renderPreview();
      },
      onRemove(evt) {
        const fieldId = evt.item.dataset.fieldId;
        const line = state.lines.find(l => l.id === lineId);
        if (!line) return;
        _draggedField = line.fields.find(f => f.id === fieldId) || null;
        line.fields = line.fields.filter(f => f.id !== fieldId);
      },
    });
  });
```

Replace with:
```javascript
  document.querySelectorAll('.line-drop-zone').forEach(zone => {
    const lineId = zone.dataset.lineId;
    if (zone._sortable) zone._sortable.destroy();
    zone._sortable = Sortable.create(zone, {
      group: { name: 'fields', pull: true, put: true },
      animation: 150,
      ghostClass: 'sortable-ghost',
      draggable: '.field-chip',
      onStart(evt) {
        // Store the dragged field at drag-start so onAdd can access it regardless of
        // event order — SortableJS fires onAdd (target) before onRemove (source).
        const fieldId = evt.item.dataset.fieldId;
        const srcLine = state.lines.find(l => l.id === lineId);
        _draggedField        = srcLine?.fields.find(f => f.id === fieldId) ?? null;
        _draggedSourceLineId = lineId;
      },
      onAdd(evt) {
        const panelFieldType     = evt.item?.dataset?.fieldType;
        const panelCustomFieldId = evt.item?.dataset?.customFieldId;
        const panelFieldKey      = evt.item?.dataset?.fieldKey;
        evt.item.remove();
        let newField;
        if (panelFieldType === 'new_fields_indicator') {
          // Diagnose palette item
          newField = { id: generateId(), type: 'new_fields_indicator', fg: null, bg: null };
          _draggedField = null;
        } else if (panelCustomFieldId) {
          // Custom-field clone from "Eigene Felder" palette → independent static copy
          const cf = state.customFields.find(f => f.id === panelCustomFieldId);
          if (!cf) return;
          newField = { id: generateId(), type: 'static', text: cf.text, fg: cf.fg, bg: cf.bg };
          _draggedField = null;
        } else if (panelFieldKey) {
          // Left-panel known field clone → apply FIELD_TYPE_DEFAULTS automatically
          const isPercentage = PERCENTAGE_KEYS.has(panelFieldKey);
          const defaults = FIELD_TYPE_DEFAULTS[panelFieldKey] || {};
          newField = isPercentage
            ? { id: generateId(), type: 'progressbar', key: panelFieldKey, progressStyle: 'color-coded', barBrackets: true, barCharset: 'block', fg: null, bg: null }
            : { id: generateId(), type: 'field', key: panelFieldKey, ...defaults, fg: null, bg: null };
          _draggedField = null;
        } else {
          // Zone-to-zone chip move: field was captured in onStart.
          // Also remove from source line here — onAdd fires before onRemove in cross-list moves.
          newField = _draggedField;
          _draggedField = null;
          if (!newField) return;
          if (_draggedSourceLineId && _draggedSourceLineId !== lineId) {
            const srcLine = state.lines.find(l => l.id === _draggedSourceLineId);
            if (srcLine) srcLine.fields = srcLine.fields.filter(f => f.id !== newField.id);
          }
          _draggedSourceLineId = null;
        }
        const line = state.lines.find(l => l.id === lineId);
        if (!line) return;
        const safeIndex = Math.min(evt.newIndex, line.fields.length);
        line.fields.splice(safeIndex, 0, newField);
        render();
      },
      onUpdate(evt) {
        const zone = evt.to;
        const chips = [...zone.querySelectorAll('.field-chip')];
        const newOrder = chips.map(c => c.dataset.fieldId);
        const line = state.lines.find(l => l.id === lineId);
        if (!line) return;
        line.fields = newOrder.map(id => line.fields.find(f => f.id === id)).filter(Boolean);
        updateExportTextarea();
        renderPreview();
      },
      onRemove(_evt) {
        // onAdd handles full state management for cross-list moves (captured in onStart).
        // onRemove is retained as a required Sortable handler but takes no action.
      },
    });
  });
```

- [ ] **Step 3: Verify in browser**

1. Open the configurator with at least two lines configured
2. Drag a field chip from line 1 to line 2 — confirm it appears in line 2 on the first attempt
3. Drag a field chip from line 2 back to line 1 — confirm it works on the first attempt
4. Drag a field within the same line (reorder) — confirm `onUpdate` still handles it correctly
5. Drag a new field from the left panel into a line — confirm it still works
6. Drag a custom field from the palette into a line — confirm it still works

- [ ] **Step 4: Commit**

```bash
git add statusline-configurator.html
git commit -m "fix(configurator): store dragged field in onStart to fix cross-line drop requiring double-drag"
```

---

## Self-Review

**Spec coverage:**

| Spec requirement | Task |
|---|---|
| Priority chain: Override > Theme > Standard | Task 1 |
| `applyTheme` non-destructive | Task 2 |
| Export `fgOverride`/`bgOverride` | Task 3 |
| Backwards compat (baked colors = override) | Task 1 (read logic) |
| Badge + toggle in Farben tab | Task 5 |
| Live preview on Override toggle/color change | Task 5 (`oninput` + `renderPreview()`) |
| Live preview on Theme FG/BG change | Already implemented (`updateThemeColor` calls `renderPreview`) |
| Live preview on threshold change | Task 4 |
| Drag bug fix | Task 7 |

**No placeholders found.**

**Type consistency check:**
- `fgOverride`/`bgOverride` used consistently in Tasks 1, 3, 5, 6
- `_draggedField` / `_draggedSourceLineId` introduced in Task 7 (global), used only in `initSortable`
- `activateColorOverride('fg'|'bg')` and `deactivateColorOverride('fg'|'bg')` defined in Task 5 and called from inline `onclick` attributes in Task 5 — consistent
- `escapeHtml(badgeText)` in Task 5: `badgeText` is built from controlled strings (no user input), but escaping is correct defensive practice
