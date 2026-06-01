#!/bin/bash
set -e


# Production deployment script for Acquisition App
# This script starts the application in production mode with Neon Cloud Database

COMPOSE="docker compose -f docker-compose.prod.yml"
CONTAINER="acquisitions-app-prod"
MAX_RETRIES=30

# Probe /health from inside the container
wait_for_app() {
  $COMPOSE exec -T app node -e "fetch('http://127.0.0.1:3000/health').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" 2>/dev/null
}

echo "🚀 Starting Acquisition App in Production Mode"
echo "==============================================="

# Check if .env.production exists
if [ ! -f .env.production ]; then
  echo "❌ Error: .env.production file not found!"
  echo "   Run: cp .env.production.example .env.production"
  echo "   Then fill in your production environment variables."
  exit 1
fi

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
  echo "❌ Error: Docker is not running!"
  echo "   Please start Docker and try again."
  exit 1
fi

echo "📦 Building and starting production container..."
echo "   - Using Neon Cloud Database (no local proxy)"
echo "   - Running in optimized production mode"
echo ""

$COMPOSE up --build -d

# Wait for the app health endpoint (Dockerfile HEALTHCHECK also monitors this)
echo "⏳ Waiting for the application to be ready..."
retry=0
until wait_for_app; do
  retry=$((retry + 1))
  if [ "$retry" -ge "$MAX_RETRIES" ]; then
    echo "❌ Application did not become ready in time."
    echo "   Check logs: docker logs $CONTAINER"
    exit 1
  fi
  sleep 2
done
echo "✅ Application is ready"

# Run migrations on the host using production env vars
echo "📜 Applying latest schema with Drizzle..."
set -a
# shellcheck disable=SC1091
source .env.production
set +a
npm run db:migrate

echo ""
echo "🎉 Production environment started!"
echo "   Application: http://localhost:3000"
echo "   Health:      http://localhost:3000/health"
echo ""
echo "Useful commands:"
echo "   View logs:  docker logs -f $CONTAINER"
echo "   Stop app:   npm run docker:prod:down"
echo "              $COMPOSE down"
