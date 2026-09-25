import 'dart:io';
import 'dart:typed_data';

class WakeOnLan {
  static Future<void> wake(String mac, {int attempts = 3}) async {
    final normalized = mac.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (normalized.length != 12) {
      throw ArgumentError('MAC inválida. Usa un formato como AA:BB:CC:DD:EE:FF.');
    }

    final macBytes = <int>[];
    for (var i = 0; i < 12; i += 2) {
      macBytes.add(int.parse(normalized.substring(i, i + 2), radix: 16));
    }

    final packet = BytesBuilder();
    packet.add(Uint8List.fromList(List<int>.filled(6, 0xFF)));
    for (var i = 0; i < 16; i++) {
      packet.add(Uint8List.fromList(macBytes));
    }

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      socket.broadcastEnabled = true;
      final data = packet.toBytes();
      for (var i = 0; i < attempts; i++) {
        socket.send(data, InternetAddress('255.255.255.255'), 9);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    } finally {
      socket.close();
    }
  }
}
