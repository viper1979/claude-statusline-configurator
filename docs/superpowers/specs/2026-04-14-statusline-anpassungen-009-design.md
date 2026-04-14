# Design Spec — Statusline Anpassungen 009

**Datum:** 2026-04-14  
**Branch:** feature/statusline-007-new-fields-defaults  
**Status:** Draft

---

## Überblick

Vier Änderungen:

1. **Bug: Braille 100%** — letztes Zeichen zeigt `⣹` statt `⣿`
2. **Bug: Drag&Drop bricht nach Merge-Toggle** — `toggleMergeNext` fehlt `initSortable()`
3. **Feature: Zeilen-Gruppen** — `mergeWithNext` auf Zeilen (analog zu Feldern)
4. **Feature: Spaltenausrichtung An/Abschalten** — globaler Toggle `columnAlignmentEnabled`

---

## 1. Bug: Braille 100%

### Ursache

In `statusline.ps1`, Funktion `Format-Progressbar`, Zeilen 204–208:

```powershell
# Aktuell (falsch):
if     ($i -eq 9)           { $inner += $bEdgeR }  # Priority zu hoch!
elseif ($i -lt $filled)     { $inner += $bFill  }
elseif ($i -eq 0)           { $inner += $bEdgeL }
else                        { $inner += $bEmpty }
```

Bei 100% (`$filled = 10`) gilt `$i -eq 9` für die letzte Position — sie bekommt `⣹` statt `⣿`.

### Fix

```powershell
# Nachher (korrekt):
if     ($i -lt $filled)     { $inner += $bFill  }
elseif ($i -eq 9)           { $inner += $bEdgeR }
elseif ($i -eq 0)           { $inner += $bEdgeL }
else                        { $inner += $bEmpty }
```

Verhalten bei allen Werten:
- 0%: pos 0 → `⣏`, pos 1–8 → `⣉`, pos 9 → `⣹` ✓
- 50%: pos 0–4 → `⣿`, pos 5–8 → `⣉`, pos 9 → `⣹` ✓
- 100%: pos 0–9 → `⣿` (alle voll) ✓

---

## 2. Bug: Drag&Drop bricht nach Merge-Toggle

### Ursache

`toggleMergeNext` ruft `renderLines()` direkt auf, ohne danach `initSortable()` aufzurufen. `renderLines()` ersetzt den kompletten DOM-Inhalt des Containers — die Sortable-Instanzen auf den `.line-drop-zone`-Elementen werden dabei zerstört und nicht neu erstellt.

### Fix

`toggleMergeNext` soll `render()` statt `renderLines()` + `renderPreview()` + `updateExportTextarea()` aufrufen. `render()` ruft alle drei Funktionen plus `initSortable()` auf.

```javascript
function toggleMergeNext(lineId, fieldId) {
  // ... state update ...
  render();  // war: renderLines(); renderPreview(); updateExportTextarea();
}
```

---

## 3. Feature: Zeilen-Gruppen (`mergeWithNext` auf Zeilen)

### 3.1 Konzept

Analog zur Feld-Gruppierung erhalten Zeilen ein `mergeWithNext`-Flag. Nur Zeilen in derselben Zeilengruppe werden gemeinsam aligniert.

**Standardverhalten (Opt-in):** Ohne `mergeWithNext` ist jede Zeile eine eigene Gruppe → keine zeilen-übergreifende Ausrichtung.

**Gruppierungsregel:** Identisch zu Feldern — sequentielle Ketten.

```
Zeile 1 (mergeWithNext: true)  ┐
Zeile 2 (mergeWithNext: true)  ├── Gruppe A → gemeinsam aligniert
Zeile 3 (mergeWithNext: false) ┘
Zeile 4 (mergeWithNext: false)    ── Gruppe B → unabhängig
```

### 3.2 State & Config

Jedes Zeilen-Objekt in `state.lines` erhält `mergeWithNext: false` als Default.

**Export** (`buildExportJson`):
```javascript
// Auf Line-Ebene (außerhalb von fields):
if (line.mergeWithNext) lineObj.mergeWithNext = true;
```

**Import** (`loadConfig`):
```javascript
state.lines = json.lines.map(line => ({
  id: generateId(),
  mergeWithNext: line.mergeWithNext === true,  // NEU
  fields: [...]
}));
```

### 3.3 UI — Merge-Handle auf Zeilen-Header

Jede Zeile bekommt in ihrer Header-Row einen Merge-Button (nach "Zeile N", vor "✕ Entfernen"):

```
[⠿] Zeile 1  [↝]  [✕ Entfernen]
[drop zone mit chips]

[⠿] Zeile 2  [→]  [✕ Entfernen]   ← aktiv: mit Zeile 3 verbunden
[drop zone mit chips]

[⠿] Zeile 3  [↝]  [✕ Entfernen]
[drop zone mit chips]
```

- `↝` (grau): kein Merge
- `→` (Akzentfarbe): Merge mit nächster Zeile aktiv

Funktion `toggleLineMergeNext(lineId)` — setzt `line.mergeWithNext = !line.mergeWithNext`, ruft `render()` auf.

Der Button auf der **letzten Zeile** ist ausgeblendet oder deaktiviert (keine nachfolgende Zeile vorhanden).

### 3.4 PS1 — `Build-LineGroups`

Neue Funktion in `statusline.ps1` (vor `Format-Lines-Aligned`):

```powershell
<#
.SYNOPSIS
    Groups line config objects into alignment groups based on mergeWithNext flags.
.PARAMETER Lines
    Array of line config PSCustomObjects.
.OUTPUTS
    Array of arrays — each inner array is one group of lines to align together.
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
```

### 3.5 PS1 — `Format-Lines-Aligned` refaktorisieren

Die bestehende Funktion wird in zwei aufgeteilt:

**`Format-Line-Group` (neue interne Funktion):**  
Enthält die aktuelle Logik von `Format-Lines-Aligned` (Three-Pass Alignment für eine Gruppe von Zeilen). Parameter: `[array]$Lines`, `[PSCustomObject]$Data`.

**`Format-Lines-Aligned` (öffentliche Funktion, refaktorisiert):**  
```powershell
function Format-Lines-Aligned {
    param([array]$Lines, [PSCustomObject]$Data)
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

### 3.6 Bestehende PS1-Tests

Die Tests `'pads shorter group to match longer group across lines'` und `'groups merged fields and aligns by group width'` testen Zeilen-übergreifendes Alignment. Sie müssen aktualisiert werden: die Test-Zeilen bekommen `mergeWithNext = $true` (außer der letzten), damit sie eine Gruppe bilden.

### 3.7 JS — `renderPreview` refaktorisieren

Analog zu PS1:

**`renderLineGroup(lineGroup)` (neue interne Hilfsfunktion):**  
Enthält die aktuelle Three-Pass-Logik von `renderPreview` für eine Gruppe von Zeilen.

**`buildLineGroups(lines)` (neue Hilfsfunktion):**  
```javascript
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

**`renderPreview` refaktorisiert:**  
Gruppiert Zeilen via `buildLineGroups`, rendert jede Gruppe separat mit `renderLineGroup`.

---

## 4. Feature: Spaltenausrichtung An/Abschalten

### 4.1 Globales Flag

`state.columnAlignmentEnabled = true` (Default).

Wenn `false`:
- `renderPreview` rendert jede Zeile als einfache Feldreihe ohne Padding
- PS1 `Invoke-Main` nutzt `Format-Line` statt `Format-Lines-Aligned`
- `mergeWithNext` auf Feldern und Zeilen hat keinen Einfluss auf die Darstellung

### 4.2 UI

Oberhalb der `lines-container` einen Toggle-Bereich einfügen:

```
[☑] Spaltenausrichtung aktivieren
```

Kleines Checkbox-Element, direkt in der Lines-Tab-Sektion.

### 4.3 Config Export/Import

**Export:**
```javascript
if (!state.columnAlignmentEnabled) config.columnAlignmentEnabled = false;
// (true ist Standard — wird nicht serialisiert)
```

**Import:**
```javascript
state.columnAlignmentEnabled = json.columnAlignmentEnabled !== false;
```

### 4.4 PS1

In `Invoke-Main` (Zeile 871):
```powershell
if ($config.columnAlignmentEnabled -ne $false) {
    return Format-Lines-Aligned $config.lines $data
} else {
    $output = $config.lines | ForEach-Object { Format-Line $_ $data } | Where-Object { $_ -ne '' }
    return $output -join "`n"
}
```

---

## Betroffene Dateien

| Datei | Änderungen |
|---|---|
| `statusline.ps1` | Bug 1 (Braille), `Build-LineGroups`, `Format-Line-Group`, `Format-Lines-Aligned` refactor, `Invoke-Main` toggle |
| `statusline-configurator.html` | Bug 2 (DnD), Feature 3 (Zeilen-UI, buildLineGroups, renderPreview refactor, export/import), Feature 4 (Toggle, export/import) |
| `tests/statusline.Tests.ps1` | Bug 1 Tests, neue Tests für `Build-LineGroups`, `Format-Line-Group`, bestehende `Format-Lines-Aligned` Tests aktualisieren |
