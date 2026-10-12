# Files 1 of 1 — Archi

[All pages](../FILE_GUIDE.md) · [Project guide](../PROJECT_GUIDE.md)

| File | Role and useful details |
| --- | --- |
| [.github/workflows/build.yml](../../.github/workflows/build.yml) | GitHub Actions workflow for build; defines automation triggers, jobs, and build/check steps. |
| [.gitignore](../../.gitignore) | Defines local data, credentials, dependencies, and generated outputs that Git should leave untracked. |
| [BUILD.md](../../BUILD.md) | Documentation: Building Archi. Covers 1. Get the prerequisites; 2. Configure and build; Linux / macOS. |
| [CMakeLists.txt](../../CMakeLists.txt) | CMake build definition for .; declares targets, dependency discovery, and compiler/build settings. |
| [LICENSE](../../LICENSE) | Preserved license, copyright, or attribution terms; read the full text before reusing the covered component. |
| [PROJECT_NOTES.md](../../PROJECT_NOTES.md) | Preserved detailed setup, usage, architecture, and development notes from the earlier README. |
| [README.md](../../README.md) | Project overview, current status, entry points, setup navigation, and documentation links. |
| [docs/DEPENDENCIES.csv](../../docs/DEPENDENCIES.csv) | Machine-readable inventory of declared and locked dependencies, versions, reported licenses, and evidence URLs. |
| [docs/FILE_GUIDE.md](../../docs/FILE_GUIDE.md) | Index of the complete tracked-file guide, with one entry for every file and links to the paginated descriptions. |
| [docs/LICENSE_REVIEW.md](../../docs/LICENSE_REVIEW.md) | Original-code license, preserved component notices, dependency-license evidence, and unresolved distribution questions. |
| [docs/PROJECT_GUIDE.md](../../docs/PROJECT_GUIDE.md) | Maintainer orientation: purpose, important entry points, source layout, commands, and project-specific boundaries. |
| [docs/archi-canvas.png](../../docs/archi-canvas.png) | Image or interface asset for archi canvas; 1280 × 800 pixels. Source/asset rights remain separate from software-license terms. |
| [docs/file-guide/files-001.md](../../docs/file-guide/files-001.md) | One page of the tracked-file catalog; links each listed path to its role and source-derived details. |
| [exports/classic-reunions.archi.json](../../exports/classic-reunions.archi.json) | Structured classic reunions.archi data; top-level fields: `format`, `version`, `title`, `backgroundColor`, `activeView`, `views`. |
| [exports/classic-reunions.png](../../exports/classic-reunions.png) | Image or interface asset for classic reunions; 1348 × 3972 pixels. Source/asset rights remain separate from software-license terms. |
| [qml/ArrowLayer.qml](../../qml/ArrowLayer.qml) | Source module for ArrowLayer; defines `labelBounds`; contributes to the application’s interface. |
| [qml/CheatSheetPopup.qml](../../qml/CheatSheetPopup.qml) | Source module for CheatSheetPopup; defines `method`, `defined`; contributes to the application’s interface. |
| [qml/InfiniteCanvas.qml](../../qml/InfiniteCanvas.qml) | Source module for InfiniteCanvas; defines `copyShape`, `captureState`, `commitBefore`, `beginChange`, `endChange`, `resetHistory`, `restoreState` and 24 more symbols; contributes to the application’s interface. |
| [qml/LogicTest.qml](../../qml/LogicTest.qml) | Source module for LogicTest; defines `assertEq`, `assertTrue`; contributes to the application’s interface. |
| [qml/Main.qml](../../qml/Main.qml) | Source module for Main; defines `toggleSavedBackground`, `openBackgroundChooser`, `cycleBackground`; contributes to the application’s interface. |
| [qml/PngExporter.qml](../../qml/PngExporter.qml) | Source module for PngExporter; defines `finish`, `exportTo`, `render`; contributes to the application’s interface. |
| [qml/ProjectWorkspace.qml](../../qml/ProjectWorkspace.qml) | Source module for ProjectWorkspace; defines `parseRecents`, `rememberProject`, `newDocumentData`, `checkWorkflow`, `insertCalculation`, `openProject`, `createProject` and 28 more symbols; contributes to the application’s interface. |
| [qml/ShapeIcon.qml](../../qml/ShapeIcon.qml) | Source module for ShapeIcon; contributes to the application’s interface. |
| [qml/ShapeItem.qml](../../qml/ShapeItem.qml) | Source module for ShapeItem; contributes to the application’s interface. |
| [qml/SyncPanel.qml](../../qml/SyncPanel.qml) | Source module for SyncPanel; defines `handle`, `startLink`, `openPreview`; contributes to the application’s interface. |
| [qml/WorkflowChecks.js](../../qml/WorkflowChecks.js) | Source module for WorkflowChecks; defines `analyze`, `label`. |
| [src/DocumentFiles.h](../../src/DocumentFiles.h) | Source module for DocumentFiles; defines `DocumentFiles`, `folder`, `writePng`, `saveChecked`, `read`, `write`, `create`. |
| [src/DocumentSync.h](../../src/DocumentSync.h) | Source module for DocumentSync; defines `DocumentSync`, `FileData`, `read`, `hash`, `failure`, `success`, `write` and 20 more symbols. |
| [src/MathEngine.h](../../src/MathEngine.h) | Source module for MathEngine; defines `MathEngine`, `connect`, `busy`, `result`, `error`, `calculate`, `cancel`. |
| [src/main.cpp](../../src/main.cpp) | Source module for main; defines `main`. |
| [src/math_engine.py](../../src/math_engine.py) | Bounded, non-evaluating expression front end for SymPy. One request per process. Defines `matrix`, `parse_expression`, `calculate`. |
| [tests/png_export.cpp](../../tests/png_export.cpp) | Test implementation for png export; defines `check`, `writeFile`, `shape`, `pixels`, `main`. |
