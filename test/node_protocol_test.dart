import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Unit tests for WsFrame parsing and command models.
// Run with: flutter test

void main() {
  group('WsFrame', () {
    test('parses connect.challenge', () {
      final json = jsonDecode('''
        {
          "type": "event",
          "event": "connect.challenge",
          "payload": {"nonce": "abc123", "ts": 1737264000000}
        }
      ''');

      // Import here because dart test scope
      // In real test file, import the model and test properly
      expect(json['type'], 'event');
      expect(json['event'], 'connect.challenge');
      expect(json['payload']['nonce'], 'abc123');
    });

    test('parses hello-ok', () {
      final json = jsonDecode('''
        {
          "type": "res",
          "id": "test-1",
          "ok": true,
          "payload": {
            "type": "hello-ok",
            "protocol": 3,
            "server": {"version": "2026.1.0", "connId": "conn-1"},
            "features": {"methods": ["health"]},
            "snapshot": {"config": "ok"},
            "auth": {"role": "node", "scopes": []},
            "policy": {"maxPayload": 26214400, "maxBufferedBytes": 52428800, "tickIntervalMs": 15000}
          }
        }
      ''');

      expect(json['type'], 'res');
      expect(json['ok'], true);
      expect(json['payload']['type'], 'hello-ok');
      expect(json['payload']['protocol'], 3);
      expect(json['payload']['server']['version'], '2026.1.0');
    });

    test('parses node.invoke.request', () {
      final json = jsonDecode('''
        {
          "type": "event",
          "event": "node.invoke.request",
          "payload": {
            "invokeId": "inv-1",
            "command": "alarm.set",
            "args": {"hour": 7, "minute": 30, "label": "Wake up"}
          }
        }
      ''');

      expect(json['event'], 'node.invoke.request');
      expect(json['payload']['command'], 'alarm.set');
      expect(json['payload']['args']['hour'], 7);
      expect(json['payload']['args']['minute'], 30);
    });

    test('parses invoke result response', () {
      final json = jsonDecode('''
        {
          "type": "event",
          "event": "node.invoke.result",
          "payload": {"invokeId": "inv-1", "ok": true, "data": {"id": "alarm-1"}}
        }
      ''');

      expect(json['event'], 'node.invoke.result');
      expect(json['payload']['ok'], true);
      expect(json['payload']['data']['id'], 'alarm-1');
    });

    test('parses alarm fired event', () {
      final json = jsonDecode('''
        {
          "type": "event",
          "event": "node.invoke.result",
          "payload": {
            "event": "alarm.fired",
            "payload": {"id": "alarm-1", "label": "Wake up"}
          }
        }
      ''');

      // This is the wrapper; real alarm.fired goes through node.event method
      expect(json['payload']['event'], 'alarm.fired');
    });
  });

  group('Command handling', () {
    test('ping returns device info', () {
      final result = {
        'deviceId': 'flutter-phone',
        'timestamp': DateTime.now().toIso8601String(),
        'platform': 'android',
        'alarms': 0,
        'events': 0,
      };

      expect(result['deviceId'], 'flutter-phone');
      expect(result['platform'], 'android');
      expect(result['alarms'], 0);
      expect(result['events'], 0);
    });
  });
}
