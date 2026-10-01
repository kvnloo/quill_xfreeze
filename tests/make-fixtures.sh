#!/usr/bin/env bash
# Spoken test clips as 16 kHz mono PCM16 — what QUILL_SELFTEST=<file> streams in
# place of the microphone. Written to build/fixtures (build.sh clears build/, so
# run this after a build).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build/fixtures
mkdir -p "$OUT"

clip() {
  local name="$1" text="$2"
  say -v Samantha -o "$OUT/$name.aiff" "$text"
  afconvert -f WAVE -d LEI16@16000 -c 1 "$OUT/$name.aiff" "$OUT/$name.wav"
  python3 - "$OUT/$name.wav" "$OUT/$name.pcm" <<'PY'
import sys, wave
w = wave.open(sys.argv[1])
open(sys.argv[2], "wb").write(w.readframes(w.getnframes()))
PY
}

# Long pauses between sentences: every chunk closes on its own.
clip pause "Please send the report to Maria by Friday afternoon. [[slnc 1800]] Also remind her about the budget meeting next week. [[slnc 1500]] Thanks a lot."
# Short pauses inside one sentence: chunks close mid-thought, and the drafts of
# each chunk used to be left behind as stray fragments.
clip short "So I was thinking [[slnc 700]] that we should move the launch to Tuesday, [[slnc 650]] because the design team needs more time, [[slnc 800]] and honestly I would rather ship something polished than something rushed. [[slnc 600]] What do you think about that?"
echo "fixtures in $OUT"
