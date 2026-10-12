# Archi

A native diagramming workspace with an infinite canvas, editable shapes, connections, and project files.

**Status:** Desktop application prototype  
**Built with:** C++20, Qt 6, QML, Python

[Project guide](docs/PROJECT_GUIDE.md) · [Every file explained](docs/FILE_GUIDE.md) · [Licenses and dependencies](docs/LICENSE_REVIEW.md)

## Start here

- [src/main.cpp](src/main.cpp) — Source module for main; defines `main`.
- [qml/Main.qml](qml/Main.qml) — Source module for Main; defines `toggleSavedBackground`, `openBackgroundChooser`, `cycleBackground`; contributes to the application’s interface.
- [CMakeLists.txt](CMakeLists.txt) — CMake build definition for .; declares targets, dependency discovery, and compiler/build settings.

The following commands are taken from this project’s source/configuration. Install its prerequisites first.

```sh
cmake -S . -B build
cmake --build build
```

[Detailed setup, usage, and development notes](PROJECT_NOTES.md) preserve the previous project documentation.

## Repository layout

| Path | Role |
| --- | --- |
| [.github/](.github/) | GitHub workflow and contributor configuration (1 tracked entries). |
| [docs/](docs/) | Project documentation, decisions, and reference material (6 tracked entries). |
| [exports/](exports/) | Project-specific exports components (2 tracked entries). |
| [qml/](qml/) | Qt Quick views and reusable UI components (11 tracked entries). |
| [src/](src/) | Application source and platform integration (5 tracked entries). |
| [tests/](tests/) | Automated checks and test fixtures (1 tracked entries). |

## Scope and current limits

Install the Qt modules listed in CMakeLists.txt before building. Optional symbolic math uses the separate Python environment described in the existing setup notes.

## License

Original project code retains **MIT** terms in [LICENSE](LICENSE). Third-party libraries, media, data, models, and tools retain their own terms. See the [license review](docs/LICENSE_REVIEW.md) and [dependency inventory](docs/DEPENDENCIES.csv).
