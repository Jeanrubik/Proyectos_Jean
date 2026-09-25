# QNED Remote

App Flutter para iPhone/iPad que controla directamente por Wi‑Fi un LG 50QNED80TSA (webOS 24), sin nube ni cuenta LG.

## Qué hace esta versión

- Encendido por Wake-on-LAN (si el TV tiene habilitado el encendido por red y la MAC está aprendida/configurada).
- Apagado por webOS/SSAP.
- Volumen + / - y mute.
- HOME / BACK / OK.
- Flechas arriba/abajo/izquierda/derecha.
- Canal + / -.
- Cursor tipo Magic Remote: deslizar para mover y tocar para hacer click.
- Guarda la IP y la clave de emparejamiento en Keychain mediante `flutter_secure_storage`.
- Aprende automáticamente la MAC Wi‑Fi/cableada cuando el firmware expone `com.webos.service.connectionmanager/getinfo`.

## Arquitectura

El iPhone se comunica directamente con el TV por WebSocket SSAP en la red local. El canal principal maneja emparejamiento, volumen, mute y apagado. El cursor y las teclas de navegación usan el socket de entrada de puntero que entrega `ssap://com.webos.service.networkinput/getPointerInputSocket`.

No hay servidor intermedio.

## Requisitos

- Flutter 3.38+ / Dart 3.10+ recomendado.
- Para compilar para iPhone: macOS + Xcode.
- iPhone y TV en la misma Wi‑Fi.
- TV encendido durante el primer emparejamiento.

## Crear las plataformas con Flutter

Este paquete está preparado para que puedas abrirlo en tu proyecto Flutter habitual. Como la carpeta iOS contiene archivos generados por la versión concreta de Flutter/Xcode, la forma más limpia es:

```bash
flutter create .
flutter pub get
flutter run
```

Después de `flutter create .`, agrega las claves indicadas en `docs/IOS_INFO_PLIST_SNIPPET.xml` a `ios/Runner/Info.plist`.

## Primer uso

1. En el TV abre la configuración de red y revisa su IP.
2. En el iPhone abre QNED Remote y coloca esa IP en Ajustes.
3. Pulsa **Conectar**.
4. El TV mostrará una solicitud de autorización. Acéptala con el control físico.
5. La app guardará la clave y no debería pedirla de nuevo.
6. Después de una conexión exitosa, la app intenta guardar automáticamente una MAC para Wake-on-LAN.

## Encendido

Apagar por Wi‑Fi es una función SSAP directa. Para encender un TV que ya está apagado, el flujo usado por la app es Wake-on-LAN. El TV debe tener habilitado el encendido por red / Wake-on-LAN en sus ajustes. Si la MAC no pudo aprenderse automáticamente, introdúcela manualmente en Ajustes.

## Certificado local

webOS puede devolver sockets `wss://` con certificados propios del TV. Esta app acepta el certificado del socket únicamente para la comunicación local con el TV. El proyecto no envía credenciales ni comandos a un servidor externo.

## Paquetes usados

- `web_socket_channel: ^3.0.3`
- `flutter_secure_storage: ^11.2.0`
- `cupertino_icons: ^1.0.8`

## Referencias técnicas

- LG Chile: https://www.lg.com/cl/tvs-y-soundbars/qned/50qned80tsa/
- webOS SSAP examples: https://github.com/hobbyquaker/lgtv2
- WebOSClient Swift: https://github.com/jareksedy/WebOSClient
- Flutter WebSocket: https://pub.dev/packages/web_socket_channel
- Flutter Secure Storage: https://pub.dev/packages/flutter_secure_storage

## Nota de compatibilidad de firmware

LG ha cambiado el comportamiento de emparejamiento y permisos en firmware recientes. Por eso el registro de la app usa un manifiesto genérico con `CONTROL_MOUSE_AND_KEYBOARD` y los permisos necesarios para el control, en lugar de intentar hacerse pasar por la app oficial de LG.
