#!/usr/bin/env bash
# AIKI Referat — installasjon/oppdatering med én kommando (Apple Silicon).
#
#   curl -fsSL https://aiki.as/referat | bash
#
# Laster ned siste utgivelse og installerer i Programmer. Nedlasting via curl
# får ikke macOS' karantene-flagg, så appen åpner uten Gatekeeper-dialogen.
# Installerer også kommandoen `aiki-referat` slik at oppdatering senere bare er:
#   aiki-referat update
set -euo pipefail

REPO="AIKI-AS/aiki-referat-dist"
BRANCH="main"
APP_NAME="AIKI Referat"
CLI_PATH="/usr/local/bin/aiki-referat"

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

echo "→ Finner siste utgivelse av $APP_NAME ..."
DMG_URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases" \
  | grep -o 'https://[^"]*aarch64[^"]*\.dmg' | head -1)

if [ -z "$DMG_URL" ]; then
  echo "❌ Fant ingen utgivelse. Kontakt AIKI (jonathan@aiki.as)."
  exit 1
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "→ Laster ned $(basename "$DMG_URL") ..."
curl -fL --progress-bar "$DMG_URL" -o "$TMP_DIR/app.dmg"

echo "→ Installerer i Programmer ..."
MOUNT_POINT=$(hdiutil attach "$TMP_DIR/app.dmg" -nobrowse | grep -oE '/Volumes/.+' | head -1)
if [ -z "$MOUNT_POINT" ]; then
  echo "❌ Kunne ikke åpne diskbildet."
  exit 1
fi

# Close a running instance so we can overwrite it.
osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
sleep 1

rm -rf "/Applications/$APP_NAME.app"
cp -R "$MOUNT_POINT/$APP_NAME.app" /Applications/
hdiutil detach "$MOUNT_POINT" -quiet
xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app" 2>/dev/null || true

# Install / refresh the `aiki-referat` command.
echo "→ Installerer kommandoen 'aiki-referat' ..."
CLI_CONTENT='#!/usr/bin/env bash
case "${1:-open}" in
  update)
    echo "Oppdaterer AIKI Referat ..."
    curl -fsSL "https://raw.githubusercontent.com/'"$REPO"'/'"$BRANCH"'/scripts/install.sh" | bash
    ;;
  open|"")
    open -a "'"$APP_NAME"'"
    ;;
  *)
    echo "Bruk: aiki-referat [update|open]"
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
  printf '{\n  "url": "%s",\n  "key": "%s"\n}\n' "$CALENDAR_URL" "$CALENDAR_KEY" \
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

echo "✅ $APP_NAME er installert. Åpner ..."
echo "   Oppdater senere med:  aiki-referat update"
open "/Applications/$APP_NAME.app"
