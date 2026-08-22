# Hoja de ruta técnica

La prioridad es robustez medible, no añadir funciones por añadir.

## Siguientes correcciones aisladas

1. Unificar la ejecución de FFmpeg/ffprobe en un proceso cancelable para que Detener o cambiar de archivo termine inmediatamente análisis, preparación y OCR abandonados.
2. Añadir un fixture sintético con portada adjunta y seleccionar/mapear siempre el índice exacto del vídeo real.
3. Elegir la dirección local según la ruta efectiva hacia el Apple TV en Macs con varias interfaces o VPN, manteniendo el comportamiento actual como fallback.
4. Añadir pruebas de caracterización del controlador AirPlay, carrera del Llavero y persistencia corrupta antes de dividir los archivos coordinadores grandes.

Cada cambio de reproducción se validará primero de forma local, después por separado en MP4 directo y HLS/fMP4, y finalmente en un Apple TV físico antes de instalarlo.

## Fuera de alcance

- Telemetría o analítica.
- Nube o subida de películas/subtítulos.
- Servidor permanente o indexación en segundo plano.
- Recodificación silenciosa.
- Dependencias pesadas sin una ventaja demostrable.
