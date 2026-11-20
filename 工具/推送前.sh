#!/usr/bin/env bash
# 台東票夾・推送前：獨立檢查（支援直接執行與 pre-push hook）
# 這格推上 main 就是更新公開網頁，所以擋三件事：
#   1. 0-byte 空檔
#   2. 多出來的檔（這格只放上鎖版成品，原稿、票券照片、筆記一律不准進來）
#   3. index.html 沒上鎖（沒有加密內容、還留著範本記號、或直接看得到行程文字）
# hook 模式會檢查「這次要推上去的每一次存檔」，不只最新那一份；放錯再刪掉也擋得到。
# 沒有 Python 就不放行（寧可擋下來，也不要把沒上鎖的推出去）。

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

_run_checks_py() {
    HOOK_REFS="$1" "$PY" -X utf8 - <<'PYEOF'
import os
import re
import subprocess
import sys

ALLOWED = {
    ".gitignore", "AGENTS.md", "日誌.md", "工具/推送前.sh",
    "index.html", "manifest.webmanifest",
    "apple-touch-icon.png", "icon-192.png", "icon-512.png",
}
ZERO = "0" * 40


def git(*a, binary=False):
    r = subprocess.run(["git", "-c", "core.quotepath=false", *a], capture_output=True)
    if r.returncode:
        sys.exit("✗ git %s 失敗：%s" % (" ".join(a), r.stderr.decode("utf-8", "replace")))
    return r.stdout if binary else r.stdout.decode("utf-8")


def check_index(data, where):
    errs = []
    t = data.decode("utf-8", "replace")
    if "PBKDF2" not in t or "AES-GCM" not in t:
        errs.append(f"[沒上鎖] {where}：找不到解鎖程式（PBKDF2／AES-GCM），這不是上鎖版")
    for mark in ("__CT__", "__SALT__", "__IV__", "__ITER__"):
        if mark in t:
            errs.append(f"[沒上鎖] {where}：還留著範本記號 {mark}，上鎖沒跑完")
    longest = max((len(m) for m in re.findall(r"[A-Za-z0-9+/=]{1000,}", t)), default=0)
    if longest < 10000:
        errs.append(f"[沒上鎖] {where}：找不到加密後的內容（最長一段只有 {longest} 字）")
    visible = re.sub(r"<script.*?</script>|<style.*?</style>", "", t, flags=re.S | re.I)
    visible = re.sub(r"<[^>]+>", " ", visible)
    visible = re.sub(r"\s+", "", visible)
    if len(visible) > 600:
        errs.append(f"[沒上鎖] {where}：不用密碼就看得到 {len(visible)} 個字（上鎖版只有密碼頁，大約一兩百字）")
    return errs


def check_files(names, read, where):
    errs = []
    for n in sorted(names):
        if n not in ALLOWED:
            errs.append(f"[多出來的檔] {where}：{n}（這格只放上鎖版成品，原稿和其他東西放 ../爸媽台東/）")
            continue
        data = read(n)
        if len(data) == 0:
            errs.append(f"[空檔] {where}：{n} 是 0-byte 空檔")
        elif n == "index.html":
            errs += check_index(data, f"{where} 的 index.html")
    if "index.html" not in names:
        errs.append(f"[少檔] {where}：沒有 index.html")
    return errs


errors = []
refs = [l.split() for l in os.environ.get("HOOK_REFS", "").splitlines() if l.strip()]
if refs:
    commits = []
    for lref, lsha, rref, rsha in refs:
        if lsha == ZERO:          # 刪遠端分支，沒有新內容
            continue
        rng = [lsha, "--not", "--remotes"] if rsha == ZERO else [f"{rsha}..{lsha}"]
        commits += git("rev-list", *rng).split()
    for c in dict.fromkeys(commits):
        names = set(git("ls-tree", "-r", "--name-only", c).splitlines())
        errors += check_files(names, lambda n, c=c: git("show", f"{c}:{n}", binary=True), f"存檔 {c[:7]}")
else:
    tracked = git("ls-files", "--cached", "--others", "--exclude-standard").splitlines()
    names = {n for n in tracked if os.path.isfile(n)}
    errors += check_files(names, lambda n: open(n, "rb").read(), "現在的檔案")

if errors:
    for e in dict.fromkeys(errors):
        print(f"✗ {e}", file=sys.stderr)
    print("✗ 台東票夾・推送前檢查沒過，這次不推。", file=sys.stderr)
    sys.exit(1)

print("台東票夾・推送前檢查：全數通過（只有上鎖版成品、沒有空檔）")
PYEOF
}

跑() {
    local refs=""
    if [ "${PRE_PUSH_HOOK:-0}" = "1" ] && [ ! -t 0 ]; then
        refs=$(cat)
    fi
    if ! _pick_py; then
        echo "✗ 找不到 Python 3.8 以上，沒辦法確認有沒有上鎖，這次不推。" >&2
        return 1
    fi
    _run_checks_py "$refs"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -u
    TOP=$(git rev-parse --show-toplevel 2>/dev/null) || exit 1
    cd "$TOP" || exit 1
    跑
fi
