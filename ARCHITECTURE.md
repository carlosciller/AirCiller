# Arquitectura

AirCiller mantiene deliberadamente una aplicación nativa pequeña y un único proceso auxiliar para AirPlay 2.

## Flujo principal

1. `MediaProbeService` inspecciona contenedor, vídeo, audio, subtítulos y capítulos mediante `ffprobe`.
2. `StreamCoordinator` elige una de dos rutas sin modificar el original.
3. `LocalHTTPServer` publica temporalmente el resultado en la red local con rangos HTTP y una ruta aleatoria.
4. `AirPlayController` inicia `airplay_helper.py`, que autentica el Apple TV y controla la cola AirPlay 2 con pyatv.
5. Los eventos del receptor actualizan posición, pausa, reanudación, final y metadatos de Ahora suena.

## Rutas multimedia

| Ruta | Uso | Invariante |
| --- | --- | --- |
| MP4 directo | HDR/Dolby Vision y subtítulos seleccionables | El vídeo se copia; no pasa por un codificador |
| HLS/fMP4 VOD | Reproducción general, audio separado y WebVTT | Todas las playlists se cierran antes de reproducir |

Las rutas comparten descubrimiento, control y servidor, pero conservan empaquetadores y pruebas físicas separados. Un cambio no debe modificar ambas en la misma entrega.

## Límites

- Swift/AppKit/SwiftUI: interfaz, estado, preparación y servidor local.
- FFmpeg/ffprobe externos: análisis y remultiplexado; nunca se distribuyen dentro de AirCiller.
- Python vendorizado desde un lock: puente AirPlay 2. No se versiona en Git porque contiene binarios específicos de cada Python y arquitectura.
- Apple Vision: OCR local y bajo demanda de PGS. No existe servicio remoto.

## Estado y datos

La playlist y el historial se guardan en `UserDefaults`; las credenciales AirPlay, en el Llavero. Los archivos preparados y cachés OCR permanecen en el Mac. Consulta [PRIVACY.md](PRIVACY.md).
