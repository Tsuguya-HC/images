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

# ツールを足したら claude-code/smoke-test.sh の check も足すこと（対で手動維持）。

# renovate: datasource=github-releases depName=cli/cli extractVersion=^v(?<version>.*)$
ARG GH_VERSION=2.100.0
# renovate: datasource=github-releases depName=spinframework/spin extractVersion=^v(?<version>.*)$
ARG SPIN_VERSION=4.1.0
# renovate: datasource=github-releases depName=kubernetes/kubernetes extractVersion=^v(?<version>.*)$
ARG KUBECTL_VERSION=1.37.0
# renovate: datasource=github-releases depName=helm/helm extractVersion=^v(?<version>.*)$
ARG HELM_VERSION=4.3.0
# renovate: datasource=github-releases depName=grafana/loki extractVersion=^v(?<version>.*)$
ARG LOGCLI_VERSION=3.7.7
# renovate: datasource=golang-version depName=go extractVersion=^v?(?<version>.*)$
ARG GO_VERSION=1.26.0
# renovate: datasource=node-version depName=node extractVersion=^v?(?<version>.*)$
ARG NODE_VERSION=24.21.0
# renovate: datasource=pypi depName=PyYAML extractVersion=^(?<version>.*)$
ARG PYYAML_VERSION=6.0.3

# setpriv は util-linux に入っており --reuid を持つ（#53 で alpine 側に足したもの）。
# e2fsprogs は block scratch の mkfs に要る（#52）。ripgrep は claude が使う。
# bash / ca-certificates は Debian の slim に既にある。取得は curl に統一する
# （alpine 版は wget と curl が混在しており hadolint DL4001 を ignore していた）。
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      curl git jq make openssl ripgrep unzip xz-utils \
      gcc libc6-dev \
      e2fsprogs util-linux \
    && rm -rf /var/lib/apt/lists/* \
    # このイメージは非 root（USER 65532）実行で、mount / su / passwd のような
    # setuid/setgid 経路を使わない。apt が入れた分も含めて権限ビットを落とす。
    && find / -xdev \( -perm -4000 -o -perm -2000 \) -type f -exec chmod u-s,g-s {} +

RUN curl -fsSL https://claude.ai/install.sh | bash \
    && cp /root/.local/share/claude/versions/* /usr/local/bin/claude \
    && chmod +x /usr/local/bin/claude \
    && rm -rf /root/.local

RUN curl -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh \
    && sh /tmp/rustup-init.sh -y --no-modify-path --default-toolchain stable --profile minimal --target wasm32-wasip1 \
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
    && chmod +x /usr/local/bin/gh /usr/local/bin/spin /usr/local/bin/kubectl /usr/local/bin/helm /usr/local/bin/logcli \
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
# 引いて敷くコマンド。中身は git の sparse checkout と GitHub App の token 生成だけ。
COPY --chmod=0755 parts /usr/local/bin/parts

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
