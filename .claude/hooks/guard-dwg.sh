#!/usr/bin/env bash
# PreToolUse + PostToolUse hook — Write|Edit
# Blocks writes to .dwg files or Mac shared paths (Parallels crash risk).
set -euo pipefail

FILE=$(echo "$CLAUDE_TOOL_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    p = d.get('file_path', '')
    print(p)
except Exception:
    print('')
" 2>/dev/null || echo "")

[ -z "$FILE" ] && exit 0

# Block .dwg writes
if [[ "$FILE" == *.dwg || "$FILE" == *.DWG ]]; then
  echo '{"continue": false, "stopReason": "BLOCKED: Writing .dwg files directly is not allowed. DWG files are managed by AutoCAD only."}'
  exit 2
fi

# Block Mac shared paths (Parallels crash risk)
if [[ "$FILE" == /Volumes/* || "$FILE" == //Mac/* || "$FILE" == *\\\\Mac\\* || "$FILE" == Z:\\* || "$FILE" == z:\\* ]]; then
  echo '{"continue": false, "stopReason": "BLOCKED: Writing to Mac shared path is not allowed (Parallels DWG corruption risk). Use Windows local drive only."}'
  exit 2
fi

exit 0
