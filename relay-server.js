// Simple WebSocket relay for OpenClaw phone bridge
// No OpenClaw node protocol — just token auth + simple JSON messages
const WebSocket = require('ws');
const http = require('http');
const crypto = require('crypto');

const PORT = 8765;
const AUTH_TOKEN = process.env.RELAY_TOKEN || 'simple-relay-token';

const clients = new Map(); // id -> { ws, role, name }

function send(ws, msg) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(msg));
  }
}

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, clients: clients.size, uptime: process.uptime() }));
    return;
  }
  res.writeHead(404);
  res.end('Not found');
});

const wss = new WebSocket.Server({ server });

wss.on('connection', (ws, req) => {
  const ip = req.socket.remoteAddress;
  let authenticated = false;
  let clientId = null;
  let clientRole = null;
  let clientName = null;
  let pingTimer = null;

  send(ws, { type: 'auth.challenge', nonce: crypto.randomUUID() });

  const authTimeout = setTimeout(() => {
    if (!authenticated) {
      ws.close(4001, 'auth timeout');
    }
  }, 10000);

  ws.on('message', (data) => {
    let msg;
    try {
      msg = JSON.parse(data.toString());
    } catch {
      return;
    }

    if (!authenticated) {
      if (msg.type === 'auth' && msg.token === AUTH_TOKEN) {
        clearTimeout(authTimeout);
        authenticated = true;
        clientId = msg.clientId || crypto.randomUUID();
        clientRole = msg.role || 'phone';
        clientName = msg.name || clientId;
        clients.set(clientId, { ws, role: clientRole, name: clientName });
        send(ws, { type: 'auth.ok', clientId, serverTime: Date.now() });
        console.log(`[+] ${clientName} (${clientRole}) from ${ip}`);

        pingTimer = setInterval(() => {
          if (ws.readyState === WebSocket.OPEN) ws.ping();
        }, 30000);
      }
      return;
    }

    switch (msg.type) {
      case 'ping':
        send(ws, { type: 'pong', serverTime: Date.now() });
        break;

      case 'invoke':
        // Forward to the opposite role (agent <-> phone)
        forwardToRole(msg, clientRole, clientName);
        break;

      case 'invoke.result':
      case 'event':
        // Forward back to the other side
        forwardToRole(msg, clientRole, clientName);
        break;

      default:
        send(ws, { type: 'error', message: `Unknown: ${msg.type}` });
    }
  });

  function forwardToRole(msg, fromRole, fromName) {
    const targetRole = fromRole === 'agent' ? 'phone' : 'agent';
    let sent = false;
    for (const [, client] of clients) {
      if (client.role === targetRole && client.ws.readyState === WebSocket.OPEN) {
        send(client.ws, msg);
        sent = true;
      }
    }
    if (!sent && msg.type === 'invoke') {
      // Return error to sender if no target connected
      send(ws, {
        type: 'invoke.result',
        requestId: msg.requestId,
        ok: false,
        error: `${targetRole} not connected`
      });
    }
    if (sent && msg.type === 'event') {
      console.log(`[event] ${fromName}: ${msg.event}`);
    }
  }

  ws.on('close', () => {
    clearTimeout(authTimeout);
    clearInterval(pingTimer);
    if (clientId) {
      clients.delete(clientId);
      console.log(`[-] ${clientName || clientId} (${clientRole}) disconnected`);
    }
  });

  ws.on('error', () => {});
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Relay on port ${PORT}, token: ${AUTH_TOKEN.substring(0, 8)}...`);
});

process.on('SIGTERM', () => {
  for (const [, client] of clients) client.ws.close(1001);
  server.close();
  process.exit(0);
});
