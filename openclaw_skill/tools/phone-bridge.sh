#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# Phone Bridge Tool — calls node.invoke on the OpenClaw Gateway to
# control the paired phone (alarms, calendar, notifications).
#
# Usage: phone-bridge <command> [json-args]
#
# Commands:
#   phone.ping              Check phone connection
#   alarm.set               Set alarm  (args: hour minute label [repeatDays])
#   alarm.list              List all alarms
#   alarm.clear [id]        Clear one or all alarms
#   alarm.toggle <id>       Enable/disable an alarm
#   calendar.list           List calendar events
#   calendar.add            Add event  (args: title startTime endTime [description])
#   calendar.remove <id>    Remove event
#   calendar.upcoming [h]   Upcoming events (default 24h)
#   notification.send       Send notification (args: title body)
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <command> [json-args]" >&2
  echo ""
  echo "Commands: phone.ping, alarm.set, alarm.list, alarm.clear,"
  echo "         alarm.toggle, calendar.list, calendar.add,"
  echo "         calendar.remove, calendar.upcoming, notification.send"
  exit 1
fi

COMMAND="$1"
shift

# Build args JSON from remaining CLI args or stdin
ARGS="{}"
if [ $# -gt 0 ]; then
  # Check if remaining args are already JSON
  if [[ "$1" == \{* ]]; then
    ARGS="$1"
  else
    # Build JSON from key=value pairs
    BUILD=""
    for pair in "$@"; do
      KEY="${pair%%=*}"
      VAL="${pair#*=}"
      # Try parsing as number, fallback to string
      if [[ "$VAL" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        BUILD+="\"$KEY\": $VAL,"
      elif [[ "$VAL" == "true" ]] || [[ "$VAL" == "false" ]]; then
        BUILD+="\"$KEY\": $VAL,"
      elif [[ "$VAL" == \{* ]]; then
        BUILD+="\"$KEY\": $VAL,"
      elif [[ "$VAL" == \[* ]]; then
        BUILD+="\"$KEY\": $VAL,"
      else
        BUILD+="\"$KEY\": \"$VAL\","
      fi
    done
    ARGS="{${BUILD%,}}"
  fi
fi

# ── OpenClaw CLI invoke ──────────────────────────────────────────────
# This uses the openclaw CLI to call node.invoke on the default gateway.
# The CLI must be configured / have gateway access.

echo "📱 Phone Bridge → $COMMAND"
echo "   Args: $ARGS"

# shellcheck disable=SC2086
openclaw node invoke "$COMMAND" "$ARGS" 2>&1 || {
  EXIT_CODE=$?
  if [ "$EXIT_CODE" == "1" ]; then
    echo ""
    echo "⚠️  Command failed. Possible causes:"
    echo "   - Phone not connected (check green dot in app)"
    echo "   - Node not paired (run: openclaw nodes list)"
    echo "   - Command not in node capabilities"
  fi
  exit $EXIT_CODE
}
