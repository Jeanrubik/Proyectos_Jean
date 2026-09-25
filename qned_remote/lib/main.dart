import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'services/lg_webos_service.dart';
import 'services/wake_on_lan.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QnedRemoteApp());
}

class QnedRemoteApp extends StatelessWidget {
  const QnedRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'QNED Remote',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.redAccent,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        useMaterial3: true,
      ),
      home: const RemoteHomePage(),
    );
  }
}

class RemoteHomePage extends StatefulWidget {
  const RemoteHomePage({super.key});

  @override
  State<RemoteHomePage> createState() => _RemoteHomePageState();
}

class _RemoteHomePageState extends State<RemoteHomePage> {
  static const _storage = FlutterSecureStorage();
  static const _ipKey = 'tv_ip';
  static const _macKey = 'tv_mac';
  static const _clientKey = 'webos_client_key';

  final _ipController = TextEditingController();
  final _macController = TextEditingController();
  final _service = LgWebOsService();

  String _status = 'Desconectado';
  bool _busy = false;
  bool _connected = false;
  bool _muted = false;
  bool _showTouchpad = true;
  int? _volume;
  String? _powerState;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final ip = await _storage.read(key: _ipKey);
    final mac = await _storage.read(key: _macKey);
    if (!mounted) return;
    setState(() {
      _ipController.text = ip ?? '';
      _macController.text = mac ?? '';
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    _macController.dispose();
    _service.disconnect();
    super.dispose();
  }

  Future<void> _connect() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      _toast('Ingresa la IP del TV.');
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Conectando…';
    });

    try {
      await _storage.write(key: _ipKey, value: ip);
      final key = await _storage.read(key: _clientKey);
      await _service.connect(ip: ip, savedClientKey: key);

      final knownMacs = _service.knownMacs;
      if (knownMacs.isNotEmpty) {
        await _storage.write(key: _macKey, value: knownMacs.first);
        _macController.text = knownMacs.first;
      }

      final power = await _service.getPowerState();
      final vol = await _service.getVolume();
      final newKey = _service.clientKey;

      if (newKey != null) {
        await _storage.write(key: _clientKey, value: newKey);
      }

      if (!mounted) return;
      setState(() {
        _connected = true;
        _powerState = power;
        _volume = vol;
        _status = 'Conectado';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connected = false;
        _status = 'No se pudo conectar';
      });
      _toast(e.toString().replaceFirst('LgWebOsException: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    await _service.disconnect();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _status = 'Desconectado';
    });
  }

  Future<void> _power() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_connected) {
        await _service.turnOff();
        if (mounted) setState(() => _powerState = 'Suspend');
      } else {
        final mac = _macController.text.trim();
        if (mac.isEmpty) {
          _toast('Conecta el TV una vez para aprender su MAC y habilitar encendido por red.');
          return;
        }
        await WakeOnLan.wake(mac);
        _toast('Paquete de encendido enviado. Espera unos segundos y pulsa Conectar.');
      }
    } catch (e) {
      _toast(e.toString().replaceFirst('LgWebOsException: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _volume(bool up) async {
    if (!_connected) return;
    try {
      if (up) {
        await _service.volumeUp();
      } else {
        await _service.volumeDown();
      }
      final volume = await _service.getVolume();
      if (mounted) setState(() => _volume = volume);
    } catch (e) {
      _toast(e.toString().replaceFirst('LgWebOsException: ', ''));
    }
  }

  Future<void> _toggleMute() async {
    if (!_connected) return;
    try {
      final targetMute = !_muted;
      await _service.mute(targetMute);
      if (mounted) {
        setState(() {
          _muted = targetMute;
        });
      }
    } catch (e) {
      _toast(e.toString().replaceFirst('LgWebOsException: ', ''));
    }
  }

  Future<void> _saveSettings() async {
    await _storage.write(key: _ipKey, value: _ipController.text.trim());
    if (_macController.text.trim().isEmpty) {
      await _storage.delete(key: _macKey);
    } else {
      await _storage.write(key: _macKey, value: _macController.text.trim());
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _forgetPairing() async {
    await _service.disconnect();
    await _storage.delete(key: _clientKey);
    await _storage.delete(key: _macKey);
    if (!mounted) return;
    setState(() {
      _connected = false;
      _status = 'Emparejamiento eliminado';
      _powerState = null;
    });
    Navigator.of(context).pop();
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 8,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Ajustes del TV', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _ipController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'IP del TV',
                      hintText: '192.168.1.50',
                      prefixIcon: Icon(Icons.lan_outlined),
                    ),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _macController,
                    decoration: const InputDecoration(
                      labelText: 'MAC para encendido (opcional)',
                      hintText: 'AA:BB:CC:DD:EE:FF',
                      prefixIcon: Icon(Icons.memory_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'La MAC se aprende automáticamente al conectar el TV cuando el firmware la expone.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _saveSettings,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Guardar'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _forgetPairing,
                    icon: const Icon(Icons.link_off_outlined),
                    label: const Text('Olvidar emparejamiento'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _roundButton(IconData icon, VoidCallback? onPressed, {double size = 62}) {
    return SizedBox(
      width: size,
      height: size,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          backgroundColor: const Color(0xFF1C1C1E),
          foregroundColor: Colors.white,
        ),
        child: Icon(icon, size: size * .36),
      ),
    );
  }

  Widget _smallKey(String label, VoidCallback? onPressed) {
    return SizedBox(
      width: 66,
      height: 48,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF1C1C1E),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _touchPad() {
    if (!_showTouchpad) return const SizedBox.shrink();

    return GestureDetector(
      onPanUpdate: (details) {
        if (_connected) {
          _service.move(details.delta.dx * 3.0, details.delta.dy * 3.0);
        }
      },
      onDoubleTap: () {
        if (_connected) _service.click();
      },
      onTap: () {
        if (_connected) _service.click();
      },
      child: Container(
        width: double.infinity,
        height: 190,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF171719), Color(0xFF0F0F10)],
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app_outlined, size: 30, color: Colors.white54),
            SizedBox(height: 10),
            Text('Cursor', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('Desliza para mover · toca para seleccionar', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _dpad() {
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(top: 8, child: _roundButton(Icons.keyboard_arrow_up, _connected ? _service.up : null)),
          Positioned(bottom: 8, child: _roundButton(Icons.keyboard_arrow_down, _connected ? _service.down : null)),
          Positioned(left: 8, child: _roundButton(Icons.keyboard_arrow_left, _connected ? _service.left : null)),
          Positioned(right: 8, child: _roundButton(Icons.keyboard_arrow_right, _connected ? _service.right : null)),
          _roundButton(Icons.circle, _connected ? _service.ok : null, size: 72),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final powerColor = _connected ? Colors.redAccent : Colors.orangeAccent;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('QNED Remote', style: TextStyle(fontWeight: FontWeight.w800)),
            Text('LG 50QNED80TSA · webOS 24', style: TextStyle(fontSize: 12, color: Colors.white54)),
          ],
        ),
        actions: [
          IconButton(onPressed: _openSettings, icon: const Icon(Icons.settings_outlined)),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: const Color(0xFF121214),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: _connected ? Colors.greenAccent : Colors.white24, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_status, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          _ipController.text.isEmpty ? 'Configura la IP del TV' : _ipController.text,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : (_connected ? _disconnect : _connect),
                    icon: Icon(_connected ? Icons.link_off : Icons.link),
                    label: Text(_connected ? 'Desconectar' : 'Conectar'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ActionTile(
                    icon: _busy ? Icons.hourglass_top : Icons.power_settings_new,
                    label: _connected ? 'APAGAR' : 'ENCENDER',
                    color: powerColor,
                    onTap: _busy ? null : _power,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionTile(
                    icon: _muted ? Icons.volume_off : Icons.volume_up,
                    label: _volume == null ? 'VOLUMEN' : 'VOL $_volume',
                    color: Colors.white,
                    onTap: _connected ? _toggleMute : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _roundButton(Icons.remove, _connected ? () => _volume(false) : null, size: 56),
                const SizedBox(width: 18),
                SizedBox(
                  width: 110,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _showTouchpad = !_showTouchpad),
                    icon: Icon(_showTouchpad ? Icons.mouse_outlined : Icons.mouse),
                    label: Text(_showTouchpad ? 'Cursor' : 'Pad'),
                  ),
                ),
                const SizedBox(width: 18),
                _roundButton(Icons.add, _connected ? () => _volume(true) : null, size: 56),
              ],
            ),
            const SizedBox(height: 14),
            _touchPad(),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _smallKey('BACK', _connected ? _service.back : null),
                const SizedBox(width: 10),
                _smallKey('HOME', _connected ? _service.home : null),
                const SizedBox(width: 10),
                _smallKey('MUTE', _connected ? _toggleMute : null),
              ],
            ),
            const SizedBox(height: 16),
            _dpad(),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _roundButton(Icons.keyboard_double_arrow_down, _connected ? _service.channelDown : null, size: 54),
                const SizedBox(width: 34),
                _roundButton(Icons.keyboard_double_arrow_up, _connected ? _service.channelUp : null, size: 54),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Estado: ${_powerState ?? '—'}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 6),
            const Text(
              'El dispositivo móvil y el TV deben estar en la misma red Wi‑Fi. El primer uso solicita autorización en la pantalla del TV.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white30, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF131315),
        foregroundColor: color,
        minimumSize: const Size.fromHeight(76),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
