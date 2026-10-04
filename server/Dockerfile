# sama-chat server — production container
FROM node:22-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY src ./src

# Uploaded images + JSON data live here; mount a volume to persist.
ENV PORT=8080 \
    DATA_DIR=/app/data \
    UPLOAD_DIR=/app/data/uploads
RUN mkdir -p /app/data

EXPOSE 8080
CMD ["node", "src/index.js"]
