# Archi

A native diagramming workspace with an infinite canvas, editable shapes, connections, and project files.

**Status:** Desktop application prototype  
**Built with:** C++20, Qt 6, QML, Python

## Reading order

1. Read the root README for project purpose and setup navigation.
2. Follow the entry points below to find the implementation.
3. Use the file guide to locate individual modules, tests, assets, and configuration.
4. Check component licenses before redistributing dependencies or assets.

## Important paths

- [src/main.cpp](../src/main.cpp) — Source module for main; defines `main`.
- [qml/Main.qml](../qml/Main.qml) — Source module for Main; defines `toggleSavedBackground`, `openBackgroundChooser`, `cycleBackground`; contributes to the application’s interface.
- [CMakeLists.txt](../CMakeLists.txt) — CMake build definition for .; declares targets, dependency discovery, and compiler/build settings.

## Structure

| Path | Role |
| --- | --- |
| [.github/](../.github/) | GitHub workflow and contributor configuration (1 tracked entries). |
| [docs/](../docs/) | Project documentation, decisions, and reference material (6 tracked entries). |
| [exports/](../exports/) | Project-specific exports components (2 tracked entries). |
| [qml/](../qml/) | Qt Quick views and reusable UI components (11 tracked entries). |
| [src/](../src/) | Application source and platform integration (5 tracked entries). |
| [tests/](../tests/) | Automated checks and test fixtures (1 tracked entries). |

## Useful commands

Run from the repository root after following the documented prerequisites.

```sh
cmake -S . -B build
cmake --build build
```

## Scope

Install the Qt modules listed in CMakeLists.txt before building. Optional symbolic math uses the separate Python environment described in the existing setup notes.

## Maintaining the guide

The file catalog is a source-inspection snapshot, not proof that every runtime path works. Update it when moving files or changing module responsibilities. The 2026-10-12 documentation review did not run every application, deploy services, or validate all historical performance claims.
