# ElAIne — EA NI local diagnostic LLM

**Version:** 0.1 · **Cost:** £0/month · **VRAM:** ~1GB · **Speed:** CPU-friendly small model

ElAIne is a local Ollama model tuned for FOG, C2k, SIMS, Windows, and Microsoft KB–style facts. It runs offline on a laptop with Ollama installed. Answers are terse and command-oriented.

## Quickstart

From this directory:

```bash
chmod +x scripts/build.sh ingest.sh
./scripts/build.sh
ollama run elaine "FOG clients stuck waiting for multicast"
```

## Add knowledge

Find a relevant MS KB URL, then:

```bash
./ingest.sh https://support.microsoft.com/kb/5021234
ollama create elaine -f Modelfile
```

`ingest.sh` expects **lynx**, **jq**, **ollama**, and optionally **monolith** (otherwise **wget**). The distill step assumes the model returns **valid JSON**; if `jq` fails, edit `$KBID.json` or retry.

## Legal / scope

Personal/internal use only. Do not distribute model weights trained on Microsoft content in violation of your policies. Distill KBs to facts and commands only.

## Why not Cursor?

Cursor does not ship with your site VLANs or “C2k cache broke on Tuesday” lore. ElAIne is an offline bundle you control.

## WENDY repo context

ElAIne is optional tooling beside the main ISO project. For the full documentation map ( **`README.md`**, **`CursorRef.md`**, **`MetaRef.md`**, **`docs/architecture.md`**, **`ROADMAP.md`**, and this tree), see **[Repository documentation](../README.md#repository-documentation)** in **`README.md`**.
