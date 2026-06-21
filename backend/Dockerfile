# Development stage
FROM node:22-alpine AS development

WORKDIR /app

# Copy ONLY package files first for better caching
COPY package*.json ./

# Install all dependencies (including devDependencies)
RUN npm ci

# Copy source code AFTER installing dependencies
COPY . .

# Build stage
FROM node:22-alpine AS build

WORKDIR /app

# Copy ONLY package files first
COPY package*.json ./

# Install all dependencies first
RUN npm ci

# Copy source code
COPY . .

# Build the application
RUN npm run build

# Install only production dependencies in a clean state
ENV NODE_ENV production
RUN rm -rf node_modules && npm ci --only=production && npm cache clean --force

# Production stage
FROM node:22-alpine AS production

WORKDIR /app

# Install Chromium and dependencies for Puppeteer
# Install Chromium + Bengali/International Fonts
RUN apk add --no-cache \
    chromium \
    nss \
    freetype \
    harfbuzz \
    ca-certificates \
    ttf-freefont \
    font-noto \
    font-noto-bengali \
    font-noto-devanagari \
    terminus-font \
    nodejs \
    yarn

# Tell Puppeteer to use installed Chromium
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

ARG FACE_API_MODEL_VERSION=1.7.15

ENV FACE_API_MODEL_PATH=/app/models/face-api


# Create a non-root user for security
RUN addgroup -g 1001 -S nodejs && adduser -S nestjs -u 1001

# Create runtime directories and download face-api models
RUN mkdir -p /app/uploads /app/models/face-api \
    && wget -q -O /app/models/face-api/tiny_face_detector_model-weights_manifest.json https://cdn.jsdelivr.net/npm/@vladmandic/face-api@${FACE_API_MODEL_VERSION}/model/tiny_face_detector_model-weights_manifest.json \
    && wget -q -O /app/models/face-api/tiny_face_detector_model.bin https://cdn.jsdelivr.net/npm/@vladmandic/face-api@${FACE_API_MODEL_VERSION}/model/tiny_face_detector_model.bin \
    && wget -q -O /app/models/face-api/ssd_mobilenetv1_model-weights_manifest.json https://cdn.jsdelivr.net/npm/@vladmandic/face-api@${FACE_API_MODEL_VERSION}/model/ssd_mobilenetv1_model-weights_manifest.json \
    && wget -q -O /app/models/face-api/ssd_mobilenetv1_model.bin https://cdn.jsdelivr.net/npm/@vladmandic/face-api@${FACE_API_MODEL_VERSION}/model/ssd_mobilenetv1_model.bin \
    && wget -q -O /app/models/face-api/face_landmark_68_model-weights_manifest.json https://cdn.jsdelivr.net/npm/@vladmandic/face-api@${FACE_API_MODEL_VERSION}/model/face_landmark_68_model-weights_manifest.json \
    && wget -q -O /app/models/face-api/face_landmark_68_model.bin https://cdn.jsdelivr.net/npm/@vladmandic/face-api@${FACE_API_MODEL_VERSION}/model/face_landmark_68_model.bin \
    && wget -q -O /app/models/face-api/face_recognition_model-weights_manifest.json https://cdn.jsdelivr.net/npm/@vladmandic/face-api@${FACE_API_MODEL_VERSION}/model/face_recognition_model-weights_manifest.json \
    && wget -q -O /app/models/face-api/face_recognition_model.bin https://cdn.jsdelivr.net/npm/@vladmandic/face-api@${FACE_API_MODEL_VERSION}/model/face_recognition_model.bin \
    && chown -R nestjs:nodejs /app/uploads /app/models

# Copy production dependencies from build stage
COPY --from=build --chown=nestjs:nodejs /app/node_modules ./node_modules

# Copy built application from build stage
COPY --from=build --chown=nestjs:nodejs /app/dist ./dist

# Copy package.json for runtime reference
COPY --chown=nestjs:nodejs package*.json ./

# Switch to non-root user
USER nestjs

# Expose the application port
EXPOSE 80

# Start the application
CMD ["node", "dist/main.js"]
