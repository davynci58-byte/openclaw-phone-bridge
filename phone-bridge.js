#!/usr/bin/env node
// Agent bridge to the phone relay server
// Usage: node phone-bridge.js <command> [args...]
//   node phone-bridge.js phone.ping
//   node phone-bridge.js alarm.set '{"hour":7,"minute":0,"label":"Wake up"}'
//   node phone-bridge.js alarm.list
//   node phone-bridge.js calendar.list
//   node phone-bridge.js notification.send '{"title":"Hello","body":"Test"}'

const WebSocket = require('ws');
const RELAY_URL = process.env.RELAY_URL || 'ws://127.0.0.1:8765';
const AUTH_TOKEN = process.env.RELAY_TOKEN || '5720c3d31ae1cb0063506b6a014f43a242f3ec436a5fa18a';

async function main() {
  const command = process.argv[2];
  if (!command) {
    console.error('Usage: phone-bridge.js <command> [jsonArgs]');
    console.error('Commands: phone.ping, alarm.set, alarm.list, alarm.clear,');
    console.error('          calendar.list, calendar.add, calendar.remove,');
    console.error('          notification.send');
    process.exit(1);
  }

  const args = process.argv[3] ? JSON.parse(process.argv[3]) : {};
  const requestId = `agent-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

  const ws = new WebSocket(RELAY_URL);
  const timeout = setTimeout(() => {
    console.error('Timeout waiting for response');
    ws.close();
    process.exit(1);
  }, 10000);

  ws.on('open', () => {
    // Wait for auth challenge, then send auth
  });

  ws.on('message', (raw) => {
    const msg = JSON.parse(raw.toString());

    if (msg.type === 'auth.challenge') {
      ws.send(JSON.stringify({
        type: 'auth',
        token: AUTH_TOKEN,
        role: 'agent',
        name: 'Artoria',
      }));
      return;
    }

    if (msg.type === 'auth.ok') {
      // Send the command
      ws.send(JSON.stringify({
        type: 'invoke',
        requestId,
        command,
        args,
      }));
      return;
    }

    if (msg.type === 'invoke.result' && msg.requestId === requestId) {
      clearTimeout(timeout);
      console.log(JSON.stringify(msg, null, 2));
      ws.close();
      process.exit(0);
    }

    if (msg.type === 'error') {
      console.error('Error:', msg.message);
      ws.close();
      process.exit(1);
    }
  });

  ws.on('error', (err) => {
    console.error('Connection error:', err.message);
    process.exit(1);
  });
}

main();
