# Estrategia de pruebas

AirCiller distingue tres niveles de validación para no confundir una compilación correcta con una reproducción real.

## 1. Comprobaciones deterministas

`./Scripts/check.sh` valida formato, compila el código con Swift 6 estricto, ejecuta las pruebas sin medios privados y comprueba el puente Python de forma simulada.

## 2. Pruebas locales con medios

Los ejecutables de `Tests/` que requieren un archivo real reciben su ruta como argumento o variable de entorno. Los medios permanecen fuera del repositorio. Estas pruebas verifican contenedores, OCR, AVPlayer y listas VOD, pero no demuestran que tvOS acepte la sesión.

## 3. Matriz física en Apple TV

Una versión no se considera validada para instalar hasta completar, por separado:

| Ruta | Caso mínimo | Resultado esperado |
| --- | --- | --- |
| MP4 directo | HDR/Dolby Vision, E-AC-3/Atmos, con subtítulo seleccionable | Imagen y pistas correctas; duración y posición sincronizadas |
| HLS/fMP4 | Sin subtítulos | VOD completo, sin indicador de directo ni pausas de preparación |
| HLS/fMP4 | Con WebVTT | Subtítulo seleccionable y sincronizado, sin quemarlo en la imagen |
| Control | Pausa larga y reanudación desde el mando | AirPlay sigue enlazado y el Mac no entra en reposo automático |

Tras la prueba se comprueba también detener, volver a reproducir y cerrar la aplicación. Solo entonces se incrementa la versión patch y se sustituye la app instalada, conservando una copia de retorno.
