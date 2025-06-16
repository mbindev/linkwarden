# syntax=docker/dockerfile:1
FROM node:18-alpine AS base

# This ARG will be populated by Railway to prefix cache mounts
ARG BUILDKIT_CACHE_MOUNT_ID

# Install dependencies only when needed
FROM base AS deps
# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
RUN apk add --no-cache libc6-compat
WORKDIR /usr/src/app

COPY pnpm-lock.yaml* package.json* ./
RUN npm install -g pnpm

# Install dependencies
RUN pnpm fetch


FROM base AS builder
WORKDIR /usr/src/app
COPY --from=deps /usr/src/app/node_modules ./node_modules
COPY . .
# This is our first build stage so we can cache the results
# Build the app
# See https://nextjs.org/docs/pages/building-your-application/deploying/production-checklist
RUN --mount=type=cache,id=${BUILDKIT_CACHE_MOUNT_ID}-nextcache,target=/usr/src/app/.next/cache \
    pnpm next build

FROM base as runner
WORKDIR /usr/src/app
# Don't run production as root
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs
# Copy the production build from the previous stage
RUN --mount=type=cache,id=${BUILDKIT_CACHE_MOUNT_ID}-nextcache-final,target=/usr/src/app/.next/cache \
    --mount=type=bind,source=public,target=/usr/src/app/public \
    --mount=type=bind,source=.next/standalone,target=/usr/src/app/.next/standalone \
    --mount=type=bind,source=.next/static,target=/usr/src/app/.next/static \
    sh -c "cp -r /usr/src/app/public /usr/src/app/.next/"
# Install prisma
RUN --mount=type=cache,id=${BUILDKIT_CACHE_MOUNT_ID}-pnpm,target=/root/.npm pnpm install --prod --frozen-lockfile
# Generate prisma client
RUN pnpm prisma generate
# Set the correct permissions for the "nextjs" user
RUN chown -R nextjs:nodejs /usr/src/app/.next
USER nextjs

ENV PORT 3000

# Next.js collects anonymous telemetry data about usage.
# Learn more here: https://nextjs.org/telemetry
# Uncomment the following line in case you want to disable telemetry.
ENV NEXT_TELEMETRY_DISABLED 1

CMD ["node", ".next/standalone/server.js"]
