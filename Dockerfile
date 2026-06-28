# Final Whistle Rooms backend — single long-lived Node instance.
# The live-room engine holds in-memory state and streams over SSE, so this must
# run as ONE persistent container (not serverless). Works on Render, Railway,
# Fly.io, a VM, or any Docker host.
FROM node:20-bookworm-slim AS base
WORKDIR /app
# Pin pnpm to the version that generated the lockfile (10.x). corepack's default
# latest (pnpm 11) needs a newer Node than this image and crashes on install.
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN corepack enable && corepack prepare pnpm@10.6.3 --activate

# deps first (better layer caching)
COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile || pnpm install

# build
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN pnpm build

ENV NODE_ENV=production
# Hosts set $PORT; default to 3000 locally.
ENV PORT=3000
EXPOSE 3000
CMD ["sh", "-c", "pnpm start -p ${PORT:-3000}"]
