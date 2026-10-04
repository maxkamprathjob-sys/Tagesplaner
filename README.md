# Tagesplaner

Persönlicher, intelligenter Tagesplaner für iPhone (optimiert für iPhone 14 Pro).
Native iOS-App in Swift/SwiftUI mit SwiftData, WidgetKit, ActivityKit, App Intents,
EventKit und lokalen Benachrichtigungen. Keine Website, keine PWA, kein Server,
kein Konto, kein Tracking.

---

## Was die App kann

| Bereich | Umsetzung |
|---|---|
| Tagesplan 00:00–24:00 | Vertikale Zeitleiste, Blockhöhe ∝ Dauer, freie Lücken sichtbar, „Jetzt“-Linie |
| Zeitblöcke | Anlegen (auch durch Tippen in die Zeitleiste), bearbeiten, löschen, **gedrückt halten + ziehen** zum Verschieben, unteren Griff ziehen für die Länge |
| Übernacht | 21:00–07:00 wird automatisch zu „heute 21:00 → morgen 07:00“ und erscheint an beiden Tagen |
| To-do-Liste | Titel, Tag, Uhrzeit, Deadline, Dauer, Priorität, Kategorie, Notiz, erledigt |
| Gemeinsames Datenmodell | **Ein** `PlanItem` ist Aufgabe, Zeitblock und/oder Termin – Änderungen sind sofort überall sichtbar, es gibt keine Kopien |
| Tageswechsel | Gestern/heute/morgen, Kalenderauswahl, Wischen im Kopfbereich; jeder Eintrag erscheint nur an seinem Tag |
| Schnelleingabe | „+“ → Text → Speichern. Lokaler deutscher Sprachparser (siehe unten) |
| Intelligente Planung | Lokale Logik: Termine, Kalender, Schlafenszeit, Pausen, Prioritäten, Deadlines. **Nur Vorschläge**: [Einplanen] [Andere Zeit] [Nicht jetzt] |
| Überlastung | „Dein heutiger Tag ist bereits stark ausgelastet …“ mit [Auf morgen] [Trotzdem einplanen] [Andere Zeit suchen] [Bearbeiten] |
| „Tag planen“ | Verteilt alle offenen Aufgaben – dringende/wichtige zuerst – zur Auswahl |
| Konflikte | Überschneidungen werden rot markiert und aufgelistet, nie automatisch verschoben |
| Deadlines | Warnung, wenn es knapp wird („Wenn du diese Aufgabe heute nicht einplanst, wird es zeitlich knapp.“) |
| Tagesanalyse | „Du hast heute ungefähr 8 Std. feste Termine …“ – bewusst gerundet, keine Scheingenauigkeit |
| Sperrbildschirm | Widgets „Heute“, „Nächster Termin“, „Offene Aufgaben“ + Live Activity |
| Home-Bildschirm | Widget klein/mittel/groß (mittel = Zeitplan links, To-dos rechts) |
| Dynamic Island | Laufender Block mit Restzeit, Fortschritt und nächstem Block |
| Benachrichtigungen | „Universität beginnt in 15 Minuten.“, Tagesüberblick offener Aufgaben |
| Apple-Kalender | Optional, nur lesend, gestrichelt dargestellt, fließt in die Planung ein |
| Siri/Kurzbefehle | „Was steht heute an“, „Nächster Termin“, „Plane etwas ein“ |

### Beispiele für die Eingabe

```
Ich muss morgen 2 Stunden lernen.
Ich habe morgen um 8 Uhr Uni bis 14 Uhr.
Um 21 Uhr möchte ich schlafen.
Ich muss heute noch einkaufen.
Plane mir morgen 90 Minuten Sport ein.
Steuererklärung bis 30.10. 18 Uhr, 2 Stunden, wichtig
Pack mir heute noch zwei Stunden Lernen zwischen Uni und Sport
29.10. Zur Universität gehen 08:00–14:00
Sport 14:52–17:00
```

Erkannt werden: heute/morgen/übermorgen, Wochentage, Daten (29.10. / 29.10.2026),
Uhrzeiten (um 8 Uhr, 14:52, von 8 bis 14 Uhr, 8–14 Uhr, abends), Dauern (2 Stunden,
90 Minuten, zwei Stunden, anderthalb Stunden, 1,5 h), Deadlines (bis …, Deadline …),
Prioritäten (wichtig, sehr wichtig, dringend, unwichtig), Schlaf und Bezüge wie
„zwischen Uni und Sport“ oder „nach der Uni“.

---

## iOS-Einschränkungen (ehrlich)

1. **Eigene Oberfläche dauerhaft auf dem Sperrbildschirm ist für Drittanbieter-Apps nicht erlaubt.**
   Ersatz: Lock-Screen-Widgets (bis zu 3 Zeilen bzw. kleine Kreise) + Live Activity.
2. **Widgets** werden nicht live gerendert. Die App liefert iOS im Voraus eine Zeitleiste
   mit einem Eintrag zu jedem Blockbeginn/-ende; Restzeiten zählen per System-Timer.
   iOS begrenzt die Anzahl der Aktualisierungen – selten kann eine Anzeige kurz verzögert sein.
3. **Live Activities** lassen sich ohne eigenen Push-Server nur starten, während die App im
   Vordergrund ist. Sie startet daher beim Öffnen der App, wenn gerade ein Block läuft, und
   wird am Blockende als „beendet“ markiert. iOS beendet Live Activities nach spätestens 8 Std.
   (Ein Push-Server wäre nötig, um sie im Hintergrund zu starten – bewusst weggelassen, weil
   das Ziel „keine Cloud“ ist.)
4. **Apple Intelligence / On-Device-Sprachmodelle** laufen auf dem iPhone 14 Pro nicht
   (benötigen A17 Pro oder neuer). Deshalb verwendet die App einen eigenen lokalen
   Regel-Parser. Eine externe Cloud-KI ist **nicht** eingebaut – es werden keinerlei Daten
   übertragen, es gibt keinen API-Schlüssel.
5. **Interaktive Widgets** (z. B. Aufgabe direkt im Widget abhaken) sind möglich, aber
   bewusst nicht umgesetzt: Widgets lesen nur eine Kopie der Daten, damit ein Widget-Fehler
   die Datenbank nie beschädigen kann.
6. Höchstens 64 geplante Benachrichtigungen pro App (iOS-Grenze) – die App plant die
   nächsten 7 Tage, maximal 60 Stück, und plant bei jeder Änderung neu.

---

## Installation ohne eigenen Mac

Eine iOS-App kann nur mit Xcode gebaut und von Apple signiert werden, und Xcode läuft
nur auf macOS. Ohne eigenen Mac ist der einfachste **offizielle** Weg:

**GitHub Actions (kostenlose Mac-Server) baut und signiert → TestFlight installiert auf dem iPhone.**

### Was du brauchst

| | Kosten |
|---|---|
| iPhone 14 Pro mit iOS 17 oder neuer | – |
| Windows-PC mit Browser | – |
| GitHub-Konto mit diesem Repository | kostenlos (privat: 2.000 Action-Minuten/Monat, macOS zählt 10-fach → ca. 15–20 Builds) |
| **Apple Developer Program** | **99 € pro Jahr** |
| App „TestFlight“ aus dem App Store | kostenlos |

**Warum das Developer Program nötig ist:** Ohne Mac gibt es keinen offiziellen Weg, eine
App mit kostenloser Apple-ID auf das iPhone zu bringen – die kostenlose Signierung
funktioniert nur direkt aus Xcode auf einem Mac (und läuft dann nach 7 Tagen ab).
TestFlight und die Signierung in der Cloud setzen die bezahlte Mitgliedschaft voraus.
Die App wird dabei **nicht** im App Store veröffentlicht; interne TestFlight-Tests
brauchen keine App-Review.

### Schritt 1 – Apple Developer Program (einmalig)

1. <https://developer.apple.com/programs/enroll/> → mit deiner Apple-ID als **Einzelperson** anmelden, 99 € zahlen.
   Die Freischaltung dauert meist wenige Stunden bis 2 Tage.
2. Unter <https://developer.apple.com/account> → „Membership details“ die **Team ID** notieren (10 Zeichen, z. B. `AB12CD34EF`).

### Schritt 2 – Kennungen festlegen (einmalig, im Browser)

Wähle ein eindeutiges Präfix, z. B. `de.maxkamprath`. Daraus entstehen:

- App: `de.maxkamprath.tagesplaner`
- Widgets: `de.maxkamprath.tagesplaner.widgets`
- App Group: `group.de.maxkamprath.tagesplaner`

Auf <https://developer.apple.com/account/resources/identifiers/list>:

1. **„+“ → App Groups** → Kennung `group.de.maxkamprath.tagesplaner` anlegen.
2. **„+“ → App IDs → App** → Bundle ID `de.maxkamprath.tagesplaner`, Capability **App Groups**
   aktivieren und die Gruppe zuweisen.
3. Dasselbe für `de.maxkamprath.tagesplaner.widgets` (ebenfalls App Groups + dieselbe Gruppe).

(Xcode kann das beim ersten Build teilweise selbst anlegen; manuell ist es zuverlässiger.)

### Schritt 3 – App in App Store Connect anlegen (einmalig)

<https://appstoreconnect.apple.com> → „Apps“ → „+“ → „Neue App“:
Plattform iOS, Name z. B. „Tagesplaner Max“ (muss im Store eindeutig sein – wird aber
nicht veröffentlicht), Sprache Deutsch, Bundle-ID `de.maxkamprath.tagesplaner`, SKU beliebig.

### Schritt 4 – API-Schlüssel für GitHub (einmalig)

App Store Connect → „Benutzer und Zugriff“ → „Integrationen“ → „App Store Connect API“ →
Teamschlüssel erzeugen, **Rolle „Admin“** (wird benötigt, damit das Signaturzertifikat
in der Cloud erstellt werden darf). Notieren:

- **Key ID**
- **Issuer ID**
- Datei **AuthKey_XXXX.p8** herunterladen (geht nur einmal!)

### Schritt 5 – GitHub einrichten (einmalig)

Im Repository → **Settings → Secrets and variables → Actions**:

| Typ | Name | Wert |
|---|---|---|
| Variable | `BUNDLE_ID_PREFIX` | `de.maxkamprath` |
| Variable | `DEVELOPMENT_TEAM` | deine Team ID |
| Secret | `ASC_KEY_ID` | Key ID |
| Secret | `ASC_ISSUER_ID` | Issuer ID |
| Secret | `ASC_PRIVATE_KEY` | kompletter Inhalt der .p8-Datei (mit Editor öffnen, alles kopieren) |

Der Schlüssel liegt nur verschlüsselt bei GitHub, nie im Quellcode.

### Schritt 6 – Bauen und hochladen

Repository → **Actions** → **TestFlight** → **Run workflow**. Dauer ca. 10–15 Minuten.
Danach verarbeitet Apple den Build noch 5–30 Minuten.

### Schritt 7 – Auf dem iPhone installieren

1. App **TestFlight** aus dem App Store installieren, mit derselben Apple-ID anmelden.
2. In App Store Connect → deine App → **TestFlight** → **Interne Tests** → Gruppe anlegen,
   dich selbst hinzufügen, Build auswählen (beim ersten Mal ggf. Frage zur
   Exportkontrolle: „Nein“ – die App nutzt keine eigene Verschlüsselung).
3. In TestFlight auf dem iPhone erscheint **Tagesplaner** → „Installieren“.
   Die App liegt danach ganz normal auf dem Home-Bildschirm.

**Wichtig:** TestFlight-Builds laufen nach **90 Tagen** ab. Einfach den Workflow erneut
starten und in TestFlight aktualisieren – **deine Daten bleiben erhalten**.

### Schritt 8 – Nach der Installation

- **Erster Start:** Einstellungen (Zahnrad) → Aufstehen und Schlafenszeit einstellen.
- **Benachrichtigungen:** Einstellungen → „Erinnerungen“ einschalten → iOS-Abfrage „Erlauben“.
- **Apple-Kalender (optional):** Einstellungen → „Apple-Kalender anzeigen“ → „Vollzugriff erlauben“.
  Abgelehnt? Die App funktioniert normal weiter.
- **Live Activity:** ist standardmäßig an; iOS-Einstellungen → Tagesplaner → „Live-Aktivitäten“ muss erlaubt sein.
- **Lock-Screen-Widget:** Sperrbildschirm lange drücken → „Anpassen“ → „Sperrbildschirm“ →
  Feld unter der Uhr antippen → „Tagesplaner“ → „Heute“, „Nächster Termin“ oder „Offene Aufgaben“.
- **Home-Screen-Widget:** Home-Bildschirm lange drücken → „Bearbeiten“ → „Widget hinzufügen“ →
  „Tagesplaner“ → Größe wählen (mittel = Zeitplan + To-dos).
- **Siri:** „Was steht heute an in Tagesplaner“.

### Alternative: Zugang zu einem Mac (Uni-Pool, Freunde, Cloud-Mac)

Mit Xcode 26 auf einem Mac:

```bash
brew install xcodegen
BUNDLE_ID_PREFIX=de.maxkamprath DEVELOPMENT_TEAM=DEINE_TEAM_ID xcodegen generate
open Tagesplaner.xcodeproj
```

iPhone per USB verbinden, Entwicklermodus aktivieren (iOS-Einstellungen → Datenschutz &
Sicherheit → Entwicklermodus), Ziel „iPhone“ wählen, ▶︎ drücken. Mit kostenloser Apple-ID
läuft die App so 7 Tage, mit Developer Program 1 Jahr.

### Nicht empfohlen

- **Sideloading-Tools für Windows** (z. B. Sideloadly, AltStore): nutzen die kostenlose
  Apple-Signatur inoffiziell; 7-Tage-Laufzeit, Begrenzungen bei App-Erweiterungen wie
  Widgets und App Groups. Nicht als zuverlässig zugesagt.
- **Eine .ipa einfach weitergeben:** funktioniert nicht – jede Installation braucht eine
  für das Gerät gültige Apple-Signatur.

---

## Weitergabe an einen Kollegen (optional)

- **Einfachster Weg:** In App Store Connect → TestFlight → **Externe Tests** → Gruppe mit
  öffentlichem Link. Der erste Build braucht dafür eine kurze Beta-Review durch Apple
  (meist < 1 Tag). Dein Kollege installiert TestFlight und öffnet den Link.
- Oder ihn als **internen Tester** einladen (er muss dann Mitglied deines App-Store-Connect-Teams werden).
- Code-Änderungen sind dafür **nicht** nötig. Jeder hat seine eigenen, lokalen Daten.

---

## Datenschutz

- Alle Daten liegen lokal in einer SwiftData-Datenbank im App-Group-Ordner des iPhones.
- Keine Netzwerkzugriffe, kein Konto, keine Analytics, keine Werbung, keine Cloud-KI.
- Kalender: nur lesend, erst nach ausdrücklicher Erlaubnis.
- Benachrichtigungen: rein lokal geplant.

---

## Architektur

```
Packages/PlannerCore/        Plattformunabhängige Logik (nur Foundation), voll getestet
  TimeMath.swift             Datum, Übernacht, Zeitumstellung, Intervalle, Dauer-Texte
  PlanningModels.swift       Priority, ScheduleEntry, TaskRequest, Einstellungen, Konflikte
  Availability.swift         Freie Zeit (Aufstehen/Schlafen/Pausen/Schlafblöcke)
  Scheduler.swift            Vorschläge, Alternativen, Überlastung, Tag planen
  Analysis.swift             Deadline-Risiko, Tagesanalyse
  NaturalLanguageParser.swift  Deutscher Freitext → strukturierte Daten
App/
  Model/                     PlanItem (SwiftData, gemeinsames Modell), Kategorien
  Persistence/               ModelContainer im App-Group-Ordner
  Store/                     PlanStore (einziger Weg für Änderungen), Einstellungen
  Services/                  Benachrichtigungen, EventKit, Live Activity, Widget-Snapshot
  Intents/                   Siri & Kurzbefehle
  UI/                        Zeitleiste, To-dos, Schnelleingabe, Vorschläge, Editor, Einstellungen
Shared/                      Von App und Widgets gemeinsam genutzt (Snapshot, Theme, Activity)
Widgets/                     Lock-/Home-Screen-Widgets, Live Activity/Dynamic Island
AppTests/                    Tests für Synchronisierung, Tagesbezug, Persistenz u. a.
.github/workflows/           build.yml (bei jedem Push), testflight.yml (manuell)
```

Die Projektdatei wird mit [XcodeGen](https://github.com/yonaskolb/XcodeGen) aus `project.yml` erzeugt.

**Anforderungen:** iOS 17.0+ (SwiftData, interaktive Widget-Container, EventKit-Vollzugriff),
Xcode 26 (auf den GitHub-Runnern `macos-26` vorinstalliert).
