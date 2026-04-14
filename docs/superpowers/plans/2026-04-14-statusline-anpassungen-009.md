# Statusline Anpassungen 009 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zwei Bugfixes (Braille 100%, DnD nach Merge-Toggle) und zwei Features (Zeilen-Gruppen für Spaltenalignment, globaler Alignment-Toggle).

**Architecture:** Tasks 1–2 sind isolierte Bugfixes. Task 3 fügt den globalen Alignment-Toggle ein (einfach). Tasks 4–6 implementieren Zeilen-Gruppen: zuerst Config/State, dann UI, dann PS1-Refactoring, dann JS-Refactoring.

**Tech Stack:** PowerShell 7 (Pester 5.x), Single-File HTML (Vanilla JS)

---

## File Map

| Datei | Tasks |
|---|---|
| `statusline.ps1` | Task 1 (Braille Bug), Task 5 (Build-LineGroups + Format-Lines-Aligned refactor + Invoke-Main toggle) |
| `tests/statusline.Tests.ps1` | Task 1 (Tests), Task 5 (neue Tests + bestehende Tests aktualisieren) |
| `statusline-configurator.html` | Task 2 (DnD Bug), Task 3 (Toggle UI+State+Export/Import), Task 4 (Zeilen mergeWithNext State+Export/Import), Task 6 (Zeilen-UI + renderPreview refactor) |

---

## Task 1: Bug — Braille Progressbar 100%

**Files:**
- Modify: `statusline.ps1:204-208`
- Modify: `tests/statusline.Tests.ps1` (neue Tests am Ende)

- [ ] **Schritt 1: Failing Tests schreiben**

  In `tests/statusline.Tests.ps1` am Ende einfügen:

  ```powershell
  Describe 'Format-Progressbar Braille' {
      It 'shows all filled chars at 100%' {
          $result = Format-Progressbar -Value 100 -Charset 'braille'
          # At 100%, all 10 positions should be the filled braille char ⣿ (U+28FF)
          $bar = $result -replace ' 100%$', ''
          $bar | Should -Be ([string][char]0x28FF * 10)
      }

      It 'shows right-edge char at last position when not full' {
          $result = Format-Progressbar -Value 90 -Charset 'braille'
          $bar = $result -replace ' 90%$', ''
          # Position 9 (last) must be the right-edge char ⣹ (U+28F9), not ⣿
          $bar[-1] | Should -Be ([char]0x28F9)
          # Positions 0-8 should all be filled ⣿
          $bar.Substring(0, 9) | Should -Be ([string][char]0x28FF * 9)
      }

      It 'shows left-edge char at position 0 when empty' {
          $result = Format-Progressbar -Value 0 -Charset 'braille'
          $bar = $result -replace ' 0%$', ''
          # Position 0 must be the left-edge char ⣏ (U+28CF)
          $bar[0] | Should -Be ([char]0x28CF)
          # Position 9 (last) must be the right-edge char ⣹ (U+28F9)
          $bar[-1] | Should -Be ([char]0x28F9)
      }
  }
  ```

- [ ] **Schritt 2: Tests ausführen — erwartet FAIL**

  ```
  pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
  ```
  Der 100%-Test muss fehlschlagen. Die 90%- und 0%-Tests sollen bereits passen.

- [ ] **Schritt 3: Fix in statusline.ps1**

  In `statusline.ps1` den Braille-Loop (Zeile ~204) von:
  ```powershell
  for ($i = 0; $i -lt 10; $i++) {
      if     ($i -eq 9)           { $inner += $bEdgeR }
      elseif ($i -lt $filled)     { $inner += $bFill  }
      elseif ($i -eq 0)           { $inner += $bEdgeL }
      else                        { $inner += $bEmpty }
  }
  ```
  auf:
  ```powershell
  for ($i = 0; $i -lt 10; $i++) {
      if     ($i -lt $filled)     { $inner += $bFill  }
      elseif ($i -eq 9)           { $inner += $bEdgeR }
      elseif ($i -eq 0)           { $inner += $bEdgeL }
      else                        { $inner += $bEmpty }
  }
  ```

- [ ] **Schritt 4: Tests ausführen — alle grün**

  ```
  pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
  ```

- [ ] **Schritt 5: Commit**

  ```bash
  git add statusline.ps1 tests/statusline.Tests.ps1
  git commit -m "fix(statusline): fix braille progressbar showing wrong char at 100%"
  ```

---

## Task 2: Bug — Drag&Drop bricht nach Merge-Toggle

**Files:**
- Modify: `statusline-configurator.html` (Funktion `toggleMergeNext`)

- [ ] **Schritt 1: Fix in toggleMergeNext**

  Suche in `statusline-configurator.html` die Funktion `toggleMergeNext`. Sie sieht aktuell so aus:

  ```javascript
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

  Ersetze die letzten drei Zeilen durch einen einzigen `render()`-Aufruf:

  ```javascript
  function toggleMergeNext(lineId, fieldId) {
    const line = state.lines.find(l => l.id === lineId);
    if (!line) return;
    const field = line.fields.find(f => f.id === fieldId);
    if (!field) return;
    field.mergeWithNext = !field.mergeWithNext;
    render();
  }
  ```

  Begründung: `render()` ruft `renderLines()` + `renderPreview()` + `updateExportTextarea()` + `initSortable()` auf. Das `initSortable()` war der fehlende Aufruf, der die Drag&Drop-Instanzen nach dem DOM-Rebuild neu initialisiert.

- [ ] **Schritt 2: Commit**

  ```bash
  git add statusline-configurator.html
  git commit -m "fix(configurator): reinitialize sortable after merge toggle by calling render()"
  ```

---

## Task 3: Feature — Spaltenausrichtung-Toggle (Global)

**Files:**
- Modify: `statusline-configurator.html` (State, UI, buildExportJson, loadConfig, renderPreview)
- Modify: `statusline.ps1` (Invoke-Main)

- [ ] **Schritt 1: State erweitern**

  Suche in `statusline-configurator.html`:
  ```javascript
  const state = { lines: [], customFields: [], themes: [], activeTheme: null, logNewFields: false };
  ```
  Ersetze durch:
  ```javascript
  const state = { lines: [], customFields: [], themes: [], activeTheme: null, logNewFields: false, columnAlignmentEnabled: true };
  ```

- [ ] **Schritt 2: Toggle-UI oberhalb des Lines-Containers einfügen**

  Suche:
  ```html
  <div id="lines-container"></div>
  ```
  Ersetze durch:
  ```html
  <div style="margin-bottom:8px;padding:6px 0;border-bottom:1px solid var(--color-border);">
    <label style="display:flex;align-items:center;gap:8px;font-size:12px;cursor:pointer;">
      <input type="checkbox" id="toggle-column-alignment" onchange="toggleColumnAlignment(this.checked)" checked>
      <span>Spaltenausrichtung aktivieren</span>
    </label>
  </div>
  <div id="lines-container"></div>
  ```

- [ ] **Schritt 3: toggleColumnAlignment Funktion hinzufügen**

  Direkt nach der `toggleMergeNext`-Funktion einfügen:

  ```javascript
  /**
   * Sets the global column alignment flag and re-renders.
   * @param {boolean} enabled - Whether column alignment should be active.
   */
  function toggleColumnAlignment(enabled) {
    state.columnAlignmentEnabled = enabled;
    renderPreview();
    updateExportTextarea();
  }
  ```

- [ ] **Schritt 4: Checkbox-State beim Render synchronisieren**

  In `renderLines()` (nach dem `container.innerHTML = ''`-Block, am Ende der Funktion) einfügen:

  ```javascript
  // Sync column alignment checkbox
  const alignEl = document.getElementById('toggle-column-alignment');
  if (alignEl) alignEl.checked = state.columnAlignmentEnabled;
  ```

- [ ] **Schritt 5: buildExportJson — columnAlignmentEnabled serialisieren**

  In `buildExportJson()`, vor `return JSON.stringify(...)`:

  ```javascript
  // Serialize only when disabled (true is the default)
  if (!state.columnAlignmentEnabled) config.columnAlignmentEnabled = false;
  ```

- [ ] **Schritt 6: loadConfig — columnAlignmentEnabled deserialisieren**

  In `loadConfig()`, nach `state.logNewFields = !!(json.logNewFields);`:

  ```javascript
  state.columnAlignmentEnabled = json.columnAlignmentEnabled !== false;
  ```

- [ ] **Schritt 7: renderPreview — Toggle beachten**

  In `renderPreview()` ist der Einstiegspunkt aktuell die Zeile:
  ```javascript
  const allLineGroups = state.lines.map(line => {
  ```

  Die Funktion soll später durch Task 6 umgebaut werden. Für jetzt genügt es, wenn `columnAlignmentEnabled = false` die einfache Darstellung wählt. Den Toggle erst in Task 6 integrieren — dieser Schritt nur für Export/Import und Checkbox-UI.

- [ ] **Schritt 8: PS1 — Invoke-Main toggle-Logik**

  In `statusline.ps1`, die Zeile:
  ```powershell
  return Format-Lines-Aligned $config.lines $data
  ```
  ersetzen durch:
  ```powershell
  if ($config.columnAlignmentEnabled -ne $false) {
      return Format-Lines-Aligned $config.lines $data
  } else {
      $output = $config.lines | ForEach-Object { Format-Line $_ $data } | Where-Object { $_ -ne '' }
      return $output -join "`n"
  }
  ```

- [ ] **Schritt 9: Tests ausführen**

  ```
  pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
  ```
  Alle Tests müssen grün sein.

- [ ] **Schritt 10: Commit**

  ```bash
  git add statusline-configurator.html statusline.ps1
  git commit -m "feat(statusline): add global column alignment toggle"
  ```

---

## Task 4: Feature — Zeilen `mergeWithNext` (Config + State)

**Files:**
- Modify: `statusline-configurator.html` (addLine, buildExportJson, loadConfig)

- [ ] **Schritt 1: addLine — mergeWithNext im neuen Zeilen-Objekt**

  Suche:
  ```javascript
  state.lines.push({ id: generateId(), fields: [] });
  ```
  Ersetze durch:
  ```javascript
  state.lines.push({ id: generateId(), mergeWithNext: false, fields: [] });
  ```

- [ ] **Schritt 2: buildExportJson — line.mergeWithNext serialisieren**

  In `buildExportJson()`, die Map-Funktion für `lines`:
  ```javascript
  const lines = state.lines.map(line => ({
    fields: line.fields.map(f => { ... })
  }));
  ```
  Ersetze durch:
  ```javascript
  const lines = state.lines.map(line => {
    const lineObj = { fields: line.fields.map(f => { ... }) };
    if (line.mergeWithNext) lineObj.mergeWithNext = true;
    return lineObj;
  });
  ```
  
  **Wichtig:** Das `line.fields.map(f => { ... })`-Lambda ist lang — es muss vollständig kopiert werden. Lese die Datei vor der Bearbeitung.

- [ ] **Schritt 3: loadConfig — line.mergeWithNext deserialisieren**

  In `loadConfig()`, im `json.lines.map`-Block:
  ```javascript
  state.lines = json.lines.map(line => ({
    id:     generateId(),
    fields: (line.fields || []).map(f => ({ ... })),
  }));
  ```
  Ersetze durch:
  ```javascript
  state.lines = json.lines.map(line => ({
    id:           generateId(),
    mergeWithNext: line.mergeWithNext === true,
    fields:       (line.fields || []).map(f => ({ ... })),
  }));
  ```

- [ ] **Schritt 4: Commit**

  ```bash
  git add statusline-configurator.html
  git commit -m "feat(configurator): add mergeWithNext to line state, export and import"
  ```

---

## Task 5: Feature — PS1 Zeilen-Gruppen + Format-Lines-Aligned Refactoring

**Files:**
- Modify: `statusline.ps1` (neue Funktionen, Format-Lines-Aligned refactoren)
- Modify: `tests/statusline.Tests.ps1` (neue Tests, bestehende Tests anpassen)

- [ ] **Schritt 1: Bestehende Format-Lines-Aligned Tests anpassen**

  Die Tests `'pads shorter group to match longer group across lines'` und `'groups merged fields and aligns by group width'` testen Zeilen-übergreifendes Alignment. Mit dem neuen Opt-in-Verhalten müssen die Zeilen explizit per `mergeWithNext` verbunden werden.

  Suche in `tests/statusline.Tests.ps1` im `Describe 'Format-Lines-Aligned'`-Block den Test `'pads shorter group to match longer group across lines'`. Dort sind zwei Zeilen-PSCustomObjects definiert. Füge `mergeWithNext = $true` zur **ersten** Zeile hinzu:

  ```powershell
  It 'pads shorter group to match longer group across lines' {
      $lines = @(
          [PSCustomObject]@{ mergeWithNext = $true; fields = @(  # NEU: mergeWithNext
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
      ...  # Rest unverändert
  }
  ```

  Dasselbe für den Test `'groups merged fields and aligns by group width'`: erste Zeile bekommt `mergeWithNext = $true`.

  Und den Test `'pads correctly when groups contain ANSI color codes'`: erste Zeile bekommt `mergeWithNext = $true`.

- [ ] **Schritt 2: Neue Failing Tests für Build-LineGroups und Format-Line-Group schreiben**

  Am Ende von `tests/statusline.Tests.ps1` einfügen:

  ```powershell
  Describe 'Build-LineGroups' {
      It 'returns one group per line when no mergeWithNext set' {
          $lines = @(
              [PSCustomObject]@{ id = 'a' },
              [PSCustomObject]@{ id = 'b' }
          )
          $groups = Build-LineGroups $lines
          $groups.Count | Should -Be 2
          $groups[0].Count | Should -Be 1
          $groups[1].Count | Should -Be 1
      }

      It 'groups two lines when first has mergeWithNext' {
          $lines = @(
              [PSCustomObject]@{ id = 'a'; mergeWithNext = $true },
              [PSCustomObject]@{ id = 'b' }
          )
          $groups = Build-LineGroups $lines
          $groups.Count | Should -Be 1
          $groups[0].Count | Should -Be 2
      }

      It 'creates two groups from A+B and C' {
          $lines = @(
              [PSCustomObject]@{ id = 'a'; mergeWithNext = $true },
              [PSCustomObject]@{ id = 'b' },
              [PSCustomObject]@{ id = 'c' }
          )
          $groups = Build-LineGroups $lines
          $groups.Count | Should -Be 2
          $groups[0].Count | Should -Be 2
          $groups[1].Count | Should -Be 1
      }

      It 'handles empty array' {
          $groups = Build-LineGroups @()
          $groups.Count | Should -Be 0
      }
  }

  Describe 'Format-Line-Group single line' {
      It 'renders a single static field' {
          $lines = @([PSCustomObject]@{
              fields = @(
                  [PSCustomObject]@{ type = 'static'; text = 'hi'; fg = $null; bg = $null }
              )
          })
          $result = Format-Line-Group $lines ([PSCustomObject]@{})
          $result | Should -Be 'hi'
      }
  }
  ```

- [ ] **Schritt 3: Tests ausführen — FAIL für neue Tests erwartet**

  ```
  pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
  ```

  Erwartet: `Build-LineGroups`- und `Format-Line-Group`-Tests schlagen fehl. Die angepassten `Format-Lines-Aligned`-Tests können ebenfalls fehlschlagen (abhängig vom aktuellen Verhalten).

- [ ] **Schritt 4: Build-LineGroups und Format-Line-Group implementieren**

  In `statusline.ps1`, **direkt vor** der aktuellen `Format-Lines-Aligned`-Funktion einfügen:

  ```powershell
  <#
  .SYNOPSIS
      Groups line config objects into alignment groups based on mergeWithNext flags.
  .DESCRIPTION
      Lines with mergeWithNext=true are chained with the following line into one group.
      Only lines in the same group share column alignment.
  .PARAMETER Lines
      Array of line config PSCustomObjects.
  .OUTPUTS
      Array of arrays — each inner array is one line group.
  #>
  function Build-LineGroups {
      param([array]$Lines)
      if (-not $Lines -or $Lines.Count -eq 0) { return , @() }
      $groups  = [System.Collections.Generic.List[object]]::new()
      $current = [System.Collections.Generic.List[object]]::new()
      foreach ($line in $Lines) {
          $current.Add($line)
          if (-not $line.mergeWithNext) {
              $groups.Add($current.ToArray())
              $current = [System.Collections.Generic.List[object]]::new()
          }
      }
      if ($current.Count -gt 0) { $groups.Add($current.ToArray()) }
      return , $groups.ToArray()
  }

  <#
  .SYNOPSIS
      Renders a group of lines with two-pass column alignment.
  .DESCRIPTION
      Identical to the previous Format-Lines-Aligned logic: Pass 1 renders groups,
      Pass 2 measures max widths, Pass 3 pads and joins.
  .PARAMETER Lines
      Array of line config objects in one alignment group.
  .PARAMETER Data
      PSCustomObject parsed from Claude Code JSON input.
  .OUTPUTS
      Rendered string for all lines in this group, joined by newline.
  #>
  function Format-Line-Group {
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
      $maxWidths = [int[]]::new([math]::Max(1, $maxGroupCount))
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
          if (($renderedGroups | Where-Object { (Get-VisibleWidth $_) -gt 0 } | Measure-Object).Count -eq 0) { continue }
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

- [ ] **Schritt 5: Format-Lines-Aligned refaktorisieren**

  Die bestehende `Format-Lines-Aligned`-Funktion **vollständig ersetzen** durch:

  ```powershell
  <#
  .SYNOPSIS
      Renders all configured lines with column alignment via line groups.
  .DESCRIPTION
      Groups lines by their mergeWithNext flags (Build-LineGroups), then runs
      two-pass alignment for each group independently (Format-Line-Group).
      Lines without mergeWithNext form single-line groups (no cross-line alignment).
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
      if (-not $Lines -or $Lines.Count -eq 0) { return '' }

      $lineGroups = Build-LineGroups $Lines
      $parts = [System.Collections.Generic.List[string]]::new()
      foreach ($group in $lineGroups) {
          $result = Format-Line-Group $group $Data
          if ($result) { $parts.Add($result) }
      }
      return $parts -join "`n"
  }
  ```

- [ ] **Schritt 6: Tests ausführen — alle grün**

  ```
  pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
  ```

  Alle Tests müssen grün sein.

- [ ] **Schritt 7: Commit**

  ```bash
  git add statusline.ps1 tests/statusline.Tests.ps1
  git commit -m "feat(statusline): add Build-LineGroups and refactor Format-Lines-Aligned for opt-in line alignment"
  ```

---

## Task 6: Feature — JS Zeilen-Gruppen + renderPreview Refactoring

**Files:**
- Modify: `statusline-configurator.html` (buildLineGroups, renderLineGroup, renderPreview, renderLines, toggleLineMergeNext)

- [ ] **Schritt 1: buildLineGroups Hilfsfunktion einfügen**

  Direkt vor `buildGroups` (Zeile ~1412) einfügen:

  ```javascript
  /**
   * Groups lines into alignment groups based on line-level mergeWithNext flags.
   * Mirrors the PS1 Build-LineGroups logic.
   * @param {Array} lines - Array of line objects from state.
   * @returns {Array<Array>} Array of line groups.
   */
  function buildLineGroups(lines) {
    const groups = [];
    let current = [];
    for (const line of lines) {
      current.push(line);
      if (!line.mergeWithNext) {
        groups.push(current);
        current = [];
      }
    }
    if (current.length > 0) groups.push(current);
    return groups;
  }
  ```

- [ ] **Schritt 2: renderLineGroup Hilfsfunktion — Logik aus renderPreview extrahieren**

  Die aktuelle `renderPreview`-Funktion enthält den Three-Pass Algorithmus. Extrahiere ihn in eine neue Funktion `renderLineGroup(lines)`:

  ```javascript
  /**
   * Renders a group of lines with two-pass column alignment.
   * @param {Array} lines - Array of line objects (one alignment group).
   * @returns {Array<string>} Array of rendered HTML strings, one per non-empty line.
   */
  function renderLineGroup(lines) {
    // Pass 1: render all field groups for all lines in this group
    const allLineGroups = lines.map(line => {
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
    return allLineGroups.map((lineGroups, lineIdx) => {
      if (lineGroups.length === 0) return null;
      const html = lineGroups.map((groupHtml, g) => {
        const isLast  = g === lineGroups.length - 1;
        const padding = isLast ? 0 : maxWidths[g] - getVisibleWidth(groupHtml);
        if (padding > 0) {
          return groupHtml + `<span style="white-space:pre">${' '.repeat(padding)}</span>`;
        }
        return groupHtml;
      }).join('');
      return html || null;
    }).filter(Boolean);
  }
  ```

- [ ] **Schritt 3: renderPreview refaktorisieren**

  Die aktuelle `renderPreview`-Funktion vollständig ersetzen:

  ```javascript
  function renderPreview() {
    const out = document.getElementById('preview-output');
    if (state.lines.length === 0) {
      out.innerHTML = '<span style="color:var(--color-text-muted);">Keine Zeilen konfiguriert.</span>';
      return;
    }

    let renderedLines;

    if (!state.columnAlignmentEnabled) {
      // Alignment disabled: render each line independently without padding
      renderedLines = state.lines.map(line => {
        if (line.fields.length === 0) {
          return '<span style="color:var(--color-text-muted);">(leere Zeile)</span>';
        }
        return line.fields.map(f => {
          const previewOverride = (_editDraft && _editDraft.id === f.id)
            ? (_editDraft.previewValue ?? f.previewValue ?? null)
            : (f.previewValue ?? null);
          const fieldThemeId  = f.themeId ?? (_themePreviewId ?? state.activeTheme);
          const fieldThemeObj = fieldThemeId ? state.themes.find(t => t.id === fieldThemeId) ?? null : null;
          return renderFieldHtml(f, SAMPLE_DATA, fieldThemeObj, previewOverride);
        }).join('');
      });
    } else {
      // Alignment enabled: group lines, run two-pass alignment per group
      const lineGroups = buildLineGroups(state.lines);
      renderedLines = lineGroups.flatMap(group => {
        const groupResults = renderLineGroup(group);
        return groupResults.length > 0
          ? groupResults
          : ['<span style="color:var(--color-text-muted);">(leere Zeile)</span>'];
      });
    }

    out.innerHTML = renderedLines.join('<br>');
  }
  ```

- [ ] **Schritt 4: toggleLineMergeNext Funktion hinzufügen**

  Direkt nach `toggleMergeNext` einfügen:

  ```javascript
  /**
   * Toggles the mergeWithNext flag on a line and re-renders.
   * @param {string} lineId - The ID of the line to toggle.
   */
  function toggleLineMergeNext(lineId) {
    const line = state.lines.find(l => l.id === lineId);
    if (!line) return;
    line.mergeWithNext = !line.mergeWithNext;
    render();
  }
  ```

- [ ] **Schritt 5: Merge-Button in renderLines hinzufügen**

  In `renderLines()`, im Template für den Zeilen-Header-Bereich, den Merge-Button ergänzen. Suche:

  ```javascript
  <button class="btn btn-danger" style="padding:2px 8px;font-size:11px;" onclick="removeLine('${line.id}')">✕ Entfernen</button>
  ```

  Ersetze durch:

  ```javascript
  ${lineIndex < state.lines.length - 1 ? `
    <button class="btn-icon" title="Mit nächster Zeile für Tab-Ausrichtung gruppieren"
            onclick="toggleLineMergeNext('${line.id}')"
            style="color:${line.mergeWithNext ? 'var(--color-accent)' : 'var(--color-text-muted)'};font-size:13px;">
      ${line.mergeWithNext ? '→' : '↝'}
    </button>
  ` : ''}
  <button class="btn btn-danger" style="padding:2px 8px;font-size:11px;" onclick="removeLine('${line.id}')">✕ Entfernen</button>
  ```

  Der Button erscheint nur für Zeilen, die **nicht** die letzte Zeile sind.

- [ ] **Schritt 6: Commit**

  ```bash
  git add statusline-configurator.html
  git commit -m "feat(configurator): add line grouping for column alignment and refactor renderPreview"
  ```

---

## Gesamttest

- [ ] **Alle PS1 Tests grün**

  ```
  pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
  ```

- [ ] **Branch-Log prüfen**

  ```bash
  git log --oneline -8
  ```
