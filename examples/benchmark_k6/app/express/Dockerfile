FROM node:22-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --no-audit --no-fund --loglevel=error
COPY src ./src
EXPOSE 4001
CMD ["node", "src/server.js"]