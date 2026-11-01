#!/bin/zsh
# Writes Bite/Voice/VoiceRelay.plist, which Bite reaches this relay with: its address, and the
# token it lets Bite in by (the APP_TOKEN secret, kept in ~/.config/bite/voice-token). The plist
# stays out of git; a build without it has no voice input.
set -euo pipefail
here=${0:A:h}
python3 -I - "$here/../../Bite/Voice/VoiceRelay.plist" <<'PY'
import os, plistlib, sys
token = open(os.path.expanduser("~/.config/bite/voice-token")).read().strip()
if not token:
    sys.exit("No token in ~/.config/bite/voice-token")
with open(sys.argv[1], "wb") as f:
    plistlib.dump({"URL": "https://bite-voice.emblem-push.workers.dev", "Token": token}, f)
print("Wrote", os.path.normpath(sys.argv[1]))
PY
