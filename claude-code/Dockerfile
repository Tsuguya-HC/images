# ベースは Debian（glibc）。alpine ではなく Debian を選ぶ理由は Python にある:
# エージェントは複雑な集計を使い捨ての Python で書く癖があり、musl 環境では
# duckdb のような主要ホイールが musllinux 版を出していない（home-trading の
# `duckdb>=1.5,<2` は python:3.14-alpine では解決不能、glibc 側は 1.5.5）。
# 対象リポの本番イメージも python:3.14-slim なので、ベースを揃えて環境差を消す。
# 軽さを理由に alpine を選ぶ意味は、go / rust / node を焼いた時点で既に無い。
#
# Python のバージョンだけは go / rust / node と違い ARG ではなく FROM タグを直接
# 編集して上げる。Renovate はこのタグも minor 更新として追跡し、"all non-major
# updates" グループで他の依存と一緒に自動マージする。
#
# 今のところそれで問題ない — このイメージでの Python の実需はエージェントが書く
# 使い捨てスクリプト用で、home-trading（CNP の egress に pypi が無く、まだこの
# イメージでは扱っていない）とバージョンを揃え続ける理由が無い。将来ここで
# home-trading のテストを回すようになったら、対象リポの本番イメージ
# （PYTHON_IMAGE）と揃っているか、依存 wheel が新しい cp タグで揃っているかを
# 見た上で、renovate.jsonc の packageRules で automerge を制御すること。
FROM python:3.14-slim-trixie@sha256:caaf356f40667c496d405780745b9ac25771c189a51dfcc42430d531ea09f8a2

# ツールを足したら claude-code/structure-test.yaml にもテストを足すこと（対で手動維持）。版を固定した
# ツールは、同じ `# renovate:` 注記を付けて expectedOutput に版を書く。

# renovate: datasource=github-releases depName=cli/cli extractVersion=^v(?<version>.*)$
ARG GH_VERSION=2.101.0
# Spin はクラスタのノード（containerd-shim-spin）が動かせる版が天井。新しい CLI は、ノードが
# 拒否する component でもビルドと e2e を緑にする。home-rss のリリースと同じ版に揃え、
# minor 以上の更新は renovate.jsonc で承認必須にしてある。
# renovate: datasource=github-releases depName=spinframework/spin extractVersion=^v(?<version>.*)$
ARG SPIN_VERSION=4.0.2
# dbmate は対象リポの e2e がマイグレーションを当てるのに使う。リリースに checksum が無いので
# バイナリのハッシュを固定しており、版を上げるときはハッシュも一緒に上げる。
# renovate: datasource=github-releases depName=amacneil/dbmate extractVersion=^v(?<version>.*)$
ARG DBMATE_VERSION=2.36.0
ARG DBMATE_SHA256=47e284b3d8cbad1ba5f090495aa05afd1bbd5f35e2ed5577aad06da74ce780ce
# opencode は OpenRouter 経由の非 Claude モデルを動かすハーネスの候補（Claude Code と比べる）。
# リリースに checksum ファイルが無いので tarball のハッシュを固定しており、版を上げるときは
# ハッシュも一緒に上げる。リリースは immutable なので、上げるハッシュは
# `gh release verify-asset v<版> opencode-linux-x64.tar.gz -R anomalyco/opencode` で確かめる。
# renovate: datasource=github-releases depName=anomalyco/opencode extractVersion=^v(?<version>.*)$
ARG OPENCODE_VERSION=1.18.33
ARG OPENCODE_SHA256=e546123213ae47909a4268692aa4b94950d011afe9cac9938753a2194f1c16d5
# cargo-llvm-cov は変更行のカバレッジ計測に使う。リリースに checksum ファイルが無いので
# tarball のハッシュを固定しており、版を上げるときはハッシュも一緒に上げる。リリースは
# immutable なので、上げるハッシュは
# `gh release verify-asset v<版> cargo-llvm-cov-x86_64-unknown-linux-gnu.tar.gz -R taiki-e/cargo-llvm-cov` で確かめる。
# renovate: datasource=github-releases depName=taiki-e/cargo-llvm-cov extractVersion=^v(?<version>.*)$
ARG CARGO_LLVM_COV_VERSION=0.9.1
ARG CARGO_LLVM_COV_SHA256=b3f68e625481fed9b16444174f3fa5ebcdbde4a1878803a35eabe2dcefcdc41a
# renovate: datasource=github-releases depName=kubernetes/kubernetes extractVersion=^v(?<version>.*)$
ARG KUBECTL_VERSION=1.37.0
# renovate: datasource=github-releases depName=helm/helm extractVersion=^v(?<version>.*)$
ARG HELM_VERSION=4.3.0
# renovate: datasource=github-releases depName=grafana/loki extractVersion=^v(?<version>.*)$
ARG LOGCLI_VERSION=3.7.8
# renovate: datasource=golang-version depName=go extractVersion=^v?(?<version>.*)$
ARG GO_VERSION=1.27.1
# renovate: datasource=node-version depName=node extractVersion=^v?(?<version>.*)$
ARG NODE_VERSION=24.21.0
# renovate: datasource=pypi depName=PyYAML extractVersion=^(?<version>.*)$
ARG PYYAML_VERSION=6.0.3

# setpriv は util-linux に入っており --reuid を持つ（#53 で alpine 側に足したもの）。
# e2fsprogs は block scratch の mkfs に要る（#52）。ripgrep は claude が使う。
# bash / ca-certificates は Debian の slim に既にある。取得は curl に統一する
# （alpine 版は wget と curl が混在しており hadolint DL4001 を ignore していた）。
#
# apt は既定で http://deb.debian.org を引くが、このイメージをビルドするクラスタ側の
# egress（home-cluster の manifests/image-build/netpol.yaml）は 0.0.0.0/0 に対して
# 443 しか開けていない。alpine の apk が https だったので今まで顕在化していなかった。
# ポリシーを広げるのではなく取得を https に寄せる（2026-09-20 実測: 書き換えないと
# クラスタのビルドが `E: Unable to locate package curl` で exit 100。手元の docker
# build は egress 制限が無いので通ってしまい、ここだけ CI では再現しない）。
# hadolint ignore=DL3008
RUN sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list.d/debian.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
      curl git jq make openssl ripgrep unzip xz-utils \
      gcc libc6-dev \
      e2fsprogs util-linux \
    && rm -rf /var/lib/apt/lists/* \
    # このイメージは非 root（USER 65532）実行で、mount / su / passwd のような
    # setuid/setgid 経路を使わない。apt が入れた分も含めて権限ビットを落とす。
    && find / -xdev \( -perm -4000 -o -perm -2000 \) -type f -exec chmod u-s,g-s {} +

# psql は調査の handler が SQL をその場で実測するのに要る。メジャーはクラスタの PostgreSQL に
# 揃える（違う版の psql で測ると構文とメタコマンドの出力がずれる）。Debian の apt は 17 までなので
# PGDG から入れる。鍵はハッシュで固定し、差し替わったらビルドを止める（鍵の指紋 B97B0AFCAA1A47F0
# 44F244A07FCC7D46ACCC4CF8 を確かめてからハッシュを更新する）。
# PG_MAJOR / PGDG_KEY_SHA256 は Renovate の対象外: メジャーはクラスタの PostgreSQL と
# 一緒に手動で上げる（上のコメント参照）ので、自動追跡すると psql だけ先行してずれる。
ARG PG_MAJOR=18
# structure-test.yaml が Dockerfile と二重管理せず照合できるよう、ビルド後も参照できる値にする。
ENV PG_MAJOR=${PG_MAJOR}
ARG PGDG_KEY_SHA256=0144068502a1eddd2a0280ede10ef607d1ec592ce819940991203941564e8e76
# hadolint ignore=DL3008
RUN install -d /usr/share/postgresql-common/pgdg \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
    && echo "${PGDG_KEY_SHA256}  /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc" | sha256sum -c - \
    && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt trixie-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends "postgresql-client-${PG_MAJOR}" \
    && rm -rf /var/lib/apt/lists/* \
    && find / -xdev \( -perm -4000 -o -perm -2000 \) -type f -exec chmod u-s,g-s {} +

# claude は版を固定する。途中で HTTP 400 になって止まる版があったので、新しい版は
# llm-gateway 経由の OpenRouter のモデルで implement が最後まで通ると確かめてから上げる
# （更新は renovate.jsonc で承認必須にしてある）。
# renovate: datasource=npm depName=@anthropic-ai/claude-code extractVersion=^(?<version>.*)$
ARG CLAUDE_CODE_VERSION=2.1.286
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CODE_VERSION}" \
    && cp "/root/.local/share/claude/versions/${CLAUDE_CODE_VERSION}" /usr/local/bin/claude \
    && chmod +x /usr/local/bin/claude \
    && rm -rf /root/.local
# 固定した版を実行時に入れ替えさせない。
ENV DISABLE_AUTOUPDATER=1

RUN curl -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh \
    && sh /tmp/rustup-init.sh -y --no-modify-path --default-toolchain stable --profile minimal --target wasm32-wasip1 \
        --component rustfmt --component clippy --component llvm-tools \
    && cp -a /root/.cargo /usr/local/cargo \
    && cp -a /root/.rustup /usr/local/rustup \
    && rm -rf /root/.cargo /root/.rustup /tmp/rustup-init.sh

# Node は Debian の apt 版が古すぎるので公式 tarball から。Renovate が追う。
# apk と違い署名検証が無い経路なので、nodejs.org が公開する SHASUMS256.txt で
# sha256 を照合してから展開する（GPG 署名検証までは鍵の管理点が増えるので行わない）。
RUN curl -fsSL -o "/tmp/node-v${NODE_VERSION}-linux-x64.tar.xz" \
      "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" -o /tmp/SHASUMS256.txt \
    && node_sha256=$(grep " node-v${NODE_VERSION}-linux-x64.tar.xz$" /tmp/SHASUMS256.txt | cut -d' ' -f1) \
    && echo "${node_sha256}  /tmp/node-v${NODE_VERSION}-linux-x64.tar.xz" | sha256sum -c - \
    && tar xJf "/tmp/node-v${NODE_VERSION}-linux-x64.tar.xz" -C /usr/local --strip-components=1 \
         --exclude=CHANGELOG.md --exclude=LICENSE --exclude=README.md \
    && rm -f "/tmp/node-v${NODE_VERSION}-linux-x64.tar.xz" /tmp/SHASUMS256.txt \
    && npm install -g pnpm@10.32.0 \
    && npm cache clean --force

RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" -o /tmp/gh.tar.gz \
    && tar xzf /tmp/gh.tar.gz -C /tmp && mv /tmp/gh_${GH_VERSION}_linux_amd64/bin/gh /usr/local/bin/ \
    && curl -fsSL "https://github.com/spinframework/spin/releases/download/v${SPIN_VERSION}/spin-v${SPIN_VERSION}-linux-amd64.tar.gz" -o /tmp/spin.tar.gz \
    && tar xzf /tmp/spin.tar.gz -C /usr/local/bin spin \
    && curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl \
    && curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" -o /tmp/helm.tar.gz \
    && tar xzf /tmp/helm.tar.gz -C /tmp && mv /tmp/linux-amd64/helm /usr/local/bin/ \
    && curl -fsSL "https://github.com/grafana/loki/releases/download/v${LOGCLI_VERSION}/logcli-linux-amd64.zip" -o /tmp/logcli.zip \
    && unzip -o /tmp/logcli.zip -d /tmp && mv /tmp/logcli-linux-amd64 /usr/local/bin/logcli \
    && curl -fsSL "https://github.com/amacneil/dbmate/releases/download/v${DBMATE_VERSION}/dbmate-linux-amd64" -o /usr/local/bin/dbmate \
    && echo "${DBMATE_SHA256}  /usr/local/bin/dbmate" | sha256sum -c - \
    && curl -fsSL "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x64.tar.gz" -o /tmp/opencode.tar.gz \
    && echo "${OPENCODE_SHA256}  /tmp/opencode.tar.gz" | sha256sum -c - \
    && tar xzf /tmp/opencode.tar.gz -C /usr/local/bin opencode \
    && curl -fsSL "https://github.com/taiki-e/cargo-llvm-cov/releases/download/v${CARGO_LLVM_COV_VERSION}/cargo-llvm-cov-x86_64-unknown-linux-gnu.tar.gz" -o /tmp/cargo-llvm-cov.tar.gz \
    && echo "${CARGO_LLVM_COV_SHA256}  /tmp/cargo-llvm-cov.tar.gz" | sha256sum -c - \
    && tar xzf /tmp/cargo-llvm-cov.tar.gz -C /usr/local/bin cargo-llvm-cov \
    && chmod +x /usr/local/bin/gh /usr/local/bin/spin /usr/local/bin/kubectl /usr/local/bin/helm /usr/local/bin/logcli /usr/local/bin/dbmate /usr/local/bin/opencode /usr/local/bin/cargo-llvm-cov \
    && rm -rf /tmp/*

# Go は Go を要求するリポジトリをレビューするために要る。ツールチェーン本体だけを置き、
# golangci-lint / setup-envtest といった個々のツールは焼かない — 対象リポの Makefile が
# 自分でバージョンを固定して取りに行き、Renovate がそれを追っているので、ここに焼くと
# バージョンの管理点が 2 つになって必ず片方が腐る。
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tar.gz \
    && tar xzf /tmp/go.tar.gz -C /usr/local \
    && rm -f /tmp/go.tar.gz

# 対象リポの依存は焼かない（Go と同じ理由）。ここに置くのはエージェントが書く
# 使い捨てスクリプトの常備品だけ。YAML は標準ライブラリに無く、CNP の egress に
# pypi が無いので、実行時に pip で取ることはできない。
RUN pip install --no-cache-dir "PyYAML==${PYYAML_VERSION}"

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    USE_BUILTIN_RIPGREP=0 \
    PNPM_HOME="/usr/local/share/pnpm"
ENV PATH="/usr/local/share/pnpm:/usr/local/cargo/bin:/usr/local/go/bin:${PATH}"

# parts — handler の initContainer が部品（skill / agent / CLAUDE.md 断片）を parts リポから
# 引いて敷くコマンド。中身は git の sparse checkout と、gateway 経由または GitHub App の token での認証だけ。
COPY --chmod=0755 parts /usr/local/bin/parts

# github-signed-commit.sh — 署名付きコミットを GitHub API で作る。handler は GitHub の
# 資格情報を持たず、gateway 経由で `gh api` を呼ぶ（home-cluster #1038）。以前は
# handler が init で argo-tools から emptyDir へコピーしていた。
#
# **argo-tools/github-signed-commit.sh と同一のファイル**で、CI（claude-code-smoke）が
# 一致を確かめている。argo-tools のビルドから COPY --from で取り出す形は、GitHub の
# ランナーが Harbor を引けず（403）CI のビルドが通らないので使えない。
COPY --chmod=0755 github-signed-commit.sh /usr/local/bin/github-signed-commit.sh

# openrouter-broker — 実装 handler のサイドカーが動かす。API キーをエージェントの
# 到達できない別コンテナに閉じ込め、Authorization はここで付ける（home-cluster の
# manifests/claude-code-build/）。エージェント側には実値を一切渡さない。
COPY --chmod=0755 openrouter-broker.js /usr/local/bin/openrouter-broker.js

# setuid/setgid の網羅チェック。apt レイヤーの sweep は apt が入れた分しか掃わない。claude / rustup /
# node / go / pip / COPY まで全レイヤーが積み上がったこの時点で、まだ root なので
# 全ディレクトリを盲点なく走査できる（smoke-test.sh 側は非 root で /root 配下を
# 見られず、ここが唯一の網羅チェック）。1件でもあればビルド自体を失敗させる。
# `find | wc -l` だと find 自体が失敗して無出力のまま終わっても wc が 0 を返し
# 真空成立してしまう（RUN の /bin/sh -c は既定で pipefail が効かない）ため、
# find の出力を変数に落として set -e で失敗を拾い、内容は test -z で見る。
RUN set -eu; \
    found="$(find / -xdev \( -perm -4000 -o -perm -2000 \) -type f)"; \
    test -z "$found"

USER 65532:65532
