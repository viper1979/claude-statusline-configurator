# Statusline Anpassungen 008 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fünf unabhängige Erweiterungen: K/M/B-Großschreibung, Derived Fields (used_tokens/remain_tokens), Cache-Efficiency-Progressbar-Fix, logNewFields in Edit-Dialog und Tab-Ausrichtung via `mergeWithNext`.

**Architecture:** Tasks 1–5 sind unabhängige Kleinänderungen an `statusline.ps1` und `statusline-configurator.html`. Tasks 6–10 implementieren Tab-Ausrichtung: zuerst Config-Schema, dann UI-Controls, dann PS1-Two-Pass-Rendering, dann JS-Preview-Alignment.

**Tech Stack:** PowerShell 7 (Pester 5.x Tests), Single-File HTML (Vanilla JS, kein Build-Step), Sortable.js

---

## File Map

| Datei | Änderungen |
|---|---|
| `statusline.ps1` | Task 1 (K/M/B), Task 2 (Derived Fields), Task 8 (Get-VisibleWidth + Build-Groups), Task 9 (Format-Lines-Aligned + Invoke-Main) |
| `tests/statusline.Tests.ps1` | Task 1 (Tests update), Task 2 (neue Tests), Task 8 (neue Tests), Task 9 (neue Tests) |
| `statusline-configurator.html` | Task 3 (Palette), Task 4 (PERCENTAGE_KEYS + Typ-Toggle), Task 5 (logNewFields), Task 6 (Export/Import), Task 7 (Quick-Handle + Edit-Dialog), Task 10 (renderPreview) |

---

## Task 1: K/M/B Großschreibung

**Files:**
- Modify: `tests/statusline.Tests.ps1:390-397`
- Modify: `statusline.ps1:318-320`

- [ ] **Schritt 1: Tests auf neue Großbuchstaben umstellen**

  In `tests/statusline.Tests.ps1` Zeilen 390–397 ändern:

  ```powershell
  It 'formats number with k suffix' {
      Format-FieldValue -Value 12345 -DataType 'number' -Format 'k' -FormatOptions $null |
          Should -Be '12K'
  }

  It 'formats number with m suffix' {
      Format-FieldValue -Value 12000000 -DataType 'number' -Format 'm' -FormatOptions $null |
          Should -Be '12M'
  }
  ```

- [ ] **Schritt 2: Tests ausführen — erwartet FAIL**

  ```
  pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
  ```
  Erwartet: 2 Tests schlagen fehl (`12k` / `12m` statt `12K` / `12M`).

- [ ] **Schritt 3: PS1 Zeilen 318–320 anpassen**

  In `statusline.ps1` die drei Zeilen:

  ```powershell
  if ($n -ge 1000000000) { return "$([math]::Round($n / 1000000000))B" }
  if ($n -ge 1000000)    { return "$([math]::Round($n / 1000000))M" }
  if ($n -ge 1000)       { return "$([math]::Round($n / 1000))K" }
  ```

- [ ] **Schritt 4: Tests ausführen — erwartet alle grün**

  ```
  pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
  ```
  Erwartet: alle Tests Pass.

- [ ] **Schritt 5: Commit**

  ```bash
  git add statusline.ps1 tests/statusline.Tests.ps1
  git commit -m "fix(statusline): uppercase K/M/B number suffixes"
  ```

---

## Task 2: Derived Fields — PS1

**Files:**
- Modify: `tests/statusline.Tests.ps1:1115` (nach dem letzten `Compute-DerivedFields`-Block)
- Modify: `statusline.ps1:607-618` (Compute-DerivedFields)

- [ ] **Schritt 1: Failing Tests schreiben**

  In `tests/statusline.Tests.ps1` direkt nach Zeile 1115 (Ende des `Describe 'Compute-DerivedFields'` Blocks — **vor** der schließenden `}`) einfügen:

  ```powershell
  It 'sets used_tokens correctly' {
      $data = [PSCustomObject]@{
          context_window = [PSCustomObject]@{
              context_window_size = 200000
              used_percentage     = 15
          }
      }
      Compute-DerivedFields -Data $data
      $data.context_window.used_tokens | Should -Be 30000
  }

  It 'sets remain_tokens correctly' {
      $data = [PSCustomObject]@{
          context_window = [PSCustomObject]@{
              context_window_size  = 200000
              remaining_percentage = 85
          }
      }
      Compute-DerivedFields -Data $data
      $data.context_window.remain_tokens | Should -Be 170000
  }

  It 'does not set used_tokens when context_window_size is 0' {
      $data = [PSCustomObject]@{
          context_window = [PSCustomObject]@{
              context_window_size = 0
              used_percentage     = 15
          }
      }
      Compute-DerivedFields -Data $data
      $data.context_window.PSObject.Properties['used_tokens'] | Should -BeNullOrEmpty
  }

  It 'does not set remain_tokens when remaining_percentage is null' {
      $data = [PSCustomObject]@{
          context_window = [PSCustomObject]@{
              context_window_size = 200000
          }
      }
      Compute-DerivedFields -Data $data
      $data.context_window.PSObject.Properties['remain_tokens'] | Should -BeNullOrEmpty
  }
  ```

- [ ] **Schritt 2: Tests ausführen — erwartet FAIL**

  ```
  pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
  ```
  Erwartet: 4 neue Tests schlagen fehl.

- [ ] **Schritt 3: Compute-DerivedFields erweitern**

  In `statusline.ps1` die Funktion `Compute-DerivedFields` (ab Zeile 607) nach dem `cache_efficiency`-Block (nach Zeile 617) ergänzen:

  ```powershell
  # used_tokens = floor(context_window_size * used_percentage / 100)
  $ctxSize  = Get-NestedValue $Data 'context_window.context_window_size'
  $usedPct  = Get-NestedValue $Data 'context_window.used_percentage'
  if ($null -ne $ctxSize -and [double]$ctxSize -gt 0 -and $null -ne $usedPct) {
      $usedTokens = [math]::Floor([double]$ctxSize * [double]$usedPct / 100)
      $Data.context_window | Add-Member -NotePropertyName 'used_tokens' `
                                        -NotePropertyValue $usedTokens -Force
  }

  # remain_tokens = floor(context_window_size * remaining_percentage / 100)
  $remainPct = Get-NestedValue $Data 'context_window.remaining_percentage'
  if ($null -ne $ctxSize -and [double]$ctxSize -gt 0 -and $null -ne $remainPct) {
      $remainTokens = [math]::Floor([double]$ctxSize * [double]$remainPct / 100)
      $Data.context_window | Add-Member -NotePropertyName 'remain_tokens' `
                                        -NotePropertyValue $remainTokens -Force
  }
  ```

  Außerdem den Docstring der Funktion (Zeilen 596–606) aktualisieren — `@.DESCRIPTION` anpassen:

  ```powershell
  <#
  .SYNOPSIS
      Computes derived fields and injects them into $Data via Add-Member.
  .DESCRIPTION
      General-purpose hook for all derived field computations. Computes:
      - context_window.cache_efficiency = cache_read_input_tokens / total_input_tokens * 100
      - context_window.used_tokens      = context_window_size * used_percentage / 100
      - context_window.remain_tokens    = context_window_size * remaining_percentage / 100
      Guards prevent computation when required inputs are null or zero.
  .PARAMETER Data
      PSCustomObject parsed from Claude Code's JSON input (already enriched).
  #>
  ```

- [ ] **Schritt 4: Tests ausführen — erwartet alle grün**

  ```
  pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
  ```

- [ ] **Schritt 5: Commit**

  ```bash
  git add statusline.ps1 tests/statusline.Tests.ps1
  git commit -m "feat(statusline): add used_tokens and remain_tokens derived fields"
  ```

---

## Task 3: Derived Fields — Configurator Palette

**Files:**
- Modify: `statusline-configurator.html:343-355` (AVAILABLE_FIELDS Context Window)
- Modify: `statusline-configurator.html:418-423` (FIELD_TYPE_DEFAULTS)
- Modify: `statusline-configurator.html:456-462` (SAMPLE_DATA)

- [ ] **Schritt 1: AVAILABLE_FIELDS ergänzen**

  In `statusline-configurator.html` die `Context Window`-Gruppe (Zeilen 343–355) — nach `cache_efficiency` zwei neue Einträge:

  ```javascript
  { group: 'Context Window', items: [
    { key: 'context_window.used_percentage',      label: 'Used %' },
    { key: 'context_window.remaining_percentage', label: 'Remaining %' },
    { key: 'context_window.total_input_tokens',   label: 'Input Tokens' },
    { key: 'context_window.total_output_tokens',  label: 'Output Tokens' },
    { key: 'context_window.context_window_size',  label: 'Window Size' },
    { key: 'context_window.current_usage.input_tokens',                label: 'Current Input Tokens' },
    { key: 'context_window.current_usage.output_tokens',               label: 'Current Output Tokens' },
    { key: 'context_window.current_usage.cache_creation_input_tokens', label: 'Cache Creation Tokens' },
    { key: 'context_window.current_usage.cache_read_input_tokens',     label: 'Cache Read Tokens' },
    { key: 'exceeds_200k_tokens',                                      label: 'Exceeds 200k Tokens' },
    { key: 'context_window.cache_efficiency', label: 'Cache Efficiency %' },
    { key: 'context_window.used_tokens',      label: 'Used Tokens' },
    { key: 'context_window.remain_tokens',    label: 'Remaining Tokens' },
  ]},
  ```

- [ ] **Schritt 2: FIELD_TYPE_DEFAULTS ergänzen**

  Nach dem `cache_efficiency`-Eintrag (Zeile 423) einfügen:

  ```javascript
  'context_window.used_tokens':          { dataType: 'number',         format: 'auto' },
  'context_window.remain_tokens':        { dataType: 'number',         format: 'auto' },
  ```

- [ ] **Schritt 3: SAMPLE_DATA ergänzen**

  In SAMPLE_DATA das `context_window`-Objekt (ca. Zeile 456–462) um die neuen Felder erweitern:

  ```javascript
  context_window: {
    used_percentage: 15, remaining_percentage: 85,
    context_window_size: 200000,
    total_input_tokens: 8500, total_output_tokens: 1200,
    current_usage: { input_tokens: 8500, output_tokens: 1200,
                     cache_creation_input_tokens: 5000, cache_read_input_tokens: 2000 },
    cache_efficiency: 73.4,
    used_tokens: 30000,
    remain_tokens: 170000,
  },
  ```

- [ ] **Schritt 4: Im Browser prüfen**

  `statusline-configurator.html` öffnen → Palette "Context Window" → "Used Tokens" und "Remaining Tokens" erscheinen → Drag auf Zeile → Chip erscheint → Preview zeigt `30K` / `170K`.

- [ ] **Schritt 5: Commit**

  ```bash
  git add statusline-configurator.html
  git commit -m "feat(configurator): add used_tokens and remain_tokens to field palette"
  ```

---

## Task 4: Cache Efficiency als Progressbar + Typ-Toggle

**Files:**
- Modify: `statusline-configurator.html:388-393` (PERCENTAGE_KEYS)
- Modify: `statusline-configurator.html:1781-1787` (renderEditTabGeneral — field-Branch)
- Modify: `statusline-configurator.html:2078-2095` (saveEditDialog)
- Modify: `statusline-configurator.html:1628-1631` (openEditDialog — Datentyp-Tab Visibility)

- [ ] **Schritt 1: cache_efficiency zu PERCENTAGE_KEYS hinzufügen**

  Zeilen 388–393 in `statusline-configurator.html`:

  ```javascript
  const PERCENTAGE_KEYS = new Set([
    'context_window.used_percentage',
    'context_window.remaining_percentage',
    'rate_limits.five_hour.used_percentage',
    'rate_limits.seven_day.used_percentage',
    'context_window.cache_efficiency',
  ]);
  ```

- [ ] **Schritt 2: Typ-Toggle in renderEditTabGeneral für Prozentwert-Felder**

  Im Branch `else` (type === 'field', Zeile 1789) — direkt vor dem `key`-Display-Block eine Typ-Toggle-Section einfügen. Der vollständige neue `else`-Branch:

  ```javascript
  } else {
    // type === 'field' — key is read-only; path fields also show pathDepth option
    const isPathField   = PATH_KEYS.has(f.key);
    const hasDepth      = f.pathDepth != null && f.pathDepth > 0;
    const isPercentage  = PERCENTAGE_KEYS.has(f.key);
    el.innerHTML = `
      ${isPercentage ? `
      <div style="margin-bottom:12px;">
        <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:6px;">Darstellung</div>
        <label style="display:inline-flex;align-items:center;gap:6px;font-size:12px;cursor:pointer;margin-right:16px;">
          <input type="radio" name="edit-display-type" value="field" checked> Wert
        </label>
        <label style="display:inline-flex;align-items:center;gap:6px;font-size:12px;cursor:pointer;">
          <input type="radio" name="edit-display-type" value="progressbar"> Progressbar
        </label>
      </div>
      ` : ''}
      <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:4px;">Key</div>
      <div style="padding:6px 8px;border-radius:4px;border:1px solid var(--color-border);
                  background:var(--color-surface-2);font-size:12px;color:var(--color-text-muted);
                  margin-bottom:${isPathField ? '12px' : '0'};">
        ${escapeHtml(f.key || '')}
      </div>
      ${isPathField ? `
        <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:6px;margin-top:12px;">Pfadtiefe</div>
        <label style="display:flex;align-items:center;gap:8px;font-size:12px;margin-bottom:4px;cursor:pointer;">
          <input type="radio" name="edit-path-depth" value="full" ${!hasDepth ? 'checked' : ''}>
          <span>Vollständiger Pfad</span>
        </label>
        <label style="display:flex;align-items:center;gap:8px;font-size:12px;cursor:pointer;">
          <input type="radio" name="edit-path-depth" value="limited" ${hasDepth ? 'checked' : ''}>
          <span>Letzte</span>
          <input type="number" id="edit-path-depth-n" min="1" max="99" value="${hasDepth ? f.pathDepth : 2}"
                 oninput="document.querySelector('[name=edit-path-depth][value=limited]').checked=true"
                 style="width:52px;padding:3px 6px;border-radius:4px;border:1px solid var(--color-border);
                        background:var(--color-surface-2);color:var(--color-text);font-size:12px;">
          <span>Segment(e)</span>
        </label>
      ` : ''}
    `;
  }
  ```

  Für den `progressbar`-Branch (Zeile 1715) ebenfalls den Toggle ergänzen — direkt am Anfang des `progressbar`-Blocks, wenn das Feld in PERCENTAGE_KEYS ist:

  ```javascript
  } else if (f.type === 'progressbar') {
    const isPercentage = PERCENTAGE_KEYS.has(f.key);
    // ... existing code ...
    el.innerHTML = `
      ${isPercentage ? `
      <div style="margin-bottom:12px;">
        <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:6px;">Darstellung</div>
        <label style="display:inline-flex;align-items:center;gap:6px;font-size:12px;cursor:pointer;margin-right:16px;">
          <input type="radio" name="edit-display-type" value="field"> Wert
        </label>
        <label style="display:inline-flex;align-items:center;gap:6px;font-size:12px;cursor:pointer;">
          <input type="radio" name="edit-display-type" value="progressbar" checked> Progressbar
        </label>
      </div>
      ` : ''}
      ... (restlicher bisheriger progressbar-HTML-Inhalt unverändert) ...
    `;
  ```

- [ ] **Schritt 3: saveEditDialog — Typ-Toggle auslesen und Typ-Wechsel durchführen**

  In `saveEditDialog()` (Zeile 2078) direkt **nach** `if (pbBracketsEl !== null) _editDraft.barBrackets = pbBracketsEl.checked;` (Zeile 2095) einfügen:

  ```javascript
  // Handle field ↔ progressbar type toggle for PERCENTAGE_KEYS fields
  const displayTypeRadio = document.querySelector('[name="edit-display-type"]:checked');
  if (displayTypeRadio) {
    const newDisplayType = displayTypeRadio.value;
    if (newDisplayType === 'progressbar' && _editDraft.type === 'field') {
      // Switch field → progressbar
      _editDraft.type          = 'progressbar';
      _editDraft.progressStyle = _editDraft.progressStyle || 'color-coded';
      _editDraft.barBrackets   = _editDraft.barBrackets !== undefined ? _editDraft.barBrackets : true;
      _editDraft.barCharset    = _editDraft.barCharset   || 'block';
      _editDraft.dataType      = null;
      _editDraft.format        = null;
    } else if (newDisplayType === 'field' && _editDraft.type === 'progressbar') {
      // Switch progressbar → field
      _editDraft.type          = 'field';
      const defaults           = FIELD_TYPE_DEFAULTS[_editDraft.key] || {};
      _editDraft.dataType      = defaults.dataType || 'number';
      _editDraft.format        = defaults.format   || 'raw';
      _editDraft.progressStyle = undefined;
      _editDraft.barBrackets   = undefined;
      _editDraft.barCharset    = undefined;
    }
  }
  ```

- [ ] **Schritt 4: Datentyp-Tab Visibility beim Typ-Wechsel**

  In `openEditDialog()` (Zeile 1628) die Visibility-Logik anpassen:

  ```javascript
  // Show/hide Datentyp tab — only for line fields of type 'field'
  const isDatatypeVisible = source === 'line' && field.type === 'field';
  document.querySelector('.edit-tab-btn[data-tab="datatype"]').style.display =
    isDatatypeVisible ? '' : 'none';
  ```

  Diese Logik bleibt unverändert — der Typ-Wechsel wird erst beim Speichern wirksam (Dialog öffnet sich neu bei nächstem Klick mit korrektem Typ).

- [ ] **Schritt 5: Im Browser prüfen**

  - `cache_efficiency` aus Palette ziehen → Progressbar-Chip erscheint (nicht mehr Field-Chip)
  - Bestehenden `cache_efficiency`-Field-Chip bearbeiten → Toggle "Wert / Progressbar" sichtbar → auf Progressbar schalten → speichern → Chip zeigt Progressbar

- [ ] **Schritt 6: Commit**

  ```bash
  git add statusline-configurator.html
  git commit -m "feat(configurator): add progressbar type toggle for percentage fields and fix cache_efficiency drag"
  ```

---

## Task 5: logNewFields in Edit-Dialog

**Files:**
- Modify: `statusline-configurator.html:994-1008` (Sidebar-Toggle entfernen)
- Modify: `statusline-configurator.html:1781-1787` (new_fields_indicator Edit-Dialog)
- Modify: `statusline-configurator.html:2078` (saveEditDialog)

- [ ] **Schritt 1: Sidebar-Toggle entfernen**

  In `statusline-configurator.html` den gesamten Block Zeilen 994–1008 entfernen:

  ```javascript
  // Settings section appended after theme content in both empty and non-empty state
  const settingsHtml = `
    <div style="margin-top:16px;border-top:1px solid var(--color-border);padding-top:12px;">
      <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:6px;">Einstellungen</div>
      <div>
        <label style="display:flex;align-items:center;gap:6px;font-size:12px;cursor:pointer;">
          <input type="checkbox" id="logNewFieldsToggle"
                 onchange="state.logNewFields = this.checked; updateExportTextarea();"
                 ${state.logNewFields ? 'checked' : ''}
                 title="Unbekannte Payload-Keys in statusline-new-fields.log schreiben">
          Neue Felder protokollieren
        </label>
      </div>
    </div>
  `;
  ```

  Und die Verwendung von `settingsHtml` in den nachfolgenden `el.innerHTML`-Assignments entfernen.

- [ ] **Schritt 2: Edit-Dialog für new_fields_indicator ergänzen**

  In `renderEditTabGeneral()` den `new_fields_indicator`-Branch (Zeile 1781–1787) ersetzen:

  ```javascript
  } else if (f.type === 'new_fields_indicator') {
    el.innerHTML = `
      <p style="font-size:12px;color:var(--color-text-muted);line-height:1.5;margin-bottom:12px;">
        Zeigt an, ob der aktuelle JSON-Payload Keys enthält, die dem Konfigurator noch unbekannt sind.<br>
        Beispielausgabe: <code>● 3 neue Felder</code>
      </p>
      <label style="display:flex;align-items:center;gap:8px;font-size:12px;cursor:pointer;">
        <input type="checkbox" id="edit-log-new-fields" ${state.logNewFields ? 'checked' : ''}>
        <span>In Log-Datei schreiben</span>
      </label>
      <p style="font-size:10px;color:var(--color-text-muted);margin-top:4px;margin-left:24px;">
        Pfad: &lt;scriptdir&gt;/statusline-new-fields.log
      </p>
    `;
  ```

- [ ] **Schritt 3: saveEditDialog — logNewFields aus Checkbox lesen**

  In `saveEditDialog()` direkt nach der `bgInput`-Zeile (Zeile 2135) einfügen:

  ```javascript
  // Sync logNewFields from new_fields_indicator edit dialog
  const logNewFieldsEl = document.getElementById('edit-log-new-fields');
  if (logNewFieldsEl !== null) state.logNewFields = logNewFieldsEl.checked;
  ```

- [ ] **Schritt 4: Im Browser prüfen**

  - Themes-Tab öffnen → kein "Neue Felder protokollieren"-Toggle mehr sichtbar
  - `● Neue Felder`-Chip auf eine Zeile ziehen → Chip bearbeiten → Checkbox "In Log-Datei schreiben" sichtbar → Haken setzen → speichern → Export-JSON enthält `"logNewFields": true`

- [ ] **Schritt 5: Commit**

  ```bash
  git add statusline-configurator.html
  git commit -m "feat(configurator): move logNewFields toggle from sidebar to new_fields_indicator edit dialog"
  ```

---

## Task 6: Tab-Ausrichtung — mergeWithNext in Config-Export/Import

**Files:**
- Modify: `statusline-configurator.html:1429-1449` (buildExportJson)
- Modify: `statusline-configurator.html:1529-1562` (loadConfig field-mapping)

- [ ] **Schritt 1: buildExportJson — mergeWithNext serialisieren**

  In `buildExportJson()` (Zeile 1429) nach dem `placeholder`-Eintrag (Zeile 1447) einfügen:

  ```javascript
  if (f.mergeWithNext) base.mergeWithNext = true;
  ```

- [ ] **Schritt 2: loadConfig — mergeWithNext deserialisieren**

  Im field-mapping in `loadConfig` (Zeile 1531) nach `placeholder` (Zeile 1561) einfügen:

  ```javascript
  mergeWithNext: f.mergeWithNext === true,
  ```

- [ ] **Schritt 3: Im Browser prüfen**

  - Ein Feld bearbeiten, `mergeWithNext` per Checkbox setzen (Task 7 noch nicht implementiert → direkt in DevTools im State setzen: `state.lines[0].fields[0].mergeWithNext = true; updateExportTextarea()`) → Export-JSON enthält `"mergeWithNext": true` → JSON importieren → `mergeWithNext` bleibt erhalten.

- [ ] **Schritt 4: Commit**

  ```bash
  git add statusline-configurator.html
  git commit -m "feat(configurator): add mergeWithNext to config export and import"
  ```

---

## Task 7: Tab-Ausrichtung — UI (Quick-Handle + Edit-Dialog Checkbox)

**Files:**
- Modify: `statusline-configurator.html:1236-1258` (renderFieldChip)
- Modify: `statusline-configurator.html:1661` (renderEditTabGeneral — alle Feld-Typen)
- Modify: `statusline-configurator.html:2078` (saveEditDialog)

- [ ] **Schritt 1: toggleMergeNext Hilfsfunktion hinzufügen**

  Direkt nach der `fieldLabel`-Funktion (nach Zeile 1272) einfügen:

  ```javascript
  /**
   * Toggles the mergeWithNext flag on a field chip and re-renders.
   * @param {string} lineId - The ID of the line containing the field.
   * @param {string} fieldId - The ID of the field to toggle.
   */
  function toggleMergeNext(lineId, fieldId) {
    const line = state.lines.find(l => l.id === lineId);
    if (!line) return;
    const field = line.fields.find(f => f.id === fieldId);
    if (!field) return;
    field.mergeWithNext = !field.mergeWithNext;
    renderLines();
    renderPreview();
    updateExportTextarea();
  }
  ```

- [ ] **Schritt 2: Quick-Handle am Chip in renderFieldChip hinzufügen**

  `renderFieldChip` (Zeile 1236) — den `<span>`-Inhalt erweitern:

  ```javascript
  function renderFieldChip(field, lineId) {
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
    return `
      <span class="field-chip" data-field-id="${field.id}" data-line-id="${lineId}"
            style="display:inline-flex;align-items:center;gap:4px;padding:3px 8px;
                   border-radius:4px;font-size:12px;background:var(--color-surface-2);
                   border:1px solid var(--color-border);${bg}${fg}cursor:default;">
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

- [ ] **Schritt 3: Checkbox in renderEditTabGeneral für alle Feld-Typen**

  In `renderEditTabGeneral()` muss die `mergeWithNext`-Checkbox in **allen** Branches erscheinen (`static`, `progressbar`, `new_fields_indicator`, `field`). Dazu am **Ende** jedes `el.innerHTML`-Assignments (vor dem schließenden Template-Literal `` ` ``) die Checkbox anhängen.

  Die einfachste Implementierung: einen gemeinsamen Block am Ende der Funktion (nach dem `el.innerHTML`-Assignment) hinzufügen:

  ```javascript
  // Append mergeWithNext checkbox to the general tab for all field types
  const mergeSection = document.createElement('div');
  mergeSection.style.cssText = 'margin-top:12px;border-top:1px solid var(--color-border);padding-top:10px;';
  mergeSection.innerHTML = `
    <label style="display:flex;align-items:center;gap:8px;font-size:12px;cursor:pointer;">
      <input type="checkbox" id="edit-merge-next" ${_editDraft.mergeWithNext ? 'checked' : ''}>
      <span>Mit nächstem Feld gruppieren (Tab-Ausrichtung)</span>
    </label>
  `;
  el.appendChild(mergeSection);
  ```

  Dieser Block wird am Ende von `renderEditTabGeneral()` eingefügt, nach dem letzten `} else {`-Block.

- [ ] **Schritt 4: saveEditDialog — mergeWithNext aus Checkbox lesen**

  In `saveEditDialog()` nach dem `logNewFieldsEl`-Block einfügen:

  ```javascript
  // Read mergeWithNext checkbox
  const mergeNextEl = document.getElementById('edit-merge-next');
  if (mergeNextEl !== null) _editDraft.mergeWithNext = mergeNextEl.checked;
  ```

- [ ] **Schritt 5: Im Browser prüfen**

  - Feld-Chip zeigt `↝`-Handle → Klick → Handle wird zu `→` (Akzentfarbe) → Chip visuell verbunden
  - Edit-Dialog → Checkbox "Mit nächstem Feld gruppieren" → setzen → speichern → Export enthält `mergeWithNext: true`

- [ ] **Schritt 6: Commit**

  ```bash
  git add statusline-configurator.html
  git commit -m "feat(configurator): add mergeWithNext quick-handle on chips and edit dialog checkbox"
  ```

---

## Task 8: Tab-Ausrichtung — PS1 Hilfsfunktionen

**Files:**
- Modify: `statusline.ps1:518-526` (nach Format-Line, neue Funktionen einfügen)
- Modify: `tests/statusline.Tests.ps1:1115` (neue Describe-Blöcke)

- [ ] **Schritt 1: Failing Tests schreiben**

  In `tests/statusline.Tests.ps1` am Ende der Datei (nach dem letzten `}`) einfügen:

  ```powershell
  Describe 'Get-VisibleWidth' {
      It 'returns length of plain string' {
          Get-VisibleWidth 'hello' | Should -Be 5
      }

      It 'strips ANSI color codes before measuring' {
          # ESC[38;2;74;222;128m = green color, ESC[0m = reset
          $ansiString = "$([char]27)[38;2;74;222;128mhello$([char]27)[0m"
          Get-VisibleWidth $ansiString | Should -Be 5
      }

      It 'returns 0 for empty string' {
          Get-VisibleWidth '' | Should -Be 0
      }

      It 'returns 0 for ANSI-only string' {
          Get-VisibleWidth "$([char]27)[0m" | Should -Be 0
      }
  }

  Describe 'Build-Groups' {
      It 'returns one group per field when no mergeWithNext flags set' {
          $fields = @(
              [PSCustomObject]@{ type = 'field'; key = 'a' },
              [PSCustomObject]@{ type = 'field'; key = 'b' },
              [PSCustomObject]@{ type = 'field'; key = 'c' }
          )
          $groups = Build-Groups $fields
          $groups.Count | Should -Be 3
          $groups[0].Count | Should -Be 1
          $groups[1].Count | Should -Be 1
          $groups[2].Count | Should -Be 1
      }

      It 'groups two fields when first has mergeWithNext' {
          $fields = @(
              [PSCustomObject]@{ type = 'field'; key = 'a'; mergeWithNext = $true },
              [PSCustomObject]@{ type = 'field'; key = 'b' }
          )
          $groups = Build-Groups $fields
          $groups.Count | Should -Be 1
          $groups[0].Count | Should -Be 2
          $groups[0][0].key | Should -Be 'a'
          $groups[0][1].key | Should -Be 'b'
      }

      It 'creates three groups from chain A-B-C, D, E-F' {
          $fields = @(
              [PSCustomObject]@{ key = 'a'; mergeWithNext = $true },
              [PSCustomObject]@{ key = 'b'; mergeWithNext = $true },
              [PSCustomObject]@{ key = 'c' },
              [PSCustomObject]@{ key = 'd' },
              [PSCustomObject]@{ key = 'e'; mergeWithNext = $true },
              [PSCustomObject]@{ key = 'f' }
          )
          $groups = Build-Groups $fields
          $groups.Count | Should -Be 3
          $groups[0].Count | Should -Be 3   # a, b, c
          $groups[1].Count | Should -Be 1   # d
          $groups[2].Count | Should -Be 2   # e, f
      }

      It 'handles single field' {
          $fields = @([PSCustomObject]@{ key = 'a' })
          $groups = Build-Groups $fields
          $groups.Count | Should -Be 1
      }

      It 'handles empty array' {
          $groups = Build-Groups @()
          $groups.Count | Should -Be 0
      }
  }
  ```

- [ ] **Schritt 2: Tests ausführen — erwartet FAIL**

  ```
  pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
  ```
  Erwartet: alle neuen Tests schlagen fehl.

- [ ] **Schritt 3: Get-VisibleWidth und Build-Groups implementieren**

  In `statusline.ps1` direkt **vor** `function Format-Line` (Zeile 518) einfügen:

  ```powershell
  <#
  .SYNOPSIS
      Returns the visible character width of a string after stripping ANSI escape sequences.
  .PARAMETER Text
      String possibly containing ANSI color codes (e.g. ESC[38;2;R;G;Bm).
  .OUTPUTS
      Integer: number of visible characters.
  #>
  function Get-VisibleWidth {
      param([string]$Text)
      return ($Text -replace "`e\[[0-9;]*m", '').Length
  }

  <#
  .SYNOPSIS
      Groups an array of field objects into column groups based on mergeWithNext flags.
  .DESCRIPTION
      Walks fields left to right. A field with mergeWithNext=true is merged with the
      following field into the same group. Groups form the unit of column alignment.
  .PARAMETER Fields
      Array of field PSCustomObjects from the config.
  .OUTPUTS
      Array of arrays — each inner array is one group of fields.
  #>
  function Build-Groups {
      param([array]$Fields)
      if (-not $Fields -or $Fields.Count -eq 0) { return , @() }
      $groups  = [System.Collections.Generic.List[object]]::new()
      $current = [System.Collections.Generic.List[object]]::new()
      foreach ($field in $Fields) {
          $current.Add($field)
          if (-not $field.mergeWithNext) {
              $groups.Add($current.ToArray())
              $current = [System.Collections.Generic.List[object]]::new()
          }
      }
      # Safety: trailing mergeWithNext=true on last field
      if ($current.Count -gt 0) { $groups.Add($current.ToArray()) }
      return , $groups.ToArray()
  }
  ```

- [ ] **Schritt 4: Tests ausführen — erwartet alle grün**

  ```
  pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
  ```

- [ ] **Schritt 5: Commit**

  ```bash
  git add statusline.ps1 tests/statusline.Tests.ps1
  git commit -m "feat(statusline): add Get-VisibleWidth and Build-Groups for tab alignment"
  ```

---

## Task 9: Tab-Ausrichtung — PS1 Two-Pass Rendering

**Files:**
- Modify: `statusline.ps1:518` (Format-Lines-Aligned hinzufügen)
- Modify: `statusline.ps1:744-745` (Invoke-Main rendering ersetzen)
- Modify: `tests/statusline.Tests.ps1` (neue Tests am Ende)

- [ ] **Schritt 1: Failing Tests schreiben**

  In `tests/statusline.Tests.ps1` am Ende einfügen:

  ```powershell
  Describe 'Format-Lines-Aligned' {
      It 'renders single line without padding' {
          $lines = @([PSCustomObject]@{
              fields = @(
                  [PSCustomObject]@{ type = 'static'; text = 'hi'; fg = $null; bg = $null }
              )
          })
          $result = Format-Lines-Aligned $lines ([PSCustomObject]@{})
          $result | Should -Be 'hi'
      }

      It 'pads shorter group to match longer group across lines' {
          $lines = @(
              [PSCustomObject]@{ fields = @(
                  [PSCustomObject]@{ type = 'static'; text = 'hi';    fg = $null; bg = $null },
                  [PSCustomObject]@{ type = 'static'; text = ' | ';   fg = $null; bg = $null },
                  [PSCustomObject]@{ type = 'static'; text = 'world'; fg = $null; bg = $null }
              )},
              [PSCustomObject]@{ fields = @(
                  [PSCustomObject]@{ type = 'static'; text = 'hello'; fg = $null; bg = $null },
                  [PSCustomObject]@{ type = 'static'; text = ' | ';   fg = $null; bg = $null },
                  [PSCustomObject]@{ type = 'static'; text = 'x';     fg = $null; bg = $null }
              )}
          )
          $result = Format-Lines-Aligned $lines ([PSCustomObject]@{})
          $resultLines = $result -split "`n"
          # Group 1: 'hi' padded to width of 'hello' (5), group 2: ' | ' (3), group 3: no padding on last
          $resultLines[0] | Should -Be 'hi    | world'
          $resultLines[1] | Should -Be 'hello | x'
      }

      It 'groups merged fields and aligns by group width' {
          $lines = @(
              [PSCustomObject]@{ fields = @(
                  [PSCustomObject]@{ type = 'static'; text = 'a'; fg = $null; bg = $null; mergeWithNext = $true },
                  [PSCustomObject]@{ type = 'static'; text = 'b'; fg = $null; bg = $null },
                  [PSCustomObject]@{ type = 'static'; text = 'X'; fg = $null; bg = $null }
              )},
              [PSCustomObject]@{ fields = @(
                  [PSCustomObject]@{ type = 'static'; text = 'longgroup'; fg = $null; bg = $null },
                  [PSCustomObject]@{ type = 'static'; text = 'Y';         fg = $null; bg = $null }
              )}
          )
          $result = Format-Lines-Aligned $lines ([PSCustomObject]@{})
          $resultLines = $result -split "`n"
          # Group 1: 'ab' (2 chars) vs 'longgroup' (9 chars) → 'ab' padded to 9
          $resultLines[0] | Should -Be 'ab       X'
          $resultLines[1] | Should -Be 'longgroupY'
      }

      It 'skips empty lines' {
          $lines = @(
              [PSCustomObject]@{ fields = @() },
              [PSCustomObject]@{ fields = @(
                  [PSCustomObject]@{ type = 'static'; text = 'ok'; fg = $null; bg = $null }
              )}
          )
          $result = Format-Lines-Aligned $lines ([PSCustomObject]@{})
          $result | Should -Be 'ok'
      }

      It 'does not pad the last group of each line' {
          $lines = @(
              [PSCustomObject]@{ fields = @(
                  [PSCustomObject]@{ type = 'static'; text = 'short'; fg = $null; bg = $null }
              )},
              [PSCustomObject]@{ fields = @(
                  [PSCustomObject]@{ type = 'static'; text = 'much longer text'; fg = $null; bg = $null }
              )}
          )
          $result = Format-Lines-Aligned $lines ([PSCustomObject]@{})
          $resultLines = $result -split "`n"
          # Last group — no trailing padding on either line
          $resultLines[0] | Should -Be 'short'
          $resultLines[1] | Should -Be 'much longer text'
      }
  }
  ```

- [ ] **Schritt 2: Tests ausführen — erwartet FAIL**

  ```
  pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
  ```

- [ ] **Schritt 3: Format-Lines-Aligned implementieren**

  In `statusline.ps1` direkt **nach** `Build-Groups` (und **vor** `Format-Line`) einfügen:

  ```powershell
  <#
  .SYNOPSIS
      Renders all configured lines with column alignment via two-pass rendering.
  .DESCRIPTION
      Pass 1: Renders each group of fields per line and measures visible width.
      Pass 2: Pads each group to the maximum width of that group position across all lines.
      The last group in each line is never padded (no trailing whitespace).
  .PARAMETER Lines
      Array of line config objects (each with a .fields array).
  .PARAMETER Data
      PSCustomObject parsed from Claude Code's JSON input.
  .OUTPUTS
      All non-empty rendered lines joined by newline.
  #>
  function Format-Lines-Aligned {
      param(
          [array]$Lines,
          [PSCustomObject]$Data
      )

      # Pass 1: render all groups for all lines, measure visible widths
      $allLineGroups = [System.Collections.Generic.List[object]]::new()
      foreach ($line in $Lines) {
          if (-not $line.fields -or $line.fields.Count -eq 0) {
              $allLineGroups.Add(@())
              continue
          }
          $groups = Build-Groups $line.fields
          $renderedGroups = [System.Collections.Generic.List[string]]::new()
          foreach ($group in $groups) {
              $rendered = ($group | ForEach-Object { Format-Field $_ $Data }) -join ''
              $renderedGroups.Add($rendered)
          }
          $allLineGroups.Add($renderedGroups.ToArray())
      }

      # Pass 2: compute max visible width per group position
      $maxGroupCount = 0
      foreach ($rg in $allLineGroups) { if ($rg.Count -gt $maxGroupCount) { $maxGroupCount = $rg.Count } }
      $maxWidths = @(0) * [math]::Max(1, $maxGroupCount)
      for ($g = 0; $g -lt $maxGroupCount; $g++) {
          foreach ($renderedGroups in $allLineGroups) {
              if ($g -lt $renderedGroups.Count) {
                  $w = Get-VisibleWidth $renderedGroups[$g]
                  if ($w -gt $maxWidths[$g]) { $maxWidths[$g] = $w }
              }
          }
      }

      # Pass 3: apply padding and join
      $outputLines = [System.Collections.Generic.List[string]]::new()
      foreach ($renderedGroups in $allLineGroups) {
          if ($renderedGroups.Count -eq 0) { continue }
          # Skip line if all groups are empty strings (field returned nothing)
          if (($renderedGroups | Where-Object { $_ -ne '' } | Measure-Object).Count -eq 0) { continue }
          $lineParts = [System.Collections.Generic.List[string]]::new()
          for ($g = 0; $g -lt $renderedGroups.Count; $g++) {
              $text    = $renderedGroups[$g]
              $isLast  = $g -eq $renderedGroups.Count - 1
              $padding = if (-not $isLast) { $maxWidths[$g] - (Get-VisibleWidth $text) } else { 0 }
              $lineParts.Add($text + (' ' * [math]::Max(0, $padding)))
          }
          $outputLines.Add($lineParts -join '')
      }

      return $outputLines -join "`n"
  }
  ```

- [ ] **Schritt 4: Invoke-Main auf Format-Lines-Aligned umstellen**

  In `statusline.ps1` Zeilen 744–745 ersetzen:

  ```powershell
  # Vorher:
  $output = $config.lines | ForEach-Object { Format-Line $_ $data } | Where-Object { $_ -ne '' }
  return $output -join "`n"

  # Nachher:
  return Format-Lines-Aligned $config.lines $data
  ```

- [ ] **Schritt 5: Tests ausführen — erwartet alle grün**

  ```
  pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
  ```

- [ ] **Schritt 6: Commit**

  ```bash
  git add statusline.ps1 tests/statusline.Tests.ps1
  git commit -m "feat(statusline): implement two-pass column alignment via Format-Lines-Aligned"
  ```

---

## Task 10: Tab-Ausrichtung — JS Preview Alignment

**Files:**
- Modify: `statusline-configurator.html:1400-1426` (renderPreview)

- [ ] **Schritt 1: buildGroups Hilfsfunktion hinzufügen**

  Direkt vor `renderPreview()` (Zeile 1400) einfügen:

  ```javascript
  /**
   * Groups fields into column groups based on mergeWithNext flags.
   * Mirrors the PS1 Build-Groups logic exactly.
   * @param {Array} fields - Array of field objects from a line.
   * @returns {Array<Array>} Array of groups, each group is an array of fields.
   */
  function buildGroups(fields) {
    const groups = [];
    let current = [];
    for (const field of fields) {
      current.push(field);
      if (!field.mergeWithNext) {
        groups.push(current);
        current = [];
      }
    }
    if (current.length > 0) groups.push(current);
    return groups;
  }

  /**
   * Returns the visible character count of an HTML snippet by stripping tags.
   * Used for column width measurement in the preview alignment.
   * @param {string} html - HTML string (spans with colors, no ANSI codes).
   * @returns {number} Visible text length.
   */
  function getVisibleWidth(html) {
    const tmp = document.createElement('span');
    tmp.innerHTML = html;
    return tmp.textContent.length;
  }
  ```

- [ ] **Schritt 2: renderPreview auf Two-Pass Alignment umstellen**

  `renderPreview()` (Zeilen 1400–1426) vollständig ersetzen:

  ```javascript
  function renderPreview() {
    const out = document.getElementById('preview-output');
    if (state.lines.length === 0) {
      out.innerHTML = '<span style="color:var(--color-text-muted);">Keine Zeilen konfiguriert.</span>';
      return;
    }

    // Pass 1: render all groups for all lines, measure visible widths
    const allLineGroups = state.lines.map(line => {
      if (line.fields.length === 0) return [];
      return buildGroups(line.fields).map(groupFields =>
        groupFields.map(f => {
          const previewOverride = (_editDraft && _editDraft.id === f.id)
            ? (_editDraft.previewValue ?? f.previewValue ?? null)
            : (f.previewValue ?? null);
          const fieldThemeId  = f.themeId ?? (_themePreviewId ?? state.activeTheme);
          const fieldThemeObj = fieldThemeId ? state.themes.find(t => t.id === fieldThemeId) ?? null : null;
          return renderFieldHtml(f, SAMPLE_DATA, fieldThemeObj, previewOverride);
        }).join('')
      );
    });

    // Pass 2: max visible width per group position
    const maxGroupCount = Math.max(0, ...allLineGroups.map(g => g.length));
    const maxWidths = new Array(maxGroupCount).fill(0);
    for (let g = 0; g < maxGroupCount; g++) {
      for (const lineGroups of allLineGroups) {
        if (g < lineGroups.length) {
          const w = getVisibleWidth(lineGroups[g]);
          if (w > maxWidths[g]) maxWidths[g] = w;
        }
      }
    }

    // Pass 3: pad and join per line
    const lines = allLineGroups.map(lineGroups => {
      if (lineGroups.length === 0) {
        return '<span style="color:var(--color-text-muted);">(leere Zeile)</span>';
      }
      return lineGroups.map((groupHtml, g) => {
        const isLast  = g === lineGroups.length - 1;
        const padding = isLast ? 0 : maxWidths[g] - getVisibleWidth(groupHtml);
        if (padding > 0) {
          return groupHtml + `<span style="white-space:pre">${' '.repeat(padding)}</span>`;
        }
        return groupHtml;
      }).join('');
    });

    out.innerHTML = lines.join('<br>');
  }
  ```

- [ ] **Schritt 3: Im Browser prüfen**

  - Zwei Zeilen konfigurieren, erste Zeile: `[model_name] [separator] [used_pct]`, zweite Zeile: `[cost] [separator] [cache_eff]`
  - Ohne mergeWithNext: Felder alignieren sich bereits nach Position
  - `model_name`-Chip → `→`-Handle klicken → `model_name` und `separator` werden zu Gruppe 1 → Preview zeigt aktualisierte Ausrichtung
  - Konfiguration exportieren → `mergeWithNext: true` in JSON → importieren → Ausrichtung bleibt erhalten

- [ ] **Schritt 4: Commit**

  ```bash
  git add statusline-configurator.html
  git commit -m "feat(configurator): implement two-pass column alignment in preview"
  ```

---

## Gesamttest

- [ ] **Alle PS1 Tests grün**

  ```
  pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
  ```
  Erwartet: alle Tests Pass (vorher 26, neu min. 26 + ~20 neue).

- [ ] **Final Commit / Branch bereit für Review**

  ```bash
  git log --oneline -10
  ```
