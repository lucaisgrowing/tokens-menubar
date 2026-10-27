#!/bin/bash
# Run only on a disposable macOS runner: renders the unmodified release binary.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:?path to released TokensBar.app}"
BIN="$APP/Contents/MacOS/TokensBar"
OUT="${2:-readme-snapshots}"
mkdir -p "$OUT" "$HOME/.config/tokens-menubar" "$HOME/.cargo/bin"
# This setup never reads a user's credentials or contacts the production API.
[[ ! -e "$HOME/.config/tokens-menubar/config.json" ]]
[[ ! -e "$HOME/.cargo/bin/tokens" ]]
cat > "$HOME/.config/tokens-menubar/config.json" <<'JSON'
{"username":"demo-user","apiBase":"http://127.0.0.1:8765","language":"en","menuBarRank":"all"}
JSON
cat > "$HOME/.cargo/bin/tokens" <<'SH'
#!/bin/bash
# A sample dry-run report, not the real tokens CLI.
[[ "$*" == *"--dry-run"* ]] || exit 1
case "$*" in
  *--week*) printf 'Total tokens: 48,200,000\nTotal cost: $60.25\n';;
  *--month*) printf 'Total tokens: 163,800,000\nTotal cost: $204.75\n';;
  *) printf 'Total tokens: 6,941,007\nTotal cost: $6.55\n';;
esac
SH
chmod +x "$HOME/.cargo/bin/tokens"
python3 Tools/readme-fixture-server.py > "$OUT/fixture-server.log" 2>&1 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null || true; rm -f "$HOME/.config/tokens-menubar/config.json" "$HOME/.cargo/bin/tokens"' EXIT
for i in {1..20}; do
  curl -fsS http://127.0.0.1:8765/api/users/demo-user > /dev/null && break
  sleep 0.5
done
"$BIN" --dump --lang en > "$OUT/sample-data-dump.txt"
for LANG in en zh; do
  DIR="$OUT/$LANG"
  mkdir -p "$DIR"
  "$BIN" --panel-png "$DIR/menu.png" --lang "$LANG"
  "$BIN" --panel-png "$DIR/menu-dark.png" dark --lang "$LANG"
  "$BIN" --panel-png "$DIR/panel-actions.png" menu --lang "$LANG"
  "$BIN" --panel-png "$DIR/panel-actions-dark.png" menu dark --lang "$LANG"
  "$BIN" --chart-png "$DIR/chart-today-tokens.png" today tokens --lang "$LANG"
  "$BIN" --chart-png "$DIR/chart-lifetime-cost.png" lifetime cost dark --lang "$LANG"
  "$BIN" --contrib-png "$DIR/contributions.png" models --lang "$LANG"
  mkdir -p "$OUT/states/$LANG"
  "$BIN" --panel-png "$OUT/states/$LANG/hover-submit.png" hit 7 --lang "$LANG"
  "$BIN" --panel-png "$OUT/states/$LANG/hover-submit-dark.png" dark hit 7 --lang "$LANG"
  "$BIN" --panel-png "$OUT/states/$LANG/notice-info-dark.png" dark notice info Sample --lang "$LANG"
  "$BIN" --panel-probe "$OUT/states/$LANG/panel-probe.png" --lang "$LANG" > "$OUT/states/$LANG/panel-probe.txt"
  "$BIN" --share-png "$OUT/states/$LANG/share-card.png" --lang "$LANG"
  for PNG in "$DIR"/*.png; do
    [[ -s "$PNG" ]]
    sips -g pixelWidth -g pixelHeight "$PNG"
  done
done
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" > "$OUT/release-version.txt"
shasum -a 256 "$BIN" > "$OUT/release-binary-sha256.txt"
sw_vers > "$OUT/macos-version.txt"
