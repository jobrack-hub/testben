# ============================================================
# Stage 1: Build SvelteKit → static files
# ============================================================
FROM node:20-alpine AS frontend
WORKDIR /app
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ .
RUN npm run build

# ============================================================
# Stage 2: Build Vapor binary
# ============================================================
FROM swift:6.0-jammy AS backend
WORKDIR /app
RUN apt-get update && apt-get install -y libsqlite3-dev && rm -rf /var/lib/apt/lists/*
COPY backend/Package.* ./
RUN swift package resolve
COPY backend/Sources ./Sources
RUN swift build -c release --product Run

# ============================================================
# Stage 3: Minimal runtime image
# ============================================================
FROM swift:6.0-jammy-slim
RUN apt-get update \
    && apt-get install -y libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Vapor binary
COPY --from=backend /app/.build/release/Run .

# SvelteKit static build → Vapor's Public/ directory
COPY --from=frontend /app/build ./Public

# Directory for SQLite volume mount
RUN mkdir -p /data

EXPOSE 8080
CMD ["./Run", "serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
