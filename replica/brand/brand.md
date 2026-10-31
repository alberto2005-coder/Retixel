# Marca — Retixel

<!-- sweep:ignore-file -->
Fase 9. Documento de decisiones de identidad. No es asesoría legal.

## Nombre

**Retixel** (retícula + píxel). Se lee igual en español y en inglés, tiene 7
letras, no usa la «X» de la app de referencia y describe el producto sin copiar
su expresión.

### Por qué no se mantiene «CleanCrosshair»

| Problema | Detalle |
|---|---|
| Poco distintivo | Es la unión de dos palabras descriptivas del producto; una marca así es débil y difícil de defender |
| Ya está en uso | Aparece como nombre de mira en catálogos comunitarios y como gamertag en listas públicas (búsqueda web, 2026-10-31) |
| Confusión | Se parece demasiado a la categoría («clean crosshair»), no a un producto |
| Rebautizar después | Renombrar carpeta, binarios, datos y documentación cuesta más cuanto más código hay |

### Candidatos descartados

| Candidato | Motivo |
|---|---|
| Retik | Retik Finance: marca registrada en software (USPTO 99288325) |
| Retico | Marca registrada en software (USPTO, clases 9/42) y empresa de IT en Polonia |
| Mirilla | Nombre de una mira publicada en el Workshop de la app de referencia |
| CleanCrosshair | Descriptivo y ya usado (ver arriba) |

### Comprobaciones hechas (2026-10-31)

- Búsqueda web de «Retixel»: sin producto de software, app ni marca activa; solo
  un listado de anagramas y una transcripción que dice «Retro Pixel».
- `https://retixel.com`: no responde (transport error). **No** implica que el
  dominio esté libre; hay que comprobarlo en un registrador.
- Pendiente y fuera de mi alcance: búsqueda formal en OEPM, EUIPO y USPTO por
  clases 9 (software) y 42 (SaaS), y disponibilidad de dominio/handles. Lo tiene
  que cerrar el usuario o su abogado antes de publicar.

## Paleta

| Rol | Hex | Uso |
|---|---|---|
| background | `#0A0C10` | fondo de la app |
| surface | `#12161D` | tarjetas y barras |
| surface_alt | `#1A2029` | controles, hover |
| text | `#F2F5F7` | texto principal |
| muted | `#98A4B3` | texto secundario |
| primary | `#4ADEDE` | acento, foco, acción principal |
| on_primary | `#04201F` | texto sobre primary |
| accent | `#FFB454` | punto de mira del logo, avisos suaves |
| success | `#66D9A3` | overlay activo |
| warning | `#FFC65C` | atajo ocupado, límites |
| danger | `#FF6B6B` | errores, borrar |

Verificado con `contrast.py`: todos los pares en AA (ver `replica/design/tokens.json`).
La paleta no reutiliza colores de la app de referencia; el cian/ámbar es propio.

## Voz

Tres adjetivos: **directa, técnica, tranquila**.

- «Tu mira, al píxel. Sin menús que estorben.»
- «El overlay se dibuja fuera del juego: no inyecta nada.»
- «Si el atajo está ocupado, te lo decimos; no lo escondemos.»

Nada de mayúsculas gritadas, signos de exclamación ni promesas de ventaja
competitiva. Se dice lo que hace y lo que no.

## Logo

- Concepto: retícula de cuatro ticks + anillo + punto ámbar central. El anillo
  cian representa el overlay; el punto, la precisión.
- Archivos: `assets/branding/retixel.svg` (fuente vectorial),
  `retixel_1024/512/256/128/64/48/32/16.png`, `retixel_banner.png` y
  `windows/runner/resources/app_icon.ico` (16–256 px).
- En la app el logo se dibuja con `BrandMark` (CustomPainter), así que no
  depende de assets ni se pixela.
- Tipografía de la interfaz: la del sistema (Segoe UI en Windows). Sin fuentes
  propietarias de terceros.

## Pendiente antes de publicar

- [ ] Búsqueda formal de marca (OEPM/EUIPO/USPTO, clases 9 y 42).
- [ ] Dominio y handles.
- [ ] Sustituir el placeholder de copyright del README por el titular real.
- [ ] `sweep.py` a 0 sobre el código (se ejecuta en la fase 11).
