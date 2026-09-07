FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b
# renovate: datasource=github-releases depName=siderolabs/talos extractVersion=^v(?<version>.*)$
ARG TALOSCTL_VERSION=1.14.0
# renovate: datasource=github-releases depName=kubernetes/kubernetes extractVersion=^v(?<version>.*)$
ARG KUBECTL_VERSION=1.37.0
# renovate: datasource=github-releases depName=jqlang/jq extractVersion=^jq-(?<version>.*)$
ARG JQ_VERSION=1.8.2

RUN apk add --no-cache curl \
    && wget -qO /usr/local/bin/talosctl "https://github.com/siderolabs/talos/releases/download/v${TALOSCTL_VERSION}/talosctl-linux-amd64" \
    && wget -qO /usr/local/bin/kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && wget -qO /usr/local/bin/jq "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64" \
    && chmod +x /usr/local/bin/talosctl /usr/local/bin/kubectl /usr/local/bin/jq
USER 65532:65532
