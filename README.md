# Retixel

<p align="center">
  <img src="assets/branding/retixel_128.png" alt="Retixel" width="96" />
</p>

[![Flutter](https://img.shields.io/badge/Flutter-Desktop-02569B?logo=flutter&logoColor=white)](https://flutter.dev/desktop)
[![Windows](https://img.shields.io/badge/Windows-10%20%2F%2011%20x64-0078D6?logo=windows&logoColor=white)](https://www.microsoft.com/windows)
[![GPL-3.0](https://img.shields.io/badge/Licencia-GPL--3.0-blue)](LICENSE)

[Español](#español) · [English](#english)

---

## Español

### Índice

- [Descripción](#descripción)
- [Características](#características)
- [Descarga](#descarga)
- [Compilación desde el código fuente](#compilación-desde-el-código-fuente)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Por qué es seguro para los anti-cheat](#por-qué-es-seguro-para-los-anti-cheat)
- [Licencia](#licencia)

### Descripción

**Retixel** es una utilidad de escritorio ligera para **Windows** que dibuja una **mira flotante** personalizable sobre cualquier juego. La interfaz está hecha en **Flutter** y el overlay se renderiza en un motor nativo **Win32 en C++**, de modo que la latencia es mínima y la UI no interfiere con el juego.

La aplicación **no inyecta código ni manipula la memoria** de otros procesos: es una ventana transparente *always-on-top*, sin hooks.

### Características

- **Motor de overlay nativo**: ventana en capas transparente, independiente del bucle de la interfaz.
- **Cuatro estilos de mira**: cruz, punto, círculo y sprites o imágenes PNG propias.
- **Personalización en vivo**: tamaño, grosor, separación central (*gap*), opacidad y paletas RGB.
- **Perfiles y presets**: guarda configuraciones por juego o por arma y cámbialas con un clic.
- **Multiplataforma de escritorio**: pensado para Windows 10/11 x64, con compilación para macOS y Linux desde el mismo código.
- **Interfaz bilingüe** español/inglés.

### Descarga

La versión lista para usar está en [**Releases**](https://github.com/alberto2005-coder/Retixel/releases):

- **ZIP portable**: descomprime y ejecuta `retixel.exe`. No requiere instalación.
- También hay un instalador generado con Inno Setup (`installer.iss`).

### Compilación desde el código fuente

```powershell
flutter pub get
flutter build windows --release
```

El ejecutable y sus librerías quedan en `build\windows\x64\runner\Release\`.

Requisitos: **Flutter 3.x** con soporte de escritorio Windows, **Visual Studio 2022** con la carga de trabajo *Desktop development with C++* y **Windows 10/11 x64**.

### Estructura del proyecto

```text
Retixel/
├── lib/
│   ├── main.dart                 # Arranque y ventana principal
│   └── src/
│       ├── overlay_service.dart  # Puente con el motor de overlay
│       ├── painter.dart          # Dibujo de la mira
│       ├── panel.dart            # Controles de la interfaz
│       ├── model.dart            # Perfiles y presets
│       ├── storage.dart          # Persistencia local
│       ├── sprite.dart           # Miras basadas en imagen
│       ├── i18n.dart             # Español / inglés
│       ├── theme.dart
│       └── brand.dart
├── assets/branding/              # Logos e iconos
├── installer.iss                 # Instalador de Inno Setup
├── replica/                      # Documentación de arquitectura y diseño
└── windows/                      # Proyecto nativo C++
```

### Por qué es seguro para los anti-cheat

Retixel no abre un handle al proceso del juego, no escribe en su memoria, no inyecta DLLs y no lee su estado. Solo crea una ventana transparente por encima del escritorio. Aun así, conviene revisar las normas de cada juego y de cada torneo: algunas competiciones prohíben overlays externos aunque no interactúen con el proceso.

### Licencia

**GNU General Public License v3.0 (GPL-3.0)** — consulta [LICENSE](LICENSE).

---

## English

### Table of contents

- [Overview](#overview)
- [Features](#features)
- [Download](#download)
- [Building from source](#building-from-source)
- [Project structure](#project-structure)
- [Why it is anti-cheat safe](#why-it-is-anti-cheat-safe)
- [License](#license)

### Overview

**Retixel** is a lightweight **Windows** desktop utility that draws a customizable **floating crosshair** over any game. The UI is built with **Flutter** and the overlay renders through a native **Win32 C++** engine, keeping latency minimal and the UI out of the game's way.

The app **does not inject code or manipulate** other processes' memory: it is a transparent *always-on-top* window with no hooks.

### Features

- **Native overlay engine**: layered transparent window, decoupled from the UI loop.
- **Four crosshair styles**: cross, dot, circle, and custom sprites or PNG images.
- **Live customization**: size, thickness, centre gap, opacity and RGB palettes.
- **Profiles and presets**: save per-game or per-weapon setups and switch with one click.
- **Desktop multi-platform**: built for Windows 10/11 x64, compilable for macOS and Linux from the same code.
- **Bilingual UI**: Spanish and English.

### Download

Grab the ready-to-run build from [**Releases**](https://github.com/alberto2005-coder/Retixel/releases):

- **Portable ZIP**: extract and run `retixel.exe`. No installation needed.
- An Inno Setup installer is also included (`installer.iss`).

### Building from source

```powershell
flutter pub get
flutter build windows --release
```

The executable and its libraries land in `build\windows\x64\runner\Release\`.

Requirements: **Flutter 3.x** with Windows desktop support, **Visual Studio 2022** with the *Desktop development with C++* workload, and **Windows 10/11 x64**.

### Project structure

```text
Retixel/
├── lib/
│   ├── main.dart                 # Bootstrap and main window
│   └── src/
│       ├── overlay_service.dart  # Bridge to the overlay engine
│       ├── painter.dart          # Crosshair drawing
│       ├── panel.dart            # UI controls
│       ├── model.dart            # Profiles and presets
│       ├── storage.dart          # Local persistence
│       ├── sprite.dart           # Image-based crosshairs
│       ├── i18n.dart             # Spanish / English
│       ├── theme.dart
│       └── brand.dart
├── assets/branding/              # Logos and icons
├── installer.iss                 # Inno Setup installer
├── replica/                      # Architecture and design docs
└── windows/                      # Native C++ project
```

### Why it is anti-cheat safe

Retixel never opens a handle to the game process, never writes to its memory, never injects DLLs and never reads its state. It only creates a transparent window above the desktop. Even so, check each game's and tournament's rules: some competitions ban external overlays even when they do not touch the process.

### License

**GNU General Public License v3.0 (GPL-3.0)** — see [LICENSE](LICENSE).
