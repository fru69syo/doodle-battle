# syntax=docker/dockerfile:1
#
# Realtime battle server image. Build from the REPOSITORY ROOT (the server reads shared/ data):
#   docker build -f server/realtime/Dockerfile -t battle .
# Dockerfile.dockerignore (next to this file) keeps the build context small.
#
# Two stages: a full Node image compiles TypeScript; the runtime image is Google's distroless
# Node.js (no shell, no package manager, runs as a non-root user): fewer things to patch and a
# smaller attack surface. Base images are pinned by digest so builds are reproducible; bump the
# digests deliberately (e.g. monthly) to pick up security fixes. mirror.gcr.io is Google's cache
# of Docker Hub (same image and digest, no Docker Hub pull rate limit).

FROM mirror.gcr.io/library/node:22-bookworm-slim@sha256:c3de60bf2f9dd0ac6370e6117950ff62d6e339527e7472301c9c78a017978392 AS build
# Engine v3 (shared/battle_engine_v3_ts) is a `file:` dependency of the server. Build it first:
# its `prepare` script compiles dist/ with its own TypeScript, and npm links it into the
# server's node_modules (docs/REALTIME_PROTOCOL.md §9).
WORKDIR /repo/shared/battle_engine_v3_ts
COPY shared/battle_engine_v3_ts/package.json shared/battle_engine_v3_ts/package-lock.json shared/battle_engine_v3_ts/tsconfig.json shared/battle_engine_v3_ts/tsconfig.build.json ./
COPY shared/battle_engine_v3_ts/src/ ./src/
RUN npm ci --no-audit --no-fund
WORKDIR /repo/server/realtime
COPY shared/cost_mode/ /repo/shared/cost_mode/
COPY server/realtime/package.json server/realtime/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY server/realtime/tsconfig.json server/realtime/tsconfig.build.json ./
COPY server/realtime/scripts/ ./scripts/
COPY server/realtime/src/ ./src/
# npm links the file: dependency (a symlink out of server/realtime). Replace the link with a
# plain copy of the compiled engine so the runtime image needs nothing outside /app.
RUN npm run build && npm prune --omit=dev \
 && rm node_modules/@doodle-battle/battle-engine-v3 \
 && mkdir node_modules/@doodle-battle/battle-engine-v3 \
 && cp -R /repo/shared/battle_engine_v3_ts/package.json /repo/shared/battle_engine_v3_ts/dist node_modules/@doodle-battle/battle-engine-v3/ \
 && node -e "require('@doodle-battle/battle-engine-v3')"

FROM gcr.io/distroless/nodejs22-debian12:nonroot@sha256:13593b7570658e8477de39e2f4a1dd25db2f836d68a0ba771251572d23bb4f8e
WORKDIR /app
COPY --from=build /repo/server/realtime/package.json ./
COPY --from=build /repo/server/realtime/node_modules ./node_modules
COPY --from=build /repo/server/realtime/lib ./lib
ENV NODE_ENV=production \
    PORT=8080
EXPOSE 8080
USER nonroot
# The distroless entrypoint is `node`.
CMD ["lib/index.js"]
