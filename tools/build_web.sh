#!/usr/bin/env bash
# Exports the web build to build/web/. Thread support is off, so the output
# runs on any static host (itch.io, nginx, GitHub Pages) without special headers.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot4 || echo "$HOME/bin/godot4")}"
mkdir -p build/web
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --export-release "Web" build/web/index.html

# Godot 4.4's web audio loops a sound by starting a fresh copy from JavaScript
# when the last one ends: a short gap every time round, and the copy forgets
# its pitch. That's fine for a three-minute song but makes a one-second engine
# loop stutter. Patch the exported player to use the browser's own gapless
# looping (AudioBufferSourceNode.loop) for looping sounds instead.
python3 - build/web/index.js <<'PY'
import sys
path = sys.argv[1]
js = open(path, encoding="utf-8").read()
old = "this._source.buffer=this.getSample().getAudioBuffer();"
new = (old + "{const s=this.getSample();if(s.loopMode===\"forward\"){const b=this._source.buffer;"
       "this._source.loop=true;this._source.loopStart=s.loopBegin/b.sampleRate;"
       "this._source.loopEnd=s.loopEnd>s.loopBegin?Math.min(s.loopEnd/b.sampleRate,b.duration):0}}")
count = js.count(old)
if count != 2:
    sys.exit("build_web.sh: Godot's web audio code changed (%d matches); check whether the loop patch is still needed" % count)
open(path, "w", encoding="utf-8").write(js.replace(old, new))
print("patched web audio: native gapless loops")
PY
ls -la build/web
