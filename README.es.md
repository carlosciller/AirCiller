<div align="center">
  <img src="Resources/AirCiller-1024.png" width="132" alt="Icono de AirCiller">
  <h1>AirCiller</h1>
  <p><strong>Tu película. Tu Apple TV. Nada en medio.</strong></p>
  <p>Una pequeña app nativa para macOS que envía vídeo local al Apple TV mediante AirPlay 2, conservando HDR, Dolby Vision, pistas de audio y subtítulos seleccionables cuando el archivo lo permite.</p>
  <p>
    <a href="https://github.com/carlosciller/AirCiller/releases/latest"><strong>Descargar AirCiller</strong></a>
    · <a href="README.md">English</a>
    · <a href="CHANGELOG.md">Novedades</a>
  </p>
  <p>
    <a href="https://github.com/carlosciller/AirCiller/releases/latest"><img src="https://img.shields.io/github/v/release/carlosciller/AirCiller?style=flat-square&label=release" alt="Última versión"></a>
    <a href="https://github.com/carlosciller/AirCiller/actions/workflows/ci.yml"><img src="https://github.com/carlosciller/AirCiller/actions/workflows/ci.yml/badge.svg" alt="Estado de las pruebas"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/carlosciller/AirCiller?style=flat-square" alt="Licencia GPL-3.0"></a>
  </p>
</div>

AirCiller nació de una frustración sencilla: tener una gran copia de una película en el Mac no debería obligarte a montar una biblioteca multimedia, crear una cuenta o aceptar una conversión misteriosa antes de verla en la televisión.

Abre el archivo, elige el Apple TV, selecciona las pistas y pulsa Reproducir. AirCiller se ocupa del trabajo delicado y después desaparece.

## Hecha para ver, no para gestionar

- **Conserva la imagen que elegiste.** El vídeo H.264 y HEVC puede mantenerse intacto, incluidos HDR y Dolby Vision cuando el archivo y el Apple TV son compatibles.
- **Aprovecha las pistas que ya contiene la película.** Elige audio y subtítulos, cambia las pistas compatibles durante la reproducción y ajusta la sincronización cuando una edición lo necesite.
- **Hace útiles los subtítulos gráficos.** SRT, WebVTT y ASS/SSA conviven con PGS de Blu-ray y VobSub de DVD, que AirCiller puede convertir localmente en texto seleccionable mediante Apple Vision.
- **Se mantiene sincronizada con la televisión.** La pausa, la reanudación, los saltos y la posición siguen al mando del Apple TV en lugar de fingir que el Mac todavía controla la sesión.
- **Ofrece una biblioteca pequeña y práctica.** Playlist ordenable, películas recientes, progreso y capítulos, sin pedirte que mantengas un servidor multimedia permanente.
- **Muestra los diagnósticos cuando sirven.** La demanda del archivo, el margen de red y la preparación viven detrás de un panel de información, no invadiendo el reproductor.

## Descargar

La versión estable actual es **AirCiller 0.10.1** para Mac con Apple silicon y macOS 14 o posterior.

### [Descargar la última versión →](https://github.com/carlosciller/AirCiller/releases/latest)

Descomprime AirCiller y muévela a la carpeta Aplicaciones. La compilación pública actual utiliza una firma local y todavía no está notarizada con un Apple Developer ID, por lo que macOS puede pedirte que confirmes la primera apertura. También puedes revisar cada paso y compilarla desde el código fuente.

También necesitas:

- Un Apple TV compatible con AirPlay 2 en la misma red local.
- [FFmpeg](https://ffmpeg.org/) y `ffprobe`; se admiten Homebrew y MacPorts.

## Privada por diseño

AirCiller no tiene cuenta, publicidad, telemetría, analítica, biblioteca en la nube ni servidor permanente.

- Nunca sube ni modifica las películas originales.
- Nunca recodifica el vídeo silenciosamente.
- Explica cualquier conversión de audio y pide una decisión antes de hacerla.
- El OCR de subtítulos gráficos se ejecuta en el Mac y crea una pista local seleccionable; nunca quema los subtítulos en la imagen.
- El servidor temporal de reproducción solo existe en la red local y se cierra con la sesión.
- Las credenciales de AirPlay se guardan en el Llavero de macOS.

El comportamiento completo está documentado en [PRIVACY.md](PRIVACY.md).

## Cómo conserva la reproducción

AirCiller mantiene separadas dos rutas:

1. **MP4 directo**, que conserva vídeo HDR/Dolby Vision y audio compatibles sin recodificar la imagen.
2. **VOD HLS/fMP4**, que empaqueta otras fuentes compatibles para el Apple TV y puede añadir subtítulos WebVTT seleccionables.

La app indica qué ruta está usando y por qué. Si el Apple TV no acepta una pista, AirCiller explica la incompatibilidad en lugar de cambiarla en silencio.

## Qué hay debajo

AirCiller es una aplicación nativa escrita en Swift 6 con SwiftUI y AppKit. La barra de lenguajes de GitHub también muestra una pequeña parte en Python: es el puente `pyatv` incluido para descubrir el Apple TV, autorizar AirPlay 2, controlar la cola y recibir eventos del televisor. No es la interfaz ni la canalización multimedia.

FFmpeg analiza y empaqueta los archivos cuando hace falta; Apple Vision realiza el OCR local. Durante la reproducción, un servidor HTTP privado y temporal permite que el Apple TV lea el archivo o el VOD preparado. No hace falta Internet para reproducir.

La explicación técnica completa está en [Arquitectura](ARCHITECTURE.md) y [Pruebas](TESTING.md).

## Compilar desde el código

Requisitos:

- Mac con Apple silicon y macOS 14 o posterior.
- Xcode Command Line Tools con Swift 6.
- FFmpeg y `ffprobe`. La referencia validada actualmente es FFmpeg 9.0.1.
- Python 3.11 o posterior para el entorno reproducible del puente AirPlay.

```sh
brew bundle
./Scripts/bootstrap_dependencies.sh
./build.sh
```

El resultado se crea en `.build/AirCiller.app`; compilar nunca sustituye ni abre una copia instalada.

Para ejecutar la validación local completa:

```sh
./Scripts/check.sh
```

Los cambios de reproducción se prueban primero localmente y después por separado en un Apple TV físico mediante las dos rutas antes de convertirse en una versión instalada. Consulta [CONTRIBUTING.md](CONTRIBUTING.md) antes de proponer un cambio.

## Un proyecto personal, hecho en abierto

AirCiller es pequeña y deliberadamente exigente con sus principios. Nació para un único salón y poco a poco se generalizó para que otra persona pudiera entenderla, auditarla y quizá encontrarla útil.

La mantiene [Carlos Ciller](https://github.com/carlosciller) y ha sido desarrollada, revisada y depurada con ayuda sustancial de **OpenAI Codex**. Esa colaboración forma parte de la historia del proyecto, pero no sustituye el criterio humano: las decisiones de producto y la validación física en Apple TV siguen siendo responsabilidad del mantenedor. OpenAI no patrocina ni respalda el proyecto.

Los informes de errores y las propuestas concretas son bienvenidos. Elimina nombres de archivos privados, receptores, direcciones y credenciales antes de abrir una incidencia.

## Licencia y marcas

El código y los recursos gráficos originales de AirCiller son software libre bajo la [GNU General Public License v3.0](LICENSE). Las dependencias conservan sus propias licencias; consulta los [avisos de terceros](THIRD_PARTY_NOTICES.md).

AirCiller es independiente y no está afiliada con Apple. Apple, macOS, tvOS, Apple TV y AirPlay son marcas de Apple Inc. El nombre y el icono de AirCiller son elementos originales de este proyecto.
