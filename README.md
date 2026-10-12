<h1 align="center">Archi</h1>
<p align="center"><b>An infinite-canvas diagramming tool for sketching systems, written in Qt 6 and QML.</b></p>
<p align="center">
<img alt="Qt" src="https://img.shields.io/badge/Qt-6.5%2B-41cd52">
<img alt="C++" src="https://img.shields.io/badge/C%2B%2B-17-blue">
<img alt="CMake" src="https://img.shields.io/badge/build-CMake-informational">
<img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
</p>

Archi is a lightweight, native desktop app for drawing architecture and flow diagrams. You get an endless pan-and-zoom canvas, draggable shapes and connecting arrows, all rendered by Qt Quick so it stays fast and looks the same on every platform.

## Features

- **Infinite canvas:** pan and zoom without edges.
- **Shapes and arrows:** drop shapes, connect them with arrow layers and arrange freely.
- **Cross-platform:** plain Qt 6 and CMake with no OS-specific code, so the same source builds on Linux, Windows and macOS.
- **Tiny codebase:** a single C++ entry point plus a handful of QML components.

## Build and run

You need Qt 6.5+, CMake and a C++ compiler. On Arch Linux:

```sh
sudo pacman -S qt6-base qt6-declarative qt6-shadertools cmake gcc
cmake -S . -B build
cmake --build build
./build/archi
```

Platform-specific steps for Windows, macOS and ChromeOS are in [BUILD.md](BUILD.md).

## Project layout

| Path | Purpose |
|---|---|
| `src/main.cpp` | Application entry point |
| `qml/Main.qml` | Main window |
| `qml/InfiniteCanvas.qml` | Pan and zoom canvas |
| `qml/ShapeItem.qml`, `qml/ShapeIcon.qml` | Diagram shapes |
| `qml/ArrowLayer.qml` | Connecting arrows |
| `.github/workflows/` | CI builds |

## License

Released under the [MIT License](LICENSE).
