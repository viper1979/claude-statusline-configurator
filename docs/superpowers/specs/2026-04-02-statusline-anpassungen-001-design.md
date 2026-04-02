# Design: Statusline Anpassungen 001

**Datum:** 2026-04-02
**Status:** Approved
**Scope:** Edit-Dialog, Datentyp-System, Custom-Felder, PS JSON-Persistenz

---

## Überblick

Vier unabhängige, aber zusammenhängende Erweiterungen des Statusline-Systems:

1. **Einheitlicher Edit-Dialog** — ersetzt das bestehende 🎨-Popup durch einen tabellarischen Modal-Dialog
2. **Datentyp-System** — Felder erhalten einen Datentyp mit konfigurierbarer Formatierung
3. **Wiederverwendbare Custom-Felder** — eigene statische Felder in der Palette definieren und mehrfach verwenden
4. **PS JSON-Persistenz & Erkennungsfeld** — letzten JSON-Payload speichern, neue unbekannte Keys erkennen

---

## 1. Config-Schema (Erweiterung)

Das bestehende Schema bleibt rückwärtskompatibel. Neue Properties sind optional — fehlen sie, verhält sich alles wie bisher.

```json
{
  "lines": [
    {
      "fields": [
        {
          "type": "field",
          "key": "rate_limits.seven_day.resets_at",
          "dataType": "unix_timestamp",
          "format": "short",
          "fg": null,
          "bg": null
        },
        {
          "type": "field",
          "key": "model.display_name",
          "dataType": "string",
          "fg": "#ffffff",
          "bg": null
        },
        {
          "type": "field",
          "key": "active",
          "dataType": "bool",
          "format": "checkmark",
          "fg": null,
          "bg": null
        },
        {
          "type": "field",
          "key": "some_bool",
          "dataType": "bool",
          "format": "custom",
          "formatOptions": { "trueLabel": "aktiv", "falseLabel": "inaktiv" },
          "fg": null,
          "bg": null
        },
        {
          "type": "new_fields_indicator",
          "fg": "#facc15",
          "bg": null
        }
      ]
    }
  ],
  "customFields": [
    { "id": "sep-pipe",   "label": "Pipe",        "text": " | ",  "fg": "#666666", "bg": null },
    { "id": "sep-space",  "label": "Leerzeichen",  "text": "  ",  "fg": null,      "bg": null }
  ],
  "knownKeys": [
    "model.display_name",
    "model.id",
    "cost.total_cost",
    "rate_limits.seven_day.resets_at"
  ]
}
```

### Neue Field-Properties

| Property | Typ | Pflicht | Beschreibung |
|---|---|---|---|
| `dataType` | string | nein | Einer der definierten Datentypen |
| `format` | string | nein | Format-Variante passend zum Typ |
| `formatOptions` | object | nein | Nur bei `bool` mit `format: "custom"` |

### Neue Root-Properties

| Property | Typ | Beschreibung |
|---|---|---|
| `customFields` | array | Palette der eigenen statischen Felder |
| `knownKeys` | array | Alle bekannten Keys aus `AVAILABLE_FIELDS`, beim Export automatisch befüllt |

---

## 2. Einheitlicher Edit-Dialog

### Trigger

Der bestehende 🎨-Button auf Field-Chips wird durch einen ✏️-Button ersetzt. Das bisherige Styling-Popup entfällt vollständig.

### Struktur

```
┌─────────────────────────────────────────┐
│  Feld bearbeiten: model.display_name    │
├────────────┬────────────┬───────────────┤
│ Allgemein  │ Datentyp   │ Farben        │
├────────────┴────────────┴───────────────┤
│                                         │
│  [Tab-Inhalt]                           │
│                                         │
├─────────────────────────────────────────┤
│                [Abbrechen] [Speichern]  │
└─────────────────────────────────────────┘
```

### Tab: Allgemein

| Field-Typ | Inhalt |
|---|---|
| `field` | Key (read-only) |
| `static` | Textfeld zum Bearbeiten des Inhalts |
| `progressbar` | Progress-Style-Auswahl (block / slim / color-coded) |
| `new_fields_indicator` | Nur Hinweistext, keine Eingaben |

### Tab: Datentyp & Format

Nur sichtbar für `type: "field"`. Nicht verfügbar für static, progressbar, new_fields_indicator.

- **Datentyp-Dropdown** — vorbefüllt aus `FIELD_TYPE_DEFAULTS`, überschreibbar
- **Format-Auswahl** — Radio-Buttons, passend zum gewählten Typ (siehe Abschnitt 3)
- Bei `bool` + `format: "custom"`: zwei Textfelder für True-Label und False-Label

### Tab: Farben

Identisch zum heutigen Styling-Popup: FG- und BG-Color-Picker (`<input type="color">`) jeweils mit "Keiner"-Checkbox.

### Verhalten

- **Öffnen**: Dialog-Overlay einblenden, kein `render()`-Aufruf
- **Abbrechen**: Alle Änderungen verwerfen, Dialog schließen
- **Speichern**: State-Objekt aktualisieren → `render()` → Dialog schließen

### Edit-Dialog für Custom-Felder in der Palette

Beim ✏️-Klick auf einen Palette-Eintrag (nicht auf einen platzierten Chip) öffnet sich der Dialog mit:
- **Tab: Allgemein** — Label und Text bearbeiten
- **Tab: Farben** — FG/BG

Änderungen hier aktualisieren die `customFields`-Definition in `state`.

---

## 3. Datentyp-System

### Datentypen und Formate

| Typ | Format-Optionen | Beispiel-Ausgabe |
|---|---|---|
| `string` | — | `claude-opus-4-6` |
| `currency` | — (immer 2 Dezimalstellen) | `0.00` |
| `bool` | `true_false` / `yes_no` / `checkmark` / `custom` | `true` / `yes` / `✓` / benutzerdefiniert |
| `number` | `raw` / `k` / `m` | `12345678` / `12346k` / `12m` |
| `unix_timestamp` | `hours` / `short` / `long` / `raw` | `75h 32m` / `1d 4h 32m` / `1d 4hr 32min` / `1738857600` |
| `duration` | `hours` / `short` / `long` | `75h 32m` / `1d 4h 32m` / `1d 4hr 32min` |

**Number-Scaling-Logik:**
- `k`: Wert ÷ 1000, auf ganze Zahl gerundet, Suffix `k`
- `m`: Wert ÷ 1000000, auf ganze Zahl gerundet, Suffix `m`

**Duration vs. Unix Timestamp:**
- `unix_timestamp`: Epochenwert in Sekunden → Differenz zu `UtcNow` berechnen → als verbleibende Zeit anzeigen
- `duration`: Wert ist bereits eine Zeitdauer in Sekunden → direkt umrechnen

### Hartes Mapping `FIELD_TYPE_DEFAULTS` (JS)

```javascript
const FIELD_TYPE_DEFAULTS = {
  // Model
  "model.display_name":                         { dataType: "string" },
  "model.id":                                   { dataType: "string" },
  // Cost
  "cost.total_cost":                            { dataType: "currency" },
  "cost.input_cost":                            { dataType: "currency" },
  "cost.output_cost":                           { dataType: "currency" },
  // Context Window
  "context_window.used_tokens":                 { dataType: "number",          format: "raw" },
  "context_window.max_tokens":                  { dataType: "number",          format: "raw" },
  "context_window.used_percentage":             { dataType: "number",          format: "raw" },
  // Rate Limits — Timestamps
  "rate_limits.minute.resets_at":               { dataType: "unix_timestamp",  format: "hours" },
  "rate_limits.five_minute.resets_at":          { dataType: "unix_timestamp",  format: "hours" },
  "rate_limits.hour.resets_at":                 { dataType: "unix_timestamp",  format: "hours" },
  "rate_limits.day.resets_at":                  { dataType: "unix_timestamp",  format: "short" },
  "rate_limits.seven_day.resets_at":            { dataType: "unix_timestamp",  format: "short" },
  // Rate Limits — Counts
  "rate_limits.minute.requests_limit":          { dataType: "number",          format: "raw" },
  "rate_limits.minute.requests_remaining":      { dataType: "number",          format: "raw" },
  "rate_limits.minute.tokens_limit":            { dataType: "number",          format: "k" },
  "rate_limits.minute.tokens_remaining":        { dataType: "number",          format: "k" },
};
```

Beim Drag eines Feldes aus der Palette wird der Default automatisch ins Field-Objekt übernommen. Im Edit-Dialog ist er überschreibbar.

### PowerShell: `Format-FieldValue`

Neue Hilfsfunktion, aufgerufen aus `Format-Field` nach `Get-NestedValue`:

```powershell
function Format-FieldValue {
    param($Value, $DataType, $Format, $FormatOptions)

    switch ($DataType) {
        "unix_timestamp" {
            $remaining = [DateTimeOffset]::FromUnixTimeSeconds([long]$Value) - [DateTimeOffset]::UtcNow
            # Format-Varianten: hours / short / long / raw
        }
        "duration" {
            $ts = [TimeSpan]::FromSeconds([double]$Value)
            # Format-Varianten: hours / short / long
        }
        "number" {
            switch ($Format) {
                "k" { return "$([math]::Round($Value / 1000))k" }
                "m" { return "$([math]::Round($Value / 1000000))m" }
                default { return "$Value" }
            }
        }
        "currency" { return "$([math]::Round([double]$Value, 2))" }
        "bool" {
            switch ($Format) {
                "yes_no"   { return if ([bool]$Value) { "yes" } else { "no" } }
                "checkmark" { return if ([bool]$Value) { "✓" } else { "✗" } }
                "custom"   { return if ([bool]$Value) { $FormatOptions.trueLabel } else { $FormatOptions.falseLabel } }
                default    { return "$Value" }
            }
        }
        default { return "$Value" }
    }
}
```

---

## 4. Wiederverwendbare Custom-Felder

### Palette

Eine neue Gruppe **"Eigene Felder"** erscheint als letzte Gruppe in der Feldpalette (kollabierbar). Sie enthält:

- Alle Einträge aus `state.customFields`
- Einen **"+ Neues Feld"**-Button am Ende der Gruppe

### Neues Feld anlegen

Der Edit-Dialog öffnet sich im Anlege-Modus (kein bestehendes Feld, leere Felder) mit:
- **Label** — Anzeigename in der Palette
- **Text** — der statische Inhalt
- **FG/BG** — optional

### Drag & Drop

Das Custom-Feld erzeugt beim Ziehen in eine Zeile eine **unabhängige Kopie** (`type: "static"`). Änderungen an der Kopie im Edit-Dialog betreffen nur diese Instanz, nicht die Palette-Definition.

### Löschen aus der Palette

🗑️-Button auf jedem Palette-Eintrag. Eintrag wird aus `state.customFields` entfernt. Bereits platzierte Kopien in Zeilen bleiben unberührt (sie sind eigenständige `static`-Felder).

---

## 5. PowerShell: JSON-Persistenz & Erkennungsfeld

### JSON auf Festplatte speichern

In `Invoke-Main`, direkt nach dem Parsen des Input-JSONs:

```powershell
try {
    $InputJson | Set-Content -Path (Join-Path $PSScriptRoot "last-payload.json") -Encoding UTF8
} catch {
    # Silently ignore — writing the payload file is optional diagnostics only
}
```

- Datei: `last-payload.json` im selben Verzeichnis wie `statusline.ps1`
- Immer aktiv, kein Flag nötig
- Bei jedem Aufruf überschrieben (letzter Stand)
- Fehler (z.B. fehlende Schreibrechte) werden still ignoriert — kein Absturz, kein Impact auf die Ausgabe

### Virtuelles Erkennungsfeld: `new_fields_indicator`

In `Format-Field`, neuer Case für `type = "new_fields_indicator"`:

1. Alle Keys im aktuellen JSON-Payload rekursiv mit Dot-Notation auflisten
2. Gegen `config.knownKeys` prüfen
3. Differenz ermitteln

```
Ausgabe wenn neue Keys vorhanden:  "● 3 neue Felder"
Ausgabe wenn keine neuen Keys:     ""
```

`knownKeys` wird beim Export aus dem Konfigurator automatisch aus `AVAILABLE_FIELDS` befüllt.

### Im Konfigurator

Das Erkennungsfeld erscheint in der Palette unter einer neuen Gruppe **"Diagnose"** als einzelner Eintrag "Neue Felder". Im Edit-Dialog: nur **Tab: Farben**.

---

## Änderungsübersicht bestehender Komponenten

| Komponente | Änderung |
|---|---|
| `statusline-configurator.html` | 🎨-Button → ✏️-Button; Styling-Popup entfernt; Edit-Dialog-Modal hinzufügen; `FIELD_TYPE_DEFAULTS` hinzufügen; Custom-Felder-Palette; Diagnose-Gruppe; `knownKeys` im Export |
| `statusline.ps1` | `Format-FieldValue` hinzufügen; `Format-Field` erweitern; JSON-Persistenz in `Invoke-Main`; `new_fields_indicator`-Case |
| `statusline-config.json` | Schema-Erweiterung (rückwärtskompatibel) |
| `tests/statusline.Tests.ps1` | Tests für `Format-FieldValue` pro Datentyp; Test für JSON-Persistenz; Test für `new_fields_indicator` |
