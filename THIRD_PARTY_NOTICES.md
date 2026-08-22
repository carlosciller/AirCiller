# Dependencias de terceros

AirCiller se apoya en proyectos independientes que conservan sus propias licencias:

| Proyecto | Uso | Licencia |
| --- | --- | --- |
| [pyatv](https://github.com/postlund/pyatv) | Descubrimiento, autenticación y base del transporte AirPlay 2 | MIT |
| [FFmpeg](https://ffmpeg.org/) | Análisis y preparación local de contenedores, audio y subtítulos | Según la compilación instalada; normalmente LGPL o GPL |

`Scripts/airplay_helper.py` amplía y adapta comportamiento del transporte AirPlay 2 de pyatv. Se conserva el aviso y texto MIT correspondiente en [LICENSES/pyatv-MIT.md](LICENSES/pyatv-MIT.md).

Las dependencias Python transitivas se instalan localmente desde `requirements.lock` y no se guardan en Git. Sus metadatos y textos de licencia quedan incluidos dentro de la aplicación compilada cuando así los proporciona el paquete.

AirCiller no incorpora binarios de FFmpeg: utiliza la instalación existente en el Mac. La licencia concreta de FFmpeg depende de las opciones con las que se haya compilado ese binario.
