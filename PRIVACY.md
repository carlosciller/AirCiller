# Privacidad

AirCiller no incluye cuentas, telemetría, analítica, publicidad, nube ni actualización automática.

## Datos procesados en el Mac

- Playlist, recientes, posición y rutas de archivos se guardan en las preferencias locales de la aplicación.
- Las credenciales AirPlay se guardan en el Llavero de macOS.
- El OCR de subtítulos PGS se ejecuta mediante Apple Vision y su WebVTT resultante puede conservarse en la caché local para evitar repetir el reconocimiento.
- Los VOD y pistas preparados se crean en almacenamiento temporal y se eliminan al terminar la sesión o durante la limpieza posterior.

## Red local

Durante la reproducción, AirCiller abre un servidor HTTP temporal en la red local para que el Apple TV lea el archivo o VOD. La URL utiliza una ruta aleatoria de sesión y el servidor se cierra al detener la reproducción. AirPlay requiere este transporte local sin TLS; no se publica en Internet ni funciona como servidor permanente.

## Registros

El registro unificado de macOS puede contener estados técnicos, pero los nombres de archivos, receptores, direcciones y URI se marcan como privados. Antes de compartir un diagnóstico, revisa y elimina cualquier dato personal restante.

AirCiller no transmite la biblioteca, subtítulos, diagnósticos o credenciales a su mantenedor, OpenAI ni terceros.
