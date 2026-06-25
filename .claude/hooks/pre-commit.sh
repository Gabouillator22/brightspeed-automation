#!/usr/bin/env bash
# Pre-commit gate: lint + type check + tests.
# Installed as .git/hooks/pre-commit by setup (see below).
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

echo "=== pre-commit: running checks ==="

# 1. Ruff lint on staged Python files
STAGED_PY=$(git diff --cached --name-only --diff-filter=ACM | grep '\.py$' || true)
if [ -n "$STAGED_PY" ]; then
  echo "--- ruff ---"
  if command -v ruff &>/dev/null; then
    echo "$STAGED_PY" | xargs ruff check --quiet 2>/dev/null || {
      echo "FAIL: ruff found issues. Run: ruff check --fix"
      exit 1
    }
  else
    echo "SKIP: ruff not found in PATH"
  fi
fi

# 2. Paren balance on staged .lsp files
STAGED_LSP=$(git diff --cached --name-only --diff-filter=ACM | grep '\.lsp$' || true)
if [ -n "$STAGED_LSP" ]; then
  echo "--- lsp paren balance ---"
  FAIL=0
  while IFS= read -r f; do
    OPENS=$(grep -o '(' "$f" | wc -l)
    CLOSES=$(grep -o ')' "$f" | wc -l)
    if [ "$OPENS" -ne "$CLOSES" ]; then
      echo "FAIL: $f unbalanced parens (opens=$OPENS closes=$CLOSES)"
      FAIL=1
    fi
  done <<< "$STAGED_LSP"
  [ "$FAIL" -eq 1 ] && exit 1
fi

# 3. Guard: no hardcoded absolute paths in staged files
echo "--- hardcoded path check ---"
STAGED_ALL=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(lsp|py)$' || true)
if [ -n "$STAGED_ALL" ]; then
  FOUND=$(echo "$STAGED_ALL" | xargs grep -lE 'C:\\\\Users\\\\|/Users/[^/]+/Desktop|C:/Users/' 2>/dev/null || true)
  if [ -n "$FOUND" ]; then
    echo "FAIL: hardcoded absolute paths found in:"
    echo "$FOUND"
    exit 1
  fi
fi

# 4. Guard: no secrets (PAT patterns)
echo "--- secret scan ---"
if [ -n "$STAGED_ALL" ]; then
  SECRETS=$(echo "$STAGED_ALL" | xargs grep -lE 'ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{82}' 2>/dev/null || true)
  if [ -n "$SECRETS" ]; then
    echo "FAIL: possible GitHub token found in:"
    echo "$SECRETS"
    exit 1
  fi
fi

# 5. pytest (only if tests exist and pytest available)
if command -v pytest &>/dev/null && [ -d "05_toolkit/python/tests" ]; then
  echo "--- pytest ---"
  pytest 05_toolkit/python/tests/ -q --tb=short 2>/dev/null || {
    echo "FAIL: tests failed."
    exit 1
  }
fi

echo "=== pre-commit: all checks passed ==="
exit 0
