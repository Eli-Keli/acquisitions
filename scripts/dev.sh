#!/bin/bash
set -e


# Development startup script for Acquisition App with Neon Local
# This script starts the application in development mode with Neon Local

COMPOSE="docker compose -f docker-compose.dev.yml"
MAX_RETRIES=60  # Neon Local may take time on first run while creating an ephemeral branch

# Neon Local returns HTTP 400 on GET / (expected) — check for its server header instead of 2xx
wait_for_neon_local() {
  curl -sI http://localhost:5432/ 2>/dev/null | grep -qi "neon-local-proxy"
}

echo "🚀 Starting Acquisition App in Development Mode"
echo "================================================"

# Check if .env.development exists
if [ ! -f .env.development ]; then
  echo "❌ Error: .env.development file not found!"
  echo "   Copy .env.example values into .env.development and add your Neon credentials."
  exit 1
fi

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
  echo "❌ Error: Docker is not running!"
  echo "   Please start Docker Desktop and try again."
  exit 1
fi

# Create .neon_local directory if it doesn't exist
mkdir -p .neon_local

# Add .neon_local to .gitignore if not already present
if ! grep -q ".neon_local/" .gitignore 2>/dev/null; then
  echo ".neon_local/" >> .gitignore
  echo "✅ Added .neon_local/ to .gitignore"
fi

echo "📦 Building and starting development containers..."
echo "   - Neon Local proxy will create an ephemeral database branch"
echo "   - Application will run with hot reload enabled"
echo ""

$COMPOSE up --build -d

# Wait for Neon Local (400 on GET / is normal — proxy is up when server header appears)
echo "⏳ Waiting for Neon Local to be ready..."
retry=0
until wait_for_neon_local; do
  retry=$((retry + 1))
  if [ "$retry" -ge "$MAX_RETRIES" ]; then
    echo "❌ Neon Local did not become ready in time."
    echo "   Check logs: $COMPOSE logs neon-local"
    exit 1
  fi
  sleep 2
done
echo "✅ Neon Local is ready"

# Wait for the app to respond on /health
echo "⏳ Waiting for the application to be ready..."
retry=0
until wait_for_app; do
  retry=$((retry + 1))
  if [ "$retry" -ge "$MAX_RETRIES" ]; then
    echo "❌ Application did not become ready in time."
    echo "   Check logs: $COMPOSE logs app"
    exit 1
  fi
  sleep 2
done
echo "✅ Application is ready"

# Run migrations inside the app container (uses neon-local hostname from .env.development)
echo "📜 Applying latest schema with Drizzle..."
$COMPOSE exec app npm run db:migrate

echo ""
echo "🎉 Development environment started!"
echo "   Application: http://localhost:3000"
echo "   Health:      http://localhost:3000/health"
echo "   Database:    postgres://neon:npg@localhost:5432/neondb"
echo ""
echo "To stop:  npm run docker:dev:down"
echo "          $COMPOSE down"
echo ""
echo "Streaming logs (Ctrl+C to stop watching — containers keep running)..."
echo ""

$COMPOSE logs -f
