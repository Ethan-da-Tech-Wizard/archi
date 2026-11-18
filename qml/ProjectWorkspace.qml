// Program: archi - ProjectWorkspace.qml
// Programmer: Ethan-da-Tech-Wizard (written with Claude, an AI assistant)
// Last Modified: 2026-11-18
// Purpose: Main screen of Archi: extends the Main window with project files (new, open, save, autosave, recovery, reload), multiple views, node search, the details inspector, math calculator, workflow check, PNG export and document sync status.

// Bound makes QML resolve ids in this file strictly.
pragma ComponentBehavior: Bound

// Qt Quick basics, controls, layouts, dialogs and saved settings.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
// Import the other QML files in this folder (Archi.Main is the base window) and the JavaScript workflow checker.
import "." as Archi
import "WorkflowChecks.js" as WorkflowChecks

// This window is the Main window plus project handling.
Archi.Main {
    id: board
    width: 1360
    height: 880
    minimumWidth: 420
    minimumHeight: 360
    // Window title shows the project name and a star when there are unsaved changes.
    title: "Archi - " + (document ? document.title : "Untitled") + (dirty ? " *" : "")

    // Where the project file is, and where to export a PNG when started from the command line.
    property url documentUrl: ""
    property url pngExportTarget: ""
    // Options set at startup: remember recent projects and reopen the last one.
    property bool rememberProjects: true
    property bool restoreLastProject: true
    // Recent projects list, read from saved settings.
    property var recentProjects: parseRecents(projectSettings.recentJson)
    // The open project's data (title, views, background color); null when none.
    property var document: null
    // Shortcut name for the drawing canvas inherited from Main.
    readonly property var boardCanvas: diagramCanvas
    // Which view (page of the diagram) is showing.
    property int viewIndex: 0
    // The exact text last read or written on disk, used to detect outside edits.
    property string diskRevision: ""
    // Message shown in the bottom bar.
    property string status: "Opening"
    // True when there are unsaved changes.
    property bool dirty: false
    // True while a project or view is being loaded, so loading is not counted as a change.
    property bool loading: false
    // Set once the user has decided to close, so the close handler lets it happen.
    property bool allowClose: false
    // Whether changes are saved automatically after a short pause.
    property bool autoSave: true
    // Counter that goes up on every change; other parts watch it.
    property int revision: 0
    // The currently selected shape (a copy) shown in the details panel.
    property var selectedNode: null
    // Search results.
    property var matches: []
    // Per-view undo and redo history kept while switching views.
    property var viewHistory: ({})
    // True when the details panel has typed text that has not been applied to the shape yet.
    readonly property bool inspectorDirty: !!selectedNode && (titleEdit.text !== selectedNode.text
        || notesEdit.text !== selectedNode.description || codeEdit.text !== selectedNode.pseudocode)
    // Same idea for the label of a selected arrow.
    readonly property bool edgeDirty: boardCanvas.selectedArrow >= 0 && boardCanvas.selectedArrow < boardCanvas.arrows.length
        && edgeEdit.text !== (boardCanvas.arrows[boardCanvas.selectedArrow].label || "")
    // True while a sync check is pending or edits are unapplied.
    readonly property bool syncDraftPending: syncTimer.running || inspectorDirty || edgeDirty
    // Restart the sync check timer when edits appear, unless loading.
    onInspectorDirtyChanged: if (!loading) syncTimer.restart()
    onEdgeDirtyChanged: if (!loading) syncTimer.restart()
    // Leave room on the right for the details panel on wide windows.
    canvasRightInset: inspector.opened && width >= 1100 ? inspector.width : 0

    // Saved settings: recent projects and the last opened project.
    Settings {
        id: projectSettings
        location: "file://" + StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/Archi/projects.ini"
        category: "Projects"
        property string recentJson: "[]"
        property string lastUrl: ""
    }
    // Read the saved JSON text of recent projects, keeping only valid entries.
    function parseRecents(raw) {
        try { return JSON.parse(raw).filter(p => typeof p.url === "string" && typeof p.title === "string") }
        catch (error) { return [] }
    }
    // Put this project at the top of the recent list (max 20) and remember it as the last project.
    function rememberProject() {
        if (!rememberProjects || !String(documentUrl)) return
        const item = {url: String(documentUrl), title: document.title}
        projectSettings.recentJson = JSON.stringify([item].concat(recentProjects.filter(p => p.url !== item.url)).slice(0, 20))
        projectSettings.lastUrl = item.url
        projectSettings.sync()
    }
    // Return a new empty project: format name, version, title, background and one empty main view.
    function newDocumentData(title) {
        return {format: "archi-brainstorm", version: 1, title: title || "Untitled", backgroundColor: String(bgColor),
                views: [{id: "main", title: "Main", notes: "", shapes: [], arrows: []}]}
    }
    // Run the structural workflow check on the current view and return the report text.
    function checkWorkflow() {
        commitDetails()
        snapshotView()
        return WorkflowChecks.analyze(document.views[viewIndex])
    }
    // Add a diagram shape in the middle of the view holding a math result (operation, answer and expression).
    function insertCalculation(operation, expression, result) {
        const x = boardCanvas.viewX + boardCanvas.width / boardCanvas.zoom / 2
        const y = boardCanvas.viewY + boardCanvas.height / boardCanvas.zoom / 2
        boardCanvas.createShape(x, y)
        const index = boardCanvas.shapesModel.count - 1
        boardCanvas.shapesModel.setProperty(index, "text", operation)
        boardCanvas.shapesModel.setProperty(index, "description", result)
        boardCanvas.shapesModel.setProperty(index, "pseudocode", expression + "\n=> " + result)
        boardCanvas.editingIndex = -1
        updateSelection()
    }
    // Open another project; first save any unsaved changes, and go back if loading fails.
    function openProject(url) {
        commitDetails()
        if (dirty && !saveDocument()) return false
        const previous = documentUrl
        documentUrl = url
        if (loadDocument()) return true
        documentUrl = previous
        return false
    }
    // Create a new project file with the given title and open it.
    function createProject(url, title) {
        commitDetails()
        if (dirty && !saveDocument()) return false
        const result = boardFiles.create(url, JSON.stringify(newDocumentData(title), null, 2) + "\n")
        if (!result.ok) { status = result.error; return false }
        return openProject(url)
    }
    // Add a new view (page) and show it.
    function addView(title) {
        commitDetails()
        snapshotView()
        viewHistory[document.views[viewIndex].id] = {undo: boardCanvas.undoStack, redo: boardCanvas.redoStack}
        let id = "view-" + Date.now()
        while (document.views.some(view => view.id === id)) id += "-new"
        const view = {id: id, title: title || "New view", notes: "", shapes: [], arrows: []}
        document = Object.assign({}, document, {views: document.views.concat([view])})
        showView(document.views.length - 1)
        changed()
    }
    // If the details panel has unapplied typed text, apply it to the diagram.
    function commitDetails() {
        if (edgeDirty) { applyDetails(); return }
        if (!selectedNode) return
        if (titleEdit.text !== selectedNode.text || notesEdit.text !== selectedNode.description || codeEdit.text !== selectedNode.pseudocode)
            applyDetails()
    }
    // When the background color changes, store it in the project and mark it changed.
    onBgColorChanged: {
        if (document && !loading) {
            document.backgroundColor = String(bgColor)
            changed()
        }
    }

    // Read a text file through the C++ file helper, throwing an error if it fails.
    function readFile(url) {
        const result = boardFiles.read(url)
        if (!result.ok) throw new Error(result.error)
        return result.text
    }
    // Write a text file through the C++ file helper, throwing an error if it fails.
    function writeFile(url, text) {
        const result = boardFiles.write(url, text)
        if (!result.ok) throw new Error(result.error)
    }
    // Check a loaded project is valid: right format and version, size limits, unique ids, finite sizes and arrows that point at real shapes.
    function validate(data) {
        if (data.format !== "archi-brainstorm" || data.version !== 1
                || !Array.isArray(data.views) || !data.views.length)
            throw new Error("Unsupported board document")
        const viewIds = new Set()
        for (const view of data.views) {
            if (view.shapes && view.shapes.length > 1500)
                throw new Error("View exceeds the 1500-node limit")
            if (view.arrows && view.arrows.length > 5000)
                throw new Error("View exceeds the 5000-connection limit")
            if (viewIds.has(view.id) || !Array.isArray(view.shapes) || !Array.isArray(view.arrows))
                throw new Error("Invalid view")
            viewIds.add(view.id)
            const ids = new Set()
            for (const shape of view.shapes) {
                if (!Number.isInteger(shape.shapeId) || shape.shapeId < 1 || ids.has(shape.shapeId)
                        || ![shape.px, shape.py, shape.pw, shape.ph].every(Number.isFinite)
                        || shape.pw <= 0 || shape.ph <= 0 || typeof shape.text !== "string"
                        || typeof shape.shapeKind !== "string" || typeof shape.shapeColor !== "string")
                    throw new Error("Invalid shape in " + view.title)
                ids.add(shape.shapeId)
            }
            for (const arrow of view.arrows) {
                if (!ids.has(arrow.fromId) || !ids.has(arrow.toId))
                    throw new Error("Connection has a missing endpoint")
                if (arrow.points && !arrow.points.every(p => Number.isFinite(p.x) && Number.isFinite(p.y)))
                    throw new Error("Invalid connection route")
            }
        }
    }
    // Record that something changed: mark unsaved, bump the counter, show the status and start the sync and autosave timers.
    function changed() {
        if (loading || !document) return
        dirty = true
        revision++
        status = "Unsaved changes"
        syncTimer.restart()
        if (autoSave) saveTimer.restart()
    }
    // Send the current diagram (including unapplied edits) to the sync checker as the draft.
    function refreshSyncDraft() {
        syncTimer.stop()
        if (!document || loading) return
        snapshotView()
        const candidate = JSON.parse(JSON.stringify(document))
        if (inspectorDirty) {
            const shape = candidate.views[viewIndex].shapes.find(s => s.shapeId === selectedNode.shapeId)
            if (shape) { shape.text = titleEdit.text; shape.description = notesEdit.text; shape.pseudocode = codeEdit.text }
        }
        if (edgeDirty) candidate.views[viewIndex].arrows[boardCanvas.selectedArrow].label = edgeEdit.text
        projectSync.updateDraft(JSON.stringify(candidate))
    }
    // Copy the live canvas back into the document data for the current view.
    function snapshotView() {
        if (!document) return
        const view = document.views[viewIndex]
        const originals = new Map(view.shapes.map(s => [s.shapeId, s]))
        view.shapes = boardCanvas.captureState().shapes.map(s => Object.assign({}, originals.get(s.shapeId) || {}, s))
        view.arrows = JSON.parse(JSON.stringify(boardCanvas.arrows))
        view.viewport = {x: boardCanvas.viewX, y: boardCanvas.viewY, zoom: boardCanvas.zoom}
        document.activeView = view.id
        document.backgroundColor = String(bgColor)
    }
    // Show view number index: clear the canvas, load its shapes and arrows, restore its undo history and view position.
    function showView(index) {
        if (!document || index < 0 || index >= document.views.length) return
        loading = true
        boardCanvas.editingIndex = -1
        boardCanvas.restoring = true
        viewIndex = index
        const view = document.views[index]
        boardCanvas.clearCanvas()
        let maxId = 0
        for (const shape of view.shapes) {
            boardCanvas.shapesModel.append(boardCanvas.copyShape(shape))
            maxId = Math.max(maxId, shape.shapeId)
        }
        boardCanvas.nextShapeId = maxId + 1
        boardCanvas.arrows = JSON.parse(JSON.stringify(view.arrows))
        boardCanvas.rebuildArrowGeometry()
        const history = viewHistory[view.id]
        boardCanvas.resetHistory()
        if (history) {
            boardCanvas.undoStack = history.undo
            boardCanvas.redoStack = history.redo
        }
        boardCanvas.restoring = false
        // Use the saved view position if it is valid; otherwise fit the diagram, or reset for an empty view.
        if (view.viewport && [view.viewport.x, view.viewport.y, view.viewport.zoom].every(Number.isFinite)
                && view.viewport.zoom > 0) {
            boardCanvas.viewX = view.viewport.x
            boardCanvas.viewY = view.viewport.y
            boardCanvas.zoom = view.viewport.zoom
        } else if (boardCanvas.shapesModel.count) {
            boardCanvas.fitView()
        } else {
            boardCanvas.viewX = 0; boardCanvas.viewY = 0; boardCanvas.zoom = 1
        }
        loading = false
        selectedNode = null
        revision++
        boardCanvas.forceActiveFocus()
    }
    // Switch to another view, saving the current one and its history first.
    function switchView(index) {
        if (!document || index === viewIndex) return
        commitDetails()
        boardCanvas.editingIndex = -1
        snapshotView()
        viewHistory[document.views[viewIndex].id] = {undo: boardCanvas.undoStack, redo: boardCanvas.redoStack}
        showView(index)
        changed()
    }
    // Jump to a view by its id.
    function goToView(id) {
        const index = document.views.findIndex(v => v.id === id)
        if (index >= 0) switchView(index)
    }
    function fitView() { boardCanvas.fitView() }
    // Load the project file from documentUrl, validate it and show it; sets the status message on failure.
    function loadDocument() {
        saveTimer.stop()
        try {
            const raw = readFile(documentUrl)
            const parsed = JSON.parse(raw)
            validate(parsed)
            loading = true
            document = parsed
            bgColor = parsed.backgroundColor || "#ffffff"
            viewHistory = ({})
            diskRevision = raw
            const index = parsed.views.findIndex(v => v.id === parsed.activeView)
            showView(index < 0 ? 0 : index)
            dirty = false
            status = "Saved locally"
            projectSync.track(documentUrl, JSON.stringify(document), diskRevision)
            rememberProject()
            return true
        } catch (error) {
            status = String(error)
            return false
        }
    }
    // Save the project (to a new file if target is given); keeps a recovery copy if saving fails.
    function saveDocument(target) {
        saveTimer.stop()
        commitDetails()
        if (!target && !String(documentUrl)) { copyDialog.open(); return false }
        try {
            if (!document) throw new Error("No document is open")
            snapshotView()
            validate(document)
            const url = target ? String(target) : String(documentUrl)
            const raw = JSON.stringify(document, null, 2) + "\n"
            // When saving to the same file, check it did not change on disk meanwhile; otherwise write to the new file.
            if (url === String(documentUrl)) {
                const result = boardFiles.saveChecked(documentUrl, diskRevision, raw)
                if (!result.ok) throw new Error(result.error)
            } else writeFile(url, raw)
            documentUrl = url
            diskRevision = raw
            dirty = false
            projectSync.track(documentUrl, raw, diskRevision)
            rememberProject()
            status = "Saved " + Qt.formatTime(new Date(), "hh:mm:ss")
            return true
        } catch (error) {
            status = String(error)
            // If the save failed, try to keep a .recovery.json copy so the work is not lost.
            try {
                writeFile(String(documentUrl) + ".recovery.json", JSON.stringify(document, null, 2) + "\n")
                status += " Recovery saved."
            } catch (recoveryError) { status += " Recovery failed: " + recoveryError }
            return false
        }
    }
    // Reload from disk, asking first if there are unsaved changes.
    function requestReload() {
        if (dirty) reloadDialog.open()
        else loadDocument()
    }
    // Start exporting the current view as a PNG.
    function exportPng(target) {
        if (pngExporter.busy) return false
        commitDetails()
        status = "Exporting PNG..."
        return pngExporter.exportTo(boardCanvas, target)
    }
    // Fill the details panel from whatever is selected.
    function updateSelection() {
        const s = boardCanvas.findShapeById(boardCanvas.selectedId)
        selectedNode = s ? boardCanvas.copyShape(s) : null
        titleEdit.text = s ? s.text : ""
        notesEdit.text = s ? s.description || "" : ""
        codeEdit.text = s ? s.pseudocode || "" : ""
        edgeEdit.text = boardCanvas.selectedArrow >= 0 ? boardCanvas.arrows[boardCanvas.selectedArrow].label || "" : ""
    }
    // Write the details panel text back into the selected shape or arrow label as one undoable change.
    function applyDetails() {
        boardCanvas.editingIndex = -1
        boardCanvas.beginChange()
        if (selectedNode) {
            for (let i = 0; i < boardCanvas.shapesModel.count; ++i) {
                if (boardCanvas.shapesModel.get(i).shapeId === selectedNode.shapeId) {
                    boardCanvas.shapesModel.setProperty(i, "text", titleEdit.text)
                    boardCanvas.shapesModel.setProperty(i, "description", notesEdit.text)
                    boardCanvas.shapesModel.setProperty(i, "pseudocode", codeEdit.text)
                    break
                }
            }
        } else if (boardCanvas.selectedArrow >= 0) {
            const arrows = JSON.parse(JSON.stringify(boardCanvas.arrows))
            arrows[boardCanvas.selectedArrow].label = edgeEdit.text
            boardCanvas.arrows = arrows
        }
        boardCanvas.endChange()
        updateSelection()
    }
    // Search all views for nodes whose text, key or description contains the query; show up to 80 matches.
    function searchNodes(query) {
        if (!document) return
        snapshotView()
        const q = query.trim().toLowerCase()
        const found = []
        if (q) document.views.forEach((v, vi) => v.shapes.forEach(s => {
            if ((s.text + " " + (s.nodeKey || "") + " " + (s.description || "")).toLowerCase().includes(q))
                found.push({viewIndex: vi, id: s.shapeId, title: s.text, key: s.nodeKey || "", view: v.title})
        }))
        matches = found.slice(0, 80)
        if (q) searchPopup.open()
        else searchPopup.close()
    }

    // When the screen has loaded: open the last or requested project, run a PNG export if asked, otherwise start a new empty project.
    Component.onCompleted: Qt.callLater(function() {
        const initial = String(documentUrl)
        if (rememberProjects && restoreLastProject && projectSettings.lastUrl) {
            documentUrl = projectSettings.lastUrl
            if (loadDocument()) return
        }
        documentUrl = initial
        if (initial && loadDocument()) {
            if (String(pngExportTarget)) Qt.callLater(function() { board.exportPng(board.pngExportTarget) })
            return
        }
        if (String(pngExportTarget)) {
            console.error("PNG export failed: " + status)
            Qt.exit(1)
            return
        }
        document = newDocumentData("Untitled")
        showView(0)
        dirty = false
        status = "New project"
        projectSync.track(documentUrl, JSON.stringify(document), "")
    })
    // Timers: save after 1.2 seconds of quiet, and refresh the sync draft shortly after edits.
    Timer { id: saveTimer; interval: 1200; onTriggered: if (board.dirty && String(board.documentUrl)) board.saveDocument() }
    Timer { id: syncTimer; interval: 180; onTriggered: board.refreshSyncDraft() }
    // The document sync dialog.
    Archi.SyncPanel { id: syncPanel; workspace: board }
    // React to canvas changes: shape data and view movement count as changes, selection updates the details panel.
    Connections {
        target: board.boardCanvas.shapesModel
        function onDataChanged() { board.changed() }
        function onCountChanged() { board.changed() }
    }
    Connections {
        target: board.boardCanvas
        function onModified() { board.changed(); board.updateSelection() }
        function onSelectedIdChanged() { if (!board.loading) board.commitDetails(); board.updateSelection() }
        function onInspectShapeRequested(id) { board.updateSelection(); inspector.open() }
        function onSelectedArrowChanged() { board.updateSelection() }
        function onViewXChanged() { board.changed() }
        function onViewYChanged() { board.changed() }
        function onZoomChanged() { board.changed() }
    }
    // Keyboard shortcuts: save, export PNG, open, reload, fit view and search.
    Shortcut { sequences: [StandardKey.Save]; onActivated: board.saveDocument() }
    Shortcut { sequence: "Ctrl+Shift+E"; enabled: !pngExporter.busy; onActivated: pngDialog.open() }
    Shortcut { sequences: [StandardKey.Open]; onActivated: if (!board.dirty || board.saveDocument()) openDialog.open() }
    Shortcut { sequence: "Ctrl+R"; onActivated: board.requestReload() }
    Shortcut { sequence: "Ctrl+0"; onActivated: board.fitView() }
    Shortcut { sequence: "Ctrl+F"; onActivated: searchField.forceActiveFocus() }

    // Reusable toolbar button type with an icon and tooltip.
    component BoardTool: ToolButton {
        property string glyph
        property string tip
        implicitWidth: 34
        implicitHeight: 34
        icon.name: glyph
        icon.source: "file:///usr/share/icons/breeze/actions/22/" + glyph + ".svg"
        display: AbstractButton.IconOnly
        ToolTip.visible: hovered
        ToolTip.text: tip
        Accessible.name: tip
    }

    // The top bar: project buttons, project picker, math, workflow check, save and export, then view picker and search.
    menuBar: ToolBar {
        implicitHeight: 86
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 5
            spacing: 3
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                BoardTool { glyph: "document-new"; tip: "New project"; onClicked: newProjectDialog.open() }
                BoardTool { glyph: "document-open"; tip: "Open project"; onClicked: if (!board.dirty || board.saveDocument()) openDialog.open() }
                ToolButton {
                    implicitWidth: 30; implicitHeight: 30
                    background: Rectangle { color: board.bgColor; border.color: "#687580"; radius: 3 }
                    onClicked: board.openBackgroundChooser()
                    ToolTip.visible: hovered; ToolTip.text: "Background color"
                }
                ComboBox {
                    objectName: "projectPicker"
                    Layout.fillWidth: true
                    model: board.recentProjects
                    textRole: "title"
                    displayText: board.document ? board.document.title : "Untitled"
                    currentIndex: board.recentProjects.findIndex(p => p.url === String(board.documentUrl))
                    onActivated: board.openProject(board.recentProjects[currentIndex].url)
                }
                BoardTool { glyph: "formula"; tip: "Math and logic"; onClicked: mathDialog.open() }
                BoardTool { glyph: "dialog-ok-apply"; tip: "Check workflow"; onClicked: { checkReport.text = board.checkWorkflow(); checkDialog.open() } }
                BoardTool { glyph: "document-save"; tip: "Save project"; onClicked: board.saveDocument() }
                ToolButton {
                    objectName: "exportPng"
                    text: "Export PNG"
                    enabled: !pngExporter.busy
                    ToolTip.visible: hovered
                    ToolTip.text: "Export current view as PNG (Ctrl+Shift+E)"
                    onClicked: pngDialog.open()
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 5
            ComboBox {
                id: viewPicker
                Layout.preferredWidth: Math.min(260, board.width * 0.39)
                model: board.document ? board.document.views : []
                textRole: "title"
                currentIndex: board.viewIndex
                onActivated: board.switchView(currentIndex)
            }
            BoardTool { glyph: "list-add"; tip: "New view"; onClicked: newViewDialog.open() }
            TextField {
                id: searchField
                Layout.fillWidth: true
                Layout.minimumWidth: 65
                placeholderText: "Search nodes"
                onTextEdited: board.searchNodes(text)
            }
            BoardTool { objectName: "showDetails"; glyph: "document-properties"; tip: "Node details"; onClicked: inspector.opened ? inspector.close() : inspector.open() }
            }
        }
    }

    // Popup listing the search matches; clicking one jumps to that node.
    Popup {
        id: searchPopup
        x: Math.max(8, board.width - width - 12)
        y: 0
        width: Math.min(520, board.width - 16)
        height: Math.min(360, board.height - 160)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        ListView {
            anchors.fill: parent
            clip: true
            model: board.matches
            delegate: ItemDelegate {
                required property var modelData
                width: ListView.view.width
                text: modelData.key + "  " + modelData.title + "  (" + modelData.view + ")"
                highlighted: hovered
                onClicked: {
                    board.switchView(modelData.viewIndex)
                    board.boardCanvas.focusShape(modelData.id)
                    searchPopup.close()
                }
            }
            ScrollBar.vertical: ScrollBar {}
            Label { anchors.centerIn: parent; visible: board.matches.length === 0; text: "No matching nodes" }
        }
    }

    // Side panel (drawer) showing the details of the selected node or arrow, with editors for text, analysis, pseudocode or branch label.
    Drawer {
        id: inspector
        objectName: "nodeInspector"
        edge: Qt.RightEdge
        width: Math.min(370, board.width - 24)
        height: board.contentItem.height
        y: board.header.height + board.menuBar.height
        modal: board.width < 1100
        interactive: false
        closePolicy: Popup.CloseOnEscape
        ScrollView {
            objectName: "detailsScroll"
            background: Rectangle { color: "#f7f8fa" }
            anchors.fill: parent
            anchors.margins: 12
            contentWidth: availableWidth
            ColumnLayout {
                width: parent.width
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: board.selectedNode ? board.selectedNode.nodeKey || "New node" : board.boardCanvas.selectedArrow >= 0 ? "Connection" : "View"; font.bold: true; Layout.fillWidth: true }
                    BoardTool { glyph: "window-close"; tip: "Close details"; onClicked: inspector.close() }
                }
                Label {
                    Layout.fillWidth: true
                    visible: !board.selectedNode && board.boardCanvas.selectedArrow < 0
                    text: board.document && board.document.views[board.viewIndex] ? board.document.views[board.viewIndex].notes || "" : ""
                    wrapMode: Text.Wrap
                }
                Label { text: "Operation"; visible: !!board.selectedNode }
                TextArea { id: titleEdit; objectName: "nodeTitle"; Layout.fillWidth: true; visible: !!board.selectedNode; wrapMode: TextEdit.Wrap; selectByMouse: true }
                Label { text: "Analysis"; visible: !!board.selectedNode }
                TextArea { id: notesEdit; objectName: "nodeNotes"; Layout.fillWidth: true; visible: !!board.selectedNode; wrapMode: TextEdit.Wrap; selectByMouse: true }
                Label { text: "Pseudocode"; visible: !!board.selectedNode }
                TextArea { id: codeEdit; objectName: "nodeCode"; Layout.fillWidth: true; visible: !!board.selectedNode; wrapMode: TextEdit.WrapAnywhere; selectByMouse: true; font.family: "monospace" }
                Label { text: "Branch"; visible: board.boardCanvas.selectedArrow >= 0 }
                TextField { id: edgeEdit; Layout.fillWidth: true; visible: board.boardCanvas.selectedArrow >= 0 }
                Button { text: "Apply"; visible: !!board.selectedNode || board.boardCanvas.selectedArrow >= 0; onClicked: board.applyDetails() }
                Button {
                    text: "Open flow"
                    visible: !!board.selectedNode && !!board.selectedNode.linkView
                    onClicked: board.goToView(board.selectedNode.linkView)
                }
            }
        }
    }

    // Dialog asking for a new project's name, then a file location.
    Dialog {
        id: newProjectDialog
        title: "New Project"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        TextField { id: projectName; placeholderText: "Project name"; text: "Untitled"; selectByMouse: true }
        onAccepted: newProjectFile.open()
    }

    // Math and Logic dialog: pick an operation and variable, type an expression, and calculate it using the C++ MathEngine.
    Dialog {
        id: mathDialog
        objectName: "mathDialog"
        property string submittedKey: ""
        // Key that identifies the current inputs, so an old result is not shown for changed inputs.
        readonly property string currentKey: JSON.stringify([mathExpression.text, mathOperation.currentText, mathVariable.text])
        // True when there is a fresh, successful result that can be added to the diagram.
        readonly property bool hasCurrentResult: submittedKey === currentKey && !mathEngine.busy && !!mathEngine.result && !mathEngine.error
        title: "Math & Logic"
        anchors.centerIn: parent
        width: Math.min(670, board.width - 24)
        height: Math.min(440, board.height - 24)
        modal: true
        standardButtons: Dialog.Close
        // Closing the dialog cancels any running calculation.
        onClosed: mathEngine.cancel()
        contentItem: ColumnLayout {
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                ComboBox {
                    id: mathOperation
                    objectName: "mathOperation"
                    Layout.fillWidth: true
                    enabled: !mathEngine.busy
                    model: ["Simplify", "Expand", "Factor", "Differentiate", "Integrate", "Solve = 0", "Determinant", "Inverse", "Eigenvalues", "Boolean simplify", "Satisfiable"]
                }
                Label { text: "Variable" }
                TextField { id: mathVariable; text: "x"; Layout.preferredWidth: 65; enabled: !mathEngine.busy }
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 76
                Layout.minimumHeight: 40
                TextArea { id: mathExpression; objectName: "mathExpression"; placeholderText: "(x + 1)**3"; readOnly: mathEngine.busy; textFormat: TextEdit.PlainText; wrapMode: TextEdit.Wrap; selectByMouse: true; font.family: "monospace" }
            }
            RowLayout {
                Layout.fillWidth: true
                Button { objectName: "calculateMath"; text: "Calculate"; enabled: !mathEngine.busy; onClicked: { mathDialog.submittedKey = mathDialog.currentKey; mathEngine.calculate(mathExpression.text, mathOperation.currentText, mathVariable.text) } }
                BoardTool { glyph: "process-stop"; tip: "Cancel calculation"; enabled: mathEngine.busy; onClicked: mathEngine.cancel() }
                BusyIndicator { Layout.preferredWidth: 28; Layout.preferredHeight: 28; running: mathEngine.busy }
                Item { Layout.fillWidth: true }
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 60
                TextArea {
                    id: mathResult
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    font.family: "monospace"
                    text: mathDialog.submittedKey === mathDialog.currentKey ? mathEngine.error || mathEngine.result : ""
                }
            }
            RowLayout {
                Button { objectName: "insertMath"; text: "Add to diagram"; enabled: mathDialog.hasCurrentResult; onClicked: { board.insertCalculation(mathOperation.currentText, mathExpression.text, mathEngine.result); mathDialog.close() } }
                BoardTool { glyph: "edit-copy"; tip: "Copy result"; enabled: mathDialog.hasCurrentResult; onClicked: { mathResult.selectAll(); mathResult.copy() } }
            }
        }
    }
    // Workflow Check dialog showing the report text.
    Dialog {
        id: checkDialog
        title: "Workflow Check"
        anchors.centerIn: parent
        width: Math.min(650, board.width - 24)
        height: Math.min(420, board.height - 24)
        modal: true
        standardButtons: Dialog.Close
        ScrollView {
            anchors.fill: parent
            TextArea { id: checkReport; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText }
        }
    }
    // File dialog that creates a new project file.
    FileDialog {
        id: newProjectFile
        title: "Create Project"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Archi project (*.json)"]
        defaultSuffix: "archi.json"
        onAccepted: board.createProject(selectedFile, projectName.text)
    }
    // Dialog asking for a new view's name.
    Dialog {
        id: newViewDialog
        title: "New View"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        TextField { id: viewName; placeholderText: "View name"; text: "Main"; selectByMouse: true }
        onAccepted: board.addView(viewName.text)
    }

    // File dialogs for opening a project, saving a copy and exporting a PNG; each starts in the project folder or the Documents folder.
    FileDialog {
        id: openDialog
        title: "Open Board"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Archi brainstorm (*.json)"]
        currentFolder: String(board.documentUrl) ? boardFiles.folder(board.documentUrl) : "file://" + StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        onAccepted: board.openProject(selectedFile)
    }
    FileDialog {
        id: copyDialog
        title: "Save a Copy"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Archi brainstorm (*.json)"]
        defaultSuffix: "json"
        currentFolder: String(board.documentUrl) ? boardFiles.folder(board.documentUrl) : "file://" + StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        onAccepted: board.saveDocument(selectedFile)
    }
    FileDialog {
        id: pngDialog
        objectName: "pngExportDialog"
        title: "Export Current View as PNG"
        fileMode: FileDialog.SaveFile
        nameFilters: ["PNG image (*.png)"]
        defaultSuffix: "png"
        currentFolder: String(board.documentUrl) ? boardFiles.folder(board.documentUrl) : "file://" + StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        onAccepted: board.exportPng(selectedFile)
    }
    // Helper that renders the PNG; update the status when finished and exit with the result when started from the command line.
    Archi.PngExporter {
        id: pngExporter
        onFinished: (file, result) => {
            if (result.ok) {
                board.status = "PNG exported (" + result.width + " × " + result.height + "): " + decodeURIComponent(String(file).split("/").pop())
            } else {
                board.status = "PNG export failed: " + result.error
                if (!String(board.pngExportTarget)) {
                    pngError.text = result.error
                    pngError.open()
                }
            }
            if (String(board.pngExportTarget)) {
                if (result.ok) console.log(board.status)
                else console.error(board.status)
                Qt.exit(result.ok ? 0 : 1)
            }
        }
    }
    // Error dialog for failed PNG exports.
    MessageDialog {
        id: pngError
        title: "PNG export failed"
    }
    // Confirmation before discarding changes on reload.
    Dialog {
        id: reloadDialog
        title: "Discard unsaved changes and reload?"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Discard | Dialog.Cancel
        onDiscarded: board.loadDocument()
    }
    // Ask to save, discard or cancel when closing with unsaved changes.
    Dialog {
        id: closeDialog
        title: "Save changes before closing?"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Save | Dialog.Discard | Dialog.Cancel
        onAccepted: if (board.saveDocument()) { board.allowClose = true; board.close() }
        onDiscarded: { board.allowClose = true; board.close() }
    }
    // When the window is closing, try to save; if that fails, stop closing and ask.
    onClosing: close => {
        if (dirty && !allowClose && !saveDocument()) { close.accepted = false; closeDialog.open() }
    }

    // The bottom bar: document sync status and the file status, node count, autosave switch and save/reload buttons.
    footer: ToolBar {
        implicitHeight: 72
        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                spacing: 5
                BoardTool { objectName: "openSync"; glyph: "insert-link"; tip: "Document sync"; onClicked: syncPanel.open() }
                Label {
                    objectName: "syncStatus"
                    Layout.fillWidth: true
                    text: board.inspectorDirty || board.edgeDirty ? "Unapplied diagram edits" : syncTimer.running ? "Checking diagram edits..." : projectSync.report.summary || "Documents not linked"
                    textFormat: Text.PlainText
                    color: projectSync.report.state === "current" ? "#17634b" : "#9a372d"
                    elide: Text.ElideRight
                    ToolTip.visible: syncHover.hovered
                    ToolTip.text: text
                    HoverHandler { id: syncHover }
                }
                BoardTool { glyph: "view-refresh"; tip: "Check document sync"; onClicked: { board.refreshSyncDraft(); projectSync.refresh() } }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 5
            Label {
                text: board.status
                Layout.fillWidth: true
                elide: Text.ElideRight
                ToolTip.visible: statusHover.hovered
                ToolTip.text: String(board.documentUrl) + "\n" + board.status
                HoverHandler { id: statusHover }
            }
            Label { visible: board.width > 650; text: board.boardCanvas.shapesModel.count + " nodes" }
            Switch { text: "Autosave"; checked: board.autoSave; onToggled: { board.autoSave = checked; if (checked && board.dirty) saveTimer.restart(); else saveTimer.stop() } }
            BoardTool { glyph: "document-save-as"; tip: "Save a copy"; onClicked: copyDialog.open() }
            BoardTool { glyph: "view-refresh"; tip: "Reload board"; onClicked: board.requestReload() }
            }
        }
    }
}
