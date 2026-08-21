# Building Archi

Archi is a plain Qt 6 / CMake project with no OS-specific code, so the same
source builds on every target platform — you just need Qt 6 (6.5+) and a
C++ compiler installed on that machine. There is no installer/binary
download yet; every platform currently means "build from source" using the
steps below.

## 1. Get the prerequisites

| Platform | Install |
|---|---|
| Linux | Your distro's Qt 6 packages (`qt6-base`, `qt6-declarative`, `qt6-shadertools`) + CMake + a C++ compiler (g++/clang++). On Arch: `sudo pacman -S qt6-base qt6-declarative qt6-shadertools cmake gcc` |
| Windows | [Qt Online Installer](https://www.qt.io/download-qt-installer) → install Qt 6.5+ with the MSVC (or MinGW) kit → install [CMake](https://cmake.org/download/) → install Visual Studio 2022 (Desktop C++ workload) if using the MSVC kit |
| macOS | [Qt Online Installer](https://www.qt.io/download-qt-installer) → install Qt 6.5+ macOS kit → install Xcode (from the App Store) → `brew install cmake` |
| ChromeOS | Enable Linux (Crostini) in ChromeOS Settings, then follow the **Linux** steps above inside that container |
| iOS | Requires a Mac: install Qt's **iOS** kit via the Qt Online Installer, plus Xcode with the iOS platform support |

## 2. Configure and build

From the project root (`archi/`):

```sh
# Linux / macOS
cmake -S . -B build -DCMAKE_PREFIX_PATH=<path-to-your-Qt-install>
cmake --build build -j

# Windows (from a "x64 Native Tools Command Prompt for VS")
cmake -S . -B build -DCMAKE_PREFIX_PATH="C:\Qt\6.8.0\msvc2022_64"
cmake --build build --config Release
```

`<path-to-your-Qt-install>` is wherever Qt installed itself, e.g.:
- Linux (system packages): `/usr/lib/qt6`
- Linux (Qt Online Installer): `~/Qt/6.8.0/gcc_64`
- macOS: `~/Qt/6.8.0/macos`
- Windows: `C:\Qt\6.8.0\msvc2022_64`

## 3. Run it

- Linux/macOS: `./build/archi`
- Windows: `build\Release\archi.exe` (or `build\archi.exe` for a MinGW/Debug build)
- ChromeOS: same as Linux, run inside the Crostini terminal — the window
  appears on your ChromeOS desktop like any other Linux app
- iOS: build produces an Xcode project/`.app`; run it via Xcode on a
  connected device or the iOS Simulator (needs an Apple Developer account
  to run on a physical device)

## Notes

- The app opens a single window — no separate server, no localhost, no
  network access at all.
- `ARCHI_ENTRY=LogicTest ./build/archi` runs the built-in headless
  regression suite instead of the normal UI (used during development, not
  needed for regular use).
- If CMake can't find Qt, double check `CMAKE_PREFIX_PATH` points at the
  directory containing `lib/cmake/Qt6/` for your install.
