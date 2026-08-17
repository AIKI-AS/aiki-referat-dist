#!/usr/bin/env bash
# AIKI Meetings — installasjon/oppdatering med én kommando (Apple Silicon).
#
#   curl -fsSL https://referat.aiki.as/install | bash
#
# That address, not a raw.githubusercontent one: the code repo is private, so a
# GitHub URL answers a customer with 404. This command is copied into emails and
# onto the onboarding page, and a 404 there is the first thing a customer meets.
#
# Laster ned siste utgivelse og installerer i Programmer. Nedlasting via curl
# får ikke macOS' karantene-flagg, så nedlastingen i seg selv utløser ingen
# Gatekeeper-dialog — men appen må likevel være signert, fordi installasjonen
# under avviser en app Gatekeeper ikke godkjenner.
# Installerer også kommandoen `aiki-meetings` slik at oppdatering senere bare er:
#   aiki-meetings update
set -euo pipefail

REPO="AIKI-AS/aiki-referat-dist"
BRANCH="main"
APP_NAME="AIKI Meetings"
APP_IDENTIFIER="as.aiki.referat"
CLI_PATH="/usr/local/bin/aiki-meetings"
# Appen har hatt to navn før dette. En pilotmaskin kan fortsatt ha begge liggende,
# og to nesten like apper ved siden av hverandre er hvordan feil versjon startes.
LEGACY_APP_NAMES=("AKTI" "AIKI Referat")
LEGACY_CLI_PATHS=("/usr/local/bin/akti" "/usr/local/bin/aiki-referat")

# Zero-touch provisjonering (INTERN-400/404/406): AIKI gir kunden en install-
# kommando med nøkkel bakt inn, og appen konfigurerer seg selv:
#   curl -fsSL .../install.sh | bash -s -- --calendar-key <kundenøkkel> \
#     --vocab "AIKI,Beauty Technologies,Laila"
# Flagg: --no-model hopper over forhåndsnedlasting av NB-Whisper (~1 GB).
CALENDAR_KEY=""
CALENDAR_URL="https://referat.aiki.as"
SEED_MODEL=1
VOCAB=""
while [ $# -gt 0 ]; do
  case "$1" in
    --calendar-key) CALENDAR_KEY="${2:-}"; shift 2 ;;
    --server) CALENDAR_URL="${2:-}"; shift 2 ;;
    --no-model) SEED_MODEL=0; shift ;;
    --vocab) VOCAB="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

# Ingen nøkkel på kommandolinja: spør etter den i stedet. Det holder
# kommandoen kort og lik for alle kunder, og nøkkelen havner ikke i
# brukerens shell-historikk. Vi leser fra /dev/tty fordi stdin er opptatt
# av selve scriptet når dette kjøres via «curl | bash».
if [ -z "$CALENDAR_KEY" ] && [ -t 1 ] && { : < /dev/tty; } 2>/dev/null; then
  printf 'Lim inn nøkkelen du fikk av AIKI (Enter for å hoppe over): '
  if read -r CALENDAR_KEY < /dev/tty 2>/dev/null; then
    CALENDAR_KEY=$(printf '%s' "$CALENDAR_KEY" | tr -d '[:space:]')
  else
    CALENDAR_KEY=""
    echo
  fi
fi

if [ "$(uname -m)" != "arm64" ]; then
  echo "❌ $APP_NAME krever en Mac med Apple Silicon (M-serien)."
  exit 1
fi

MACOS_VERSION=$(sw_vers -productVersion)
MACOS_MAJOR=${MACOS_VERSION%%.*}
MACOS_REST=${MACOS_VERSION#*.}
MACOS_MINOR=${MACOS_REST%%.*}
if [ "$MACOS_MAJOR" -lt 14 ] || { [ "$MACOS_MAJOR" -eq 14 ] && [ "$MACOS_MINOR" -lt 4 ]; }; then
  echo "❌ $APP_NAME krever macOS 14.4 eller nyere (fant $MACOS_VERSION)."
  exit 1
fi

echo "→ Finner siste utgivelse av $APP_NAME ..."
DMG_URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep -o 'https://[^"]*/AIKI-Meetings\.dmg' | head -1 || true)

if [ -z "$DMG_URL" ]; then
  echo "❌ Fant ingen utgivelse. Kontakt AIKI (jonathan@aiki.as)."
  exit 1
fi

TMP_DIR=$(mktemp -d)
MOUNT_POINT=""
cleanup() {
  if [ -n "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "→ Laster ned $(basename "$DMG_URL") ..."
curl -fL --progress-bar "$DMG_URL" -o "$TMP_DIR/app.dmg"

# Integriteten til nedlastingen, uavhengig av Apple. Sjekksummen ligger ved
# siden av DMG-en i utgivelsen, og fanger både en manipulert fil og en som
# brakk underveis. Dette er den ene kontrollen som virker i dag, og den blir
# stående også etter at notariseringen er på plass.
echo "→ Kontrollerer nedlastingen ..."
EXPECTED_SHA=$(curl -fsSL "$DMG_URL.sha256" 2>/dev/null | awk '{print $1}' || true)
if [ -z "$EXPECTED_SHA" ]; then
  echo "❌ Utgivelsen mangler sjekksum. Kontakt AIKI (jonathan@aiki.as)."
  exit 1
fi
ACTUAL_SHA=$(shasum -a 256 "$TMP_DIR/app.dmg" | awk '{print $1}')
if [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
  echo "❌ Nedlastingen stemmer ikke med utgivelsen. Avbryter."
  exit 1
fi

echo "→ Installerer i Programmer ..."
MOUNT_POINT=$(hdiutil attach "$TMP_DIR/app.dmg" -nobrowse | grep -oE '/Volumes/.+' | head -1 || true)
if [ -z "$MOUNT_POINT" ]; then
  echo "❌ Kunne ikke åpne diskbildet."
  exit 1
fi

SOURCE_APP="$MOUNT_POINT/$APP_NAME.app"
if [ ! -d "$SOURCE_APP" ]; then
  echo "❌ Diskbildet inneholder ikke $APP_NAME.app."
  exit 1
fi
# Apple-signeringen er bestilt, men ikke på plass. Til den kommer er appen
# adhoc-signert, og da kan verken identiteten, codesign eller Gatekeeper
# svare det de skal — ikke fordi noe er galt, men fordi det ikke finnes et
# sertifikat å svare med. macOS selv blokkerer bare filer med karantene-
# flagget, og curl setter ikke det. Derfor kjører appen fint.
#
# Kontrollene står igjen som en ekte kontroll for den dagen sertifikatet er
# der: består Gatekeeper, kreves alt det andre også. Da skjerper skriptet seg
# selv, uten at noen må huske å endre det tilbake.
if spctl --assess --type execute "$SOURCE_APP" >/dev/null 2>&1; then
  FOUND_IDENTIFIER=$(codesign -dv --verbose=4 "$SOURCE_APP" 2>&1 | sed -n 's/^Identifier=//p' || true)
  if [ "$FOUND_IDENTIFIER" != "$APP_IDENTIFIER" ]; then
    echo "❌ Ugyldig app-identitet i utgivelsen."
    exit 1
  fi
  codesign --verify --deep --strict "$SOURCE_APP" >/dev/null 2>&1 \
    || { echo "❌ App-signaturen er ugyldig."; exit 1; }
  NOTARIZED=1
else
  echo "ℹ️  Denne utgaven er ikke Apple-notarisert ennå."
  echo "   Nedlastingen er kontrollert mot sjekksummen i utgivelsen."
  NOTARIZED=0
fi

# Kopier og verifiser før den eksisterende appen røres.
DEST_APP="/Applications/$APP_NAME.app"
NEW_APP="/Applications/.$APP_NAME.installing.$$.app"
OLD_APP="$TMP_DIR/previous.app"
rm -rf "$NEW_APP"
ditto "$SOURCE_APP" "$NEW_APP"
# En adhoc-signert app kan ikke kontrolleres med codesign, så kopien måles i
# stedet mot originalen. Det fanger nøyaktig det denne kontrollen fantes for:
# at ditto skrev noe annet enn det som lå i diskbildet.
if [ "$NOTARIZED" = "1" ]; then
  codesign --verify --deep --strict "$NEW_APP" >/dev/null 2>&1 \
    || { rm -rf "$NEW_APP"; echo "❌ Signaturen ble skadet under kopiering."; exit 1; }
else
  BIN_PATH="Contents/MacOS/$APP_NAME"
  SRC_BIN_SHA=$(shasum -a 256 "$SOURCE_APP/$BIN_PATH" 2>/dev/null | awk '{print $1}')
  NEW_BIN_SHA=$(shasum -a 256 "$NEW_APP/$BIN_PATH" 2>/dev/null | awk '{print $1}')
  if [ -z "$SRC_BIN_SHA" ] || [ "$SRC_BIN_SHA" != "$NEW_BIN_SHA" ]; then
    rm -rf "$NEW_APP"
    echo "❌ Appen ble skadet under kopiering."
    exit 1
  fi
fi

# Close a running instance so we can replace it atomically.
osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
sleep 1
if [ -e "$DEST_APP" ]; then
  mv "$DEST_APP" "$OLD_APP"
fi
if ! mv "$NEW_APP" "$DEST_APP"; then
  [ ! -e "$OLD_APP" ] || mv "$OLD_APP" "$DEST_APP"
  echo "❌ Installasjonen feilet; forrige versjon er gjenopprettet."
  exit 1
fi

# Install / refresh the `aiki-meetings` command.
echo "→ Installerer kommandoen 'aiki-meetings' ..."
CLI_CONTENT='#!/usr/bin/env bash
case "${1:-open}" in
  update)
    echo "Oppdaterer AIKI Meetings ..."
    curl -fsSL "https://raw.githubusercontent.com/'"$REPO"'/'"$BRANCH"'/scripts/install.sh" | bash
    ;;
  open|"")
    open -a "'"$APP_NAME"'"
    ;;
  *)
    echo "Bruk: aiki-meetings [update|open]"
    ;;
esac'
if [ -w "$(dirname "$CLI_PATH")" ] || [ ! -e "$(dirname "$CLI_PATH")" ]; then
  mkdir -p "$(dirname "$CLI_PATH")" 2>/dev/null || true
  printf '%s\n' "$CLI_CONTENT" > "$CLI_PATH" 2>/dev/null && chmod +x "$CLI_PATH" 2>/dev/null || NEED_SUDO=1
else
  NEED_SUDO=1
fi
if [ "${NEED_SUDO:-0}" = "1" ]; then
  # sudo reads the password from /dev/tty, so this works even via curl | bash.
  echo "  (krever administratorpassord én gang for å legge kommandoen i PATH)"
  sudo mkdir -p "$(dirname "$CLI_PATH")"
  printf '%s\n' "$CLI_CONTENT" | sudo tee "$CLI_PATH" >/dev/null
  sudo chmod +x "$CLI_PATH"
fi

if [ -n "$CALENDAR_KEY" ]; then
  mkdir -p "$HOME/aiki-referat"
  printf '{\n  "url": "%s",\n  "key": "%s",\n  "summary": { "provider": "server" }\n}\n' \
    "$CALENDAR_URL" "$CALENDAR_KEY" \
    > "$HOME/aiki-referat/calendar-server.json"
  chmod 600 "$HOME/aiki-referat/calendar-server.json"
  echo "→ Kalenderoppsett provisjonert (appen konfigurerer seg selv)"
fi

# Modell-seeding (INTERN-404): last ned NB-Whisper Large på forhånd slik at
# første oppstart ikke må vente på ~1 GB. Samme URL og filnavn som appen selv
# bruker (config.rs / whisper_engine.rs) — appen ser bare at modellen finnes.
MODELS_DIR="$HOME/Library/Application Support/as.aiki.referat/models"
MODEL_FILE="$MODELS_DIR/ggml-nb-whisper-large.bin"
MODEL_URL="https://huggingface.co/NbAiLab/nb-whisper-large/resolve/main/ggml-model-q5_0.bin"
if [ "$SEED_MODEL" = "1" ]; then
  MIN_BYTES=$((900 * 1024 * 1024))
  CUR_BYTES=$(stat -f%z "$MODEL_FILE" 2>/dev/null || echo 0)
  if [ "$CUR_BYTES" -ge "$MIN_BYTES" ]; then
    echo "→ NB-Whisper-modellen finnes allerede — hopper over nedlasting"
  else
    echo "→ Laster ned NB-Whisper Large (~1 GB) — dette tar noen minutter ..."
    mkdir -p "$MODELS_DIR"
    if curl -fL --progress-bar -C - "$MODEL_URL" -o "$MODEL_FILE.part" \
       && [ "$(stat -f%z "$MODEL_FILE.part" 2>/dev/null || echo 0)" -ge "$MIN_BYTES" ]; then
      mv "$MODEL_FILE.part" "$MODEL_FILE"
      echo "→ Modell klar — transkribering fungerer fra første sekund"
    else
      rm -f "$MODEL_FILE.part"
      echo "⚠️  Modellnedlasting feilet — appen laster den ned selv ved første bruk"
    fi
  fi
fi

# Ordliste-seeding (INTERN-406): kundens egennavn, komma-separert via --vocab.
if [ -n "$VOCAB" ]; then
  mkdir -p "$HOME/aiki-referat"
  printf '%s\n' "$VOCAB" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' \
    > "$HOME/aiki-referat/ordliste.txt" || true
  echo "→ Ordliste provisjonert ($(grep -c . "$HOME/aiki-referat/ordliste.txt") begreper)"
fi

# Rydd bort de gamle navnene. Gjøres etter at den nye appen står trygt i
# Programmer, slik at en feilet installasjon aldri etterlater maskinen tom.
for legacy in "${LEGACY_APP_NAMES[@]}"; do
  if [ -d "/Applications/$legacy.app" ]; then
    rm -rf "/Applications/$legacy.app" 2>/dev/null \
      || sudo -n rm -rf "/Applications/$legacy.app" 2>/dev/null || true
    echo "→ Fjernet gammel installasjon: $legacy"
  fi
done
for legacy in "${LEGACY_CLI_PATHS[@]}"; do
  [ -e "$legacy" ] || continue
  rm -f "$legacy" 2>/dev/null || sudo -n rm -f "$legacy" 2>/dev/null || true
done

echo "✅ $APP_NAME er installert. Åpner ..."
echo "   Oppdater senere med:  aiki-meetings update"
open "/Applications/$APP_NAME.app"
