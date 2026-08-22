# AirCiller

AirCiller es una aplicación macOS ligera para abrir un archivo de vídeo local y enviarlo a un Apple TV mediante AirPlay 2. Está pensada para el flujo **abrir, enviar y ver**: sin biblioteca permanente, nube, telemetría ni recodificación silenciosa.

> Estado: proyecto personal en desarrollo. La versión instalada y validada físicamente es la 0.9.7; la rama de trabajo puede contener cambios todavía pendientes de probar en un Apple TV real.

## Qué hace

- Conserva el vídeo H.264/HEVC original, incluidos HDR y Dolby Vision cuando el archivo y tvOS son compatibles.
- Mantiene dos rutas independientes: MP4 directo para HDR/Dolby Vision y VOD HLS/fMP4 para el resto de casos.
- Permite elegir pista de audio, ajustar su sincronización y convertir audio solo tras una elección explícita.
- Ofrece subtítulos seleccionables SRT, WebVTT, ASS/SSA y PGS de Blu-ray mediante OCR local con Apple Vision.
- Conserva una playlist local, progreso, capítulos y control sincronizado con el Apple TV.
- Analiza demanda y red bajo petición, sin telemetría ni procesos permanentes.

AirCiller no descarga contenidos ni incluye medios. Utilízalo únicamente con archivos que tengas derecho a reproducir.

## Principios del proyecto

- Nunca modificar el archivo original.
- Nunca recodificar vídeo o audio sin explicarlo y pedir una decisión.
- Nunca quemar subtítulos en la imagen ni subirlos a un servicio externo.
- Mantener separadas y probadas las rutas MP4 directo y HLS/fMP4.
- No declarar una función validada en Apple TV basándose solo en una prueba local.

## Requisitos

- Mac con Apple Silicon y macOS 14 o posterior.
- Xcode Command Line Tools con Swift 6.
- [FFmpeg](https://ffmpeg.org/) y `ffprobe` accesibles mediante Homebrew o MacPorts. La referencia validada actualmente es FFmpeg 9.0.1.
- Python 3.11 o posterior para preparar el motor AirPlay local.
- Apple TV compatible con AirPlay 2 en la misma red local.

## Preparar y compilar

```sh
brew bundle
./Scripts/bootstrap_dependencies.sh
./build.sh
```

El resultado queda en `.build/AirCiller.app`. Compilar no sustituye ni abre ninguna aplicación instalada. Para evitar incompatibilidades binarias, vuelve a preparar `VendorPython` en cada Mac o después de cambiar la versión de Python.

## Comprobaciones

```sh
./Scripts/check.sh
```

Las pruebas automáticas cubren lógica, servidor HTTP, subtítulos y el puente AirPlay sin contactar con un Apple TV. Las pruebas que necesitan películas reales reciben las rutas mediante argumentos o variables de entorno y no forman parte del repositorio.

Antes de instalar una versión se verifican físicamente, por separado:

1. MP4 directo HDR/Dolby Vision con E-AC-3/Atmos y subtítulo seleccionable.
2. HLS/fMP4 VOD con WebVTT, tanto con subtítulos como sin ellos.
3. Pausa larga, reanudación, posición, parada y control remoto.

Consulta [ARCHITECTURE.md](ARCHITECTURE.md) para el diseño, [TESTING.md](TESTING.md) para la validación, [ROADMAP.md](ROADMAP.md) para el trabajo pendiente y [CHANGELOG.md](CHANGELOG.md) para el historial.

## Privacidad y seguridad

Todo el procesamiento se realiza en el Mac. AirCiller abre un servidor HTTP temporal limitado a la red local y protegido por una ruta aleatoria durante la reproducción; no incluye cuentas, analítica, nube ni actualización automática. Las credenciales AirPlay se guardan en el Llavero de macOS.

No abras incidencias públicas con registros que contengan nombres de dispositivos, direcciones locales o nombres de archivos privados. Consulta [SECURITY.md](SECURITY.md) antes de compartir un diagnóstico.

## Origen y atribución

AirCiller es un proyecto independiente desarrollado, revisado y depurado con asistencia sustancial de **OpenAI Codex**. Las decisiones de producto y la validación física corresponden al mantenedor. OpenAI no patrocina ni respalda este proyecto.

AirCiller no está afiliado con Apple, Airflow ni Infuse. Apple, macOS, tvOS, Apple TV y AirPlay son marcas de Apple Inc. El nombre AirCiller es propio. El icono actual es un recurso provisional de desarrollo y se sustituirá por un diseño original antes de cualquier publicación del repositorio o distribución de la aplicación.

## Licencia

El código fuente de AirCiller se publica bajo la [GNU General Public License v3.0](LICENSE). Si distribuyes una versión modificada, debes ofrecer también su código fuente bajo la misma licencia. Las dependencias conservan sus propias licencias; consulta [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Los recursos gráficos provisionales de `Resources/` no se ofrecen para redistribución y serán reemplazados antes de hacer público el proyecto.
