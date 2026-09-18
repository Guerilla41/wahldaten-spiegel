#!/usr/bin/env bash
#
# Spiegelt die amtlichen Wahlexporte des Landeswahlamts Berlin.
#
# Laeuft unverandert unter GitHub Actions (Ubuntu) und auf einem Mac.
# Schreibt eine Datei nur dann, wenn der Abruf geglueckt ist und der Inhalt
# plausibel aussieht. Eine Fehlerseite wird niemals uebernommen.

set -uo pipefail

BASIS="https://www.wahlen-berlin.de/wahlen/Be2026/AFSPRAES"
WURZEL="$(cd "$(dirname "$0")" && pwd)"
ZIEL="$WURZEL/daten"
KENNUNG="bwa-sitzverteilung Spiegel (+https://github.com/Guerilla41/wahldaten-spiegel)"

# Kleiner als das darf keine echte Exportdatei sein. Die Kopfzeile allein
# misst schon rund 1.350 Bytes.
MINDESTGROESSE=5000

QUELLEN="
bvv.csv|$BASIS/bvv/Datenexport_BVV2026_Stimme_A_BE.csv
agh-zweitstimme.csv|$BASIS/agh/Datenexport_AGH2026_Zweitstimme_A_BE.csv
agh-erststimme.csv|$BASIS/agh/Datenexport_AGH2026_Erststimme_A_BE.csv
"

mkdir -p "$ZIEL"

pruefsumme() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	else
		shasum -a 256 "$1" | cut -d' ' -f1
	fi
}

# Haelt eine heruntergeladene Datei fuer eine echte Exportdatei?
plausibel() {
	datei="$1"

	if [ ! -s "$datei" ]; then
		echo "Datei ist leer"
		return 1
	fi

	groesse=$(wc -c < "$datei" | tr -d ' ')
	if [ "$groesse" -lt "$MINDESTGROESSE" ]; then
		echo "nur $groesse Bytes - zu klein fuer einen Export"
		return 1
	fi

	if ! head -c 400 "$datei" | LC_ALL=C grep -a -q 'Adresse;StimmArt;Gebietsart'; then
		echo "Kopfzeile fehlt - vermutlich eine Fehlerseite"
		return 1
	fi

	zeilen=$(LC_ALL=C grep -a -c '' "$datei" | tr -d ' ')
	if [ "$zeilen" -lt 2 ]; then
		echo "nur $zeilen Zeile(n)"
		return 1
	fi

	return 0
}

zeitpunkt=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
geaendert=0
fehler=0
eintraege=""

echo "Spiegellauf $zeitpunkt"
echo

for eintrag in $QUELLEN; do
	name="${eintrag%%|*}"
	url="${eintrag#*|}"
	tmp="$(mktemp)"

	code=$(curl -sS -L \
		--connect-timeout 15 \
		--max-time 60 \
		--retry 2 \
		--retry-delay 3 \
		-A "$KENNUNG" \
		-w '%{http_code}' \
		-o "$tmp" \
		"$url" 2>/dev/null) || code="000"

	if [ "$code" != "200" ]; then
		echo "FEHLER  $name - HTTP $code"
		eintraege="$eintraege    \"$name\": { \"status\": \"fehler\", \"http\": \"$code\" },
"
		fehler=1
		rm -f "$tmp"
		continue
	fi

	if ! grund=$(plausibel "$tmp"); then
		echo "ABGELEHNT  $name - $grund"
		eintraege="$eintraege    \"$name\": { \"status\": \"abgelehnt\", \"grund\": \"$grund\" },
"
		fehler=1
		rm -f "$tmp"
		continue
	fi

	neu=$(pruefsumme "$tmp")
	alt=""
	[ -f "$ZIEL/$name" ] && alt=$(pruefsumme "$ZIEL/$name")
	groesse=$(wc -c < "$tmp" | tr -d ' ')

	if [ "$neu" = "$alt" ]; then
		echo "gleich  $name ($groesse Bytes)"
	else
		cat "$tmp" > "$ZIEL/$name"
		echo "NEU     $name ($groesse Bytes)"
		geaendert=1
	fi

	eintraege="$eintraege    \"$name\": { \"status\": \"ok\", \"bytes\": $groesse, \"sha256\": \"$neu\" },
"
	rm -f "$tmp"
done

if [ "$geaendert" = "1" ]; then
	{
		echo "{"
		echo "  \"stand\": \"$zeitpunkt\","
		echo "  \"quelle\": \"$BASIS\","
		echo "  \"dateien\": {"
		printf '%s' "$eintraege" | sed '$ s/,$//'
		echo "  }"
		echo "}"
	} > "$ZIEL/stand.json"
fi

echo
if [ "$geaendert" = "1" ]; then
	echo "Ergebnis: Daten haben sich geaendert."
else
	echo "Ergebnis: keine Aenderung."
fi

# Ein Fehlschlag einzelner Quellen bricht den Lauf nicht ab - die anderen
# Dateien sollen trotzdem aktuell werden. Der Rueckgabewert meldet ihn nur.
exit "$fehler"
