FROM node:20-alpine
WORKDIR /app

# Install only what the REST server needs — skip the msnodesqlv8/ssh2 native
# builds that the full package.json would pull in.
RUN npm install --no-save express@^5 mssql@^11

# Code + the board HTML, preserving the paths task-server.js expects
# (__dirname/../_bmad/bmm/tasks/ha-tasks.html).
COPY tools/task-server.js          /app/tools/task-server.js
COPY _bmad/bmm/tasks/ha-tasks.html /app/_bmad/bmm/tasks/ha-tasks.html

EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3001/api/tasks/stats',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "tools/task-server.js"]
