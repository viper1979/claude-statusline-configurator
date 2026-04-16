# Statusline Anpassungen 011 A+B — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tests nach Rounding-Bugfix prüfen, `duration`-Typ entfernen, `Get-AllKeys` null-Fix, Progressbar-Editor-Bug (Tab-Guard + Boolean-Normalisierung).

**Architecture:** Drei unabhängige Bereiche: (1) PowerShell-Skript `statusline.ps1` + zugehörige Tests, (2) Konfigurator `statusline-configurator.html` (JS), (3) Progressbar-Editor-Fixes im Konfigurator. Keine neuen Dateien. Alle Änderungen sind rückwärtskompatibel.

**Tech Stack:** PowerShell 7, Pester (PS-Tests), Vanilla JS (Konfigurator)

**Spec:** `docs/superpowers/specs/2026-04-16-statusline-anpassungen-011-ab-design.md`

---

## Datei-Übersicht

| Datei | Änderungen |
|-------|------------|
| `statusline.ps1` | `Get-AllKeys` null-Fix, `duration`-Case entfernen |
| `tests/statusline.Tests.ps1` | `duration`-Tests entfernen, ggf. fehlschlagende Tests anpassen |
| `statusline-configurator.html` | `duration` aus `DATATYPE_FORMATS`, Tab-Guard, Boolean-Normalisierung |

---

## Task 1: Tests ausführen und Status feststellen

**Files:**
- Run: `tests/statusline.Tests.ps1`
- Run: `tests/request-usage.Tests.ps1`

- [ ] **Step 1: Pester-Tests ausführen**

```powershell
cd D:\Development\ccstatusline
Invoke-Pester -Path tests\ -Output Detailed
```

Expected: Ausgabe zeigt PASS/FAIL pro Test. Notiere alle fehlschlagenden Tests.

- [ ] **Step 2: Fehlschlagende Tests analysieren**

Falls Tests fehlschlagen: Prüfe ob die Erwartung nach dem Rounding-Fix `f431c5e` veraltet ist.
Das Fix änderte `[int][math]::Round($response.*.utilization * 100)` — prüfe ob Testdaten
Grenzfälle (z.B. 0.425 → 42 vs 43) betreffen.

Falls alle Tests grün: Task abschließen, kein Commit nötig.

- [ ] **Step 3: Fehlschlagende Tests anpassen (nur bei Bedarf)**

Beispiel: Falls ein Test `used_percentage | Should -Be 43` erwartet aber der Fix jetzt 42 liefert,
ändere die Erwartung auf den korrekten Wert:

```powershell
# In tests/request-usage.Tests.ps1 — Beispiel, nur wenn tatsächlich fehlschlagend:
$cache.rate_limits.five_hour.used_percentage | Should -Be 42  # angepasster Wert
```

- [ ] **Step 4: Tests erneut ausführen und bestätigen**

```powershell
Invoke-Pester -Path tests\ -Output Detailed
```

Expected: Alle Tests PASS.

- [ ] **Step 5: Commit (nur bei Änderungen)**

```bash
git add tests/statusline.Tests.ps1 tests/request-usage.Tests.ps1
git commit -m "test: update expectations after rounding fix f431c5e"
```

---

## Task 2: `duration`-Datentyp entfernen

Der Typ `duration` (direkte Sekunden-Eingabe) kommt in keinem echten Payload-Feld vor.
Er wird aus PS-Skript, Tests und Konfigurator entfernt.

**Files:**
- Modify: `statusline.ps1:292,306-308`
- Modify: `tests/statusline.Tests.ps1:447-495`
- Modify: `statusline-configurator.html:2037`

- [ ] **Step 1: `duration`-Tests entfernen**

In `tests/statusline.Tests.ps1` die folgenden 5 It-Blöcke komplett entfernen
(Zeilen 447–466 und 492–495):

```powershell
# ENTFERNEN — diese 5 Tests löschen:

It 'formats duration 5000 seconds as hours format: 1h 23m' {
    Format-FieldValue -Value 5000 -DataType 'duration' -Format 'hours' -FormatOptions $null |
        Should -Be '1h 23m'
}

It 'formats duration 90061 seconds as short format with days: 1d 1h 1m' {
    Format-FieldValue -Value 90061 -DataType 'duration' -Format 'short' -FormatOptions $null |
        Should -Be '1d 1h 1m'
}

It 'formats duration 90061 seconds as long format with days: 1d 1hr 1min' {
    Format-FieldValue -Value 90061 -DataType 'duration' -Format 'long' -FormatOptions $null |
        Should -Be '1d 1hr 1min'
}

It 'formats duration under 1 day as short without day prefix' {
    # 3661 seconds = 1h 1m
    Format-FieldValue -Value 3661 -DataType 'duration' -Format 'short' -FormatOptions $null |
        Should -Be '1h 1m'
}

It 'returns 0h 0m for null duration value' {
    Format-FieldValue -Value $null -DataType 'duration' -Format 'short' -FormatOptions $null |
        Should -Be '0h 0m'
}
```

- [ ] **Step 2: Verify — Tests laufen noch (ohne `duration`)**

```powershell
Invoke-Pester -Path tests\statusline.Tests.ps1 -Output Detailed
```

Expected: Alle verbleibenden Tests PASS. Keine `duration`-Tests mehr in der Ausgabe.

- [ ] **Step 3: `duration`-Case aus `statusline.ps1` entfernen**

In `statusline.ps1` zwei Stellen ändern:

**Stelle 1 — Null-Fallback (ca. Zeile 292):**

```powershell
# Vorher:
{ $_ -in 'number','currency','duration','duration_ms' } { $Value = 0 }

# Nachher:
{ $_ -in 'number','currency','duration_ms' } { $Value = 0 }
```

**Stelle 2 — Switch-Case (ca. Zeilen 306–308) komplett entfernen:**

```powershell
# ENTFERNEN — diesen Case löschen:
'duration' {
    return Format-Duration -TotalSeconds ([long][double]$Value) -Format $Format
}
```

- [ ] **Step 4: Tests erneut ausführen**

```powershell
Invoke-Pester -Path tests\statusline.Tests.ps1 -Output Detailed
```

Expected: Alle Tests PASS.

- [ ] **Step 5: `duration` aus Konfigurator-Dropdown entfernen**

In `statusline-configurator.html` in `DATATYPE_FORMATS` (ca. Zeile 2037) die `duration`-Zeile entfernen:

```javascript
// Vorher:
const DATATYPE_FORMATS = {
  string:         [],
  currency:       [],
  bool:           [['checkmark','✓/✗'],['custom','Benutzerdefiniert']],
  number:         [['raw','Rohwert (12345678)'],['auto','Auto (456 / 33k / 939m / 12b)']],
  unix_timestamp: [['hours','Stunden (75h 32m)'],['short','Kurz (1d 4h 32m)'],['long','Lang (1d 4hr 32min)'],['raw','Rohwert']],
  duration:       [['hours','Stunden (75h 32m)'],['short','Kurz (1d 4h 32m)'],['long','Lang (1d 4hr 32min)']],
  duration_ms:    [['hours','Stunden (75h 32m)'],['short','Kurz (1d 4h 32m)'],['long','Lang (1d 4hr 32min)']],
};

// Nachher:
const DATATYPE_FORMATS = {
  string:         [],
  currency:       [],
  bool:           [['checkmark','✓/✗'],['custom','Benutzerdefiniert']],
  number:         [['raw','Rohwert (12345678)'],['auto','Auto (456 / 33k / 939m / 12b)']],
  unix_timestamp: [['hours','Stunden (75h 32m)'],['short','Kurz (1d 4h 32m)'],['long','Lang (1d 4hr 32min)'],['raw','Rohwert']],
  duration_ms:    [['hours','Stunden (75h 32m)'],['short','Kurz (1d 4h 32m)'],['long','Lang (1d 4hr 32min)']],
};
```

- [ ] **Step 6: Commit**

```bash
git add statusline.ps1 tests/statusline.Tests.ps1 statusline-configurator.html
git commit -m "refactor: remove unused duration data type from PS script and configurator"
```

---

## Task 3: `Get-AllKeys` — Null-Werte als Leaf überspringen

**Problem:** `context_window.current_usage` ist manchmal `null` im Payload (keine Cache-Daten).
`Get-AllKeys` fügt dann `"context_window.current_usage"` als Leaf-Key hinzu. Da nur die
Kind-Pfade (z.B. `context_window.current_usage.input_tokens`) in `knownKeys` stehen,
erscheint der Eltern-Pfad fälschlicherweise als "neues Feld".

**Files:**
- Modify: `statusline.ps1:43-58` (`Get-AllKeys`)
- Modify: `tests/statusline.Tests.ps1` (neuer Test)

- [ ] **Step 1: Failing-Test schreiben**

In `tests/statusline.Tests.ps1` im Describe-Block `Get-AllKeys` (falls vorhanden, sonst neuen
Describe-Block anlegen) einen neuen Test ergänzen:

```powershell
Describe 'Get-AllKeys' {
    # ... bestehende Tests ...

    It 'skips null leaf values' {
        $data = [PSCustomObject]@{
            context_window = [PSCustomObject]@{
                used_percentage = 42
                current_usage   = $null
            }
        }
        $keys = Get-AllKeys $data ''
        $keys | Should -Contain 'context_window.used_percentage'
        $keys | Should -Not -Contain 'context_window.current_usage'
    }
}
```

- [ ] **Step 2: Test ausführen — muss FAIL sein**

```powershell
Invoke-Pester -Path tests\statusline.Tests.ps1 -Output Detailed
```

Expected: FAIL — `'context_window.current_usage'` wird aktuell noch als Key zurückgegeben.

- [ ] **Step 3: Fix in `statusline.ps1` — `Get-AllKeys`**

In `statusline.ps1` die `else`-Clause von `Get-AllKeys` (ca. Zeile 52–55) anpassen:

```powershell
# Vorher:
} else {
    # Leaf value (string, number, bool, array, null) — add directly
    $result += $key
}

# Nachher:
} elseif ($null -ne $_.Value) {
    # Leaf value (string, number, bool, array) — add directly; skip null (container was absent)
    $result += $key
}
```

- [ ] **Step 4: Test ausführen — muss PASS sein**

```powershell
Invoke-Pester -Path tests\statusline.Tests.ps1 -Output Detailed
```

Expected: Alle Tests PASS inkl. neuem `skips null leaf values`.

- [ ] **Step 5: Commit**

```bash
git add statusline.ps1 tests/statusline.Tests.ps1
git commit -m "fix(statusline): skip null leaf values in Get-AllKeys to prevent false new-field detections"
```

---

## Task 4: Progressbar — Boolean-Normalisierung (`loadConfig` + `buildExportJson`)

Schutzmaßnahme damit `barBrackets` immer als echter JS-Boolean in State und Export landet.

**Files:**
- Modify: `statusline-configurator.html:1712-1716` (`loadConfig`)
- Modify: `statusline-configurator.html:1598` (`buildExportJson`)

- [ ] **Step 1: `loadConfig` — Boolean-Normalisierung**

In `statusline-configurator.html` den `barBrackets`-Block in `loadConfig` (ca. Zeilen 1712–1716)
ersetzen:

```javascript
// Vorher:
barBrackets: (() => {
  if (f.barBrackets !== undefined) return f.barBrackets;
  // Migrate: 'slim' had no brackets; everything else had brackets
  return f.progressStyle !== 'slim';
})(),

// Nachher:
barBrackets: (() => {
  if (f.barBrackets !== undefined && f.barBrackets !== null)
    return Boolean(f.barBrackets);
  // Migrate: 'slim' had no brackets; everything else had brackets
  return f.progressStyle !== 'slim';
})(),
```

- [ ] **Step 2: `buildExportJson` — Boolean-Normalisierung**

In `statusline-configurator.html` die `barBrackets`-Zeile in `buildExportJson` (ca. Zeile 1598)
ersetzen:

```javascript
// Vorher:
if (f.type === 'progressbar' && f.barBrackets !== undefined) base.barBrackets = f.barBrackets;

// Nachher:
if (f.type === 'progressbar' && f.barBrackets !== undefined) base.barBrackets = Boolean(f.barBrackets);
```

- [ ] **Step 3: Manuell verifizieren**

1. `statusline-configurator.html` im Browser öffnen
2. Eine Config mit Progressbar-Feldern laden (z.B. `statusline-config.json`)
3. Ein Progressbar-Feld mit `barBrackets: false` öffnen
4. Prüfen: Klammern-Checkbox ist **nicht** angehakt
5. Config exportieren → im JSON prüfen: `"barBrackets": false` (Boolean, nicht `0` oder `null`)

- [ ] **Step 4: Commit**

```bash
git add statusline-configurator.html
git commit -m "fix(configurator): normalize barBrackets to Boolean in loadConfig and buildExportJson"
```

---

## Task 5: Progressbar — Tab-Guard in `saveEditDialog`

Verhindert, dass `saveEditDialog` Datatype-Tab-Werte in `_editDraft` schreibt,
wenn der Datatype-Tab für den aktuellen Feldtyp ausgeblendet ist.

**Files:**
- Modify: `statusline-configurator.html:2346-2365` (`saveEditDialog`)

- [ ] **Step 1: Tab-Guard einfügen**

In `statusline-configurator.html` den Datatype-Lese-Block in `saveEditDialog` (ca. Zeilen 2346–2365)
ergänzen:

```javascript
// Vorher:
// Read Datentyp tab values into draft (only when tab is visible and type did not just switch)
const typeEl = document.getElementById('edit-datatype');
if (typeEl && !typeJustSwitched) {

// Nachher:
// Read Datentyp tab values into draft (only when tab is visible and type did not just switch)
const isDatatypeTabVisible =
  document.querySelector('.edit-tab-btn[data-tab="datatype"]')?.style.display !== 'none';
const typeEl = document.getElementById('edit-datatype');
if (typeEl && !typeJustSwitched && isDatatypeTabVisible) {
```

Der restliche Block (bis zum schließenden `}`) bleibt unverändert.

- [ ] **Step 2: Manuell verifizieren — Szenario A (Hauptfix)**

1. `statusline-configurator.html` im Browser öffnen
2. Config laden mit mehreren Feldern (u.a. ein `field`-Typ und ein `progressbar`-Typ)
3. Zuerst das `field`-Feld öffnen → Datentyp-Tab anklicken → irgendwas ändern → **Abbrechen**
4. Dann das `progressbar`-Feld öffnen
5. **Erwartung:** General-Tab zeigt die korrekten gespeicherten Werte (`progressStyle`, `barBrackets`, `barCharset`)
6. Ohne Änderung Speichern → Config exportieren → Werte im JSON prüfen

- [ ] **Step 3: Manuell verifizieren — Szenario B (Regression)**

1. Ein `field`-Feld öffnen → Datentyp auf `duration_ms` stellen → Speichern
2. Gleiches Feld erneut öffnen → Datentyp-Tab → Wert muss noch `duration_ms` sein
3. Speichern → Config exportieren → `"dataType": "duration_ms"` im JSON prüfen

- [ ] **Step 4: Abschließende Test-Suite ausführen**

```powershell
Invoke-Pester -Path tests\ -Output Detailed
```

Expected: Alle Tests PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline-configurator.html
git commit -m "fix(configurator): add tab-guard in saveEditDialog to prevent stale datatype tab values overwriting progressbar draft"
```

---

## Abschluss

Nach Task 5 sind alle A+B-Punkte implementiert. Die nächste Sitzung behandelt Spec C
(Preview-Font, UX-Redesign).
