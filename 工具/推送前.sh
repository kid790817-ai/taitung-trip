#!/usr/bin/env bash
# 台東票夾・推送前：獨立檢查（無 0-byte 空檔，支援直接執行與 pre-push hook）

_pick_py() {
    if [ -n "${PY:-}" ] && "$PY" -c 'import sys; sys.exit(sys.version_info < (3, 8))' >/dev/null 2>&1; then
        return 0
    fi
    for PY in python3 python; do
        "$PY" -c 'import sys; sys.exit(sys.version_info < (3, 8))' >/dev/null 2>&1 && return 0
    done
    PY=""
    return 1
}

_consume_hook_stdin() {
    if [ "${PRE_PUSH_HOOK:-0}" = "1" ] && [ ! -t 0 ]; then
        while read -r _lref _lsha _rref _rsha; do
            :
        done
    fi
}

_run_checks_py() {
    "$PY" -X utf8 - <<'PYEOF'
import os
import sys
from pathlib import Path

root = Path(".")
errors = []

for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in (".git", "__pycache__", "封存")]
    for fname in filenames:
        if fname in (".DS_Store", ".gitkeep"):
            continue
        p = Path(dirpath) / fname
        if p.is_file() and p.stat().st_size == 0:
            errors.append(f"[空檔] {p.as_posix()} 為 0-byte 空檔")

if errors:
    for e in errors:
        print(f"✗ {e}", file=sys.stderr)
    sys.exit(1)

print("台東票夾・推送前檢查：全數通過（無 0-byte 空檔）")
PYEOF
}

_run_checks_bash() {
    local empty
    empty=$(find . \( -name .git -o -name __pycache__ -o -name 封存 \) -prune -o -type f -empty ! -name '.DS_Store' ! -name '.gitkeep' -print)
    if [ -n "$empty" ]; then
        echo "✗ [空檔] 發現 0-byte 空檔：$empty" >&2
        return 1
    fi
    echo "台東票夾・推送前檢查：全數通過（無 0-byte 空檔）"
}

跑() {
    if _pick_py; then
        _run_checks_py
    else
        _run_checks_bash
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -u
    TOP=$(git rev-parse --show-toplevel 2>/dev/null) || exit 1
    cd "$TOP" || exit 1
    _consume_hook_stdin
    跑
fi
