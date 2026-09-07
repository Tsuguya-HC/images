FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b
# renovate: datasource=github-releases depName=jqlang/jq extractVersion=^jq-(?<version>.*)$
ARG JQ_VERSION=1.8.2
# renovate: datasource=github-releases depName=kubernetes/kubernetes extractVersion=^v(?<version>.*)$
ARG KUBECTL_VERSION=1.37.0
# renovate: datasource=github-releases depName=cli/cli extractVersion=^v(?<version>.*)$
ARG GH_VERSION=2.100.0
# renovate: datasource=github-releases depName=mikefarah/yq extractVersion=^v(?<version>.*)$
ARG YQ_VERSION=4.53.6
# renovate: datasource=github-releases depName=sigstore/cosign extractVersion=^v(?<version>.*)$
ARG COSIGN_VERSION=3.1.3
# renovate: datasource=github-releases depName=argoproj/argo-cd extractVersion=^v(?<version>.*)$
ARG ARGOCD_VERSION=3.5.2
# renovate: datasource=github-releases depName=google/go-containerregistry extractVersion=^v(?<version>.*)$
ARG CRANE_VERSION=0.22.1
# renovate: datasource=github-releases depName=GoogleContainerTools/container-structure-test extractVersion=^v(?<version>.*)$
ARG CST_VERSION=1.22.1
# renovate: datasource=github-releases depName=aquaproj/aqua extractVersion=^v(?<version>.*)$
ARG AQUA_VERSION=2.62.3

RUN apk add --no-cache curl git openssl \
    && wget -qO /usr/local/bin/jq "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64" \
    && wget -qO /usr/local/bin/kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && wget -qO /tmp/gh.tar.gz "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
    && tar xzf /tmp/gh.tar.gz -C /tmp && mv /tmp/gh_${GH_VERSION}_linux_amd64/bin/gh /usr/local/bin/ && rm -rf /tmp/gh* \
    && wget -qO /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" \
    && wget -qO /usr/local/bin/cosign "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-amd64" \
    && wget -qO /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-amd64" \
    && wget -qO /tmp/crane.tar.gz "https://github.com/google/go-containerregistry/releases/download/v${CRANE_VERSION}/go-containerregistry_Linux_x86_64.tar.gz" \
    && tar xzf /tmp/crane.tar.gz -C /usr/local/bin crane && rm /tmp/crane.tar.gz \
    && wget -qO /usr/local/bin/container-structure-test "https://github.com/GoogleContainerTools/container-structure-test/releases/download/v${CST_VERSION}/container-structure-test-linux-amd64" \
    && wget -qO /tmp/aqua.tar.gz "https://github.com/aquaproj/aqua/releases/download/v${AQUA_VERSION}/aqua_linux_amd64.tar.gz" \
    && tar xzf /tmp/aqua.tar.gz -C /usr/local/bin aqua && rm /tmp/aqua.tar.gz \
    && chmod +x /usr/local/bin/aqua \
    && chmod +x /usr/local/bin/jq /usr/local/bin/kubectl /usr/local/bin/gh /usr/local/bin/yq /usr/local/bin/cosign /usr/local/bin/argocd /usr/local/bin/crane /usr/local/bin/container-structure-test
COPY --chmod=755 github-auth.sh github-signed-commit.sh /usr/local/bin/
USER 65532:65532
