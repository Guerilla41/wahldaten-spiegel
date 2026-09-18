#!/usr/bin/env bash
#
# Schiebt die gespiegelten Dateien unmittelbar in die WordPress-Installation.
#
# Der Weg ohne Zwischenspeicher. Holt das Plugin die Dateien selbst von hier
# ab, liegen zwischen einer Aenderung und der Seite bis zu fuenf Minuten, weil
# GitHub seine Auslieferung so lange vorhaelt. Dieser Weg umgeht das: Die
# Dateien gehen direkt an die Einspieltuer des Plugins.
#
# Erwartet im Umfeld:
#   BWA_ZIEL        Adresse der Einspieltuer, siehe Reiter Betrieb
#   BWA_SCHLUESSEL  Einspiel-Schluessel, ebendort
#   BWA_TROCKEN     1 = nur rechnen und melden, nichts ablegen (Voreinstellung 0)
#   BWA_ERZWINGEN   1 = auch eine unveraenderte Lieferung neu rechnen
#
# Ohne die ersten beiden tut das Skript nichts und meldet das. Es soll den
# Spiegellauf nicht abbrechen, nur weil niemand die Tuer eingerichtet hat.

set -uo pipefail

WURZEL="$(cd "$(dirname "$0")" && pwd)"
ZIEL="${BWA_ZIEL:-}"
SCHLUESSEL="${BWA_SCHLUESSEL:-}"
TROCKEN="${BWA_TROCKEN:-0}"
ERZWINGEN="${BWA_ERZWINGEN:-0}"

if [ -z "$ZIEL" ] || [ -z "$SCHLUESSEL" ]; then
	echo "Einspieltuer nicht eingerichtet (BWA_ZIEL oder BWA_SCHLUESSEL fehlt) - uebersprungen."
	exit 0
fi

# Feldname im Plugin, Dateiname im Spiegel.
FELDER="
bvv|bvv.csv
agh_zweit|agh-zweitstimme.csv
agh_erst|agh-erststimme.csv
"

args=()
mitgeschickt=0

for eintrag in $FELDER; do
	feld="${eintrag%%|*}"
	datei="$WURZEL/daten/${eintrag#*|}"

	if [ -s "$datei" ]; then
		args+=( -F "${feld}=@${datei};type=text/csv" )
		mitgeschickt=$(( mitgeschickt + 1 ))
	else
		echo "Hinweis: ${datei##*/} fehlt oder ist leer - nicht mitgeschickt."
	fi
done

if [ "$mitgeschickt" -eq 0 ]; then
	echo "Keine Datei zum Einspielen vorhanden."
	exit 1
fi

[ "$TROCKEN" = "1" ] && args+=( -F "trocken=1" )
[ "$ERZWINGEN" = "1" ] && args+=( -F "erzwingen=1" )

antwort="$(mktemp)"

# Der Schluessel reist im Rumpf und nicht in der Adresse: So landet er in
# keinem Zugriffsprotokoll auf dem Weg.
code=$(curl -sS \
	--connect-timeout 15 \
	--max-time 120 \
	--retry 2 \
	--retry-delay 3 \
	-X POST \
	-F "schluessel=${SCHLUESSEL}" \
	"${args[@]}" \
	-w '%{http_code}' \
	-o "$antwort" \
	"$ZIEL" 2>/dev/null) || code="000"

zusatz=""
[ "$TROCKEN" = "1" ] && zusatz=" (trocken - es wird nichts abgelegt)"

echo "Einspielung: HTTP ${code}, ${mitgeschickt} Datei(en)${zusatz}"

if [ -s "$antwort" ]; then
	# Die Antwort ist kurzes JSON. Ungefiltert ausgeben statt zu zerlegen -
	# jq gibt es nicht ueberall, und die Meldung soll vollstaendig im
	# Protokoll stehen.
	cat "$antwort"
	echo
fi

rm -f "$antwort"

case "$code" in
	200)
		# Angekommen. Ob etwas daraus wurde, steht in "ok" der Antwort und im
		# Reiter Betrieb unter "letzter Lauf".
		exit 0
		;;
	403)
		echo "FEHLER: Schluessel abgelehnt. Im Reiter Betrieb nachsehen und das Repository-Secret nachtragen."
		exit 1
		;;
	000)
		echo "FEHLER: Die Seite war nicht erreichbar."
		exit 1
		;;
	*)
		echo "FEHLER: Unerwartete Antwort."
		exit 1
		;;
esac
