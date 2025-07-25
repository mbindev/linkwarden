# syntax=docker/dockerfile:1
FROM node:18-alpine AS base

# This ARG is populated by Railway with a cache key, fulfilling their specific format.
# Source: https://docs.railway.com/guides/dockerfiles#cache-mounts
ARG CACHE_KEY

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
# Re-declare the ARG in this build stage to ensure it's available
ARG CACHE_KEY
WORKDIR /usr/src/app
COPY --from=deps /usr/src/app/node_modules ./node_modules
COPY . .
# Build the app using the required cache mount format
RUN --mount=type=cache,id=${CACHE_KEY}-nextcache,target=/usr/src/app/.next/cache \
    pnpm next build

FROM base as runner
# Re-declare the ARG in this build stage as well
ARG CACHE_KEY
WORKDIR /usr/src/app
# Don't run production as root
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs
# Copy the production build from the previous stage
RUN --mount=type=cache,id=${CACHE_KEY}-nextcache-final,target=/usr/src/app/.next/cache \
    --mount=type=bind,source=public,target=/usr/src/app/public \
    --mount=type=bind,source=.next/standalone,target=/usr/src/app/.next/standalone \
    --mount=type=bind,source=.next/static,target=/usr/src/app/.next/static \
    sh -c "cp -r /usr/src/app/public /usr/src/app/.next/"
# Install prisma using the required cache mount format
RUN --mount=type=cache,id=${CACHE_KEY}-pnpm,target=/root/.npm pnpm install --prod --frozen-lockfile
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
