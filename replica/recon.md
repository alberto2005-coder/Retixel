# Recon — overlay de mira para Windows

<!-- sweep:ignore-file -->
Referencia: app comercial de mira (Crosshair X, CenterPoint Gaming). Estudio de comportamiento
observable a partir de fuentes públicas. Sin código, assets ni contenido del original.

## Superficies

| Superficie | Qué cubre |
|---|---|
| App de escritorio (Win10/11) | Panel de control: diseñador, biblioteca, ajustes de overlay |
| Overlay en el juego | Ventana sin bordes, encima del juego, sin interacción |
| Extensión Game Bar | Fullscreen exclusivo (fuera de alcance) |
| Web + Workshop | Galería comunitaria y compartición (fuera de alcance) |

## Pantallas

| Pantalla | Propósito | Estados |
|---|---|---|
| Panel / diseñador | Construir la mira y verla en vivo | normal, sin perfil, imagen inválida |
| Vista previa | Comprobar forma, color y contraste | con/sin fondo, zoom |
| Ajustes de overlay | Monitor, posición, atajo, ADS | overlay activo/inactivo, exe ausente |
| Biblioteca de perfiles | Guardar, cargar, renombrar, borrar | vacía, con perfiles, nombre duplicado |
| Compartir / exportar | Código de mira y PNG | copiado, error de escritura |

## Flujos

### F1 · Diseñar una mira
Abrir panel → elegir forma y nº de brazos → tamaño/grosor/hueco → contorno → color/opacidad
→ ver preview en vivo → guardar perfil.
Límites: valores extremos (grosor > tamaño/2), color sin contraste sobre fondo claro,
rotación con hueco, tamaño mayor que el canvas.

### F2 · Activar el overlay
Pulsar activar → el panel renderiza la mira a un sprite → escribe config y lanza el proceso
overlay → overlay aparece centrado en el monitor elegido → jugar.
Límites: overlay ya activo, monitor desconectado, exe del overlay ausente, panel cerrado
(el overlay debe morir con él), segundo intento de activación.

### F3 · Ajustar posición
Botones de desplazamiento o "centrar" → config se reescribe → overlay recarga sin parpadeo.
Límites: offsets fuera del monitor, cambios mientras el juego está en foco.

### F4 · Ocultar al apuntar (ADS)
Mantener botón derecho → overlay se oculta → soltar → reaparece.
Límites: ADS en ventana sin foco, clic derecho fuera del juego, toggle manual durante ADS.

### F5 · Atajo global
Pulsar atajo configurado → overlay visible/oculto, aunque el juego tenga el foco.
Límites: atajo en conflicto con otro programa (RegisterHotKey falla), atajo inválido,
cambio de atajo en caliente.

### F6 · Perfiles
Guardar con nombre → aparece en la lista → cargar restaura todos los valores → borrar pide
confirmación. Al arrancar se restaura el último perfil usado.

### F7 · Imagen propia
Elegir PNG → se usa como mira, escalada al tamaño elegido → quitar y volver al diseñador.
Límites: archivo enorme, no-PNG, imagen con fondo opaco, ruta inexistente.

### F8 · Compartir y exportar
Copiar código base64 de la mira → pegarlo en otra máquina → cargarla. Exportar PNG a disco.
Límites: código corrupto, versión distinta, PNG sin permisos de escritura.

## Modelo de datos (inferido)

```
Profile   { id, name, shape, arms, size, thickness, gap, dot, outline, outlineWidth,
            color, opacity, rotation, blur, imagePath, monitor, offsetX, offsetY,
            hotkey, hideOnAds, updatedAt }
Settings  { activeProfileId, launchAtStartup? }
```
Invariantes: el sprite generado siempre cabe en su lienzo (clamp de tamaño);
el overlay nunca recibe clics; un perfil no puede quedar sin forma ni color válidos.

## Fuera de alcance (y por qué)

- Galería/Workshop comunitaria y Steam Cloud: contenido y servicios de terceros.
- Fullscreen exclusivo vía Game Bar: exige publicar un widget propio en Microsoft Store.
- GIF animado, capas de texto/emoji, SVG: no en v1, documentado como gap.

## Tamaño

| Flujo | Talla | Riesgo |
|---|---|---|
| Diseñador + preview | M | Bajo: pintura vectorial |
| Overlay nativo layered | L | Alto: transparencia por píxel y click-through |
| Sprite + config en vivo | M | Medio: recarga sin parpadeo |
| ADS + hotkey | S | Medio: conflicto de atajos |
| Perfiles + compartir | S | Bajo |
| Imagen propia | M | Medio: decodificar y escalar |

## Fuentes

- Ficha pública de la app en Steam (funciones y límites de plataforma), consultada 2026-10-31.
- Web oficial: páginas de funciones, ayuda y compatibilidad, consultadas 2026-10-31.
- Precio y modelo de venta: pago único, sin suscripción.
