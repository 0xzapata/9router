# syntax=docker/dockerfile:1.7
ARG BUN_IMAGE=oven/bun:1.3.2-alpine
FROM ${BUN_IMAGE} AS base
WORKDIR /app

FROM base AS builder

RUN apk --no-cache upgrade && apk --no-cache add nodejs npm python3 make g++ linux-headers

COPY package.json ./
RUN --mount=type=cache,target=/root/.npm \
  npm install

COPY . ./
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM ${BUN_IMAGE} AS runner
WORKDIR /app

LABEL org.opencontainers.image.title="9router"

ENV NODE_ENV=production
ENV PORT=20128
ENV HOSTNAME=0.0.0.0
ENV NEXT_TELEMETRY_DISABLED=1
ENV DATA_DIR=/app/data

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/open-sse ./open-sse
# Next file tracing can omit sibling files; MITM runs server.js as a separate process.
COPY --from=builder /app/src/mitm ./src/mitm
# Standalone node_modules may omit deps only required by the MITM child process.
COPY --from=builder /app/node_modules/node-forge ./node_modules/node-forge

RUN mkdir -p /app/data && chown -R bun:bun /app && \
  mkdir -p /app/data-home && chown bun:bun /app/data-home && \
  ln -sf /app/data-home /root/.9router 2>/dev/null || true

# Fix permissions at runtime (handles mounted volumes)
RUN apk --no-cache upgrade && apk --no-cache add su-exec && \
  printf '#!/bin/sh\nchown -R bun:bun /app/data /app/data-home 2>/dev/null\nexec su-exec bun "$@"\n' > /entrypoint.sh && \
  chmod +x /entrypoint.sh

EXPOSE 20128

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bun", "server.js"]

FROM runner AS runner-cli
WORKDIR /app

# Install system dependencies for CLI agents (git+ssh references, Python for some tools)
# Note: python3-pip is not available in Alpine 3.22, use get-pip.py instead
RUN apk --no-cache upgrade && apk --no-cache add git ca-certificates python3 bash curl && \
  git config --system url."https://github.com/".insteadOf "ssh://git@github.com/" && \
  curl -sS https://bootstrap.pypa.io/get-pip.py | python3 --break-system-packages

# Install AI CLI agents globally with graceful fallbacks
# Claude CLI
RUN bun install -g @anthropic-ai/claude-code 2>/dev/null || echo "claude-code installation skipped"
# Cursor CLI
RUN bun install -g cursor-cli 2>/dev/null || echo "cursor-cli installation skipped"
# Gemini CLI
RUN bun install -g @google/generative-ai 2>/dev/null || echo "gemini-cli installation skipped"
# Codex CLI
RUN bun install -g @openai/codex 2>/dev/null || echo "codex installation skipped"
# Kimi CLI (Python-based)
RUN pip3 install --no-cache-dir --break-system-packages kimi-cli 2>/dev/null || echo "kimi-cli installation skipped"
# OpenClaw agent
RUN bun install -g openclaw@latest 2>/dev/null || echo "openclaw installation skipped"
# Droid CLI
RUN bun install -g droid 2>/dev/null || echo "droid installation skipped"

# Create persistent home directory structure for CLI configs and cache
RUN mkdir -p /root/.config /root/.cache /root/.local/share /root/.ssh && chmod 700 /root/.ssh
