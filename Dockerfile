# syntax=docker/dockerfile:1   - Enable BuildKit for faster, cached multi-stage builds

# ── Base stage ──────────────────────────────────────────────────────────────
# Shared foundation for all targets. Installs dependencies once so later stages can reuse the node_modules layer without re-running npm ci.

# 1. Base image with Node.js
FROM node:22-alpine AS base

# 2. Set working directory
WORKDIR /app

# 3. Copy Node.js package files
COPY package*.json ./

# 4. Install exact dependency versions from lockfile
RUN npm ci



# ── Development target ──────────────────────────────────────────────────────
# Used by docker-compose.dev.yml. Copies the full source tree and runs the app with hot reload (node --watch).
# Source is also bind-mounted in compose so code changes on the host are reflected immediately inside the container.
FROM base AS development

# 1. Copy full project source code into the container
COPY . .

# 2. Expose the port the app listens on
EXPOSE 3000

# 3. Start dev server with hot reload via node --watch
CMD ["npm", "run", "dev"]



# ── Production dependencies ─────────────────────────────────────────────────
# Installs only runtime dependencies (no devDependencies like eslint or drizzle-kit) to keep the production image lean and secure.
FROM base AS production-deps
RUN npm ci --omit=dev

# ── Production target ─────────────────────────────────────────────────────────
# Used by docker-compose.prod.yml. Copies only what is needed to run the app in production — no source bind-mounts, no dev tools, no test files.

# 1. Fresh slim image for the final prod container
FROM node:22-alpine AS production

# 2. Set working directory
WORKDIR /app

# 3. Tell Node.js to use production environment
ENV NODE_ENV=production

# 4. Reuse the slim node_modules from the previous stage
COPY --from=production-deps /app/node_modules ./node_modules

# 5. Copy Node.js package files
COPY package*.json ./

# 6. Copy application source code
COPY src ./src

# 7. Copy Drizzle SQL migration files
COPY drizzle ./drizzle

# 8. Copy Drizzle ORM config for migrations
COPY drizzle.config.js ./

# 9. Copy startup script into PATH
# Entrypoint script runs before the main process (e.g. optional setup steps)
COPY docker-entrypoint.sh /usr/local/bin/

# 10. Make entrypoint script executable and hand /app to the non-root node user
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
  && chown -R node:node /app

# 11. Drop root privileges — run the app as the built-in node user (uid 1000)
USER node

# 12. Expose the port the app listens on
EXPOSE 3000

# 13. Probe /health to report container readiness to Docker/orchestrators
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/health').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

# 14. Run entrypoint before the main command
ENTRYPOINT ["docker-entrypoint.sh"]

# 15. Default command: start the Express server
CMD ["npm", "start"]
