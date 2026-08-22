# Contribuir a AirCiller

AirCiller es un proyecto personal, pero las revisiones y propuestas pequeñas son bienvenidas.

## Antes de proponer un cambio

- Mantén el flujo abrir–enviar–ver rápido y ligero.
- No añadas telemetría, nube, un servidor permanente o trabajo en segundo plano.
- No modifiques originales ni recodifiques silenciosamente.
- No cambies a la vez MP4 directo y HLS/fMP4.
- No incluyas películas, subtítulos comerciales, direcciones de red, nombres de dispositivos ni credenciales.

## Validación mínima

1. Ejecuta `./Scripts/check.sh`.
2. Compila con `./build.sh` usando Swift 6 estricto y warnings-as-errors.
3. Describe qué prueba es local y qué prueba se ha realizado físicamente en Apple TV.
4. Para cambios de reproducción, valida por separado las dos rutas descritas en [TESTING.md](TESTING.md).

Los cambios generados con herramientas de IA son admisibles, pero deben ser revisados, comprensibles y sometidos a las mismas pruebas que cualquier otro cambio.
