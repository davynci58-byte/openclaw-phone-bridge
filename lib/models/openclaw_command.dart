/// Models for OpenClaw Gateway node protocol commands + events.

/// An invoke command received from the Gateway.
class NodeInvoke {
  final String command;
  final Map<String, dynamic> args;
  final String invokeId;

  NodeInvoke({
    required this.command,
    required this.args,
    required this.invokeId,
  });

  factory NodeInvoke.fromJson(Map<String, dynamic> json) => NodeInvoke(
        command: json['command'] as String,
        args: (json['args'] as Map<String, dynamic>?) ?? {},
        invokeId: json['invokeId'] as String? ?? '',
      );
}

/// Result sent back for an invoke command.
class InvokeResult {
  final String invokeId;
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;

  InvokeResult({
    required this.invokeId,
    required this.success,
    this.data,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'invokeId': invokeId,
        'success': success,
        if (data != null) 'data': data,
        if (error != null) 'error': error,
      };
}

/// An event the node (app) sends to the Gateway.
class NodeEvent {
  final String event;
  final Map<String, dynamic> payload;

  NodeEvent({required this.event, required this.payload});

  Map<String, dynamic> toJson() => {
        'event': event,
        'payload': payload,
      };
}

/// Websocket frame types used in the Gateway protocol.
class WsFrame {
  static const String req = 'req';
  static const String res = 'res';
  static const String event = 'event';

  final String type;
  final String? id;
  final String? method;
  final Map<String, dynamic>? params;
  final String? eventName;
  final Map<String, dynamic>? payload;
  final bool? ok;
  final String? error;

  WsFrame({
    required this.type,
    this.id,
    this.method,
    this.params,
    this.eventName,
    this.payload,
    this.ok,
    this.error,
  });

  factory WsFrame.fromJson(Map<String, dynamic> json) {
    return WsFrame(
      type: json['type'] as String,
      id: json['id'] as String?,
      method: json['method'] as String?,
      params: json['params'] as Map<String, dynamic>?,
      eventName: json['event'] as String?,
      payload: json['payload'] as Map<String, dynamic>?,
      ok: json['ok'] as bool?,
      error: json['error'] as String?,
    );
  }

  bool get isConnectChallenge =>
      type == event && eventName == 'connect.challenge';

  bool get isHelloOk => type == res && ok == true && id != null && method == 'connect';

  bool get isInvokeRequest =>
      type == event && eventName == 'node.invoke.request';

  bool get isTick => type == event && eventName == 'tick';

  bool get isShutdown => type == event && eventName == 'shutdown';
}
