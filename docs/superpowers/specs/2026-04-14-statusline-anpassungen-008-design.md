# Design Spec — Statusline Anpassungen 008

**Datum:** 2026-04-14  
**Branch:** feature/statusline-007-new-fields-defaults  
**Status:** Approved

---

## Überblick

Dieses Spec beschreibt fünf unabhängige Erweiterungen des ccstatusline-Projekts:

1. **Tab-Ausrichtung** — spaltenbasierte Ausrichtung von Feldern über mehrere Zeilen
2. **Derived Fields** — `context_window.used_tokens` und `context_window.remain_tokens`
3. **Cache Efficiency als Progressbar** — Bug-Fix + genereller Typ-Toggle für Prozentwert-Felder
4. **logNewFields in Edit-Dialog** — Umzug aus der globalen Sidebar in den Feld-Edit-Dialog
5. **K/M/B Großschreibung** — Einheitliche Großbuchstaben bei Zahlen-Kurzschreibweise

---

## 1. Tab-Ausrichtung

### 1.1 Ziel

Felder auf verschiedenen Statusline-Zeilen sollen spaltenweise ausgerichtet werden. Jede Spalte hat dieselbe Breite über alle Zeilen hinweg.

### 1.2 Config-Schema

Jedes Feld-Objekt erhält ein optionales Boolean-Property `mergeWithNext` (Default: `false`). Ein Feld mit `mergeWithNext: true` wird mit dem nachfolgenden Feld zu einer **Gruppe** zusammengefasst. Gruppen bilden die Spalteneinheiten für die Ausrichtung.

```json
{
  "type": "field",
  "key": "context_window.used_percentage",
  "mergeWithNext": true
}
```

**Gruppierungsregel:** Felder werden von links nach rechts durchlaufen. Solange ein Feld `mergeWithNext: true` hat, gehört das nachfolgende Feld zur gleichen Gruppe. Das letzte Feld einer Gruppe hat `mergeWithNext: false` (oder den Default).

```
Beispiel:
  [A mergeWithNext:true] [B mergeWithNext:true] [C] [D] [E mergeWithNext:true] [F]
  Gruppen: [A B C] [D] [E F]
```

**Separatoren als Gruppenbestandteil:** `static`-Felder (z.B. ` | `) können ebenfalls `mergeWithNext: true` erhalten und werden dann in die Gruppenbreite eingerechnet. Ein Separator gehört zur Gruppe, wenn das vorherige Feld ihn per `mergeWithNext` einschließt.

**Kein Breaking Change:** Bestehende Configs ohne `mergeWithNext` verhalten sich wie bisher — jedes Feld ist seine eigene Gruppe (entspricht Option A / keine Ausrichtung, wenn alle Gruppen einelementig sind).

### 1.3 Algorithmus

Identisch in PS1 und JavaScript implementiert (Dual-Implementierung, keine gemeinsame Code-Basis wegen Infrastruktur-Aufwand).

```
buildGroups(fields):
  groups = []
  current = []
  for each field in fields:
    current.append(field)
    if field.mergeWithNext != true:
      groups.append(current)
      current = []
  return groups
```

**Two-Pass Rendering (PS1):**

- **Pass 1:** Alle Felder aller Zeilen rendern, Gruppen bilden, sichtbare Breite messen (ANSI-Codes strippen). Ergebnis: Matrix `[lineIdx][groupIdx] = { text, visibleWidth }`.
- **Pass 2:** Pro Gruppenposition `g` die maximale Breite über alle Zeilen bestimmen. Jede Gruppe mit Leerzeichen rechts auffüllen auf `maxWidth`. Zeilen mit weniger Gruppen als andere erhalten keine Auffüllung für fehlende Spalten.

**JS-Preview:** Gleiche Logik, Breitenmessung über `textContent.length` der gerenderten Span-Elemente (keine ANSI-Codes in der Preview).

**Beispiel:**

```
Zeile 1: [15%░░░░░░░░ / 158K]  [claude-sonnet-4-6  ]
Zeile 2: [73%▓▓▓▓▓░░░ / 42K ] [claude-opus-4-6    ]
         ^^^^^^^^^^^^^^^^^^^^  ^^^^^^^^^^^^^^^^^^^
         Gruppe 1              Gruppe 2
         (gleiche Breite)      (gleiche Breite)
```

### 1.4 UI — Quick-Edit Handle am Chip

Jeder Feld-Chip im Line-Builder erhält ein kleines Icon am rechten Rand zum direkten Togglen von `mergeWithNext`:

- **Inaktiv** (grau, `↝`): kein Merge
- **Aktiv** (Akzentfarbe, `→` + visuelle Verbindung zum nächsten Chip): Merge aktiv

Klick auf das Icon togglet `mergeWithNext` und re-rendert den Line-Builder sofort.

```
Inaktiv:  [used_pct ↝] [remain_tokens ↝] [ | ↝] [model ↝]

Aktiv:    [used_pct →━━━━━━━━━━━━━━━][remain_tokens ↝] [ | ↝] [model ↝]
```

### 1.5 UI — Edit-Dialog

Im Tab "Allgemein" des Edit-Dialogs erscheint für alle Feld-Typen (inkl. `static`) eine Checkbox:

```
☑ Mit nächstem Feld gruppieren (Tab-Ausrichtung)
```

Speichern setzt `mergeWithNext` im Feld-Objekt.

---

## 2. Derived Fields: `used_tokens` & `remain_tokens`

### 2.1 PS1 — `Compute-DerivedFields`

Zwei neue berechnete Felder werden in `Compute-DerivedFields` ergänzt:

| Key | Berechnung | Guard |
|---|---|---|
| `context_window.used_tokens` | `Floor(ctx_size * used_pct / 100)` | nur wenn `ctx_size > 0` und `used_pct != null` |
| `context_window.remain_tokens` | `Floor(ctx_size * remain_pct / 100)` | nur wenn `ctx_size > 0` und `remain_pct != null` |

### 2.2 Configurator — Palette

Zwei neue Einträge in der `context_window`-Gruppe der Feld-Palette:

| Key | Label | `FIELD_TYPE_DEFAULTS` |
|---|---|---|
| `context_window.used_tokens` | `Used Tokens` | `{ dataType: 'number', format: 'auto' }` |
| `context_window.remain_tokens` | `Remaining Tokens` | `{ dataType: 'number', format: 'auto' }` |

Ausgabe-Format folgt der bestehenden Zahlenformatierung (z.B. `42K`, `158K`).

---

## 3. Cache Efficiency als Progressbar

### 3.1 Bug-Fix: `PERCENTAGE_KEYS`

`context_window.cache_efficiency` wird zu `PERCENTAGE_KEYS` hinzugefügt. Damit erzeugt ein Drag aus der Palette automatisch einen `progressbar`-Chip statt eines `field`-Chips.

### 3.2 Typ-Toggle im Edit-Dialog

Für alle Felder deren `key` in `PERCENTAGE_KEYS` enthalten ist, erscheint im Tab "Allgemein" des Edit-Dialogs ein Radio-Toggle:

```
Darstellung:  ○ Wert   ● Progressbar
```

- Wechsel **Wert → Progressbar:** `f.type = 'progressbar'`, Progressbar-Defaults setzen (`progressStyle: 'color-coded'`, `barBrackets: true`, `barCharset: 'block'`), Datentyp-Tab ausblenden.
- Wechsel **Progressbar → Wert:** `f.type = 'field'`, Progressbar-Properties entfernen, Datentyp-Tab einblenden.

Der Toggle erscheint **nur** für Felder mit `key` in `PERCENTAGE_KEYS` — nicht für alle `field`-Typen.

---

## 4. logNewFields in Edit-Dialog

### 4.1 Änderungen Configurator

- Globaler `logNewFields`-Toggle aus der Sidebar-Sektion "Globale Einstellungen" **entfernen**.
- Im Edit-Dialog des `new_fields_indicator`-Chips (Tab "Allgemein") eine Checkbox ergänzen:

```
☑ In Log-Datei schreiben
   (Pfad: <scriptdir>/statusline-new-fields.log)
```

- `state.logNewFields` bleibt als globaler State erhalten (wird vom `new_fields_indicator`-Chip gesteuert).
- Config-Export und Import bleiben identisch (`logNewFields: true/false` auf Root-Ebene).

### 4.2 Keine PS1-Änderungen

Der Log-Pfad bleibt hardcoded auf `Join-Path $PSScriptRoot 'statusline-new-fields.log'`. Keine neuen Config-Properties im PS1.

---

## 5. K/M/B Großschreibung

In `statusline.ps1`, Funktion `Format-Value`, Zahlenformatierung:

```powershell
# Vorher:
if ($n -ge 1000000000) { return "$([math]::Round($n / 1000000000))b" }
if ($n -ge 1000000)    { return "$([math]::Round($n / 1000000))m" }
if ($n -ge 1000)       { return "$([math]::Round($n / 1000))k" }

# Nachher:
if ($n -ge 1000000000) { return "$([math]::Round($n / 1000000000))B" }
if ($n -ge 1000000)    { return "$([math]::Round($n / 1000000))M" }
if ($n -ge 1000)       { return "$([math]::Round($n / 1000))K" }
```

---

## Betroffene Dateien

| Datei | Änderungen |
|---|---|
| `statusline.ps1` | Compute-DerivedFields (+2 Felder), Format-Value (K/M/B), Two-Pass Rendering |
| `statusline-configurator.html` | PERCENTAGE_KEYS, FIELD_TYPE_DEFAULTS, Palette, Edit-Dialog (3x), Quick-Edit Handle, Sidebar |
| `tests/statusline.Tests.ps1` | Tests für used_tokens, remain_tokens, K/M/B, Two-Pass Rendering |
