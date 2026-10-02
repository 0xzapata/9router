# syntax=docker/dockerfile:1.7
ARG NODE_IMAGE=node:22-bookworm-slim
ARG NPM_REGISTRY=https://registry.npmjs.org/
ARG APP_VERSION=unknown

FROM ${NODE_IMAGE} AS base
WORKDIR /app

FROM base AS builder
ARG NPM_REGISTRY

RUN apt-get update && \
  apt-get install -y --no-install-recommends python3 make g++ && \
  rm -rf /var/lib/apt/lists/*

COPY package.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm install \
      --registry="${NPM_REGISTRY}" \
      --fetch-retries=5 \
      --fetch-retry-factor=2 \
      --fetch-retry-mintimeout=10000 \
      --fetch-retry-maxtimeout=120000 \
      --fetch-timeout=300000

COPY . ./
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM ${NODE_IMAGE} AS runner
ARG APP_VERSION
ARG CLI_TOOLS_REFRESH=manual
WORKDIR /app

LABEL org.opencontainers.image.title="9router" \
      org.opencontainers.image.version="${APP_VERSION}"

ENV NODE_ENV=production
ENV PORT=20128
ENV HOSTNAME=0.0.0.0
ENV NEXT_TELEMETRY_DISABLED=1
ENV DATA_DIR=/app/data

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/custom-server.js ./custom-server.js
COPY --from=builder /app/open-sse ./open-sse
# Next file tracing can omit sibling files; MITM runs server.js as a separate process.
COPY --from=builder /app/src/mitm ./src/mitm
# Standalone node_modules may omit deps only required by the MITM child process.
COPY --from=builder /app/node_modules/node-forge ./node_modules/node-forge
# Ensure `next` is available at runtime in case tracing did not include it.
COPY --from=builder /app/node_modules/next ./node_modules/next
# sql.js loads dist/sql-wasm.wasm by path at runtime; tracing only follows JS imports,
# so the last-resort DB driver would abort with ENOENT on the missing binary.
COPY --from=builder /app/node_modules/sql.js ./node_modules/sql.js
# node-machine-id is createRequire-loaded at runtime; tracing omits it.
COPY --from=builder /app/node_modules/node-machine-id ./node_modules/node-machine-id

RUN apt-get update && \
  apt-get install -y --no-install-recommends bash ca-certificates curl gosu && \
  rm -rf /var/lib/apt/lists/*

RUN --mount=type=cache,target=/root/.npm \
  echo "CLI tools refresh: ${CLI_TOOLS_REFRESH}" && \
  npm install --global --no-audit --no-fund --prefer-online \
    @anthropic-ai/claude-code@latest \
    @openai/codex@latest \
    opencode-ai@latest \
    cline@latest && \
  DEVIN_TARGET="$(case "$(uname -m)" in x86_64) echo x86_64-unknown-linux ;; aarch64) echo aarch64-unknown-linux ;; esac)" && \
  DEVIN_MANIFEST="$(curl -fsSL https://static.devin.ai/cli/current/manifest.json)" && \
  DEVIN_URL="$(DEVIN_MANIFEST="$DEVIN_MANIFEST" DEVIN_TARGET="$DEVIN_TARGET" node -p 'JSON.parse(process.env.DEVIN_MANIFEST).platforms[process.env.DEVIN_TARGET].url')" && \
  DEVIN_SHA="$(DEVIN_MANIFEST="$DEVIN_MANIFEST" DEVIN_TARGET="$DEVIN_TARGET" node -p 'JSON.parse(process.env.DEVIN_MANIFEST).platforms[process.env.DEVIN_TARGET].sha256')" && \
  mkdir -p /tmp/devin-install && \
  curl -fsSL "$DEVIN_URL" -o /tmp/devin-install/devin.tar.gz && \
  echo "$DEVIN_SHA  /tmp/devin-install/devin.tar.gz" | sha256sum -c - && \
  tar -xzf /tmp/devin-install/devin.tar.gz -C /tmp/devin-install && \
  cp /tmp/devin-install/bin/devin /usr/local/bin/devin && \
  chmod 0755 /usr/local/bin/devin && \
  rm -rf /tmp/devin-install && \
  claude --version && codex --version && opencode --version && \
  cline --version && devin --version

RUN mkdir -p /app/data && chown -R node:node /app && \
  mkdir -p /app/data-home && chown node:node /app/data-home && \
  ln -sf /app/data-home /root/.9router 2>/dev/null || true

# Fix mounted-volume permissions before starting the app as the node user.
RUN printf '#!/bin/sh\nchown -R node:node /app/data /app/data-home 2>/dev/null\nexec gosu node "$@"\n' > /entrypoint.sh && \
  chmod +x /entrypoint.sh

EXPOSE 20128

ENTRYPOINT ["/entrypoint.sh"]
CMD ["node", "custom-server.js"]
