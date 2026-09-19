#!/usr/bin/env bash
# claude-code イメージのスモークテスト。docker build 後、非 root（65532:65532）で
# `docker run --rm -u 65532:65532 <image> bash /path/to/this` として呼ぶ想定。
#
# この一覧は claude-code/Dockerfile の RUN ブロックと対で手動維持する。ツールを
# 足したらここにも check を足すこと。
#
# 各ツールは存在確認（command -v）だけでは動的リンク破損を検出できないため、
# 実際に --version / --help を実行する。1 項目でも落ちたら非ゼロで終わる。
set -euo pipefail

fail=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok: ${desc}"
  else
    echo "FAIL: ${desc}" >&2
    fail=1
  fi
}

check "claude --version" claude --version
check "gh --version" gh --version
check "spin --version" spin --version
check "kubectl version --client" kubectl version --client
check "helm version" helm version
check "logcli --version" logcli --version
check "go version" go version
check "node --version" node --version
check "npm --version" npm --version
check "pnpm --version" pnpm --version
check "cargo --version" cargo --version
check "rustc --version" rustc --version
check "python3 --version" python3 --version
check "pip --version" pip --version
check "jq --version" jq --version
check "git --version" git --version
check "rg --version" rg --version
check "make --version" make --version
check "setpriv --help" setpriv --help
check "mkfs.ext4 -V" mkfs.ext4 -V
check "curl --version" curl --version
check "openssl version" openssl version
check "unzip -v" unzip -v
check "xz --version" xz --version

# gcc は Dockerfile 内のどの RUN でもコンパイルに使われず一度も exercise されない
# ため、--version ではなく実コンパイルまでやる（非 root で /tmp に書けることも
# ついでに確認できる）。mktemp の失敗も他の check と同じ fail-soft 扱いにする —
# ここで即死すると以降の check が一切走らず、他の check と挙動が一貫しない。
cc_probe="$(mktemp /tmp/cc-probe.XXXXXX 2>/dev/null)" || cc_probe=""
if [ -z "${cc_probe}" ]; then
  echo "FAIL: gcc probe mktemp failed" >&2
  fail=1
elif echo 'int main(){return 0;}' | gcc -x c - -o "${cc_probe}" && "${cc_probe}"; then
  echo "ok: gcc can compile and run a probe binary"
else
  echo "FAIL: gcc probe compile/run failed" >&2
  fail=1
fi
rm -f "${cc_probe}"

# 非 root（USER 65532）で動いていること
if [ "$(id -u)" = "65532" ]; then
  echo "ok: uid is 65532"
else
  echo "FAIL: running as uid $(id -u), expected 65532" >&2
  fail=1
fi

# rust の wasm32-wasip1 ターゲット
if rustup target list --installed | grep -qx wasm32-wasip1; then
  echo "ok: wasm32-wasip1 target installed"
else
  echo "FAIL: wasm32-wasip1 target missing" >&2
  fail=1
fi

# setpriv --reuid（util-linux 版であること）
if setpriv --help 2>&1 | grep -q -- '--reuid'; then
  echo "ok: setpriv has --reuid"
else
  echo "FAIL: setpriv missing --reuid" >&2
  fail=1
fi

# PyYAML が import できること
if python3 -c "import yaml" >/dev/null 2>&1; then
  echo "ok: python3 can import yaml"
else
  echo "FAIL: python3 cannot import yaml" >&2
  fail=1
fi

# setuid/setgid ファイルの簡易チェック（回帰検出の補助）。非 root（65532）では
# /root のような root 専有ディレクトリを走査できず Permission denied で find が
# 非ゼロ終了する（想定内、pipefail の対象から外し件数だけを見る）ため、これは
# 「読めた範囲に 0 件」の確認でしかなく網羅ではない。網羅の保証は
# claude-code/Dockerfile の USER 直前にある root 権限の RUN assert 側にある。
setuid_count=$(find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | wc -l) || true
if [ "${setuid_count}" -eq 0 ]; then
  echo "ok: no setuid/setgid files in the readable (non-root) range"
else
  echo "FAIL: ${setuid_count} setuid/setgid file(s) found in the readable range" >&2
  fail=1
fi

exit "${fail}"
