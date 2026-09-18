#!/usr/bin/env bash
#
# Der Wahlabend-Lauf fuer einen Rechner, der die amtliche Quelle erreicht.
#
# Holt die drei Exportdateien im festen Takt, schiebt sie unmittelbar in die
# Seite und legt sie nebenbei im Spiegel ab. Laeuft, bis man ihn mit Strg-C
# beendet oder die Laufzeit abgelaufen ist.
#
# Warum dieser Weg und nicht GitHub: Die Erreichbarkeit von
# www.wahlen-berlin.de ist von Netz zu Netz verschieden und nicht stabil. Das
# Strato-Webhosting kommt ueberhaupt nicht durch; ein GitHub-Laeufer kam am
# 18.09.2026 um 20:02 durch und vier Minuten spaeter nicht mehr, mit
# Zeitueberschreitung beim Verbindungsaufbau. Ein gewoehnlicher Anschluss war
# den ganzen Tag ueber stabil. Also laeuft der Abruf dort, wo er nachweislich
# funktioniert.
#
# Vorbereitung: Eine Datei zugang.sh daneben anlegen mit
#
#   export BWA_ZIEL='https://…/wp-json/bwa/v1/einspielen'
#   export BWA_SCHLUESSEL='…'
#
# Beides steht im Plugin unter Betrieb, Abschnitt "Dateien von aussen
# einspielen". Die Datei ist in .gitignore eingetragen und wird nicht geschoben.
#
# Aufruf, mit Wachhalten des Rechners:
#
#   caffeinate -i ./wahlabend.sh
#
# Mit Laufzeit in Minuten und Takt in Sekunden:
#
#   caffeinate -i ./wahlabend.sh 420 120
#
# Trocken erproben, ohne dass etwas auf der Seite landet:
#
#   BWA_TROCKEN=1 ./wahlabend.sh 4 60

set -uo pipefail

WURZEL="$(cd "$(dirname "$0")" && pwd)"
cd "$WURZEL" || exit 1

MINUTEN="${1:-420}"
TAKT="${2:-120}"

# Das Landeswahlamt bittet um mindestens zwei Minuten Abstand.
if [ "$TAKT" -lt 120 ] 2>/dev/null; then
	if [ "${BWA_TROCKEN:-0}" != "1" ]; then
		echo "Takt auf 120 Sekunden angehoben - die Quelle bittet um diesen Abstand."
		TAKT=120
	fi
fi

# shellcheck source=/dev/null
[ -f "$WURZEL/zugang.sh" ] && . "$WURZEL/zugang.sh"

if [ -z "${BWA_ZIEL:-}" ] || [ -z "${BWA_SCHLUESSEL:-}" ]; then
	echo "FEHLER: BWA_ZIEL und BWA_SCHLUESSEL fehlen."
	echo "Legen Sie zugang.sh an - siehe Kopf dieser Datei."
	exit 1
fi

# Den Spiegel nebenher fuellen, damit der Rueckfallweg aktuell bleibt. Wer das
# nicht will, setzt BWA_SPIEGELN=0.
SPIEGELN="${BWA_SPIEGELN:-1}"

ende=$(( $(date +%s) + MINUTEN * 60 ))
durchgang=0
geholt=0
misslungen=0

echo "=============================================="
echo " Wahlabend-Lauf"
echo " Laufzeit $MINUTEN Minuten, Takt $TAKT Sekunden"
[ "${BWA_TROCKEN:-0}" = "1" ] && echo " TROCKEN - es wird nichts auf der Seite abgelegt"
echo " Beenden mit Strg-C"
echo "=============================================="
echo

while [ "$(date +%s)" -lt "$ende" ]; do
	durchgang=$(( durchgang + 1 ))

	echo "---- Durchgang $durchgang, $(date '+%H:%M:%S') ----"

	if ./spiegeln.sh; then
		geholt=$(( geholt + 1 ))
	else
		misslungen=$(( misslungen + 1 ))
		echo "Mindestens eine Quelle hat nicht geantwortet - es wird der letzte gute Stand geliefert."
	fi

	./einspielen.sh || echo "Die Einspielung ist misslungen, der naechste Durchgang versucht es erneut."

	if [ "$SPIEGELN" = "1" ] && [ -n "$(git status --porcelain daten 2>/dev/null)" ]; then
		git add daten >/dev/null 2>&1
		git commit -q -m "Stand $(date -u '+%Y-%m-%d %H:%M') UTC" >/dev/null 2>&1
		if git push -q >/dev/null 2>&1; then
			echo "Spiegel nachgefuehrt."
		else
			echo "Der Spiegel liess sich nicht schieben - die Seite hat die Daten trotzdem."
		fi
	fi

	echo

	naechster=$(( $(date +%s) + TAKT ))
	[ "$naechster" -lt "$ende" ] || break

	sleep "$TAKT"
done

echo "=============================================="
echo " Fertig: $durchgang Durchgaenge, $geholt mit Antwort der Quelle, $misslungen ohne."
echo "=============================================="
