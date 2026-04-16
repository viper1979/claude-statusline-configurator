# Spec: Statusline Anpassungen 011 — A+B

**Datum:** 2026-04-16  
**Branch:** feature/statusline-007-new-fields-defaults  
**Scope:** Bugfixes, Cleanup (Gruppe A) + Progressbar-Editor-Bug (Gruppe B)

---

## Kontext

Aus dem Anpassungsdokument `Anpasungen_011.md` werden die Punkte A (Fixes & Cleanups)
und B (Progressbar-Editor-Bug) in diesem Spec behandelt. Die Feature-Arbeit (Preview-Font,
UX-Redesign) ist als separater Spec C ausgelagert.

---

## Gruppe A — Fixes & Cleanups

### A1 — Tests nach Rounding-Bugfix (`f431c5e`)

Der Commit `f431c5e` hat ein Rundungsproblem in `request-usage.ps1` behoben.
Tests werden erst ausgeführt; nur tatsächlich fehlschlagende Expectations werden angepasst.
Keine präventiven Änderungen an grünen Tests.

**Betroffene Dateien:**
- `tests/statusline.Tests.ps1`
- `tests/request-usage.Tests.ps1`

### A2 — `duration`-Datentyp entfernen

Der Typ `duration` (direkte Sekunden-Eingabe) ist laut Analyse nicht nativ in den
aktuellen Payload-Feldern vorhanden und gilt als Dead Code.

**Änderungen:**

`statusline.ps1` — `Format-FieldValue`:
- `'duration'`-Case aus dem `switch`-Block entfernen

`statusline-configurator.html` — `DATATYPE_FORMATS`:
- `duration`-Eintrag aus dem Dropdown-Objekt entfernen

`tests/statusline.Tests.ps1`:
- Alle Tests die explizit `duration` testen entfernen (falls vorhanden)

### A3 — `Get-AllKeys`: Null-Werte nicht als Leaf loggen

**Problem:** Wenn ein JSON-Property den Wert `null` hat (z.B. `context_window.current_usage: null`
bei einer Session ohne Cache-Daten), fügt `Get-AllKeys` den Pfad als Leaf-Key hinzu.
Da `context_window.current_usage` nicht in `knownKeys` steht (nur die Kind-Pfade wie
`context_window.current_usage.input_tokens` sind bekannt), erscheint es fälschlicherweise
als "neues Feld" im `new_fields_indicator`.

Das historische Log-Artefakt `worktree.branch.Length` ist kein aktiver Bug im Code und
erfordert keinen Fix — es ist durch A3 implizit abgedeckt.

**Fix in `statusline.ps1`** — `Get-AllKeys`:

```powershell
# Vorher:
} else {
    $result += $key
}

# Nachher:
} elseif ($null -ne $_.Value) {
    $result += $key
}
```

Null-Leaf-Werte werden still übersprungen. Wenn das Property in einem späteren Payload
wieder ein echtes Objekt ist, werden die Kind-Pfade korrekt erkannt.

---

## Gruppe B — Progressbar-Editor-Bug

### Symptom

Beim Öffnen des Feld-Editors für Progressbar-Felder werden die konfigurierten Werte
(`progressStyle`, `barBrackets`, `barCharset`) gelegentlich nicht korrekt angezeigt.
Tritt bevorzugt nach dem Laden einer Konfiguration auf.

### Hypothesen zur Ursache

**Primär:** `saveEditDialog()` liest DOM-Felder aller Tabs ohne zu prüfen, ob der Tab
für den aktuellen Feldtyp sichtbar ist. Wenn der Datatype-Tab von einem vorherigen Edit
(eines `field`-Typs) noch DOM-Reste enthält und der User dann einen `progressbar`-Typ
öffnet, kann `_editDraft.dataType` durch veraltete DOM-Werte überschrieben werden.
Dies betrifft zwar nicht direkt `progressStyle`/`barBrackets`/`barCharset`, kann aber
zu inkonsistentem State führen, der beim erneuten Render des General-Tabs falsche Werte
zeigt.

**Sekundär:** `barBrackets` wird in `loadConfig` und `buildExportJson` nicht explizit
als Boolean normalisiert. JSON-Werte wie `0`, `1` oder `null` könnten durch strict
equality (`!== false`) unerwartet als `true` interpretiert werden.

### Fixes

#### B1 — Tab-Guard in `saveEditDialog`

Datatype-Tab-Felder (`edit-datatype`, `edit-format`, etc.) nur dann in `_editDraft`
schreiben, wenn der Datatype-Tab für den aktuellen Feldtyp nicht ausgeblendet ist:

```javascript
const isDatatypeTabVisible =
  document.querySelector('.edit-tab-btn[data-tab="datatype"]')?.style.display !== 'none';
if (typeEl && !typeJustSwitched && isDatatypeTabVisible) {
  // bisherige Datatype-Logik
}
```

#### B2 — Boolean-Normalisierung in `loadConfig`

`barBrackets` wird beim Laden explizit auf einen echten Boolean normalisiert:

```javascript
barBrackets: (() => {
  if (f.barBrackets !== undefined && f.barBrackets !== null)
    return Boolean(f.barBrackets);
  return f.progressStyle !== 'slim';
})(),
```

#### B3 — Boolean-Normalisierung in `buildExportJson`

Beim Export wird `barBrackets` immer als echter Boolean ausgegeben:

```javascript
if (f.type === 'progressbar' && f.barBrackets !== undefined)
  base.barBrackets = Boolean(f.barBrackets);
```

---

## Testing

- PS-Tests: `Invoke-Pester` ausführen, nur fehlschlagende anpassen (A1)
- Manuell: Konfigurator laden, Progressbar-Feld öffnen, Werte prüfen (B)
- Manuell: `context_window.current_usage: null` im Payload → kein falscher Eintrag im new_fields_indicator (A3)

---

## Nicht im Scope

- Preview-Font / NerdFont-Unterstützung → separater Spec C
- Konfigurator UX-Redesign → separater Spec C
- Neue Felder oder Datentypen hinzufügen
