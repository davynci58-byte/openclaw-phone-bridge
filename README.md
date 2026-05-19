# OpenClaw Phone Bridge 📱⚔️

A Flutter app that connects your Android phone as a **node** to your OpenClaw Gateway VPS, giving your AI agent control over phone alarms, calendar, and notifications.

## Architecture

```
┌─────────────────┐     WebSocket (WSS)      ┌─────────────────┐
│                  │◄────────────────────────►│                  │
│   Flutter App    │    OpenClaw Gateway      │  OpenClaw Agent │
│   (Your Phone)  │    Protocol (node role)   │   (Your VPS)    │
│                  │                          │                  │
│  ● Calendar      │  ◄── node.invoke ────   │  Sets alarms,   │
│  ● Alarms        │  ──── node.event ──►    │  checks cal,    │
│  ● Notifications │                          │  sends notifs   │
└─────────────────┘                          └─────────────────┘
```

## Features

- 🔗 **Persistent WebSocket connection** to your OpenClaw VPS
- 🔐 **Ed25519 crypto** for device identity
- 📅 **Calendar management** — view, add, edit, delete events
- ⏰ **Alarm management** — set, snooze, repeat alarms
- 🔔 **Push notifications** — OpenClaw sends alerts to your phone
- ⚡ **Two-way** — phone sends alarm-firing events back to OpenClaw
- 🔄 **Auto-reconnect** with exponential backoff

## Getting Started

### 1. OpenClaw VPS — Enable Gateway WS

Ensure your OpenClaw Gateway accepts WebSocket connections. Default port is `443` (HTTPS) with TLS, or a custom port.

```bash
# Check Gateway status
openclaw status
openclaw gateway status
```

Your VPS needs to be reachable from your phone (public IP or Tailscale).

### 2. Gateway Auth Token

Set a gateway auth token:

```bash
openclaw config patch '{"gateway":{"auth":{"mode":"token","token":"your-secret-token-here"}}}'
openclaw gateway restart
```

Save this token — you'll put it in the Flutter app.

### 3. Install OpenClaw Skill

Copy the skill folder:

```bash
cp -r openclaw_skill/ ~/.openclaw/workspace/skills/phone-bridge/
```

Or install via ClawHub if published.

### 4. Build the Flutter App

```bash
cd flutter_openclaw_app/
flutter pub get
flutter build apk --release
```

### 5. Configure & Run

1. Open the app on your phone
2. Go to **Settings** → enter your VPS host/IP, port, and gateway token
3. Tap **Reconnect**
4. On your VPS, check the node is connected: `openclaw nodes list`
5. The connection dot turns **green** ✓

### 6. Approve the Node on VPS

First time connecting, you'll need to approve the pairing:

```bash
openclaw nodes list          # Shows pending node
openclaw nodes approve       # Approve the new phone node
```

## Important: Android Permissions

The app requires these permissions (set in AndroidManifest.xml):

- `POST_NOTIFICATIONS` — Alarm & notification display
- `SCHEDULE_EXACT_ALARM` — Precise alarm timing
- `USE_EXACT_ALARM` — Exact alarm permission (Android 12+)
- `VIBRATE` — Alarm vibration
- `RECEIVE_BOOT_COMPLETED` — Restore alarms after reboot
- `READ_CALENDAR` / `WRITE_CALENDAR` — Native calendar integration

## Configuration

Edit `lib/config.dart` or use the in-app Settings screen:

| Setting | Default | Description |
|---------|---------|-------------|
| `gatewayHost` | `your-vps-ip-or-domain.com` | VPS address |
| `gatewayPort` | `443` | WebSocket port |
| `useTls` | `true` | Use WSS (always true for remote) |
| `gatewayToken` | `''` | Your OpenClaw gateway token |
| `deviceDisplayName` | `Kono's Phone` | Name in node list |

## OpenClaw Usage

Once connected, just ask your agent anything:

> **"Set an alarm for 6 AM tomorrow called 'Morning run'"**
>
> **"What's on my calendar today?"**
>
> **"Add a dentist appointment for Friday at 2 PM"**
>
> **"Send a notification to my phone: Don't forget to buy milk"**
>
> **"Check if my phone is connected"**

## File Structure

```
flutter_openclaw_app/
├── pubspec.yaml                    # Dependencies
├── lib/
│   ├── main.dart                   # Entry point + command handler
│   ├── config.dart                 # VPS connection settings
│   ├── models/
│   │   ├── calendar_event.dart     # Calendar event model
│   │   ├── alarm.dart              # Device alarm model
│   │   └── openclaw_command.dart   # WS protocol frame models
│   ├── services/
│   │   ├── openclaw_node_service.dart  # 🔑 Gateway node protocol
│   │   ├── calendar_service.dart       # Calendar CRUD
│   │   ├── alarm_service.dart          # Alarm CRUD + notifications
│   │   ├── notification_service.dart   # Push notifications
│   │   └── storage_service.dart        # Local persistence
│   ├── screens/
│   │   ├── home_screen.dart            # Dashboard
│   │   ├── calendar_screen.dart        # Calendar view
│   │   ├── alarm_screen.dart           # Alarm manager
│   │   └── settings_screen.dart        # Connection config
│   └── widgets/
│       └── connection_status.dart      # Status indicator
├── openclaw_skill/
│   └── SKILL.md                    # OpenClaw skill doc
└── README.md                       # This file
```

## Security

- **Ed25519 keys**: Each device generates a unique keypair on first launch
- **Challenge-response**: Connect handshake uses server nonce + Ed25519 signing
- **Device tokens**: Gateway issues scoped tokens after pairing
- **Gateway token**: Your VPS auth token stays in the app config
- All credentials are stored in the app's private storage only

## License

Made for Kono by Artoria ⚔️
