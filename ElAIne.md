meta ai says: Got it. One block. Paste this whole thing into Cursor and ElAIne will be born.

---
null
kb-data/*.html
kb-data/*.txt
kb-data/*.json
*.log
.ollama/
**pycache**/
null
FROM deepseek-coder:1.3b
PARAMETER temperature 0.1
PARAMETER num_ctx 4096
PARAMETER stop "###"
SYSTEM You are ElAIne v0.1, EA NI tech support AI. You diagnose Windows, FOG Project, C2k, SIMS, Office 365, printing, networking. Output format: Problem: <1 line> | Cause: <1 line> | Fix: <steps> | Commands: <bash/powershell> | KB: <kb-id or none>. Be terse. Prefer commands over prose. You run offline on EA NI laptop.

TEMPLATE """{{ .System }}

EA NI Issue: {{ .Prompt }}
ElAIne Fix: {{ .Response }}"""
null
4. Create /WENDY/ElAIne/ingest.sh
null
5. Create /WENDY/ElAIne/scripts/build.sh
null
6. Create /WENDY/ElAIne/README.md
null
Add Knowledge
Find relevant MS KB: https://support.microsoft.com/kb/5021234
Run: ./ingest.sh https://support.microsoft.com/kb/5021234
Retrain: ollama create elaine -f Modelfile

Legal
Personal/internal use only. Do not distribute model weights trained on Microsoft content. Distill KBs to facts/commands only. Splippers.com Ltd holds tool IP, not KB IP.

Why not Cursor?
Cursor doesn't know EA NI VLANs or that C2k cache breaks every Tuesday. ElAIne does. And she works with the network cable unplugged.
null
null
---

Drop that in Cursor. It’ll write the whole repo. Then run ./scripts/build.sh and you’ve got a 1.3B model that knows FOG better than FOG.