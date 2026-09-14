FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b

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
# renovate: datasource=golang-version depName=go
ARG GO_VERSION=1.26.0

RUN apk add --no-cache \
      bash curl git jq libgcc libstdc++ make openssl ripgrep unzip \
      rustup gcc musl-dev \
      e2fsprogs setpriv

RUN curl -fsSL https://claude.ai/install.sh | bash \
    && cp /root/.local/share/claude/versions/* /usr/local/bin/claude \
    && chmod +x /usr/local/bin/claude \
    && rm -rf /root/.local

RUN rustup-init -y --default-toolchain stable --profile minimal --target wasm32-wasip1 \
    && . /root/.cargo/env \
    && cp -a /root/.cargo /usr/local/cargo \
    && cp -a /root/.rustup /usr/local/rustup \
    && rm -rf /root/.cargo /root/.rustup

RUN apk add --no-cache nodejs npm \
    && npm install -g pnpm@10.32.0

RUN wget -qO /tmp/gh.tar.gz "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
    && tar xzf /tmp/gh.tar.gz -C /tmp && mv /tmp/gh_${GH_VERSION}_linux_amd64/bin/gh /usr/local/bin/ \
    && wget -qO /tmp/spin.tar.gz "https://github.com/spinframework/spin/releases/download/v${SPIN_VERSION}/spin-v${SPIN_VERSION}-linux-amd64.tar.gz" \
    && tar xzf /tmp/spin.tar.gz -C /usr/local/bin spin \
    && wget -qO /usr/local/bin/kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && wget -qO /tmp/helm.tar.gz "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
    && tar xzf /tmp/helm.tar.gz -C /tmp && mv /tmp/linux-amd64/helm /usr/local/bin/ \
    && wget -qO /tmp/logcli.zip "https://github.com/grafana/loki/releases/download/v${LOGCLI_VERSION}/logcli-linux-amd64.zip" \
    && unzip -o /tmp/logcli.zip -d /tmp && mv /tmp/logcli-linux-amd64 /usr/local/bin/logcli \
    && chmod +x /usr/local/bin/gh /usr/local/bin/spin /usr/local/bin/kubectl /usr/local/bin/helm /usr/local/bin/logcli \
    && rm -rf /tmp/*

# Go は Go を要求するリポジトリをレビューするために要る。ツールチェーン本体だけを置き、
# golangci-lint / setup-envtest といった個々のツールは焼かない — 対象リポの Makefile が
# 自分でバージョンを固定して取りに行き、Renovate がそれを追っているので、ここに焼くと
# バージョンの管理点が 2 つになって必ず片方が腐る。
RUN wget -qO /tmp/go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
    && tar xzf /tmp/go.tar.gz -C /usr/local \
    && rm -f /tmp/go.tar.gz

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    USE_BUILTIN_RIPGREP=0 \
    PNPM_HOME="/usr/local/share/pnpm"
ENV PATH="/usr/local/share/pnpm:/usr/local/cargo/bin:/usr/local/go/bin:${PATH}"

# parts — handler の initContainer が部品（skill / agent / CLAUDE.md 断片）を parts リポから
# 引いて敷くコマンド。中身は git の sparse checkout と GitHub App の token 生成だけ。
COPY --chmod=0755 parts /usr/local/bin/parts

USER 65532:65532
