# Statusline Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement three enhancements to `statusline-configurator.html` and `statusline.ps1`: layout redesign (preview moves into right panel), CWD path depth option, and a theming system with FG/BG colors and configurable progressbar thresholds.

**Architecture:** All HTML-side changes are in the single file `statusline-configurator.html`. The PS changes extend `statusline.ps1` with a `Truncate-Path` function and dynamic threshold reading. Tasks are ordered: layout first (no logic changes), CWD depth second (isolated feature), theming last (most invasive).

**Tech Stack:** Vanilla HTML/CSS/JS (no build step), PowerShell 7+, Pester 5.x

---

## File Map

| File | Changes |
|---|---|
| `statusline-configurator.html` | CSS (layout), HTML (tab structure), JS (tab switching, truncatePath, PATH_KEYS, pathDepth edit UI, theme state, renderThemeTab, applyTheme, makeProgressBar thresholds) |
| `statusline.ps1` | `Truncate-Path` function, `Format-Field` pathDepth call, `$script:PbThresholds`, `Format-ProgressBar` dynamic thresholds, `Invoke-Main` theme reading |
| `tests/statusline.Tests.ps1` | New Describe blocks for `Truncate-Path` and dynamic thresholds |

---

## Task 1: Layout Redesign — CSS and HTML

**Files:**
- Modify: `statusline-configurator.html` (CSS ~line 86, HTML ~line 184)

### Overview
Replace the full-width bottom `.preview-section` with a layout where preview lives inside `.config-panel` at the bottom. The config panel becomes a flex-column container with a tab bar on top, scrollable content in the middle, and a fixed preview at the bottom.

- [ ] **Step 1: Update `.config-panel` CSS**

Find and replace the existing `.config-panel` block:
```css
/* OLD: */
.config-panel {
  padding: 16px;
  overflow-y: auto;
}
```
Replace with:
```css
/* NEW: */
.config-panel {
  display: flex;
  flex-direction: column;
  overflow: hidden;
  min-height: 0;
}

.config-tabs-bar {
  display: flex;
  border-bottom: 1px solid var(--color-border);
  flex-shrink: 0;
  background: var(--color-surface);
}

.config-tab-btn {
  padding: 10px 16px;
  font-size: 12px;
  font-weight: 500;
  background: none;
  border: none;
  border-bottom: 2px solid transparent;
  color: var(--color-text-muted);
  cursor: pointer;
  transition: color 0.12s;
}

.config-tab-btn:hover { color: var(--color-text); }

.config-tab-btn.active {
  color: var(--color-accent);
  border-bottom-color: var(--color-accent);
}

.config-tabs-content {
  flex: 1;
  overflow-y: auto;
  padding: 16px;
}
```

- [ ] **Step 2: Replace `.main-panel` HTML content**

Find the existing `<main class="config-panel">` block (currently lines ~184–188):
```html
    <main class="config-panel">
      <div class="panel-title">Konfiguration</div>
      <div id="lines-container"></div>
      <button class="btn" id="btn-add-line" onclick="addLine()" style="margin-top:8px;">+ Zeile hinzufügen</button>
    </main>
  </div>
```
Replace with:
```html
    <main class="config-panel">
      <div class="config-tabs-bar">
        <button class="config-tab-btn active" data-tab="lines" onclick="switchMainTab('lines')">Zeilen</button>
        <button class="config-tab-btn" data-tab="theme" onclick="switchMainTab('theme')">Theme</button>
      </div>
      <div class="config-tabs-content">
        <div class="main-tab-content" id="main-tab-lines">
          <div id="lines-container"></div>
          <button class="btn" id="btn-add-line" onclick="addLine()" style="margin-top:8px;">+ Zeile hinzufügen</button>
        </div>
        <div class="main-tab-content" id="main-tab-theme" style="display:none;"></div>
      </div>
      <section class="preview-section">
        <div class="panel-title" style="margin-bottom:8px;">Vorschau</div>
        <div class="preview-output" id="preview-output" aria-live="polite"></div>
      </section>
    </main>
  </div>
```

- [ ] **Step 3: Remove the standalone `<section class="preview-section">`**

Find and delete the standalone preview section that currently appears right after the closing `</div>` of `.main-panel`:
```html
  <section class="preview-section">
    <div class="panel-title" style="margin-bottom:8px;">Vorschau</div>
    <div class="preview-output" id="preview-output" aria-live="polite"></div>
  </section>
```
Delete this block entirely (the preview now lives inside `.config-panel`).

- [ ] **Step 4: Add `switchMainTab` JS function**

In the JS section, after the `render()` function definition, add:
```javascript
// ─── Main tab switching ───────────────────────────────────────────────────

/**
 * Switches between 'lines' and 'theme' tabs in the config panel.
 * @param {string} tab - 'lines' | 'theme'
 */
function switchMainTab(tab) {
  document.querySelectorAll('.config-tab-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.tab === tab);
  });
  document.querySelectorAll('.main-tab-content').forEach(el => {
    el.style.display = el.id === `main-tab-${tab}` ? '' : 'none';
  });
  if (tab === 'theme') renderThemeTab();
}
```

- [ ] **Step 5: Verify in browser**

Open `statusline-configurator.html` in a browser. Expected:
- Header at top
- Two-column layout below (fields panel left, config panel right fills height)
- Inside config panel: "Zeilen" and "Theme" tabs at top
- Preview section fixed at bottom of config panel — always visible when scrolling lines
- Export section still below the full layout
- "Zeilen" tab active by default and shows existing lines-container content

---

## Task 2: CWD Path Depth — JS helpers and preview rendering

**Files:**
- Modify: `statusline-configurator.html` (constants ~line 295, renderFieldHtml ~line 1329)

- [ ] **Step 1: Add `PATH_KEYS` constant**

Directly after the `PERCENTAGE_KEYS` constant block:
```javascript
// Fields that contain file-system paths (offer pathDepth option)
const PATH_KEYS = new Set(['cwd', 'workspace.current_dir', 'workspace.project_dir']);
```

- [ ] **Step 2: Add `truncatePath` helper function**

In the JS section near the other utility functions (after `escapeHtml`):
```javascript
/**
 * Truncates a path string to the last N segments, prefixed with "..." if segments
 * were removed. Returns the original value unchanged if depth is null/0 or the path
 * has fewer segments than depth.
 * @param {string} value - path string (may use / or \ as separator)
 * @param {number|null} depth - number of trailing segments to keep
 * @returns {string}
 */
function truncatePath(value, depth) {
  if (!depth || depth <= 0) return value;
  const sep   = value.includes('\\') ? '\\' : '/';
  const parts = value.split(/[/\\]/).filter(p => p !== '');
  if (parts.length <= depth) return value;
  return '...' + sep + parts.slice(parts.length - depth).join(sep);
}
```

- [ ] **Step 3: Update `renderFieldHtml` to apply path truncation**

In `renderFieldHtml`, find the final block for `type === 'field'`:
```javascript
  // type === 'field' — apply dataType formatting if configured
  const formatted = field.dataType
    ? formatFieldValue(raw, field.dataType, field.format, field.formatOptions)
    : String(raw);
  return `<span style="${style}">${escapeHtml(formatted)}</span>`;
```
Replace with:
```javascript
  // type === 'field' — apply dataType formatting if configured
  let displayValue = field.dataType
    ? formatFieldValue(raw, field.dataType, field.format, field.formatOptions)
    : String(raw);
  if (field.pathDepth && PATH_KEYS.has(field.key)) {
    displayValue = truncatePath(displayValue, field.pathDepth);
  }
  return `<span style="${style}">${escapeHtml(displayValue)}</span>`;
```

- [ ] **Step 4: Verify in browser**

Drag the "CWD" field into a line. The sample data value is `/home/user/myproject`. Expected: full path shown (no pathDepth set yet). The feature is not exposed in UI yet — that's Task 3.

---

## Task 3: CWD Path Depth — Edit dialog, export, and import

**Files:**
- Modify: `statusline-configurator.html` (renderEditTabGeneral ~line 1028, saveEditDialog ~line 1170, loadConfig ~line 822, buildExportJson ~line 741)

- [ ] **Step 1: Add pathDepth UI to `renderEditTabGeneral`**

Find the `else` branch at the end of `renderEditTabGeneral` (the `type === 'field'` case):
```javascript
  } else {
    // type === 'field' — key is read-only
    el.innerHTML = `
      <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:4px;">Key</div>
      <div style="padding:6px 8px;border-radius:4px;border:1px solid var(--color-border);
                  background:var(--color-surface-2);font-size:12px;color:var(--color-text-muted);">
        ${escapeHtml(f.key || '')}
      </div>
    `;
  }
```
Replace with:
```javascript
  } else {
    // type === 'field' — key is read-only; path fields also show pathDepth option
    const isPathField = PATH_KEYS.has(f.key);
    const hasDepth    = f.pathDepth != null && f.pathDepth > 0;
    el.innerHTML = `
      <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:4px;">Key</div>
      <div style="padding:6px 8px;border-radius:4px;border:1px solid var(--color-border);
                  background:var(--color-surface-2);font-size:12px;color:var(--color-text-muted);
                  margin-bottom:${isPathField ? '12px' : '0'};">
        ${escapeHtml(f.key || '')}
      </div>
      ${isPathField ? `
        <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:6px;">Pfadtiefe</div>
        <label style="display:flex;align-items:center;gap:8px;font-size:12px;margin-bottom:4px;cursor:pointer;">
          <input type="radio" name="edit-path-depth" value="full" ${!hasDepth ? 'checked' : ''}>
          <span>Vollständiger Pfad</span>
        </label>
        <label style="display:flex;align-items:center;gap:8px;font-size:12px;cursor:pointer;">
          <input type="radio" name="edit-path-depth" value="limited" ${hasDepth ? 'checked' : ''}>
          <span>Letzte</span>
          <input type="number" id="edit-path-depth-n" min="1" value="${hasDepth ? f.pathDepth : 2}"
                 style="width:52px;padding:3px 6px;border-radius:4px;border:1px solid var(--color-border);
                        background:var(--color-surface-2);color:var(--color-text);font-size:12px;">
          <span>Segment(e)</span>
        </label>
      ` : ''}
    `;
  }
```

- [ ] **Step 2: Update `saveEditDialog` to read pathDepth**

In `saveEditDialog`, after the block that reads the progressbar style radio:
```javascript
  if (pbCharsetRadio)       _editDraft.barCharset  = pbCharsetRadio.value;
  if (pbBracketsEl !== null) _editDraft.barBrackets = pbBracketsEl.checked;
```
Add:
```javascript
  // Read pathDepth for path-key fields
  const pathDepthRadio = document.querySelector('[name="edit-path-depth"]:checked');
  if (pathDepthRadio) {
    if (pathDepthRadio.value === 'full') {
      _editDraft.pathDepth = null;
    } else {
      const n = parseInt(document.getElementById('edit-path-depth-n')?.value, 10);
      _editDraft.pathDepth = (isNaN(n) || n < 1) ? 1 : n;
    }
  }
```

- [ ] **Step 3: Update `loadConfig` to load `pathDepth`**

In `loadConfig`, inside the field mapping (after the `formatOptions` line):
```javascript
      dataType:      f.dataType      || null,
      format:        f.format        || null,
      formatOptions: f.formatOptions || null,
```
Add:
```javascript
      pathDepth:     f.pathDepth     || null,
```

- [ ] **Step 4: Update `buildExportJson` to export `pathDepth`**

In `buildExportJson`, inside the field mapping, after the `formatOptions` line:
```javascript
      if (f.dataType)      base.dataType = f.dataType;
      if (f.format)        base.format = f.format;
      if (f.formatOptions) base.formatOptions = f.formatOptions;
      return base;
```
Add before `return base;`:
```javascript
      if (f.pathDepth)     base.pathDepth = f.pathDepth;
```

- [ ] **Step 5: Verify round-trip in browser**

1. Drag CWD field into a line
2. Click the chip to open the edit dialog
3. In Allgemein tab: select "Letzte 2 Segmente"
4. Save — preview should now show `...user/myproject`
5. Click "Download" — JSON should contain `"pathDepth": 2` on the cwd field
6. Reload page, import that JSON — CWD chip should show `...user/myproject` in preview
7. Commit:
```bash
git add statusline-configurator.html
git commit -m "feat(configurator): add pathDepth option for CWD and path fields"
```

---

## Task 4: CWD Path Depth — PowerShell

**Files:**
- Modify: `statusline.ps1` (after `Format-FieldValue`, inside `Format-Field` default branch)
- Modify: `tests/statusline.Tests.ps1`

- [ ] **Step 1: Write failing Pester tests for `Truncate-Path`**

Add to `tests/statusline.Tests.ps1` at the end of the file:
```powershell
Describe 'Truncate-Path' {
    It 'returns full path when depth is null' {
        Truncate-Path -Value '/home/user/myproject' -Depth $null | Should -Be '/home/user/myproject'
    }

    It 'returns full path when depth equals segment count' {
        Truncate-Path -Value '/home/user/myproject' -Depth 3 | Should -Be '/home/user/myproject'
    }

    It 'returns full path when depth exceeds segment count' {
        Truncate-Path -Value '/home/user/myproject' -Depth 10 | Should -Be '/home/user/myproject'
    }

    It 'truncates unix path to last 1 segment without prefix' {
        Truncate-Path -Value '/home/user/myproject' -Depth 1 | Should -Be 'myproject'
    }

    It 'truncates unix path to last 2 segments with ... prefix' {
        Truncate-Path -Value '/home/user/myproject' -Depth 2 | Should -Be '.../user/myproject'
    }

    It 'truncates windows path to last 3 segments with ... prefix' {
        Truncate-Path -Value 'C:\Das\ist\mein\super\langer\Pfad' -Depth 3 | Should -Be '...\super\langer\Pfad'
    }

    It 'truncates windows path to last 1 segment without prefix' {
        Truncate-Path -Value 'C:\Das\ist\mein\Pfad' -Depth 1 | Should -Be 'Pfad'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```
Expected: `Truncate-Path` tests fail with "CommandNotFoundException" or similar.

- [ ] **Step 3: Add `Truncate-Path` to `statusline.ps1`**

After the `Format-FieldValue` function (before `Format-Field`), add:
```powershell
<#
.SYNOPSIS
    Truncates a file system path to the last N segments, prepending "..." if segments
    were removed. Returns the original path unchanged if depth is null or the path
    has fewer or equal segments.
.PARAMETER Value
    The path string to truncate.
.PARAMETER Depth
    Number of trailing path segments to keep. Null or 0 returns the full path.
.OUTPUTS
    Truncated path string.
#>
function Truncate-Path {
    param(
        [string]$Value,
        [object]$Depth
    )
    if ($null -eq $Depth -or [int]$Depth -le 0) { return $Value }
    $n   = [int]$Depth
    $sep = if ($Value -match '\\') { '\' } else { '/' }
    $parts = $Value -split '[/\\]' | Where-Object { $_ -ne '' }
    if ($parts.Count -le $n) { return $Value }
    return '...' + $sep + ($parts | Select-Object -Last $n) -join $sep
}
```

- [ ] **Step 4: Run `Truncate-Path` tests to verify they pass**

```powershell
pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```
Expected: All `Truncate-Path` tests pass. Remaining tests still pass (26 existing + new ones).

- [ ] **Step 5: Update `Format-Field` to apply `Truncate-Path`**

In `Format-Field`, inside the `default` branch (type = 'field'), find:
```powershell
        default {
            # type = 'field'
            $value = Get-NestedValue $Data $Field.key
            if ($null -eq $value -or "$value" -eq '') { return '' }
            $formatted = if ($Field.dataType) {
                Format-FieldValue -Value $value -DataType $Field.dataType -Format $Field.format -FormatOptions $Field.formatOptions
            } else {
                "$value"
            }
            return "${fgAnsi}${bgAnsi}${formatted}${resetAnsi}"
        }
```
Replace with:
```powershell
        default {
            # type = 'field'
            $value = Get-NestedValue $Data $Field.key
            if ($null -eq $value -or "$value" -eq '') { return '' }
            $formatted = if ($Field.dataType) {
                Format-FieldValue -Value $value -DataType $Field.dataType -Format $Field.format -FormatOptions $Field.formatOptions
            } else {
                "$value"
            }
            # Apply path truncation for path-type fields when pathDepth is configured
            $pathKeys = @('cwd', 'workspace.current_dir', 'workspace.project_dir')
            if ($Field.pathDepth -and $pathKeys -contains $Field.key) {
                $formatted = Truncate-Path -Value $formatted -Depth $Field.pathDepth
            }
            return "${fgAnsi}${bgAnsi}${formatted}${resetAnsi}"
        }
```

- [ ] **Step 6: Write integration test for `Format-Field` with `pathDepth`**

Add to the `Describe 'Format-Field'` block in `tests/statusline.Tests.ps1`:
```powershell
    It 'applies pathDepth truncation to cwd field' {
        $data  = [PSCustomObject]@{ cwd = '/home/user/myproject' }
        $field = [PSCustomObject]@{ type='field'; key='cwd'; fg=$null; bg=$null; pathDepth=2; dataType=$null; format=$null; formatOptions=$null }
        $result = Format-Field $field $data
        $result | Should -Match 'user/myproject'
        $result | Should -Match '\.\.\.'
    }

    It 'shows full path for cwd field when pathDepth is null' {
        $data  = [PSCustomObject]@{ cwd = '/home/user/myproject' }
        $field = [PSCustomObject]@{ type='field'; key='cwd'; fg=$null; bg=$null; pathDepth=$null; dataType=$null; format=$null; formatOptions=$null }
        $result = Format-Field $field $data
        $result | Should -Match '/home/user/myproject'
    }
```

- [ ] **Step 7: Run all tests**

```powershell
pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```
Expected: All tests pass (previously 26 + new Truncate-Path + new Format-Field tests).

- [ ] **Step 8: Commit**

```bash
git add statusline.ps1 tests/statusline.Tests.ps1
git commit -m "feat(statusline): add Truncate-Path and pathDepth support for path fields"
```

---

## Task 5: Theming — State, export, and import

**Files:**
- Modify: `statusline-configurator.html` (state ~line 531, loadConfig ~line 822, buildExportJson ~line 741)

- [ ] **Step 1: Extend `state` with theme properties**

Find:
```javascript
const state = { lines: [], customFields: [] };
```
Replace with:
```javascript
const state = { lines: [], customFields: [], themes: [], activeTheme: null };
```

- [ ] **Step 2: Update `loadConfig` to parse themes**

In `loadConfig`, after the `state.customFields` assignment:
```javascript
  // knownKeys: not stored in state — rebuilt on every export from AVAILABLE_FIELDS

  render();
```
Replace with:
```javascript
  state.themes      = (json.themes || []).map(t => ({
    id:                  t.id || generateId(),
    name:                t.name || 'Theme',
    fieldFg:             t.fieldFg || null,
    fieldBg:             t.fieldBg || null,
    progressThresholds:  Array.isArray(t.progressThresholds)
      ? t.progressThresholds.map(pt => ({ upTo: pt.upTo, fg: pt.fg }))
      : [{ upTo: 50, fg: '#4ade80' }, { upTo: 80, fg: '#facc15' }, { upTo: 100, fg: '#f87171' }],
  }));
  state.activeTheme = json.activeTheme || null;

  // knownKeys: not stored in state — rebuilt on every export from AVAILABLE_FIELDS

  render();
```

- [ ] **Step 3: Update `buildExportJson` to include themes**

Find:
```javascript
  return JSON.stringify({ lines, customFields, knownKeys }, null, 2);
```
Replace with:
```javascript
  const themes      = state.themes;
  const activeTheme = state.activeTheme;
  return JSON.stringify({ activeTheme, themes, lines, customFields, knownKeys }, null, 2);
```

- [ ] **Step 4: Verify in browser**

Open file, add a line, click "Download". JSON should now contain `"activeTheme": null, "themes": []`. Import it back — should load without error.

---

## Task 6: Theming — Theme Tab UI and CRUD

**Files:**
- Modify: `statusline-configurator.html` (JS section — add renderThemeTab and CRUD functions)

- [ ] **Step 1: Declare `_themePreviewId` variable**

Add after `switchMainTab` (before `renderThemeTab`):
```javascript
let _themePreviewId = null; // id of theme currently being previewed (null = use activeTheme)
```

- [ ] **Step 2: Add `renderThemeTab` function**

Add directly after the `_themePreviewId` declaration:
```javascript
// ─── Theme Tab ────────────────────────────────────────────────────────────

/**
 * Renders the Theme tab content into #main-tab-theme.
 * Called each time the Theme tab is activated or state.themes changes.
 */
function renderThemeTab() {
  const el = document.getElementById('main-tab-theme');
  if (!el) return;

  const themes     = state.themes;
  const activeId   = state.activeTheme;
  const previewId  = _themePreviewId;
  const currentId  = previewId ?? activeId;
  const theme      = themes.find(t => t.id === currentId);

  const thresholdRows = theme
    ? theme.progressThresholds.map((pt, i) => `
        <div style="display:flex;align-items:center;gap:8px;margin-bottom:6px;">
          <span style="font-size:12px;color:var(--color-text-muted);">bis</span>
          <input type="number" class="theme-threshold-pct" data-index="${i}" min="1" max="100" value="${pt.upTo}"
                 style="width:56px;padding:4px 6px;border-radius:4px;border:1px solid var(--color-border);
                        background:var(--color-surface-2);color:var(--color-text);font-size:12px;">
          <span style="font-size:12px;color:var(--color-text-muted);">%</span>
          <input type="color" class="theme-threshold-fg" data-index="${i}" value="${pt.fg || '#ffffff'}"
                 style="width:36px;height:28px;border:1px solid var(--color-border);border-radius:4px;padding:2px;cursor:pointer;">
          <button class="btn-icon" onclick="removeThreshold(${i})" title="Entfernen"
                  style="margin-left:auto;" ${theme.progressThresholds.length <= 1 ? 'disabled' : ''}>✕</button>
        </div>
      `).join('')
    : '';

  el.innerHTML = themes.length === 0
    ? `
        <p style="font-size:12px;color:var(--color-text-muted);margin-bottom:12px;">
          Noch kein Theme vorhanden.
        </p>
        <button class="btn" onclick="createTheme()">+ Neues Theme erstellen</button>
      `
    : `
        <div style="margin-bottom:14px;">
          <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:4px;">Theme</div>
          <div style="display:flex;gap:8px;align-items:center;">
            <select id="theme-select"
                    style="flex:1;padding:6px 8px;border-radius:4px;border:1px solid var(--color-border);
                           background:var(--color-surface-2);color:var(--color-text);font-size:12px;"
                    onchange="onThemeSelect(this.value)">
              ${themes.map(t => `<option value="${t.id}" ${t.id === currentId ? 'selected' : ''}>${escapeHtml(t.name)}</option>`).join('')}
            </select>
            <button class="btn" onclick="createTheme()">+ Neu</button>
            <button class="btn btn-danger" onclick="deleteTheme('${currentId}')"
                    ${!currentId || currentId === activeId || themes.length <= 1 ? 'disabled' : ''}>Löschen</button>
          </div>
        </div>
        ${theme ? `
          <div style="margin-bottom:14px;">
            <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:4px;">Name</div>
            <input id="theme-name" type="text" value="${escapeHtml(theme.name)}"
                   style="width:100%;box-sizing:border-box;padding:6px 8px;border-radius:4px;
                          border:1px solid var(--color-border);background:var(--color-surface-2);
                          color:var(--color-text);font-size:12px;"
                   oninput="renameTheme('${theme.id}', this.value)">
          </div>
          <div style="margin-bottom:14px;">
            <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:6px;">Felder-Farben</div>
            <div style="display:flex;gap:12px;align-items:center;flex-wrap:wrap;">
              <label style="display:flex;align-items:center;gap:6px;font-size:12px;">
                <span>FG</span>
                <input type="color" id="theme-fg" value="${theme.fieldFg || '#e0e0e0'}"
                       style="width:36px;height:28px;border:1px solid var(--color-border);border-radius:4px;padding:2px;cursor:pointer;"
                       oninput="updateThemeColor('${theme.id}', 'fieldFg', this.value)">
                <button class="btn-icon" onclick="updateThemeColor('${theme.id}', 'fieldFg', null)" title="Keine FG-Farbe">✕</button>
              </label>
              <label style="display:flex;align-items:center;gap:6px;font-size:12px;">
                <span>BG</span>
                <input type="color" id="theme-bg" value="${theme.fieldBg || '#161616'}"
                       style="width:36px;height:28px;border:1px solid var(--color-border);border-radius:4px;padding:2px;cursor:pointer;"
                       oninput="updateThemeColor('${theme.id}', 'fieldBg', this.value)">
                <button class="btn-icon" onclick="updateThemeColor('${theme.id}', 'fieldBg', null)" title="Kein BG">✕</button>
              </label>
            </div>
          </div>
          <div style="margin-bottom:14px;">
            <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:6px;">Progressbar-Schwellen</div>
            <div id="theme-thresholds">${thresholdRows}</div>
            <button class="btn" style="margin-top:6px;" onclick="addThreshold('${theme.id}')">+ Schwelle hinzufügen</button>
          </div>
          <div style="display:flex;gap:8px;margin-top:4px;">
            <button class="btn btn-primary" onclick="applyTheme('${theme.id}')">Anwenden</button>
            <button class="btn" onclick="cancelThemePreview()">Abbrechen</button>
          </div>
        ` : ''}
      `;
}
```

- [ ] **Step 3: Add theme CRUD functions**

Add after `renderThemeTab`:
```javascript
/**
 * Creates a new theme with default values and switches to it in preview.
 */
function createTheme() {
  const id = generateId();
  state.themes.push({
    id,
    name:               'Neues Theme',
    fieldFg:            null,
    fieldBg:            null,
    progressThresholds: [
      { upTo: 50,  fg: '#4ade80' },
      { upTo: 80,  fg: '#facc15' },
      { upTo: 100, fg: '#f87171' },
    ],
  });
  _themePreviewId = id;
  renderThemeTab();
  updateExportTextarea();
}

/**
 * Deletes a theme by id. Cannot delete the active theme or last remaining theme.
 * @param {string} id
 */
function deleteTheme(id) {
  if (id === state.activeTheme || state.themes.length <= 1) return;
  state.themes = state.themes.filter(t => t.id !== id);
  if (_themePreviewId === id) _themePreviewId = null;
  renderThemeTab();
  updateExportTextarea();
}

/**
 * Updates a theme's name inline.
 * @param {string} id
 * @param {string} name
 */
function renameTheme(id, name) {
  const t = state.themes.find(t => t.id === id);
  if (t) t.name = name;
  updateExportTextarea();
}

/**
 * Updates a theme's fieldFg or fieldBg color.
 * @param {string} id
 * @param {'fieldFg'|'fieldBg'} prop
 * @param {string|null} value
 */
function updateThemeColor(id, prop, value) {
  const t = state.themes.find(t => t.id === id);
  if (t) { t[prop] = value; renderPreview(); renderThemeTab(); }
  updateExportTextarea();
}

/**
 * Adds a new threshold row to a theme.
 * @param {string} id
 */
function addThreshold(id) {
  const t = state.themes.find(t => t.id === id);
  if (!t) return;
  t.progressThresholds.push({ upTo: 100, fg: '#ffffff' });
  renderThemeTab();
  updateExportTextarea();
}

/**
 * Removes a threshold row by index from the currently previewed/selected theme.
 * @param {number} index
 */
function removeThreshold(index) {
  const id = _themePreviewId ?? state.activeTheme;
  const t  = state.themes.find(t => t.id === id);
  if (!t || t.progressThresholds.length <= 1) return;
  t.progressThresholds.splice(index, 1);
  renderThemeTab();
  updateExportTextarea();
}

/**
 * Saves all threshold input values from the DOM back into the theme object.
 * Called before apply/preview operations that read threshold data.
 * @param {string} id
 */
function saveThresholdInputs(id) {
  const t = state.themes.find(t => t.id === id);
  if (!t) return;
  const pctInputs = document.querySelectorAll('.theme-threshold-pct');
  const fgInputs  = document.querySelectorAll('.theme-threshold-fg');
  pctInputs.forEach((el, i) => {
    if (t.progressThresholds[i]) t.progressThresholds[i].upTo = parseInt(el.value, 10) || 100;
  });
  fgInputs.forEach((el, i) => {
    if (t.progressThresholds[i]) t.progressThresholds[i].fg = el.value;
  });
}
```

- [ ] **Step 4: Verify CRUD in browser**

Note: "Anwenden" and "Abbrechen" buttons will throw JS errors until Task 7 is complete — that is expected.

1. Switch to "Theme" tab
2. Click "+ Neues Theme erstellen" — form should appear with default name, colors, thresholds
3. Rename the theme by typing in name field
4. Create a second theme
5. Delete the first theme (should succeed since it's not active)
6. Attempting to delete the last theme should be disabled

---

## Task 7: Theming — Preview, Apply, and Cancel

**Files:**
- Modify: `statusline-configurator.html` (makeProgressBar ~line 1252, renderFieldHtml ~line 1329, renderPreview ~line 720, add applyTheme/cancelThemePreview/onThemeSelect)

- [ ] **Step 1: Update `makeProgressBar` to accept optional thresholds**

Find the function signature:
```javascript
function makeProgressBar(value, style, fg, brackets = true, charset = 'block') {
```
Replace with:
```javascript
/**
 * ...existing jsdoc...
 * @param {Array|null} thresholds - optional [{upTo, fg}] overriding PB_COLORS; null = use defaults
 */
function makeProgressBar(value, style, fg, brackets = true, charset = 'block', thresholds = null) {
```

Then find the threshold color line:
```javascript
  const thresholdColor = pct < 50 ? PB_COLORS.low : pct < 80 ? PB_COLORS.mid : PB_COLORS.high;
```
Replace with:
```javascript
  const activeThresholds = thresholds || [
    { upTo: 50,  fg: PB_COLORS.low  },
    { upTo: 80,  fg: PB_COLORS.mid  },
    { upTo: 100, fg: PB_COLORS.high },
  ];
  const matched        = activeThresholds.find(t => pct < t.upTo);
  const thresholdColor = matched ? matched.fg : activeThresholds[activeThresholds.length - 1].fg;
```

- [ ] **Step 2: Update `renderFieldHtml` to accept optional `previewTheme`**

Find:
```javascript
function renderFieldHtml(field, data) {
  const fg = field.fg;
  const bg = field.bg;
  const style = [fg ? `color:${fg};` : '', bg ? `background:${bg};padding:1px 3px;border-radius:3px;` : ''].join('');
```
Replace with:
```javascript
/**
 * ...existing jsdoc...
 * @param {object|null} previewTheme - optional theme object; its fieldFg/fieldBg are used as
 *   fallback colors when the field has no individual fg/bg set
 */
function renderFieldHtml(field, data, previewTheme = null) {
  const fg = field.fg ?? (previewTheme?.fieldFg || null);
  const bg = field.bg ?? (previewTheme?.fieldBg || null);
  const style = [fg ? `color:${fg};` : '', bg ? `background:${bg};padding:1px 3px;border-radius:3px;` : ''].join('');
```

Then update the progressbar rendering inside `renderFieldHtml` to pass thresholds. Find:
```javascript
    const { bar, color } = makeProgressBar(raw, field.progressStyle || 'color-coded', fg, brackets, charset);
```
Replace with:
```javascript
    const { bar, color } = makeProgressBar(raw, field.progressStyle || 'color-coded', fg, brackets, charset, previewTheme?.progressThresholds || null);
```

- [ ] **Step 3: Update `renderPreview` to pass the active/preview theme**

Find the `renderPreview` function and its inner `.map`:
```javascript
    return line.fields.map(f => renderFieldHtml(f, SAMPLE_DATA)).join('');
```
Replace with:
```javascript
    const activeThemeObj = (() => {
      const id = _themePreviewId ?? state.activeTheme;
      return id ? state.themes.find(t => t.id === id) || null : null;
    })();
    return line.fields.map(f => renderFieldHtml(f, SAMPLE_DATA, activeThemeObj)).join('');
```

- [ ] **Step 4: Add `onThemeSelect`, `applyTheme`, `cancelThemePreview`**

Add after the CRUD functions:
```javascript
/**
 * Called when the user picks a theme in the dropdown — enters preview mode.
 * Saves current threshold inputs before switching.
 * @param {string} id
 */
function onThemeSelect(id) {
  const prevId = _themePreviewId ?? state.activeTheme;
  if (prevId) saveThresholdInputs(prevId);
  _themePreviewId = id;
  renderPreview();
  renderThemeTab();
}

/**
 * Applies the selected theme: writes fieldFg/fieldBg onto every field object in all lines,
 * sets state.activeTheme, and clears the preview state.
 * @param {string} id
 */
function applyTheme(id) {
  saveThresholdInputs(id);
  const theme = state.themes.find(t => t.id === id);
  if (!theme) return;
  state.lines.forEach(line => {
    line.fields.forEach(field => {
      if (theme.fieldFg !== null) field.fg = theme.fieldFg;
      if (theme.fieldBg !== null) field.bg = theme.fieldBg;
    });
  });
  state.activeTheme = id;
  _themePreviewId   = null;
  render();
}

/**
 * Cancels theme preview and re-renders from the real state.
 */
function cancelThemePreview() {
  _themePreviewId = null;
  renderPreview();
  renderThemeTab();
}
```

- [ ] **Step 5: Verify in browser**

1. Create a theme with fieldFg = `#ff0000` (red) and thresholds with a custom color
2. Add a CWD field and a progressbar to a line
3. Select the theme in the dropdown → preview should immediately show red text and custom progressbar color
4. Click Abbrechen → preview returns to original colors
5. Select again, click Anwenden → field chips in the line now have red fg applied
6. Verify exported JSON contains `"activeTheme": "<id>"` and `"themes": [...]`

- [ ] **Step 6: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): add theming system with FG/BG colors and progressbar thresholds"
```

---

## Task 8: Theming — PowerShell

**Files:**
- Modify: `statusline.ps1` (`$script:PbThresholds` init, `Format-ProgressBar`, `Invoke-Main`)
- Modify: `tests/statusline.Tests.ps1`

- [ ] **Step 1: Write failing Pester tests for dynamic thresholds**

Add to `tests/statusline.Tests.ps1` in the `Describe 'Format-ProgressBar'` block:
```powershell
    It 'uses custom threshold colors when Thresholds parameter is provided' {
        $thresholds = @(
            [PSCustomObject]@{ upTo = 50;  fg = '#0000ff' },
            [PSCustomObject]@{ upTo = 80;  fg = '#ff00ff' },
            [PSCustomObject]@{ upTo = 100; fg = '#00ffff' }
        )
        $low = Format-ProgressBar -Value 20 -Style 'color-coded' -Fg $null -Thresholds $thresholds
        $low | Should -Match '0;0;255'      # blue = #0000ff

        $mid = Format-ProgressBar -Value 65 -Style 'color-coded' -Fg $null -Thresholds $thresholds
        $mid | Should -Match '255;0;255'    # magenta = #ff00ff

        $high = Format-ProgressBar -Value 85 -Style 'color-coded' -Fg $null -Thresholds $thresholds
        $high | Should -Match '0;255;255'   # cyan = #00ffff
    }
```

Also add a test for `Invoke-Main` reading the active theme's thresholds. Add a new `Describe` block:
```powershell
Describe 'Invoke-Main theme integration' {
    It 'uses active theme progressbar thresholds when rendering' {
        $config = @{
            activeTheme = 'theme1'
            themes      = @(
                @{
                    id                 = 'theme1'
                    name               = 'Test'
                    fieldFg            = $null
                    fieldBg            = $null
                    progressThresholds = @(
                        @{ upTo = 50;  fg = '#0000ff' },
                        @{ upTo = 80;  fg = '#ff00ff' },
                        @{ upTo = 100; fg = '#00ffff' }
                    )
                }
            )
            lines       = @(
                @{ fields = @(@{ type='progressbar'; key='context_window.used_percentage'; progressStyle='color-coded'; fg=$null; bg=$null }) }
            )
        } | ConvertTo-Json -Depth 10

        $configPath = Join-Path $TestDrive 'statusline-config.json'
        Set-Content -Path $configPath -Value $config -Encoding UTF8

        $input = '{"context_window":{"used_percentage":20}}'
        $result = Invoke-Main -ConfigPath $configPath -InputJson $input
        # blue = #0000ff = RGB 0,0,255
        $result | Should -Match '0;0;255'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```
Expected: `Thresholds` parameter tests fail; `Invoke-Main theme integration` test fails.

- [ ] **Step 3: Replace hardcoded `$script:PbColorLow/Mid/High` with `$script:PbThresholds`**

Find the three hardcoded threshold color variables in `statusline.ps1`:
```powershell
# Threshold colors (matches configurator JS constants)
$script:PbColorLow  = '#4ade80'   # green  — 0–49%
$script:PbColorMid  = '#facc15'   # yellow — 50–79%
$script:PbColorHigh = '#f87171'   # red    — 80–100%
```
Replace with:
```powershell
# Default progressbar threshold colors (overridden by active theme at runtime)
$script:PbThresholds = @(
    [PSCustomObject]@{ upTo = 50;  fg = '#4ade80' },
    [PSCustomObject]@{ upTo = 80;  fg = '#facc15' },
    [PSCustomObject]@{ upTo = 100; fg = '#f87171' }
)
```

- [ ] **Step 4: Update `Format-ProgressBar` to use `$script:PbThresholds` and accept `Thresholds` parameter**

In `Format-ProgressBar`, add a `Thresholds` parameter and replace the hardcoded color logic.

Find the param block:
```powershell
function Format-ProgressBar {
    param(
        [double]$Value,
        [string]$Style,
        [string]$Fg,
        [bool]$Brackets   = $true,
        [string]$Charset  = 'block'
    )
```
Replace with:
```powershell
function Format-ProgressBar {
    param(
        [double]$Value,
        [string]$Style,
        [string]$Fg,
        [bool]$Brackets   = $true,
        [string]$Charset  = 'block',
        [object]$Thresholds = $null   # optional array of {upTo, fg}; null = use script defaults
    )
```

Then find the hardcoded color block inside the function:
```powershell
    # Color: use Fg override if provided; otherwise apply threshold only for color-coded
    $color = if ($Fg) {
        $Fg
    } elseif ($Style -eq 'color-coded') {
        if ($pct -lt 50) { $script:PbColorLow }
        elseif ($pct -lt 80) { $script:PbColorMid }
        else { $script:PbColorHigh }
    } else {
        $null
    }
```
Replace with:
```powershell
    # Color: use Fg override if provided; otherwise apply threshold only for color-coded
    $color = if ($Fg) {
        $Fg
    } elseif ($Style -eq 'color-coded') {
        $activeThresholds = if ($Thresholds) { $Thresholds } else { $script:PbThresholds }
        $matched = $activeThresholds | Where-Object { $pct -lt $_.upTo } | Select-Object -First 1
        if ($matched) { $matched.fg } else { ($activeThresholds | Select-Object -Last 1).fg }
    } else {
        $null
    }
```

- [ ] **Step 5: Update `Invoke-Main` to read active theme thresholds**

In `Invoke-Main`, after the `$script:KnownKeys` line:
```powershell
    # Expose knownKeys to script scope so Format-Field can access them for new_fields_indicator
    $script:KnownKeys = if ($config.knownKeys) { $config.knownKeys } else { $null }
```
Add:
```powershell
    # Load active theme thresholds into script scope for Format-ProgressBar
    if ($config.activeTheme -and $config.themes) {
        $activeThemeObj = $config.themes | Where-Object { $_.id -eq $config.activeTheme } | Select-Object -First 1
        if ($activeThemeObj -and $activeThemeObj.progressThresholds) {
            $script:PbThresholds = $activeThemeObj.progressThresholds
        }
    }
```

- [ ] **Step 6: Update `Format-Field` to pass `$script:PbThresholds` to `Format-ProgressBar`**

In `Format-Field`, find the call to `Format-ProgressBar`:
```powershell
            $bar = Format-ProgressBar -Value ([double]$value) -Style $effectiveStyle -Fg $Field.fg `
                                       -Brackets $effectiveBrackets -Charset $effectiveCharset
```
Replace with:
```powershell
            $bar = Format-ProgressBar -Value ([double]$value) -Style $effectiveStyle -Fg $Field.fg `
                                       -Brackets $effectiveBrackets -Charset $effectiveCharset `
                                       -Thresholds $script:PbThresholds
```

- [ ] **Step 7: Run all tests**

```powershell
pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```
Expected: All tests pass. The existing color tests still pass because the default `$script:PbThresholds` contains the same values as the old hardcoded constants.

- [ ] **Step 8: Commit**

```bash
git add statusline.ps1 tests/statusline.Tests.ps1
git commit -m "feat(statusline): read active theme progressbar thresholds from config"
```
