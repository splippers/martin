#!/usr/bin/env bash
set -euo pipefail

echo "==> ElAIne Bootstrap"
if ! command -v ollama >/dev/null 2>&1; then
  echo "Installing Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
fi
command -v monolith >/dev/null 2>&1 || echo "Optional: cargo install monolith (for ingest.sh HTML capture)"
command -v lynx >/dev/null 2>&1 || echo "Install lynx: sudo apt install lynx -y"
command -v jq >/dev/null 2>&1 || echo "Install jq: sudo apt install jq -y"

echo "==> Pulling base model..."
ollama pull deepseek-coder:1.3b

echo "==> Creating ElAIne..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ollama create elaine -f "$ROOT/Modelfile"

echo "==> Test run:"
ollama run elaine "FOG multicast not sending UDP"
echo "==> Done. Use: ollama run elaine \"<your EA NI issue>\""
echo "==> Ingest KB (from $ROOT): ./ingest.sh https://support.microsoft.com/kb/5021234"
