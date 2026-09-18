# Spiegel der Berliner Wahlexporte

Ein Ausweichweg für die Wahl am **20.09.2026**.

Das Plugin [bwa-sitzverteilung](https://github.com/Guerilla41/bwa-sitzverteilung)
holt die amtlichen Ergebnisexporte des Landeswahlamts normalerweise direkt von
`www.wahlen-berlin.de`. Vom Strato-Webhosting aus scheitert dieser Abruf mit
einer Zeitüberschreitung beim Verbindungsaufbau, während dieselbe Adresse von
anderen Netzen aus in rund 20 Millisekunden antwortet.

Dieses Repository legt die drei Exportdateien deshalb unverändert an einer
zweiten Stelle ab, die vom Webhosting aus erreichbar ist.

## Was hier liegt

| Datei | Quelle |
|---|---|
| `daten/bvv.csv` | `…/bvv/Datenexport_BVV2026_Stimme_A_BE.csv` |
| `daten/agh-zweitstimme.csv` | `…/agh/Datenexport_AGH2026_Zweitstimme_A_BE.csv` |
| `daten/agh-erststimme.csv` | `…/agh/Datenexport_AGH2026_Erststimme_A_BE.csv` |
| `daten/stand.json` | Zeitpunkt, Größe und Prüfsumme des letzten Abrufs |

Grundadresse aller Quellen:
`https://www.wahlen-berlin.de/wahlen/Be2026/AFSPRAES`

Die Dateien werden **byteweise unverändert** übernommen — UTF-8 mit BOM,
CRLF als Zeilenende, 268 Spalten. Dafür sorgt `.gitattributes`; ohne diese
Datei würde Git die Zeilenenden umschreiben und der Parser des Plugins
stolpern.

## Zwei Wege zur Seite

**Der direkte Weg** — der schnelle. Nach jedem Spiegellauf schiebt
`einspielen.sh` die drei Dateien unmittelbar an die Einspieltür des Plugins.
Zwischen einer Änderung an der Quelle und der Seite liegt dann nur der Takt des
Dauerlaufs, also zwei Minuten.

Dafür braucht das Repository zwei Secrets unter
*Settings → Secrets and variables → Actions*:

| Name | Inhalt |
|---|---|
| `BWA_ZIEL` | Die Adresse der Einspieltür, im Plugin unter *Betrieb → Dateien von aussen einspielen* |
| `BWA_SCHLUESSEL` | Der Einspiel-Schlüssel, ebendort |

Fehlt eines der beiden, überspringt das Skript die Einspielung und meldet das.
Der Spiegellauf läuft trotzdem durch.

**Der Weg über den Zwischenspeicher** — der langsame, als Rückfall. Das Plugin
holt sich die Dateien selbst von hier ab. Dazu im Plugin unter
**Einstellungen → Quellen** eintragen:

```
https://raw.githubusercontent.com/Guerilla41/wahldaten-spiegel/main/daten/bvv.csv
https://raw.githubusercontent.com/Guerilla41/wahldaten-spiegel/main/daten/agh-zweitstimme.csv
https://raw.githubusercontent.com/Guerilla41/wahldaten-spiegel/main/daten/agh-erststimme.csv
```

Dieser Weg kostet Zeit: GitHub hält seine Auslieferung fünf Minuten vor und
räumt sie beim Schieben **nicht** vorzeitig. Gemessen am 18.09.2026: 258
Sekunden, bis eine geschobene Änderung ausgeliefert wurde. Zusammen mit dem
Zwei-Minuten-Takt und dem Abrufintervall des Plugins summiert sich das auf bis
zu zehn Minuten Rückstand.

Beide Wege nebeneinander zu betreiben schadet nicht. Das Plugin erkennt eine
Lieferung, die es schon hat, an der Prüfsumme und legt sie nicht zweimal ab.

## Trocken erproben

Vor der Wahl enthalten die amtlichen Exporte lauter Nullen. Ein Probelauf über
den gewöhnlichen Weg legte diesen Stand ab, und weil das Plugin stets den
neuesten Schnappschuss zeigt, stünde er anschliessend auf der Seite — verwerfen
lässt er sich nicht.

Deshalb der Trockenlauf: Unter *Actions → Dauerlauf → Run workflow* das Feld
**trocken** anhaken. Dann wird alles gerechnet und gemeldet, aber nichts
abgelegt. Von Hand geht dasselbe so:

```bash
BWA_ZIEL='…' BWA_SCHLUESSEL='…' BWA_TROCKEN=1 ./einspielen.sh
```

## Wie gespiegelt wird

**Dauerlauf** — der Weg für den Wahlabend. Unter *Actions → Dauerlauf → Run
workflow* von Hand starten, Laufzeit und Takt lassen sich dabei angeben. Der
Lauf holt die Dateien dann stundenlang im Zwei-Minuten-Takt und schiebt jede
Änderung sofort.

Von Hand und nicht nach Zeitplan, weil GitHub Zeitpläne nicht pünktlich
ausführt — aus fünf Minuten können fünfzehn werden.

**Takt** — die Absicherung. Läuft von allein alle fünf Minuten, aber nur
zwischen dem 18. und dem 22.09.2026. Fällt der Dauerlauf aus, füllt er die
Lücke. Beide Abläufe teilen sich eine `concurrency`-Gruppe und kommen sich
deshalb nie in die Quere.

**Auf dem eigenen Rechner** — falls GitHub die Quelle einmal nicht erreicht:

```bash
git clone https://github.com/Guerilla41/wahldaten-spiegel.git
cd wahldaten-spiegel
./spiegeln.sh && git add -A && git commit -m 'Stand von Hand' && git push
```

Dasselbe Skript, derselbe Ablauf. Es läuft unverändert unter macOS und Linux.

## Was das Skript ablehnt

`spiegeln.sh` schreibt eine Datei nur, wenn der Abruf mit HTTP 200 endet, die
Datei mindestens 5.000 Bytes groß ist, die Kopfzeile
`Adresse;StimmArt;Gebietsart` enthält und mehr als eine Zeile hat. Eine
Fehlerseite oder ein abgebrochener Download wird niemals übernommen — der
alte Stand bleibt dann stehen.

Scheitert eine der drei Quellen, laufen die beiden anderen trotzdem durch.

## Abrufabstand

Das Landeswahlamt bittet in seiner
[Pressemitteilung zur Veröffentlichung der Ergebnisse](https://www.berlin.de/wahlen/pressemitteilungen/2026/pressemitteilung.1713317.php)
darum, automatisierte Abrufe auf **zwei Minuten und mehr** einzustellen. Der
Dauerlauf hebt einen kleineren Wert stillschweigend auf zwei Minuten an.

## Herkunft der Daten

Amtliche Ergebnisexporte der Landeswahlleiterin für Berlin, veröffentlicht vom
Amt für Statistik Berlin-Brandenburg. Dieses Repository verändert sie nicht,
es legt sie nur an einer zweiten Stelle ab.
