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

# Lambda Web Adapter (arm64): an external extension that bridges the Lambda
# Function URL to the HTTP server the ENTRYPOINT starts — so the same image
# runs on Lambda and locally unchanged (the extension is inert outside the
# Lambda runtime). Digest-pinned like the base (scenario 2); arm64 manifest,
# matching the Lambda architecture.
COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:0.9.1@sha256:cd0ad9539cbf223feb1cabd8f4deb7064b6270f185614274b940a36590cdc8f9 /lambda-adapter /opt/extensions/lambda-adapter
ENV AWS_LWA_PORT=3000

# Runs as the image's built-in non-root `bun` user — never root in the
# shipped artifact (scenario 5).
USER bun
EXPOSE 3000
ENTRYPOINT ["bun", "run", "src/server.ts"]
