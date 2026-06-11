# AD User Viewer – Projektkontext

## Was ist das?

Ein PowerShell-WPF-Tool zur Anzeige von Active Directory Benutzern. Gestartet per `irm | iex` direkt aus GitHub, ohne lokale Installation.

**Aufruf:**
```powershell
irm "https://raw.githubusercontent.com/dakazanak/Get-ADUsersGUI/master/Get-ADUsersGUI.ps1" | iex
```

**Repo:** https://github.com/dakazanak/Get-ADUsersGUI (public, Account: dakazanak)

---

## Stack

- **Sprache:** PowerShell 5.1+ und PS7 kompatibel
- **GUI:** WPF mit inline-XAML (kein XAML-File, alles in einer `.ps1`)
- **AD-Zugriff:** `ActiveDirectory`-Modul (`Get-ADUser`, `Get-ADDefaultDomainPasswordPolicy`)
- **Konfiguration:** `config.json` im Skriptverzeichnis (bei `irm|iex`: `$env:USERPROFILE`)

---

## Dateien

| Datei | Zweck |
|---|---|
| `Get-ADUsersGUI.ps1` | Hauptskript, enthält XAML + Logik |
| `config.json` | Einstellungen: Fenstertitel, OU-Sichtbarkeit |

---

## Features

### Benutzeransicht (DataGrid)
Spalten: Benutzername, Anzeigename, Vorname, Nachname, Passwort geändert, Läuft nie ab, Läuft ab am, Aktiv, Gesperrt, Letzter Login

**Farbliche Hervorhebung:**
- Ganze Zeile grau → `Aktiv = Nein`
- Zelle "Läuft nie ab" rot → `PasswordNeverExpires = true`
- Zelle "Läuft ab am" rot → Passwort bereits abgelaufen
- Zelle "Läuft ab am" gelb → läuft in <14 Tagen ab
- Zelle "Gesperrt" rot+fett → `LockedOut = true`

**Passwort-Ablauf:** berechnet aus `PasswordLastSet + MaxPasswordAge` (via `Get-ADDefaultDomainPasswordPolicy`)

### OU-Panel (links)
- Zeigt alle OUs die User enthalten als Checkboxen mit vollem Pfad (z.B. `Domain > Berlin > Users`)
- Haken entfernen filtert die Userliste sofort
- Zustand wird in `config.json` gespeichert und beim nächsten Start wiederhergestellt
- Abgleich beim Start: neue OUs werden automatisch hinzugefügt (sichtbar=true), weggefallene entfernt

### Sonstiges
- Button "Ansicht aktualisieren" unten rechts → lädt alle Daten neu aus dem AD
- Beim ersten Start wird automatisch eine Desktop-Verknüpfung angelegt (nur Windows), die auf den aktuell laufenden PS-Prozess (PS5 oder PS7) zeigt

---

## Wichtige Implementierungsdetails

### irm|iex-Kompatibilität
- `$PSScriptRoot` ist leer → Fallback auf `$env:USERPROFILE` für `config.json`
- `Add-Type` für die `OUItem`-Klasse wird nur ausgeführt wenn der Typ noch nicht existiert (verhindert Fehler bei Mehrfachaufruf in derselben Session)

### OUItem-Klasse
C#-Klasse mit `INotifyPropertyChanged` – notwendig damit WPF-Checkboxen korrekt binden und den gespeicherten Zustand beim Start anzeigen. PSCustomObject reicht für TwoWay-Binding nicht aus.

### AD-Filter
`Get-ADUser -Filter *` lädt alle User, Filterung erfolgt clientseitig per `Where-Object`. Serverseitige Filter mit `-or` und `EmailAddress` schlagen in manchen AD-Umgebungen fehl.

### config.json Struktur
```json
{
    "Title": "AD User Viewer",
    "OUs": [
        { "DN": "OU=Users,DC=domain,DC=com", "Visible": true },
        { "DN": "OU=Disabled,DC=domain,DC=com", "Visible": false }
    ]
}
```

---

## Arbeitsweise / Konventionen

- Alle Antworten auf **Deutsch**
- Änderungen direkt committen und nach `private-origin` (dakazanak/Get-ADUsersGUI) pushen
- Remote heißt `private-origin` (nicht `origin`)
- Kein unnötiger Refactor — nur was der User explizit anfragt
