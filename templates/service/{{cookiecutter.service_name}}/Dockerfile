# THE deployable artifact (PRD §5.3) — Trivy and the Dockerfile policies
# (USER root, unpinned tags) apply to this, because this is what ships.
# Digest-pinned base, not `latest` (scenario 2).
# Digest verified live via `docker buildx imagetools inspect oven/bun:1.2.4-slim`
# (multi-arch index digest, not a fabricated placeholder) — re-verify before
# using in a real build if this drifts.
FROM oven/bun:1.2.4-slim@sha256:c377a08d0711e47c23a8ad8cf9a924cf9abeae4c9031dfa56be2f1786e0f8ce7 AS base
WORKDIR /app

COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile --production

COPY src ./src

# Runs as the image's built-in non-root `bun` user — never root in the
# shipped artifact (scenario 5).
USER bun
EXPOSE 3000
ENTRYPOINT ["bun", "run", "src/server.ts"]
