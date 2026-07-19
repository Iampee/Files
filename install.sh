#!/data/data/com.termux/files/usr/bin/sh
# YTdlpTermux-Lite v2.0 - Ultra-light 2026
set -eu
DL="$HOME/storage/downloads/Media"
CFG="$HOME/.config/yt-dlp"
BIN="$HOME/bin"
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

[ -n "${PREFIX:-}" ] || { echo "Run inside Termux"; exit 1; }
mkdir -p "$BIN" "$CFG"

# Storage - Android 13+ needs dialog
if [! -d "$HOME/storage" ]; then
  termux-setup-storage 2>/dev/null || true
  printf "Grant storage permission, then ENTER: "; read -r _
fi
mkdir -p "$DL"

# Only update apt cache if older than 24h
need_up=0
[ -f "$PREFIX/var/cache/apt/pkgcache.bin" ] || need_up=1
find "$PREFIX/var/cache/apt/pkgcache.bin" -mtime +0 2>/dev/null | grep -q. && need_up=1

missing=""
for p in yt-dlp ffmpeg termux-api termux-tools; do
  dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"
done

if [ -n "$missing" ]; then
  [ "$need_up" -eq 1 ] && pkg update -y
  pkg install -y $missing
else
  echo "* All packages already installed"
fi

# Minimal config
cat > "$CFG/config" <<'CONF'
--no-mtime
--no-overwrites
--continue
--no-warnings
--concurrent-fragments 4
--extractor-args youtube:player_client=android,ios
--embed-metadata
--embed-thumbnail
--embed-chapters
--sponsorblock-mark all
--merge-output-format mp4
-o ~/storage/downloads/Media/%(title).100B [%(id)s].%(ext)s
CONF

# Opener - see file below
cat > "$BIN/termux-url-opener" <<'OPENER'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
URL="${1:-}"
OUT="$HOME/storage/downloads/Media"
LOG="$HOME/.cache/yt-dlp-termux.log"
mkdir -p "$OUT"

notify(){ echo "[$(date +%F\ %T)] $1" >> "$LOG"
  if command -v termux-notification >/dev/null 2>&1; then
    termux-notification --title "YTdlp" --content "$1" 2>/dev/null || true
  elif command -v termux-toast >/dev/null 2>&1; then termux-toast "$1" 2>/dev/null || true; fi; }

[[ "$URL" =~ ^https?:// ]] || { notify "❌ No URL"; exit 1; }

termux-wake-lock 2>/dev/null || true
cd "$OUT"
echo ""; echo "URL: $URL"; echo "──────────────────"
echo " 1) 🎬 MP4 1080p (best)"; echo " 2) 📱 MP4 720p (fast)"
echo " 3) 🎵 MP3 192k"; echo " 4) 🎧 M4A best"; echo " 5) 🚀 Video + MP3"
echo "──────────────────"; printf "Select [1-5]: "; read -r CH; CH=${CH:-1}
NUM=$(echo "$CH" | tr -cd '0-9' | head -c1); [ -z "$NUM" ] && NUM=1

case "$NUM" in
  1) ARGS='-f bv*[height<=1080][ext=mp4]+ba/b[height<=1080]/best --merge-output-format mp4' ;;
  2) ARGS='-f bv*[height<=720][ext=mp4]+ba/b[height<=720]/best --merge-output-format mp4' ;;
  3) ARGS='-x --audio-format mp3 --audio-quality 192K -f ba/bestaudio' ;;
  4) ARGS='-x --audio-format m4a --audio-quality 0 -f ba[ext=m4a]/bestaudio' ;;
  5) ARGS='-k -x --audio-format mp3 --audio-quality 192K -f bv*+ba/best --merge-output-format mp4' ;;
  *) ARGS='-f bv*+ba/best --merge-output-format mp4' ;;
esac

COMMON='--no-playlist --concurrent-fragments 4 --http-chunk-size 10M --extractor-args youtube:player_client=android,ios --no-mtime'
# shellcheck disable=SC2086
if yt-dlp $COMMON $ARGS "$URL"; then
  notify "✅ Saved: $(ls -t "$OUT" | head -n1)"; termux-vibrate -d 300 2>/dev/null || true
else notify "❌ Failed"; termux-wake-unlock 2>/dev/null || true; exit 1; fi
termux-wake-unlock 2>/dev/null || true
read -p "Press ENTER to close" _
OPENER

chmod +x "$BIN/termux-url-opener"
echo "Done: yt-dlp $(yt-dlp --version) | Output: $DL"