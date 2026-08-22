# Historial de cambios de AirCiller

Las versiones instaladas se validan por separado en macOS y en un Apple TV físico. Los cambios todavía no validados se documentan bajo `Sin publicar`.

## Sin publicar

- Preparación del repositorio público: compilación reproducible, documentación, comprobaciones automáticas y retirada de rutas personales de las pruebas manuales.
- La aplicación instalada no cambia hasta superar de nuevo la validación física de AirPlay 2.
- Actualiza el entorno AirPlay auxiliar desde Python 3.9 a Python 3.13 y bloquea con hashes las dependencias; pyatv permanece en la última versión estable 0.18.0.
- Actualiza aiohttp, requests, urllib3 y zeroconf a versiones corregidas y conserva dentro del bundle los avisos de licencia de todas las dependencias.
- Fija el Apple TV de cada sesión para que una búsqueda o selección posterior no pueda invalidar credenciales del receptor equivocado.
- Separa la autorización manual de la autorización solicitada al reproducir: renovar desde el menú ya no inicia una película por su cuenta.
- Espera la confirmación del Apple TV antes de reflejar pausa o reanudación y muestra un error si ya no existe canal de control.
- Marca como privados en el registro los nombres de archivos, receptores, direcciones y URI.
- `build.sh` genera únicamente `.build/AirCiller.app`; instalar exige una acción separada y explícita con copia de retorno.

## Versión 0.9.7

- Sustituye el reordenado experimental de SwiftUI por la tabla nativa madura de AppKit usada por las listas clásicas de macOS.
- Toda la tarjeta y su asa inician el gesto; el sistema dibuja una línea de inserción entre filas, admite el final real y hace autoscroll en los bordes.
- La lista ya no muta ni recalcula sus alturas mientras se arrastra: AirCiller guarda el nuevo orden una sola vez, al soltar, eliminando el tembleque al subir.
- La misma implementación funciona desde macOS 14, sin dos comportamientos distintos según la versión del sistema.
- Añade al menú contextual `Mover al principio` y `Mover al final` como alternativa accesible al gesto, siguiendo la recomendación de ofrecer otra vía para las operaciones de arrastrar y soltar.
- No añade dependencias y mantiene intactas las rutas de reproducción AirPlay 2.
- Compila con Swift 6 estricto y warnings-as-errors; el modelo y el motor AirPlay 2 pasan sus pruebas. El gesto humano final queda pendiente antes de sustituir la 0.9.6 instalada.

## Versión 0.9.6

- Impide únicamente el reposo automático del Mac mientras AirCiller prepara, reproduce o mantiene una película en pausa; la pantalla conserva el comportamiento configurado por el usuario.
- Mantiene la protección activa durante las pausas largas para que macOS no suspenda el servidor local ni el canal de control AirPlay 2.
- Libera la protección inmediatamente al detener, terminar o fallar la sesión; AirCiller no deja el Mac despierto cuando ya no está enviando una película.
- Añade una prueba aislada del ciclo de vida de la protección, incluida su activación y liberación idempotentes.
- Validada físicamente en Apple TV 4K con tvOS 27.0: pausa superior a dos minutos, enlace conservado, reanudación confirmada y avance posterior sin `not connected`; la protección de AirCiller desapareció al detener.

## Versión 0.9.5

- Reutiliza las conexiones HTTP/1.1 entre el Apple TV y el servidor local, evitando miles de aperturas TCP innecesarias durante los picos de lectura del reproductor.
- Sirve los archivos preparados con caché privada e inmutable y conserva las peticiones por rangos de bytes que necesita AVPlayer.
- Corrige el caso en que tvOS entrega una petición completa y cierra su lado de escritura en la misma operación; AirCiller ya no la confunde con una petición incompleta ni responde con un HTTP 400 espurio.
- Separa de la medición del stream las pruebas locales y otros clientes: el diagnóstico de caudal refleja solo el tráfico destinado al Apple TV elegido.
- Añade pruebas de una conexión persistente con varios rangos, cierre unilateral tras una petición completa, archivos mayores de 4 GB, caché y filtrado de telemetría.
- Validada físicamente en Apple TV 4K con tvOS 27.0: Dolby Vision, E-AC-3 y subtítulos seleccionables; 3:36 desde el inicio, 2.954 peticiones, 273 conexiones reutilizadas, 0 HTTP 400 y 0 esperas. La 0.9.4 había registrado 3 esperas en el mismo tramo inicial.

## Versión 0.9.4

- Corrige el ciclo de códigos de la 0.9.2 y distingue una credencial HAP inválida de un rechazo posterior de la sesión de vídeo.
- Verifica una autorización nueva en una conexión independiente antes de guardarla y limita cualquier renovación a un único intento por pulsación de Reproducir.
- Elimina la consulta antigua `GET /info` de la creación del stream de control: tvOS 27 la rechaza aunque ya haya aceptado HAP, PTP y RECORD.
- Crea el canal remoto tipo 130 con un UUID local, como la ruta AirPlay 2 actual de pyatv, y mantiene el vídeo, audio y subtítulos fuera de la negociación.
- Actualiza de forma coherente la identidad de la sesión RTSP a macOS 27 y el agente AirPlay usado por la cola moderna.
- Validada físicamente en Apple TV 4K con tvOS 27.0: Dolby Vision, E-AC-3, subtítulo seleccionable, posición real, pausa, reanudación y parada sin volver a solicitar código.

## Versión 0.9.3

- Comprueba la credencial directamente con el Apple TV antes de crear el VOD; un permiso caducado ya no obliga a preparar primero la película completa.
- Descarta del Llavero una credencial únicamente cuando tvOS confirma que ya no es válida y solicita una autorización limpia.
- Permite como máximo una renovación automática por intento. Si tvOS rechaza también la credencial nueva, detiene todo y muestra el motivo en lugar de repetir código–VOD indefinidamente.
- Mantiene separadas e intactas las rutas MP4 HDR/Dolby Vision y HLS/fMP4; la corrección afecta solo a la negociación AirPlay 2.
- Adapta el build autónomo al toolchain de macOS 27 sin depender del complemento SwiftUIMacros ausente en Command Line Tools.

## Versión 0.9.2

- MKV, MP4, M4V y MOV con HEVC/H.265 o H.264.
- VOD HLS completo y cerrado antes de reproducir: Apple TV recibe duración final y no `[DIRECTO]`.
- Saltos de ±10/±30 segundos, capítulos y reanudación por archivo.
- Selector de audio, sincronización y salida Original/E-AC-3 5.1/AAC estéreo.
- Selector de subtítulos internos y externos SRT/ASS/SSA/VTT, PGS de Blu-ray mediante OCR local y ajuste de sincronización.
- ASS/SSA conserva en la ruta WebVTT la posición, alineación, márgenes, saltos, negrita, cursiva y subrayado; karaoke, movimiento, rotación y dibujos se explican y simplifican como texto estático.
- Convierte PGS bajo demanda con FFmpeg 9.0.1 y Apple Vision: conserva tiempos y posición aproximada, genera WebVTT seleccionable, reutiliza una caché local y nunca quema el texto, sube datos ni modifica el original.
- Identifica VobSub de DVD y explica que aún necesita su decodificador específico; no lo confunde con PGS ni intenta convertirlo silenciosamente.
- Indicadores 4K, Dolby Vision/HDR, Atmos/5.1 y número de subtítulos.
- Historial de orden estable, playlist persistente reordenable, reproducción consecutiva, comprobación de red y mensajes de incompatibilidad.
- Apertura múltiple, arrastrar y soltar y compatibilidad con «Abrir con AirCiller» desde Finder.
- El vídeo nunca se recodifica y el audio nunca se convierte sin una elección o confirmación explícita.
- El empaquetado termina antes de reproducir; al cerrar la ventana termina la app y se elimina el VOD temporal.
- Comprueba antes el espacio libre y nunca reduce, cambia o recodifica silenciosamente el archivo.

### Subtítulos PGS de Blu-ray de la 0.9.2

- Decodifica únicamente la pista PGS elegida como imágenes transparentes; el vídeo no pasa por el decodificador ni se recodifica.
- Reconoce el texto en el Mac mediante Apple Vision, sin red ni servicios externos, y transforma cada composición en WebVTT seleccionable.
- Conserva los tiempos del Blu-ray, elimina estados repetidos y traslada la caja gráfica a coordenadas WebVTT para mantener carteles superiores, diálogo inferior y texto lateral.
- Guarda el WebVTT pequeño en la caché de AirCiller, identificado por archivo, fecha, tamaño, pista e idioma. La primera lectura completa tarda; las siguientes reutilizan el resultado.
- Limita Vision a cuatro reconocimientos simultáneos y muestra cues terminados/total en la preparación; acelera pistas grandes sin crear un servidor ni un proceso permanente.
- Funciona en la ruta HLS/fMP4 y también en la ruta MP4 HDR/Dolby Vision: en ambos casos el vídeo sigue siendo copia exacta.
- Validado localmente con una pista PGS completa de 258 cues: 8,4 segundos, confianza media comunicada por Vision del 100 % en esa pista, tiempos coincidentes con su SRT de referencia y segunda lectura desde caché.
- Validado localmente en un MP4 Dolby Vision de 120 segundos: AVPlayer ve vídeo DV, audio y el subtítulo procedente del PGS como pista seleccionable.
- Validado físicamente en Apple TV 4K con tvOS 26.6: reproducción estable, slider sincronizado y subtítulo PGS convertido visible y correctamente situado en la zona inferior.

### Subtítulos ASS/SSA avanzados de la 0.9.1

- Traduce las coordenadas y alineaciones ASS/SSA a posiciones WebVTT nativas, incluidos márgenes, las nueve anclas `\\an`, coordenadas `\\pos(x,y)` y alineaciones SSA antiguas.
- Conserva saltos de línea, negrita, cursiva y subrayado sin recodificar el vídeo.
- Mantiene el texto de karaoke y efectos móviles en su posición inicial, pero explica que la animación, rotación y dibujos vectoriales se simplifican.
- Añade anclajes horizontales y verticales para que carteles superiores, notas laterales y diálogo inferior no queden cortados en los bordes.
- En HDR/Dolby Vision mantiene la pista seleccionable dentro del MP4 y avisa de que Apple TV simplifica el diseño; no altera la ruta directa que ya funciona.

### Modernización interna de la 0.9.0

- Migra el estado de interfaz de `ObservableObject`/`@Published` a Observation y `@Observable`, disponible desde macOS 14. Solo se invalidan las vistas que leen el valor que cambia; el reloj de reproducción ya no obliga a reconstruir toda la biblioteca.
- Adopta Swift 6 como modo oficial de compilación, con concurrencia estricta y cualquier advertencia tratada como error.
- Sustituye la conversión C obsoleta del servidor local por decodificación UTF-8 segura y actual.
- Separa la fila reordenable de la Playlist del árbol principal de navegación para reducir el coste de compilación y aislar sus gestos y menú contextual.
- Centraliza las opciones privadas de diagnóstico y arranque automático, con una prueba específica para argumentos incompletos.
- Unifica los acumuladores de salida de `ffprobe`, FFmpeg y el motor AirPlay, conservando límites de memoria y eliminando implementaciones duplicadas.
- Centraliza el ciclo común de inicio de sesión sin mezclar las dos rutas multimedia ya verificadas: MP4 directo HDR con subtítulos y VOD HLS/fMP4.
- Elimina telemetría visual y modificadores Glass antiguos que dejaron de usarse después del rediseño.
- Compila con eliminación de código muerto en el enlazado y se valida con FFmpeg 9.0.1.

### Stream Intelligence de la 0.7.0

- Mantiene la ruta nativa: vídeo HEVC/H.264 copiado sin recodificar, VOD fMP4/HLS o MP4 de inicio rápido y control directo AirPlay 2 mediante pyatv 0.18.0.
- Analiza todos los paquetes del archivo en segundo plano y mide la demanda media y el pico real en ventanas de seis segundos, incluyendo la pista de audio elegida.
- Calcula un objetivo seguro de red con un 50 % de reserva sobre el pico; el promedio del archivo ya no se presenta como requisito suficiente.
- Instrumenta el servidor local: bytes entregados, caudal observado hacia Apple TV, transferencias, rangos cancelados normalmente por AVPlayer y errores inesperados.
- Compara demanda y caudal durante la reproducción y clasifica el margen como excelente, preparado, justo o insuficiente.
- Cuenta esperas de buffer comunicadas por el propio Apple TV y conserva un registro técnico por transferencia para depurar casos reales.
- Las mediciones se hacen en la LAN Mac–Apple TV; no se confunden con una prueba de velocidad a Internet.
- No crea variantes de menor calidad ni modifica el vídeo. Una futura conversión adaptativa solo podrá ser explícita y autorizada.

### Controles de pistas nativos de la 0.6.3

- Audio y subtítulos pasan de la barra global a los controles del reproductor, junto al contenido que modifican.
- El símbolo genérico de ajustes se sustituye por `captions.bubble`, el símbolo semántico de SF Symbols para subtítulos y opciones de idioma.
- El botón mantiene el material Liquid Glass neutro del sistema, su ayuda al pasar el cursor y el popover nativo.
- El bloque central de transporte permanece geométricamente centrado aunque haya acciones a la derecha.

### Corrección visual de la 0.6.2

- Retira el amarillo heredado de todo el árbol de controles: reproductor, slider, progreso, toolbar y selección usan el material y el acento nativos de macOS.
- Todos los botones del reproductor emplean Liquid Glass neutro. El central se distingue únicamente por tamaño y posición.
- Conserva el amarillo fuera del material, como identidad gráfica en el icono, pequeños glifos de biblioteca y acentos informativos.
- Detener usa rojo semántico únicamente cuando la acción está disponible.

### Correcciones y refinamiento de la 0.6.1

- Hace pulsable toda la anchura de Playlist y Recientes, no solo sus iconos o letras.
- Sustituye el reordenado implícito de la lista por asas de arrastre reales y líneas amarillas que muestran el punto exacto de destino.
- Elimina el texto redundante «arrastra para ordenar»; la propia asa comunica la interacción.
- Identifica correctamente como 4K las películas scope de 3840×1608, 4096×1716 y tamaños equivalentes, sin depender únicamente de una altura de 2160 píxeles.
- Reemplaza las cápsulas ambiguas por cuatro datos editoriales: resolución y dimensiones, rango dinámico y perfil, audio y formato, subtítulos y pista activa.
- Escribe `Dolby Vision` y `Perfil 8.1` completos; deja de abreviar `DV P8` o resaltarlo en amarillo sin significado.
- Integra transporte y línea de tiempo sobre la imagen en Liquid Glass claro y aplica botones Glass nativos a cada control en macOS 26/27.
- Mantiene una única ventana al abrir películas desde Finder; ya no crea una segunda copia visual de AirCiller.

### Rediseño de la 0.6.0

- Adopta la navegación de macOS 27 con una sidebar real, barra de herramientas del sistema y Liquid Glass nativo en la capa de controles.
- Mantiene el contenido en materiales estándar para conservar jerarquía, contraste y legibilidad, tal como recomienda Apple.
- Reorganiza la película como contenido principal: título completo, estado del Apple TV, imagen, formato, transporte y diagnóstico se leen de un vistazo.
- Lleva red, selector de Apple TV, pistas y apertura a la barra de herramientas; los controles de reproducción quedan juntos en una pieza de vidrio flotante.
- Usa el amarillo únicamente como identidad, selección y acción principal, con compatibilidad automática para aspecto claro, oscuro, contraste y transparencia reducida.
- Renueva la biblioteca con navegación tipo Música/Mail, Playlist por defecto, nombres completos, selección clara y reordenación persistente.
- Estrena un icono amarillo de dos colores, con profundidad contenida y una marca propia de envío a pantalla legible en todos los tamaños del Dock.
- Conserva el símbolo oficial de AirPlay exclusivamente dentro de la interfaz, respetando las restricciones de Apple para SF Symbols y marcas en iconos de aplicaciones.

### Correcciones de la 0.5.3

- Sirve cada reproducción bajo una dirección privada y aleatoria que deja de existir al terminar; otro equipo de la red local ya no puede adivinar la ruta de la película.
- Desactiva la caché del contenido servido para impedir que macOS o tvOS reutilicen segmentos de una sesión anterior.
- Vacía continuamente tanto los eventos como los diagnósticos del motor AirPlay. Una ráfaga larga de avisos ya no puede llenar una tubería y congelar la conexión.
- Limita la memoria reservada para esos diagnósticos y conserva solo el tramo final útil cuando se produce un error.
- Consulta la autorización del Llavero fuera del hilo de interfaz y guarda el resultado por receptor; el aviso de macOS ya no puede congelar la ventana ni repetirse en cada redibujado.
- Hace caducar a los tres minutos un PIN de emparejamiento abandonado y permite solicitar otro con un mensaje comprensible.
- Cancela correctamente el servidor aunque la reproducción se interrumpa mientras todavía está obteniendo puerto y dirección de red.
- Adopta la comprobación estricta de concurrencia de Swift y corrige la captura mutable que será un error en Swift 6.
- Construye y firma la aplicación completa en una ubicación separada, la verifica y solo entonces sustituye la versión instalada; un build fallido ya no puede dejar una app a medias.
- Impide instalar sobre una instancia de AirCiller todavía abierta, evitando probar accidentalmente un binario anterior que macOS conserva en memoria.
- Mantiene `pyatv 0.18.0`, la última versión oficial disponible, y deja visibles los avisos útiles del motor ocultando únicamente el conocido aviso LibreSSL de la copia de Python incluida en macOS.
- Verificado con archivos reales: Dolby Vision con E-AC-3 5.1 y subtítulo interno; Dolby Vision con Atmos y English SDH; y H.264/AAC SDR mediante VOD HLS.

### Correcciones de la 0.5.2

- Aísla cada reproducción y cada emparejamiento: el cierre tardío de una sesión anterior ya no puede borrar el estado, el slider ni el canal de control de la siguiente.
- Cancela también la espera de conexión anterior al cambiar rápidamente de película o pista, evitando tareas suspendidas y VOD temporales retenidos.
- Distingue una credencial AirPlay caducada de un rechazo de reproducción real; si tvOS pide renovar autorización, muestra el código y reintenta después del emparejamiento.
- Separa las órdenes aceptadas de pausa, reanudación y salto de los estados comunicados espontáneamente por el Apple TV; el slider se corrige con la posición que confirma cada evento.
- Conserva `Reproduciendo` como estado visible cuando el título y la carátula se publican unos instantes después.
- Espera brevemente a que macOS confirme la red antes de un arranque automático, evitando falsos errores al abrir la app y reproducir inmediatamente.
- Oculta `Reanudará desde…` cuando la película ya ha terminado y trata los cambios de rango HTTP del reproductor como cierres normales, no como fallos rojos.
- Añade diagnóstico explícito de inicio, pausa, reanudación, parada y final confirmados por el Apple TV.
- Verificado físicamente en tvOS 26.6 con un fragmento Dolby Vision P8: E-AC-3 5.1, subtítulo interno, duración y slider completos, metadatos aceptados y final limpio.

### Cambios de la 0.5.1

- Publica en «Ahora suena» de Apple TV/iPhone el nombre real de la película mediante el canal moderno de metadatos MediaRemote de AirPlay 2.
- Envía el icono amarillo de AirCiller como carátula y lo muestra también en el centro «Ahora suena» de macOS.
- Mantiene los metadatos separados del vídeo: si un receptor rechaza título o carátula, la reproducción continúa sin alterarse.
- Publica esos metadatos solo después de que tvOS confirme que la película está reproduciéndose y serializa todas las órdenes con el feedback AirPlay 2.

### Cambios de la 0.5.0

- Sincroniza hacia AirCiller las pausas, reanudaciones y saltos realizados con el mando del Apple TV, incluso cuando tvOS expresa el tiempo como una estructura AirPlay 2 en lugar de segundos simples.
- Distingue entre terminar la película y salir de ella con el mando: solo el final real avanza la playlist; al salir se conserva el punto para continuar.
- Publica título, duración, posición y estado en el centro nativo «Ahora suena» de macOS y acepta desde él reproducir, pausar, saltar, buscar y detener.
- Añade título y duración a la película insertada en la cola AirPlay 2 para que Apple TV y sus superficies remotas tengan metadatos útiles.
- Desactiva los controles multimedia de AirCiller cuando no está reproduciendo, evitando apropiarse de las teclas de otras aplicaciones.

### Cambios de la 0.4.3

- Muestra el nombre original de cada pista junto a su interpretación en español, por ejemplo `English SDH — Inglés SDH`.
- Hace lo mismo con el audio y mantiene a la vista códec, Atmos o número de canales.
- Añadió un idioma de subtítulos automático persistente. En la 0.4.3 prefería una pista de texto normal, usaba SDH si era la única compatible y aún no activaba PGS/VobSub.
- Explica SDH dentro del selector de pistas.
- Sustituye el ambiguo marcador `Continuar` por `Reanudará desde 00:53` y elimina la aclaración gris redundante del pie.
- Amplía el selector de pistas para que los nombres completos resulten legibles.

### Correcciones de la 0.4.2

- Añade subtítulos de texto en HDR10 y Dolby Vision sin recodificar el vídeo: AirCiller crea un MP4 de inicio rápido con el vídeo, el audio elegido y una pista de texto seleccionable.
- Mantiene AirPlay 2 y la cola remota de `pyatv`; no usa el transporte AirPlay heredado ni requiere instalar una app en el Apple TV.
- Conserva el selector de pista, subtítulos internos o externos y el ajuste de sincronización de ±10 segundos.
- Conserva la marca MP4 directa e inyecta los metadatos estáticos HDR10 cuando corresponden, corrigiendo también los índices que se desplazan al ampliar la cabecera.
- Comprueba antes de enviar que AVPlayer ve duración, audio y una pista de subtítulos realmente seleccionable.
- La cabecera del MP4 con subtítulos contiene duración e índice completos al principio, evitando que tvOS tenga que recorrer una película grande antes de reproducirla.
- Reserva 16 MB para la cabecera y añade los metadatos HDR en ese espacio: no vuelve a copiar ni carga en memoria el archivo completo al terminar el empaquetado.
- Sirve MP4 y rangos HTTP progresivamente en bloques de 1 MB; una petición abierta de 20 GB ya no intenta reservar 20 GB de RAM.
- Verificado físicamente con un archivo de 20,59 GB: Dolby Vision, E-AC-3 5.1 y subtítulo interno visibles en Apple TV, con duración completa y slider en marcha.
- Se descartó la lista maestra HDR con WebVTT: tvOS descargaba la lista y la variante, pero rechazaba Dolby Vision antes de solicitar su cabecera multimedia.

### Correcciones de la 0.4.0

- HDR10 y Dolby Vision 8.1 usan una rendition HLS fMP4 directa con vídeo y audio multiplexados. tvOS ya no puede descartar la película en el filtro defectuoso de variantes de la lista maestra.
- Conserva intactos el bitstream HEVC/Dolby Vision y el audio compatible elegido; no hay recodificación de vídeo.
- Corrige la cabecera producida por FFmpeg: marca el segmento de inicialización como `hlsf` e incorpora en `hvcC` los metadatos estáticos HDR10 que exige Apple.
- Verificado físicamente en Apple TV con tvOS 26.6: Dolby Vision perfil 8.1 y E-AC-3 5.1, con descarga continuada de cabecera y fragmentos.
- La ruta SDR conserva audio alternativo y WebVTT seleccionable mediante lista maestra.
- La 0.4.0 detenía expresamente los subtítulos en HDR/Dolby Vision porque tvOS rechazaba la lista maestra; la 0.4.1 los integró en MP4 y la 0.4.2 corrige la espera infinita usando una cabecera de inicio rápido con duración real.
- El modo de prueba espera a terminar el descubrimiento del Apple TV antes de analizar y arrancar el archivo.
- La validación de HDR directo ya no exige la lista maestra que esa ruta elimina deliberadamente; este era el fallo que impedía que la solución aislada llegara a ejecutarse desde la app.
- El ancho de banda HLS se calcula desde el tamaño y la duración reales de todos los fragmentos, no multiplicando la media del archivo. Corrige el aborto de `Flow` en escenas con un pico muy superior a su bitrate medio.
- Retira la falsa rendition I-frame que reutilizaba segmentos completos como si contuvieran solo fotogramas clave.

### Correcciones de la 0.3.9

- El slider usa un reloj sincronizado que empieza únicamente cuando el Apple TV confirma la reproducción y se reajusta al pausar, reanudar o saltar.
- Los eventos de tvOS que no contienen posición ya no reinician el tiempo a `00:00`.
- Probó una entrega MP4 directa para Dolby Vision; las pruebas físicas posteriores demostraron que AVPlayer/tvOS no la aceptaban de forma fiable y fue sustituida en la 0.4.0 por HLS fMP4 directo.
- Mantuvo la pista Dolby Vision y el audio elegido sin recodificar durante esa investigación.
- Añadió validaciones de duración y conservación de pistas que permitieron aislar el rechazo del contenedor.

### Correcciones de la 0.3.8

- Adopta el flujo AirPlay 2 de vídeo verificado en un Apple TV 4K con tvOS 26.6: autenticación, sesión PTP con pares de reloj, `RECORD`, canal remoto `type 130` y cola `/command`.
- Obtiene `psi` desde `/info` y registra el canal `psi-RCS-1`; el Apple TV ya no recibe una sesión de control incompleta.
- Envía inserción, interés temporal y reproducción antes de iniciar el feedback. tvOS cerraba silenciosamente la conexión si ambas clases de petición coincidían.
- Sustituye el sondeo inválido de `/playback-info` por los estados que el Apple TV envía en el canal de eventos AirPlay 2.
- Restaura HLS fMP4/CMAF con listas versión 7, cabeceras MP4 y segmentos `.m4s`; HEVC y Dolby Vision ya no se encapsulan en MPEG-TS.
- Entrega las listas HLS sin gzip, igual que el CDN de referencia de Apple, y descarta sin error las conexiones especulativas que tvOS cierre sin enviar petición.
- Corrige la señalización Atmos a `ec-3` con `CHANNELS="16/JOC"` y mantiene WebVTT como rendition seleccionable.
- Experimentó con una rendition `I-FRAME-STREAM-INF`; se retiró en la 0.4.0 al comprobar que reutilizar segmentos completos no constituye una pista I-frame válida.
- Dolby Vision 8.1 anuncia su base HDR10 mediante el identificador HEVC exacto y su mejora mediante `SUPPLEMENTAL-CODECS="dvh1.08.xx/db1p"`.
- Corrige el ajuste del último segmento cuando un corte de prueba deja una cola de vídeo más corta que la diferencia entre audio y vídeo.
- Verificado localmente con Dolby Vision 5 + Atmos y Dolby Vision 8.1 HDR, tanto sin subtítulos como con una pista interna seleccionable.
- El transporte completo está verificado físicamente con H.264 y HEVC Main 10; la nueva combinación I-frame + Dolby Vision queda pendiente de aceptar una vez el aviso de Llavero de la compilación nueva.

### Correcciones de la 0.3.7

- Sustituye el arranque abreviado de vídeo de pyatv por la cola nativa de AirPlay 2 que usa Airflow.
- Crea una sesión autenticada, abre el canal de eventos y negocia un stream de control `type 130` con su `streamID` antes de insertar la película.
- Reproducir, pausar, reanudar y saltar usan comandos de cola AirPlay 2; no se introduce ningún transporte heredado.
- Replica la rama de entrega de Airflow para Apple TV: HLS 6 y segmentos MPEG-TS, conservando HEVC/Dolby Vision y E-AC-3 sin recodificación.
- Retira `SUPPLEMENTAL-CODECS` del manifiesto AirPlay; el bitstream mantiene la información Dolby Vision y `VIDEO-RANGE=PQ` anuncia su base HDR.
- Añade estados de diagnóstico comprensibles para distinguir sesión, stream de control, inserción en cola e inicio real.

### Correcciones de la 0.3.4

- Cierra cada respuesta HTTP con el contexto final de `Network.framework`, permitiendo que TCP entregue por completo cabeceras y segmentos antes de liberar la conexión.
- Evita cancelar inmediatamente conexiones con datos todavía pendientes; corrige un fallo real del servidor local, aunque la prueba física confirmó que no era la causa principal del rechazo del Apple TV.
- Sirve los segmentos MPEG-TS de diagnóstico con el tipo `video/mp2t` correcto.
- Registra el endpoint cliente de cada petición para distinguir inequívocamente el Apple TV del reproductor local.

### Correcciones de la 0.3.3

- Corrige la señalización de Dolby Vision perfil 8.1 para tvOS: la capa HDR10 se anuncia como `hvc1` y Dolby Vision mediante `SUPPLEMENTAL-CODECS` con la marca `db1p`, como exige Apple.
- Separa el audio E-AC-3/AC-3/AAC en una rendition HLS propia; el audio multicanal ya no va multiplexado dentro de los segmentos de vídeo.
- Valida por separado que vídeo y audio sean VOD completos, cerrados y con sus cabeceras y segmentos presentes.
- Alinea el `TARGETDURATION` de todas las renditions y entrega las listas HLS comprimidas con gzip, como requiere la especificación de autoría de Apple.
- Conserva los metadatos Dolby Vision al cambiar la muestra MP4 a la base `hvc1`; el vídeo continúa sin recodificarse.
- Las peticiones realizadas por el Apple TV y los errores de AVPlayer quedan registrados de forma persistente para poder diagnosticar un rechazo físico.

### Cambios de la 0.3.2

- La Playlist es la primera vista y la que se abre por defecto.
- La Playlist adopta las tarjetas de Recientes, conserva el arrastre para ordenar y muestra los nombres completos.
- Recientes también deja de recortar los nombres largos.
- El menú contextual permite iniciar una película inmediatamente desde `00:00`; en la Playlist también permite reanudarla.

### Correcciones de la 0.3.1

- Restaura la respuesta HTTP atómica. La 0.3 dividía cabecera y cuerpo en varios envíos TCP; este cambio era necesario, pero no resolvía por sí solo la señalización incorrecta de Dolby Vision 8.1 corregida en la 0.3.3.
- Añade trazas de cada petición HLS para distinguir en futuras incidencias un rechazo del formato de un problema de red.

### Correcciones de la 0.3

- Las sesiones antiguas ya no pueden reaparecer al cambiar de película o saltar rápidamente.
- Vídeo, audio y subtítulos usan listas VOD alineadas, completas y con `#EXT-X-ENDLIST`.
- Dolby Vision declara perfil/nivel, rango PQ y códecs de vídeo/audio en la lista maestra.
- Los WebVTT se segmentan con la misma línea temporal que el vídeo y cubren también los tramos sin texto.
- Pausar no deja FFmpeg trabajando: el empaquetado ya ha terminado.
- El servidor responde a HEAD y rangos, rechaza rangos inválidos y envía los segmentos por bloques sin cargarlos enteros en memoria.
- Se retiraron estilos WebVTT horneados; tamaño y posición quedan a cargo de las preferencias de Apple TV.
- «Abrir con AirCiller» conserva los archivos recibidos mientras termina de arrancar la ventana.
- Si FFmpeg termina durante la preparación, AirCiller lo explica y limpia la sesión.
- Abrir una película reciente ya no la mueve de posición; la playlist solo cambia mediante una acción explícita.
- Icono ICNS nativo con representaciones Retina, margen óptico, sombra, transparencia y silueta continua; ya no aparece como un cuadrado amarillo en el Dock.
- La lectura de metadatos y la extracción de subtítulos drenan la salida de FFmpeg mientras trabaja, evitando bloqueos con archivos complejos o muchas pistas.
- Las entradas cuyos archivos ya no existen se eliminan también del historial y la playlist persistentes.
