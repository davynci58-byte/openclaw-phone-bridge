# Phone Bridge Skill

Control your paired phone's alarms, calendar, and notifications through the OpenClaw Gateway node protocol.

## How it works

The Phone Bridge Flutter app connects to this OpenClaw instance **as a node** via WebSocket. Once paired, you can invoke commands on the phone by calling the `phone-bridge` tool.

## Dependencies

- The Phone Bridge Flutter app must be installed on the target device and connected to this Gateway (node paired).
- Gateway node-invoke access must be enabled for your session scope.

## Commands

### Phone Bridge — tool-based invoke

OpenClaw uses `node.invoke` to send commands to the paired phone node.

Available commands:

| Command | Purpose |
|---------|---------|
| `phone.ping` | Check if the phone bridge is connected |
| `alarm.set` | Set a new alarm on the phone |
| `alarm.list` | List all alarms on the phone |
| `alarm.clear` | Clear one or all alarms |
| `alarm.toggle` | Enable/disable an alarm |
| `calendar.list` | List all calendar events |
| `calendar.add` | Add a new calendar event |
| `calendar.remove` | Remove a calendar event |
| `calendar.upcoming` | List upcoming events within N hours |
| `notification.send` | Send a push notification to the phone |

## Examples

### Check if phone is connected

**You say:**
> Check if my phone is connected

**OpenClaw runs:**
```
node.invoke phone.ping
```

### Set an alarm

**You say:**
> Set an alarm for 6:30 AM tomorrow called "Morning run"

**OpenClaw runs:**
```
node.invoke alarm.set {"hour":6,"minute":30,"label":"Morning run"}
```

### Check calendar

**You say:**
> What's on my calendar today?

**OpenClaw runs:**
```
node.invoke calendar.upcoming {"hours":12}
```

### Add a calendar event

**You say:**
> Add a dentist appointment on Friday at 2 PM to my calendar

**OpenClaw runs:**
```
node.invoke calendar.add {"title":"Dentist","startTime":"2026-05-22T14:00:00","endTime":"2026-05-22T15:00:00","description":"Dentist appointment","reminderMinutes":30}
```

### Send a notification

**You say:**
> Send a notification to my phone: "Don't forget to buy milk"

**OpenClaw runs:**
```
node.invoke notification.send {"title":"Reminder","body":"Don't forget to buy milk"}
```

## Event Monitoring

The phone sends events back to OpenClaw automatically:

- `alarm.fired` — An alarm went off on the phone
- `calendar.reminder` — A calendar event reminder is due

These appear as system events in your OpenClaw session.

## Troubleshooting

- **"Node not connected"**: Make sure the Flutter app is running and connected to the Gateway (check the green dot in the app bar).
- **"Command not found"**: Verify the phone app's capabilities match what OpenClaw expects.
- **"Reconnecting"**: The app auto-reconnects with exponential backoff. Check your VPS firewall (port must be open).
- If using WSS and a self-signed cert, the app must trust your certificate or the connection will fail.
