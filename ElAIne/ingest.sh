#!/usr/bin/env bash
set -euo pipefail

# ElAIne KB ingest — personal/internal use only. Do not redistribute Microsoft content.
# Deps: monolith or wget, lynx, jq, ollama. Example: cargo install monolith; sudo apt install -y lynx jq

URL="${1:-}"
if [ -z "$URL" ]; then
  echo "Usage: ./ingest.sh <microsoft-kb-url>" >&2
  exit 1
fi

KBID=$(echo "$URL" | grep -oEi 'kb[0-9]+' | head -1 | tr 'A-Z' 'a-z')
if [ -z "$KBID" ]; then
  echo "Could not derive KB id from URL (expected kbNNNNNN)." >&2
  exit 1
fi

OUTDIR="./kb-data"
mkdir -p "$OUTDIR"

echo "[1/4] Capturing $KBID..."
if command -v monolith >/dev/null 2>&1; then
  monolith "$URL" -o "$OUTDIR/${KBID}.html" 2>/dev/null || wget -qO "$OUTDIR/${KBID}.html" "$URL"
else
  wget -qO "$OUTDIR/${KBID}.html" "$URL"
fi

echo "[2/4] Extracting text..."
lynx -dump -nolist -width=1000 "$OUTDIR/${KBID}.html" \
  | sed '/^References$/,$d' \
  | sed '/^Applies to/,$d' > "$OUTDIR/${KBID}.txt"

echo "[3/4] Distilling with local LLM..."
TEXT=$(tr '\n' ' ' <"$OUTDIR/${KBID}.txt" | head -c 8000)
DISTILL_PROMPT="You are a KB parser. Extract from this Microsoft KB into JSON with keys: problem, symptoms, cause, resolution_steps, commands, applies_to. Return ONLY valid JSON. No prose. Text: ${TEXT}"
ollama run deepseek-coder:1.3b "$DISTILL_PROMPT" >"$OUTDIR/${KBID}.json"

echo "[4/4] Appending to training-data.jsonl..."
jq -r --arg kbid "$KBID" '
  . | "{\"prompt\": \"MS " + $kbid + ": " + .problem + " | Symptoms: " + ((.symptoms // []) | join("; ")) + "\", \"completion\": \"Cause: " + .cause + " | Fix: " + (.resolution_steps | tostring) + " | Commands: " + ((.commands // []) | join(" && ") | tostring) + " | Applies: " + (.applies_to | tostring) + "\"}"
' "$OUTDIR/${KBID}.json" >>training-data.jsonl

echo "Done. $KBID added. Total lines: $(wc -l <training-data.jsonl)"
echo "Retrain: ollama create elaine -f Modelfile"
