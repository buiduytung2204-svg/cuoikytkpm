FROM node:22-alpine

WORKDIR /app

# Copy package definitions
COPY package*.json ./

# Install production dependencies
RUN npm ci --omit=dev

# Copy application files
COPY server.js giai-dau.html ./

# Environment defaults
ENV NODE_ENV=production \
    PORT=8000 \
    HOST=0.0.0.0

EXPOSE 8000

CMD ["node", "server.js"]
