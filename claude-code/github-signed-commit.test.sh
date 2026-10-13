#!/usr/bin/env bash
# github-signed-commit.sh のテスト。claude-code イメージの中で非 root（65532）として
#
#   docker run --rm -u 65532:65532 -v .../github-signed-commit.test.sh:/tmp/t.sh:ro <image> bash /tmp/t.sh
#
# のように呼ぶ想定（SIGNED_COMMIT で対象を差し替えられる）。ネットワークには出ない:
# `gh` は PATH の先頭に置いた偽物で、受け取った blob / tree を記録して決まった sha を返す。
# origin はローカルの bare リポジトリ。argo-tools/github-signed-commit.sh は CI の cmp で
# 同一と確かめているので、ここでは claude-code 側だけを見る。
#
# 見ているのは「staged の変更から」コミットを作るという約束: blob の中身とモードは
# index のものであって、作業ツリーのものではない。1 項目でも落ちたら非ゼロで終わる。
set -euo pipefail

SC="${SIGNED_COMMIT:-/usr/local/bin/github-signed-commit.sh}"
root="$(mktemp -d)"
trap 'rm -rf "${root}"' EXIT
export HOME="${root}/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "${HOME}" "${root}/bin"
git config --global user.email test@example.invalid
git config --global user.name test
git config --global init.defaultBranch main

cat > "${root}/bin/gh" <<'STUB'
#!/bin/sh
# 偽の gh。呼び出しを $GH_STUB_LOG に残し、POST された本文を保存する。
set -eu
echo "gh $*" >> "$GH_STUB_LOG/calls"
case "$*" in
  *"-X POST"*"git/blobs"*)
    n=$(find "$GH_STUB_LOG" -name 'blob-*.json' | wc -l)
    cat > "$GH_STUB_LOG/blob-$n.json"
    echo "blob$n" ;;
  *"-X POST"*"git/trees"*) cat > "$GH_STUB_LOG/tree.json"; echo tree1 ;;
  *"-X POST"*"git/commits"*) cat > "$GH_STUB_LOG/commit.json"; echo commit1 ;;
  *"-X PATCH"*) cat > /dev/null ;;
  *"git/ref/heads/"*) echo "$GH_STUB_HEAD" ;;
  *"git/commits/"*) echo basetree ;;
  *) echo "gh stub: unexpected call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "${root}/bin/gh"

fail=0
ok() { echo "ok: $1"; }
ng() { echo "FAIL: $1" >&2; fail=1; }

# new_repo <name>: origin と、そこから clone した作業ツリーを作り、作業ツリーに cd する。
# 初期状態: plain.txt / exec.sh（実行ビット付き）/ partial.txt
new_repo() {
  local d="${root}/$1"
  git init -q --bare "${d}/origin.git"
  git clone -q "${d}/origin.git" "${d}/w" 2>/dev/null
  cd "${d}/w"
  echo plain > plain.txt
  printf '#!/bin/sh\n' > exec.sh && chmod +x exec.sh
  echo base > partial.txt
  git add -A && git commit -qm init && git push -q origin HEAD:main 2>/dev/null
  git remote set-head origin main
  export GH_STUB_LOG="${d}/log" GH_STUB_HEAD
  GH_STUB_HEAD="$(git rev-parse HEAD)"
  mkdir -p "${GH_STUB_LOG}"
}

# run_sc: 対象を実行する。成功しなければ出力を見せて 1 を返す。
run_sc() {
  local out
  if out="$(PATH="${root}/bin:${PATH}" GH_TOKEN=stub sh "${SC}" -r o/r -b main -m msg 2>&1)"; then
    return 0
  fi
  echo "${out}" >&2
  return 1
}

# entry <path>: tree.json の該当エントリ（mode と blob 番号）を "mode sha" で出す。
entry() { jq -r --arg p "$1" '.tree[] | select(.path == $p) | "\(.mode) \(.sha)"' "${GH_STUB_LOG}/tree.json"; }
# blob_of <path>: そのパスに送られた blob の中身。
blob_of() {
  local sha
  sha="$(jq -r --arg p "$1" '.tree[] | select(.path == $p) | .sha' "${GH_STUB_LOG}/tree.json")"
  jq -r .content "${GH_STUB_LOG}/blob-${sha#blob}.json" | base64 -d
}

# --- 追加・変更・削除 ----------------------------------------------------------
new_repo basic
echo changed > plain.txt
echo new > added.txt
git rm -q partial.txt
git add plain.txt added.txt
if run_sc; then
  [ "$(blob_of plain.txt)" = changed ] && ok "modified file is sent" || ng "modified file content: $(blob_of plain.txt)"
  [ "$(blob_of added.txt)" = new ] && [ "$(entry added.txt | cut -d' ' -f1)" = 100644 ] \
    && ok "added file is sent as 100644" || ng "added file: $(entry added.txt)"
  [ "$(jq -c '.tree[] | select(.path == "partial.txt") | .sha' "${GH_STUB_LOG}/tree.json")" = null ] \
    && ok "deleted file is sent with sha null" || ng "deleted file entry missing"
  [ "$(jq -r .parents[0] "${GH_STUB_LOG}/commit.json")" = "${GH_STUB_HEAD}" ] \
    && ok "commit parent is the remote head" || ng "commit parent: $(jq -c .parents "${GH_STUB_LOG}/commit.json")"
else
  ng "basic add/modify/delete run failed"
fi

# --- 部分的に stage した変更 ----------------------------------------------------
new_repo partial
echo staged > partial.txt
git add partial.txt
echo unstaged >> partial.txt
if run_sc; then
  [ "$(blob_of partial.txt)" = staged ] && ok "partially staged file sends the staged content" \
    || ng "partially staged file sent the working tree: $(blob_of partial.txt | tr '\n' '|')"
else
  ng "partial staging run failed"
fi

# --- 実行ビット -----------------------------------------------------------------
new_repo mode-off
chmod -x exec.sh
git add exec.sh
if run_sc; then
  [ "$(entry exec.sh | cut -d' ' -f1)" = 100644 ] && ok "staged chmod -x is sent as 100644" \
    || ng "staged chmod -x sent as $(entry exec.sh | cut -d' ' -f1)"
else
  ng "chmod -x run failed"
fi

new_repo mode-on
chmod +x plain.txt
git add plain.txt
if run_sc; then
  [ "$(entry plain.txt | cut -d' ' -f1)" = 100755 ] && ok "staged chmod +x is sent as 100755" \
    || ng "staged chmod +x sent as $(entry plain.txt | cut -d' ' -f1)"
else
  ng "chmod +x run failed"
fi

# index では実行ビットなし、作業ツリーでだけ付けた（stage していない）。
new_repo mode-unstaged
echo changed > plain.txt
git add plain.txt
chmod +x plain.txt
if run_sc; then
  [ "$(entry plain.txt | cut -d' ' -f1)" = 100644 ] && ok "unstaged chmod +x is not sent" \
    || ng "unstaged chmod +x sent as $(entry plain.txt | cut -d' ' -f1)"
else
  ng "unstaged chmod +x run failed"
fi

# --- シンボリックリンク ---------------------------------------------------------
new_repo symlink
ln -s plain.txt link
git add link
if run_sc; then
  [ "$(entry link | cut -d' ' -f1)" = 120000 ] && [ "$(blob_of link)" = plain.txt ] \
    && ok "symlink is sent as 120000 with its target" \
    || ng "symlink sent as $(entry link | cut -d' ' -f1) with content '$(blob_of link)'"
else
  ng "symlink run failed"
fi

exit "${fail}"
