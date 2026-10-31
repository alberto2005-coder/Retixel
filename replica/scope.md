# Alcance y límites — CleanCrosshair

<!-- sweep:ignore-file -->
Fuentes: web pública de la app de referencia, su ficha de Steam y sus páginas de ayuda.
No se ha usado código, assets ni contenido propietario.

## Qué se reconstruye

Funcionalidad y flujos observables de un overlay de mira para Windows:

- Diseñador de miras (formas, brazos, grosor, hueco, punto, contorno, color, opacidad).
- Vista previa en vivo.
- Overlay real sobre el juego: transparente, sin bordes, siempre encima, click-through.
- Atajo global para mostrar/ocultar.
- Ocultado automático al apuntar (ADS).
- Selección de monitor y ajuste fino de posición.
- Perfiles locales ilimitados.
- Imagen propia como mira.
- Exportar PNG.
- Código para compartir una mira.

## Qué NO se reconstruye

| Elemento del original | Motivo |
|---|---|
| Marca, logo, nombres de miras, textos y copy | Expresión protegida |
| Catálogo/Workshop de la comunidad | Contenido de terceros con licencia propia |
| Extensión de Xbox Game Bar (fullscreen exclusivo) | Requiere publicar un widget en Microsoft Store con su cuenta y sus políticas |
| Steam Cloud / logros / integración Steam | Servicios de su plataforma |
| GIF animado y capas de texto/emoji | Fuera de v1; se documenta como gap |
| Iconos, fuentes e ilustraciones del original | Assets propietarios |

## Consecuencia funcional

El overlay se dibuja por encima de juegos en **ventana sin bordes / ventana completa**.
En **pantalla completa exclusiva** de DirectX no se verá: eso lo resuelve su extensión de Game Bar,
no una ventana Win32 normal. Se avisa en la UI y en el README.

## Anti-cheat

No se inyecta código, no se lee memoria, no se simula input, no se modifican archivos del juego.
Es una ventana layered del sistema. Aun así, cada juego decide qué overlays tolera: la
responsabilidad de comprobarlo es del usuario.
