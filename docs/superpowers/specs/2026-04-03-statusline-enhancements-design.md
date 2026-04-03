# Design Spec: Statusline Configurator Enhancements

**Date:** 2026-04-03  
**Status:** Approved

---

## Overview

Three enhancements to the existing single-file `statusline-configurator.html` and `statusline.ps1`:

1. **Layout Redesign** — Preview relocates from full-width bottom bar to right panel (under config)
2. **CWD Path Depth** — New field option to limit visible path segments
3. **Theming System** — Named themes with FG/BG colors and configurable progressbar thresholds

Implementation order: Layout → CWD Path Depth → Theming.

---

## 1. Layout Redesign

### Current Structure

```
[ Felder-Panel (260px) | Config-Panel (flex)  ]
[         Preview (full-width, outside grid)  ]
```

### Target Structure

```
[ Felder-Panel (260px) | Config-Panel         ]
[                      |   Tab-Bar            ]
[                      |   Tab-Content (scroll)|
[                      |   Preview (fixed)    ]
```

### Implementation

The `.main-panel` grid stays unchanged (260px left, flex right). The `.preview-section` is removed from the body flow and embedded at the bottom of `.config-panel`.

`.config-panel` becomes a flex-column container:

```css
.config-panel {
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.config-tabs-bar {
  flex-shrink: 0;
  /* tab buttons: [Zeilen] [Theme] */
}

.config-tabs-content {
  flex: 1;
  overflow-y: auto;
}

.preview-section {
  flex-shrink: 0;
  border-top: 1px solid var(--color-border);
}
```

The existing `panel-title` "Konfiguration" header is replaced by the tab bar. The `[Zeilen]` tab renders the existing `#lines-container` content unchanged.

---

## 2. CWD Path Depth

### Field Option

A new optional property `pathDepth` on field objects where `key` is one of: `cwd`, `workspace.current_dir`, `workspace.project_dir`.

```json
{ "type": "field", "key": "cwd", "pathDepth": 3, "fg": null, "bg": null }
```

- `pathDepth: null` — full path (default, no change in behavior)
- `pathDepth: 1` — last 1 segment, no prefix
- `pathDepth: N` — last N segments, prefixed with `...`

### Truncation Logic

Split path on both `/` and `\`. Take the last `N` segments. If segments were removed, prepend `...`. Rejoin with the detected separator (or `/` as fallback).

Examples (sample value: `/home/user/myproject`):
- `pathDepth: null` → `/home/user/myproject`
- `pathDepth: 3` → `.../home/user/myproject` (all fit, no truncation)
- `pathDepth: 1` → `myproject`

Examples (sample value: `C:\Das\ist\mein\super\langer\Pfad`):
- `pathDepth: 3` → `...\super\langer\Pfad`
- `pathDepth: 1` → `Pfad`

### Edit Dialog

For fields with a path key, a new section appears in the edit dialog:

```
Pfadtiefe
  ○ Vollständiger Pfad
  ● Letzte X Segmente: [3 ▲▼]
```

Radio toggles between full path and limited depth. Spinner/number input for X (min 1).

### Preview

`renderFieldHtml` applies the truncation when `field.pathDepth` is set.

### PowerShell Script

`statusline.ps1` must implement the same truncation logic for path-type fields when `pathDepth` is present in the field config.

---

## 3. Theming System

### Config Format

Themes are stored as a top-level array in the exported JSON alongside `lines`:

```json
{
  "activeTheme": "dark-blue",
  "themes": [
    {
      "id": "dark-blue",
      "name": "Dark Blue",
      "fieldFg": "#e0e0e0",
      "fieldBg": null,
      "progressThresholds": [
        { "upTo": 50,  "fg": "#4ade80" },
        { "upTo": 80,  "fg": "#facc15" },
        { "upTo": 100, "fg": "#f87171" }
      ]
    }
  ],
  "lines": [ ... ]
}
```

- `fieldFg` / `fieldBg` — default colors applied to all field chips when theme is applied
- `progressThresholds` — ordered array of thresholds; each entry defines the foreground color up to that percentage
- Individual field-level `fg`/`bg` values set via the edit dialog continue to take precedence over theme defaults at render time

### UI — Theme Tab

The `[Theme]` tab in the config panel contains:

1. **Theme selector** — dropdown of saved themes + `[+ Neu]` button
2. **Name field** — editable text input for theme name
3. **Field colors** — FG color picker, BG color picker
4. **Progressbar thresholds** — list of rows, each with: `bis [%]` number input + color picker. `[+ Schwelle hinzufügen]` adds a row. Each row has a delete button. Minimum 1 threshold, no hard maximum (5 is practical).
5. **Action buttons** — `[Anwenden]` and `[Abbrechen]`

### Preview Behavior

When the user selects a different theme from the dropdown, the preview updates immediately to reflect that theme's colors — without modifying the actual config state.

Implementation: on theme-dropdown change, temporarily store a `_themePreviewSnapshot` of the current state and render the preview against the snapshot with the candidate theme applied.

- `[Anwenden]` — commits the snapshot as the real state, writes `activeTheme` and applies `fieldFg`/`fieldBg` to all field objects
- `[Abbrechen]` — discards `_themePreviewSnapshot`, re-renders preview from real state

### Theme Management

- **New theme** (`[+ Neu]`) — creates a theme with default values, auto-generated ID, name "Neues Theme"
- **Delete theme** — only available if the theme is not currently active and at least one other theme exists
- **Rename** — inline via the name field in the Theme tab

### Backwards Compatibility

Existing configs without `themes` or `activeTheme` load normally. On export, if no theme has been created, `themes: []` and `activeTheme: null` are written.

### PowerShell Script

`statusline.ps1` reads `activeTheme` from the config, finds the matching theme in `themes[]`, and uses its `progressThresholds` for Progressbar color-coding. Individual field `fg`/`bg` values take precedence over `fieldFg`/`fieldBg` from the theme.

---

## Out of Scope

- Multiple theme export/import as separate files
- Theme sharing or presets
- `pathDepth` on non-path string fields
