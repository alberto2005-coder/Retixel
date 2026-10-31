# Arquitectura — CleanCrosshair

<!-- sweep:ignore-file -->

## Decisión principal

Flutter **no puede** hacer una ventana transparente por píxel en Windows (limitación del
embedder: el swapchain es opaco y la issue upstream sigue abierta). Forzar transparencia
con `WS_EX_LAYERED` sobre el árbol de Flutter deja la ventana en negro.

Por eso el overlay **no lo dibuja Flutter**: lo dibuja un proceso nativo pequeño
(`clean_crosshair_overlay.exe`) con `UpdateLayeredWindow`, que sí da alfa real por píxel.
Flutter queda como panel de control y generador del sprite.

```
┌─────────────────────────────┐        escribe                ┌──────────────────────────┐
│ clean_crosshair.exe         │  overlay.ini + crosshair.bin  │ clean_crosshair_overlay  │
│ Flutter · panel + preview   │ ────────────────────────────► │ Win32 layered · topmost  │
│                             │ ◄──────────────────────────── │ click-through · ADS      │
└─────────────────────────────┘        overlay.log            └──────────────────────────┘
                                                                    │
                                                              update 300 ms
```

## Por qué dos procesos

| Alternativa | Veredicto |
|---|---|
| Ventana Flutter transparente | No soportado: negro o artefactos con el swapchain |
| `flutter_acrylic` / `SetWindowCompositionAttribute` | No es alfa real por píxel y depende de API indocumentada |
| Multi-window de Flutter | Plugin extra y el problema de transparencia sigue |
| **Proceso nativo con `UpdateLayeredWindow`** | Alfa real, click-through, sin plugin, sin red |

## Contrato entre procesos

`%LOCALAPPDATA%\CleanCrosshair\overlay.ini` (clave=valor, UTF-8):

```ini
monitor=0            # índice según --list-monitors
offset_x=0
offset_y=-40
opacity=0.9
hotkey=ctrl+alt+f8
hide_on_ads=true
parent_pid=12345     # watchdog: si el panel muere, el overlay muere
sprite=crosshair.bin
```

`crosshair.bin`: `CXSP` + uint32 ancho + uint32 alto + RGBA recto (no premultiplicado).
El overlay premultiplica y compone; `opacity` se aplica al alfa.

El overlay relee por fecha de modificación cada 300 ms → cambios en vivo sin reiniciar.
`overlay.log` es el canal de diagnóstico (la UI muestra la última línea si algo falla).

## Invariantes

- El sprite nunca sale de su lienzo (clamp 8..200 px de tamaño, 256 px de canvas).
- El overlay jamás recibe ratón (`WS_EX_TRANSPARENT` + ventana no activable).
- Un solo overlay por sesión (mutex con nombre).
- Si `parent_pid` desaparece, el overlay se cierra solo.
- Si el atajo no se puede registrar, se registra en el log y la UI lo dice; el resto sigue.

## Datos

`profiles.json` (perfiles con nombre), `state.json` (último estado y perfil activo),
`overlay.ini` + `crosshair.bin` (runtime), `exports/` (PNG).

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Fullscreen exclusivo tapa overlays | Documentado; se usa ventana sin bordes |
| Atajo ocupado por otro programa | Log + aviso en UI, se puede cambiar |
| Monitor desconectado mientras corre | `WM_DISPLAYCHANGE` reenumera y recoloca |
| Sprite corrupto | Validación de cabecera y tamaño antes de dibujar |
| Anti-cheat | Sin inyección ni memoria; el usuario decide por juego |
