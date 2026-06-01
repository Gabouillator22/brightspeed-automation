#!/usr/bin/env bash
# PostToolUse hook — Edit|Write
# Runs ruff on Python files and paren-balance check on .lsp files.
set -euo pipefail

FILE=$(echo "$CLAUDE_TOOL_RESULT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    p = d.get('tool_input', {}).get('file_path') or d.get('tool_response', {}).get('filePath', '')
    print(p)
except Exception:
    print('')
" 2>/dev/null || echo "")

[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

case "$FILE" in
  *.py)
    if command -v ruff &>/dev/null; then
      ruff format "$FILE" --quiet 2>/dev/null || true
      ruff check "$FILE" --fix --quiet 2>/dev/null || true
    fi
    ;;
  *.lsp)
    # Paren balance check: count ( vs )
    OPENS=$(grep -o '(' "$FILE" | wc -l)
    CLOSES=$(grep -o ')' "$FILE" | wc -l)
    if [ "$OPENS" -ne "$CLOSES" ]; then
      echo "WARN: $FILE has unbalanced parentheses (opens=$OPENS, closes=$CLOSES)"
    fi
    ;;
esac

exit 0
