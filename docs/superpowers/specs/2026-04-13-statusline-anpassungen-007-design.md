# Design: Statusline Anpassungen 007

**Date:** 2026-04-13
**Branch:** feature/statusline-007-new-fields-defaults

---

## Overview

Drei unabhängige Verbesserungen an `statusline.ps1` und `statusline-configurator.html`:

1. **Neue Payload-Felder** — Drei neue Claude Code Payload-Felder (`workspace.added_dirs`, `workspace.git_worktree`, `session_name`) werden in AVAILABLE_FIELDS, FIELD_TYPE_DEFAULTS, SAMPLE_DATA und knownKeys aufgenommen.
2. **New-Fields-Logging** — Der `new_fields_indicator` schreibt unbekannte Keys in eine Logdatei; das Logging ist über den Konfigurator an- und abschaltbar.
3. **Berechnetes Feld: Cache-Effizienz** — `context_window.cache_efficiency` wird in der Enrichment-Phase berechnet und als normales Feld im Konfigurator angeboten.
4. **Null/Leer-Defaults** — Per-dataType-Standardwerte wenn ein Feldwert fehlt; optionaler `placeholder`-Override pro Feld im Konfigurator.

---

## 1. Neue Payload-Felder

### Identifizierung

Beim User wurden im Terminal "● 3 neue Felder" angezeigt. Die drei Felder wurden über die offizielle Anthropic-Dokumentation (https://code.claude.com/docs/en/statusline) identifiziert:

| Key | Gruppe | Beschreibung |
|---|---|---|
| `workspace.added_dirs` | Workspace | Zusätzliche Verzeichnisse via `/add-dir`. Immer vorhanden als Array (ggf. leer). |
| `workspace.git_worktree` | Workspace | Git-Worktree-Name wenn CWD in einem linked worktree liegt. Fehlt im Hauptarbeitsbaum. |
| `session_name` | Session | Custom Session-Name via `--name` oder `/rename`. Fehlt wenn kein Name gesetzt. |

### Darstellung

**`workspace.added_dirs`** ist ein Array. Anzeige: Anzahl der Einträge als `number`-Feld.
- Wert 0 → wird per Null/Leer-Default als `0` angezeigt
- Format-Logik in PS: `$value = $value.Count` (Array → Anzahl)
- Special handling nötig: Arrays werden von `Get-AllKeys` als Leaf behandelt, aber `Get-NestedValue` gibt das Array-Objekt zurück. Format-Field muss für `workspace.added_dirs` die `.Count`-Eigenschaft lesen.

**`workspace.git_worktree`** — string, `dataType: 'string'`

**`session_name`** — string, `dataType: 'string'`

### Änderungen Konfigurator

`AVAILABLE_FIELDS`:
```javascript
// Workspace-Gruppe — neue Einträge:
{ key: 'workspace.added_dirs',    label: 'Added Dirs Count' },
{ key: 'workspace.git_worktree',  label: 'Git Worktree' },

// Session-Gruppe — neuer Eintrag:
{ key: 'session_name',            label: 'Session Name' },
```

`FIELD_TYPE_DEFAULTS`:
```javascript
'workspace.added_dirs':   { dataType: 'number', format: 'raw' },
'workspace.git_worktree': { dataType: 'string' },
'session_name':           { dataType: 'string' },
```

`SAMPLE_DATA`:
```javascript
workspace: { ..., added_dirs: ['/home/user/extra'], git_worktree: 'my-feature' },
session_name: 'my-session',
```

`knownKeys`: Automatisch aktualisiert bei nächstem Export aus AVAILABLE_FIELDS.

### Änderungen PS-Script

In `Format-Field` (case `'field'`): Vor dem Null-Check bei `workspace.added_dirs` das Array in seine Count-Zahl umwandeln:

```powershell
# Special case: added_dirs is an array — display count
if ($Field.key -eq 'workspace.added_dirs' -and $null -ne $value) {
    if ($value -is [System.Array] -or $value -is [System.Collections.IEnumerable]) {
        $value = @($value).Count
    }
}
```

---

## 2. New-Fields-Logging

### Verhalten

Der `new_fields_indicator` erkennt weiterhin unbekannte Felder und zeigt "● N neue Felder". Zusätzlich: wenn Logging aktiviert ist, wird eine Zeile in `statusline-new-fields.log` (neben `statusline.ps1`) geschrieben.

**Format der Logzeile:**
```
[2026-04-13 22:28:00] workspace.added_dirs, workspace.git_worktree, session_name
```

### Konfiguration

Neues Config-Feld `logNewFields` (boolean, default: `false`):
```json
{
  "logNewFields": true,
  "lines": [...]
}
```

### Konfigurator-UI

Neuer Toggle in der **globalen Einstellungssektion** (oder als neuer Tab "Einstellungen"):
- Label: "Neue Felder protokollieren"
- Beschreibung: "Unbekannte Payload-Keys in statusline-new-fields.log schreiben"
- Typ: Checkbox / Toggle
- Wert wird im Config-JSON als `logNewFields: true/false` gespeichert und exportiert

### PS-Implementierung

In `Format-Field` (case `'new_fields_indicator'`):
```powershell
'new_fields_indicator' {
    if (-not $script:KnownKeys) { return '' }
    $allKeys = Get-AllKeys $Data ''
    $newKeys = $allKeys | Where-Object { $script:KnownKeys -notcontains $_ }
    $count   = ($newKeys | Measure-Object).Count
    if ($count -eq 0) { return '' }

    # Logging wenn aktiviert
    if ($script:LogNewFields) {
        $timestamp  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $keyList    = $newKeys -join ', '
        $logPath    = Join-Path $PSScriptRoot 'statusline-new-fields.log'
        try {
            "[$timestamp] $keyList" | Add-Content -Path $logPath -Encoding UTF8
        } catch {
            # Silently ignore log write failure
        }
    }

    return "${fgAnsi}${bgAnsi}● ${count} neue Felder${resetAnsi}"
}
```

`$script:LogNewFields` wird in `Invoke-Main` gesetzt:
```powershell
$script:LogNewFields = [bool]($config.logNewFields)
```

`.gitignore`: `statusline-new-fields.log` hinzufügen.

---

## 3. Berechnetes Feld: Cache-Effizienz

### Definition

**`context_window.cache_efficiency`** = `cache_read_input_tokens / total_input_tokens × 100`

- Gibt an welcher Prozentsatz der Input-Tokens aus dem Cache bedient wurde
- 0% = keine Cache-Nutzung, 100% = alle Inputs aus Cache
- Gerundet auf 1 Dezimalstelle
- Nur berechnet wenn `total_input_tokens > 0`, sonst nicht gesetzt (vermeidet Division durch 0)

### PS-Enrichment

Neue Funktion `Compute-DerivedFields` (nach dem rate_limits-Enrichment in `Invoke-Main`):

```powershell
function Compute-DerivedFields {
    param([PSCustomObject]$Data)

    # cache_efficiency = cache_read_input_tokens / total_input_tokens * 100
    $cacheRead   = Get-NestedValue $Data 'context_window.current_usage.cache_read_input_tokens'
    $totalInput  = Get-NestedValue $Data 'context_window.total_input_tokens'
    if ($null -ne $cacheRead -and $null -ne $totalInput -and [double]$totalInput -gt 0) {
        $efficiency = [Math]::Round([double]$cacheRead / [double]$totalInput * 100, 1)
        $Data.context_window | Add-Member -NotePropertyName 'cache_efficiency' -NotePropertyValue $efficiency -Force
    }
}
```

Aufruf in `Invoke-Main` nach rate_limits-Enrichment:
```powershell
Compute-DerivedFields -Data $data
```

### Konfigurator

`AVAILABLE_FIELDS` (Context Window Gruppe):
```javascript
{ key: 'context_window.cache_efficiency', label: 'Cache Efficiency (%)' },
```

`FIELD_TYPE_DEFAULTS`:
```javascript
'context_window.cache_efficiency': { dataType: 'number', format: 'raw' },
```

`SAMPLE_DATA`:
```javascript
context_window: { ..., cache_efficiency: 73.4 },
```

`knownKeys`: Automatisch durch AVAILABLE_FIELDS.

---

## 4. Null/Leer-Defaults

### Konzept

Zwei Ebenen:

1. **Per-dataType-Default** (in PS-Script): greift wenn Wert null/leer ist und kein `placeholder` gesetzt
2. **Per-field `placeholder`** (im Config/Konfigurator): überschreibt den dataType-Default

### Per-dataType-Defaults

| dataType | Default wenn null/leer |
|---|---|
| `string` | `--` |
| `number` | `0` |
| `currency` | `$0.00` |
| `duration_ms` | `--` |
| `unix_timestamp` | `--` |

Kein Default für `progressbar` (progressbar zeigt bei 0% immer einen Balken → kein Leer-Fall).

**Ausnahme:** `worktree.branch` behält seine bestehende Hardcoding (`none`) als Rückfallebene — aber wenn ein `placeholder` auf dem Feld gesetzt ist, hat dieser Vorrang.

### Per-field `placeholder`

Optionales Feld in jedem Field-Config-Objekt:
```json
{
  "type": "field",
  "key": "agent.name",
  "dataType": "string",
  "placeholder": ""
}
```

- `placeholder` nicht gesetzt (oder `undefined`): → per-dataType-Default greift
- `placeholder: ""` (leerer String): → Original-Verhalten (leer, Feld unsichtbar)
- `placeholder: "(kein Agent)"`: → dieser Text wird angezeigt wenn Wert null/leer

### PS-Implementierung

In `Format-Field` (case `'field'`), ersetze den bestehenden Null-Check:

```powershell
if ($null -eq $value -or "$value" -eq '') {
    # Priority: field.placeholder > dataType default > '' (hide)
    $placeholder = $null
    if ($Field.PSObject.Properties['placeholder']) {
        # Explicitly set placeholder (even empty string)
        $placeholder = $Field.placeholder
    } elseif ($Field.key -eq 'worktree.branch') {
        $placeholder = 'none'
    } else {
        # Per-dataType defaults
        $placeholder = switch ($Field.dataType) {
            'currency'      { '$0.00' }
            'number'        { '0' }
            'string'        { '--' }
            'duration_ms'   { '--' }
            'unix_timestamp'{ '--' }
            default         { $null }
        }
    }
    if ($null -eq $placeholder -or $placeholder -eq '') {
        return ''
    }
    return "${fgAnsi}${bgAnsi}${placeholder}${resetAnsi}"
}
```

### Konfigurator-Edit-Dialog

Neues `placeholder`-Textfeld im Edit-Dialog (Tab "Allgemein" oder "Erweitert"):
- Label: "Platzhalter (wenn leer)"
- Hint: "Leer lassen für Standardwert je Datentyp. Leerzeichen erzwingen für kein Anzeige."
- Input: text, `oninput` → `_editDraft.placeholder = ...`
- Beim Speichern: nur exportieren wenn explizit gesetzt (`placeholder !== undefined`)

Export in `buildExportJson`:
```javascript
if (f.placeholder !== undefined && f.placeholder !== null) {
    base.placeholder = f.placeholder;
}
```

---

## 5. Betroffene Dateien

| Datei | Änderungen |
|---|---|
| `statusline-configurator.html` | AVAILABLE_FIELDS (3 neue Felder + cache_efficiency), FIELD_TYPE_DEFAULTS, SAMPLE_DATA, Edit-Dialog (placeholder-Input), globaler logNewFields-Toggle, buildExportJson |
| `statusline.ps1` | `Format-Field` (added_dirs special case, new_fields_indicator Logging, placeholder-Logik), `Compute-DerivedFields`, `Invoke-Main` (LogNewFields + Compute-DerivedFields) |
| `tests/statusline.Tests.ps1` | Tests für `Compute-DerivedFields`, new_fields_indicator Logging, placeholder-Logik, added_dirs Count |
| `.gitignore` | `statusline-new-fields.log` |

---

## 6. Feature-Branch

Branch: `feature/statusline-007-new-fields-defaults`

Alle Änderungen auf diesem Branch entwickeln, danach optional merge in `master`.

---

## 7. Tests

### `Compute-DerivedFields` (3 Tests)
- Berechnet `cache_efficiency` korrekt bei normalen Werten
- Setzt `cache_efficiency` nicht wenn `total_input_tokens` 0 oder null
- Rundet auf 1 Dezimalstelle

### `new_fields_indicator` Logging (2 Tests)
- Schreibt Logzeile wenn `$script:LogNewFields = $true` und unbekannte Keys vorhanden
- Schreibt keine Logzeile wenn `$script:LogNewFields = $false`

### Placeholder-Logik (4 Tests)
- Zeigt per-dataType-Default bei null-Wert ohne `placeholder`-Property
- Zeigt leeren String (kein Output) wenn `placeholder = ''` gesetzt
- Zeigt custom placeholder wenn `placeholder = 'n/a'` gesetzt
- `worktree.branch` zeigt `none` wenn kein `placeholder` gesetzt

### `workspace.added_dirs` Count (2 Tests)
- Gibt Anzahl zurück für gefülltes Array
- Gibt `0` zurück für leeres Array (per-dataType-Default `number` → '0')
