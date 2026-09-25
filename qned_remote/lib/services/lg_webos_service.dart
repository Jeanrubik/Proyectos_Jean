import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class LgWebOsException implements Exception {
  LgWebOsException(this.message);
  final String message;

  @override
  String toString() => message;
}

class LgWebOsService {
  static const _permissions = <String>[
    'LAUNCH',
    'LAUNCH_WEBAPP',
    'APP_TO_APP',
    'CLOSE',
    'CONTROL_AUDIO',
    'CONTROL_INPUT_MEDIA_PLAYBACK',
    'CONTROL_INPUT_TV',
    'CONTROL_POWER',
    'CONTROL_TV_SCREEN',
    'CONTROL_INPUT_TEXT',
    'CONTROL_MOUSE_AND_KEYBOARD',
    'READ_APP_STATUS',
    'READ_CURRENT_CHANNEL',
    'READ_INPUT_DEVICE_LIST',
    'READ_NETWORK_STATE',
    'READ_RUNNING_APPS',
    'READ_POWER_STATE',
    'READ_TV_CHANNEL_LIST',
    'WRITE_NOTIFICATION_TOAST',
  ];

  IOWebSocketChannel? _main;
  WebSocketChannel? _pointer;
  StreamSubscription<dynamic>? _mainSub;
  StreamSubscription<dynamic>? _pointerSub;

  final _pending = <String, Completer<Map<String, dynamic>>>{};
  Completer<String?>? _registrationCompleter;
  int _requestCounter = 0;
  bool _registered = false;

  String? clientKey;
  String? learnedWifiMac;
  String? learnedWiredMac;

  bool get isConnected => _registered && _main != null;

  Future<void> connect({required String ip, String? savedClientKey}) async {
    await disconnect();
    final channel = await _connectMain(ip);

    _main = channel;
    _registrationCompleter = Completer<String?>();

    _mainSub = channel.stream.listen(
      _handleMainMessage,
      onError: (Object error, StackTrace stack) {
        _failRegistration(error);
        _failPending(error);
      },
      onDone: () {
        _failRegistration(LgWebOsException('El TV cerró la conexión.'));
        _failPending(LgWebOsException('Conexión con el TV cerrada.'));
        _registered = false;
      },
      cancelOnError: false,
    );

    try {
      // Enviamos el registro DIRECTAMENTE (webOS ignora comandos antes de registrarse)
      await _sendRegister(savedClientKey ?? clientKey);
      
      final key = await _registrationCompleter!.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw LgWebOsException(
          'Tiempo agotado esperando la autorización del TV. Acepta el aviso en la pantalla.',
        ),
      );

      if (key == null || key.isEmpty) {
        throw LgWebOsException('No se recibió la clave de emparejamiento.');
      }

      clientKey = key;
      _registered = true;
      await _openPointerSocket();
      await _learnMacAddresses();
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  Future<IOWebSocketChannel> _connectMain(String ip) async {
    Future<IOWebSocketChannel> open(Uri uri) async {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5)
        ..badCertificateCallback = (cert, host, port) => true;
      final channel = IOWebSocketChannel.connect(
        uri,
        customClient: client,
        connectTimeout: const Duration(seconds: 5),
        pingInterval: const Duration(seconds: 20),
      );
      await channel.ready;
      return channel;
    }

    try {
      return await open(Uri.parse('ws://$ip:3000'));
    } catch (_) {
      return open(Uri.parse('wss://$ip:3001'));
    }
  }

  Future<void> _sendRegister(String? key) async {
    final manifest = <String, dynamic>{
      'manifestVersion': 1,
      'appVersion': '1.0.0',
      'permissions': _permissions,
    };

    final message = <String, dynamic>{
      'type': 'register',
      'id': 'register_0',
      'payload': {
        'forcePairing': false,
        'pairingType': 'PROMPT',
        'client-key': key,
        'manifest': manifest,
        'permissions': _permissions,
      },
    };
    _main!.sink.add(jsonEncode(message));
  }

  void _handleMainMessage(dynamic raw) {
    if (raw is! String) return;

    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      data = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }

    final type = data['type'];
    final id = data['id']?.toString();
    final payload = data['payload'];

    if (id == 'register_0') {
      if (type == 'response' && payload is Map && payload['pairingType'] == 'PROMPT') {
        // La TV está desplegando el aviso en pantalla para que el usuario acepte
        return;
      }
      if (type == 'registered' && payload is Map) {
        final key = payload['client-key']?.toString();
        if (key != null && key.isNotEmpty && !(_registrationCompleter?.isCompleted ?? true)) {
          _registrationCompleter!.complete(key);
        }
      } else if (type == 'error') {
        _failRegistration(LgWebOsException(
          data['error']?.toString() ?? 'El TV rechazó el emparejamiento.',
        ));
      }
      return;
    }

    if (id != null) {
      final completer = _pending.remove(id);
      if (completer != null && !completer.isCompleted) {
        if (type == 'error') {
          completer.completeError(LgWebOsException(
            data['error']?.toString() ?? 'El TV rechazó la solicitud.',
          ));
        } else {
          final map = payload is Map
              ? Map<String, dynamic>.from(payload)
              : <String, dynamic>{};
          if (map['returnValue'] == false) {
            completer.completeError(LgWebOsException(
              map['errorText']?.toString() ?? 'La operación fue rechazada por el TV.',
            ));
          } else {
            completer.complete(map);
          }
        }
      }
    }
  }

  Future<Map<String, dynamic>> request(
    String uri, {
    Map<String, dynamic>? payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!isConnected) {
      throw LgWebOsException('El TV no está conectado.');
    }

    final id = 'req_${++_requestCounter}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    _main!.sink.add(jsonEncode({
      'type': 'request',
      'id': id,
      'uri': uri,
      'payload': payload ?? <String, dynamic>{},
    }));

    try {
      return await completer.future.timeout(timeout);
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> _openPointerSocket() async {
    final response = await request(
      'ssap://com.webos.service.networkinput/getPointerInputSocket',
    );
    final socketPath = response['socketPath']?.toString();
    if (socketPath == null || socketPath.isEmpty) {
      throw LgWebOsException('El TV no entregó el canal para el cursor.');
    }

    final uri = Uri.parse(socketPath);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..badCertificateCallback = (cert, host, port) => true;

    final pointer = IOWebSocketChannel.connect(
      uri,
      customClient: client,
      connectTimeout: const Duration(seconds: 8),
      pingInterval: const Duration(seconds: 20),
    );

    _pointer = pointer;
    _pointerSub = pointer.stream.listen(
      (_) {},
      onError: (_) {},
      onDone: () {},
      cancelOnError: false,
    );
    await pointer.ready;
  }

  void _sendPointer(String message) {
    if (_pointer == null) return;
    _pointer!.sink.add(message);
  }

  void button(String name) {
    _sendPointer('type:button\nname:$name\n\n');
  }

  void move(double dx, double dy, {bool drag = false}) {
    _sendPointer(
      'type:move\ndx:${dx.toStringAsFixed(2)}\ndy:${dy.toStringAsFixed(2)}\ndown:${drag ? 1 : 0}\n\n',
    );
  }

  void click() {
    _sendPointer('type:click\n\n');
  }

  void scroll(double dx, double dy) {
    _sendPointer(
      'type:scroll\ndx:${dx.toStringAsFixed(2)}\ndy:${dy.toStringAsFixed(2)}\n\n',
    );
  }

  Future<void> volumeUp() => request('ssap://audio/volumeUp').then((_) {});
  Future<void> volumeDown() => request('ssap://audio/volumeDown').then((_) {});
  Future<void> mute(bool value) => request(
        'ssap://audio/setMute',
        payload: {'mute': value},
      ).then((_) {});

  Future<int?> getVolume() async {
    final result = await request('ssap://audio/getVolume');
    final value = result['volume'];
    if (value is num) return value.round();
    return null;
  }

  Future<String?> getPowerState() async {
    final result = await request(
      'ssap://com.webos.service.tvpower/power/getPowerState',
    );
    return result['state']?.toString();
  }

  Future<void> turnOff() => request('ssap://system/turnOff').then((_) {});

  Future<void> home() async => button('HOME');
  Future<void> back() async => button('BACK');
  Future<void> ok() async => button('ENTER');
  Future<void> left() async => button('LEFT');
  Future<void> right() async => button('RIGHT');
  Future<void> up() async => button('UP');
  Future<void> down() async => button('DOWN');
  Future<void> channelUp() async => button('CHANNELUP');
  Future<void> channelDown() async => button('CHANNELDOWN');

  Future<void> _learnMacAddresses() async {
    try {
      final result = await request(
        'ssap://com.webos.service.connectionmanager/getinfo',
      );
      final wifi = result['wifiInfo'];
      final wired = result['wiredInfo'];
      if (wifi is Map) learnedWifiMac = wifi['macAddress']?.toString();
      if (wired is Map) learnedWiredMac = wired['macAddress']?.toString();
    } catch (_) {
      // No todos los firmwares exponen esto a apps no firmadas
    }
  }

  List<String> get knownMacs => [
        if (learnedWifiMac != null && learnedWifiMac!.isNotEmpty) learnedWifiMac!,
        if (learnedWiredMac != null && learnedWiredMac!.isNotEmpty) learnedWiredMac!,
      ];

  Future<void> disconnect() async {
    _registered = false;
    for (final entry in _pending.entries) {
      if (!entry.value.isCompleted) {
        entry.value.completeError(LgWebOsException('Conexión cerrada.'));
      }
    }
    _pending.clear();

    await _pointerSub?.cancel();
    _pointerSub = null;
    await _pointer?.sink.close();
    _pointer = null;

    await _mainSub?.cancel();
    _mainSub = null;
    await _main?.sink.close();
    _main = null;
  }

  void _failRegistration(Object error) {
    final completer = _registrationCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }
  }

  void _failPending(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }
}
