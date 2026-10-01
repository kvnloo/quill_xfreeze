#!/usr/bin/env bash
# Puts a distinctive phrase into real text fields through the real Inserter and
# reports how many times it landed. Anything but "1x" is a bug.
#
#   Chrome  (web text area, contenteditable, input) — ignores Accessibility writes,
#           so the first insert pastes after a short wait and remembers that; the
#           second goes straight to the paste.
#   TextEdit (native) — takes the Accessibility write; the clipboard stays alone.
#
# Needs Accessibility for the built Quill.app and visible Chrome / TextEdit windows.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${QUILL_APP:-build/Quill.app}"
PHRASE="${PHRASE:-purple walrus xylophone}"
status=0

insert() {
  QUILL_SELFTEST_INSERT_TEXT="$PHRASE" QUILL_SELFTEST_DELAY=1 "$APP/Contents/MacOS/Quill" 2>&1 \
    | rg 'SELFTEST (METHOD|LANDED)' || true
}

check() {
  local label="$1" want_method="$2" result="$3"
  echo "── $label"
  echo "$result"
  echo "$result" | rg -q 'LANDED: 1x' || { echo "   ✗ expected exactly one copy"; status=1; }
  echo "$result" | rg -q "METHOD: $want_method" || { echo "   ✗ expected $want_method"; status=1; }
}

defaults delete com.freeze.quill axWriteIgnoredBy 2>/dev/null || true

for field in a b c; do
  open -a "Google Chrome" "file://$PWD/tests/fixtures/field.html#$field"
  sleep 2.5
  check "chrome #$field, first insert (learns)" clipboard "$(insert)"
  open -a "Google Chrome" "file://$PWD/tests/fixtures/field.html#$field"
  sleep 2.5
  check "chrome #$field, second insert (known)" clipboard "$(insert)"
done

cp tests/fixtures/native.txt build/native.txt
open -a TextEdit "$PWD/build/native.txt"
sleep 2.5
check "textedit (native)" accessibility "$(insert)"
osascript -e 'tell application "TextEdit" to close front document saving no' >/dev/null 2>&1 || true

exit $status
