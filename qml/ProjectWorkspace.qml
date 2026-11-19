// ==============================================================================
// Program: ProjectWorkspace.qml
// Programmer: Ethan-da-Tech-Wizard
// Last Modified: November 18, 2026
// Purpose: Central workspace manager coordinating file opening, serialization to JSON,
//          recent project history tracking, math engine integration, workflow validation
//          reporting, and document export pipeline.
//
// How it fits: main.cpp loads this as the default window. It extends the base
// window `Archi.Main` (Main.qml: toolbar, InfiniteCanvas as `diagramCanvas`,
// background colour, cheat sheet) and adds everything document related:
//   * document model: one JS object (`document`) in format "archi-brainstorm"
//     version 1 = { title, backgroundColor, activeView, views: [ {id, title,
//     notes, shapes[], arrows[], viewport} ] }. The canvas holds only the
//     CURRENT view; snapshotView() copies it back into `document` and
//     showView() loads another.
//   * persistence via the C++ helper `boardFiles` (DocumentFiles.h): checked
//     saves, atomic writes, ".bak" backups, ".recovery.json" on failed saves.
//   * `projectSync` (DocumentSync.h) is told about every open/save/edit so
//     the sync panel and footer stay correct.
//   * helpers: WorkflowChecks.js (graph validation), `mathEngine` (SymPy),
//     PngExporter, SyncPanel, search, node inspector, recent-project list.
//
// State flow: any canvas change -> changed() -> dirty=true, syncTimer (180 ms
// debounce to projectSync) and, if Autosave is on, saveTimer (1.2 s) ->
// saveDocument(). Note that panning/zooming also counts as a change because
// the viewport is saved in the file.
//
// Command-line properties set by main.cpp: documentUrl, pngExportTarget,
// restoreLastProject, rememberProjects, autoSave (see "--export-png").
//
// Known limits: 1500 shapes and 5000 arrows per view (validate()); whole
// project is one JSON file; undo history is per view and in memory only.
// ==============================================================================
// Bound component behaviour: delegates/inline components reference these ids
// through qualified names (`board.`), and per-item data uses required properties.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
// "." imports this folder's QML types under the name Archi (Main, SyncPanel, PngExporter).
import "." as Archi
// Stateless library (.pragma library) with analyze(view); imported by path.
import "WorkflowChecks.js" as WorkflowChecks

// Window id `board`: referenced by child dialogs and by the helper QML types.
Archi.Main {
    id: board
    width: 1360
    height: 880
    minimumWidth: 420
    minimumHeight: 360
    // Window title shows project name and a trailing "*" while there are unsaved changes.
    title: "Archi - " + (document ? document.title : "Untitled") + (dirty ? " *" : "")

    // Project file being edited (empty = untitled, not yet saved).
    property url documentUrl: ""
    // Set only by `--export-png`: where to write the PNG, after which the app exits.
    property url pngExportTarget: ""
    // Whether to record opened projects in the recent list; the CLI export turns this off.
    property bool rememberProjects: true
    // Whether to reopen the last project at start-up.
    property bool restoreLastProject: true
    // Recent projects as [{url, title}], parsed from settings (corrupt JSON gives []).
    property var recentProjects: parseRecents(projectSettings.recentJson)
    // The whole project JSON (see header); null until loaded.
    property var document: null
    // Short alias to the InfiniteCanvas declared in Main.qml.
    readonly property var boardCanvas: diagramCanvas
    // Index into document.views of the view shown on the canvas.
    property int viewIndex: 0
    // Exact file text last read or written; sent with each save so C++ can
    // detect that someone else changed the file meanwhile (optimistic locking).
    property string diskRevision: ""
    // Text of the status line at the bottom ("Saved 14:03:02", errors, ...).
    property string status: "Opening"
    // True when in-memory content differs from disk.
    property bool dirty: false
    // True while a document or view is being loaded; suppresses change tracking.
    property bool loading: false
    // Set when the user has answered the "save before closing" prompt.
    property bool allowClose: false
    // Autosave switch (footer toggle); saves 1.2 s after the last change.
    property bool autoSave: true
    // Counter bumped on loads and edits, so bindings can react to "something changed".
    property int revision: 0
    // Copy of the selected shape's data feeding the inspector; null when none.
    property var selectedNode: null
    // Search results [{viewIndex, id, title, key, view}], at most 80.
    property var matches: []
    // Undo/redo stacks of views that are not currently shown, keyed by view id,
    // so switching views does not lose history.
    property var viewHistory: ({})
    // True when the inspector's text boxes differ from the selected shape: edits
    // typed but not yet applied. Used to avoid losing them on save/switch.
    readonly property bool inspectorDirty: !!selectedNode && (titleEdit.text !== selectedNode.text
        || notesEdit.text !== selectedNode.description || codeEdit.text !== selectedNode.pseudocode)
    // Same for the selected connection's branch label.
    readonly property bool edgeDirty: boardCanvas.selectedArrow >= 0 && boardCanvas.selectedArrow < boardCanvas.arrows.length
        && edgeEdit.text !== (boardCanvas.arrows[boardCanvas.selectedArrow].label || "")
    // True while a sync update is queued or typed edits are pending; the sync
    // panel disables review actions in that case.
    readonly property bool syncDraftPending: syncTimer.running || inspectorDirty || edgeDirty
    // Start the debounce so pending inspector text reaches the sync engine soon.
    onInspectorDirtyChanged: if (!loading) syncTimer.restart()
    onEdgeDirtyChanged: if (!loading) syncTimer.restart()
    // Make room for the docked inspector on wide windows; below 1100 px it
    // overlays the canvas instead (modal drawer).
    canvasRightInset: inspector.opened && width >= 1100 ? inspector.width : 0

    // Recent-project and last-opened-project storage in <config>/Archi/projects.ini.
    Settings {
        id: projectSettings
        location: "file://" + StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/Archi/projects.ini"
        category: "Projects"
        property string recentJson: "[]"
        property string lastUrl: ""
    }
    /**
     * Parses the stored recent-project list.
     * @param raw JSON text from settings.
     * @returns {Array<{url:string,title:string}>} valid entries only; [] if the
     *          text is not valid JSON, so a damaged settings file cannot break start-up.
     */
    function parseRecents(raw) {
        try { return JSON.parse(raw).filter(p => typeof p.url === "string" && typeof p.title === "string") }
        catch (error) { return [] }
    }
    /**
     * Adds the open project to the front of the recent list (max 20, no
     * duplicates) and stores it as the project to restore next time.
     * No-op when remembering is off or the project is untitled.
     */
    function rememberProject() {
        if (!rememberProjects || !String(documentUrl)) return
        const item = {url: String(documentUrl), title: document.title}
        projectSettings.recentJson = JSON.stringify([item].concat(recentProjects.filter(p => p.url !== item.url)).slice(0, 20))
        projectSettings.lastUrl = item.url
        projectSettings.sync()
    }
    /**
     * Builds an empty project document: one empty view "main".
     * @param title Project name; "Untitled" if empty.
     */
    function newDocumentData(title) {
        return {format: "archi-brainstorm", version: 1, title: title || "Untitled", backgroundColor: String(bgColor),
                views: [{id: "main", title: "Main", notes: "", shapes: [], arrows: []}]}
    }
    /**
     * Runs the structural workflow analysis on the current view and returns the
     * report text. Pending inspector edits and canvas state are flushed first so
     * the check sees what the user sees.
     */
    function checkWorkflow() {
        commitDetails()
        snapshotView()
        return WorkflowChecks.analyze(document.views[viewIndex])
    }
    /**
     * Adds a node holding a finished calculation to the middle of the visible
     * canvas: title = operation, description = result, pseudocode =
     * "expression => result". Called by the Math dialog's "Add to diagram".
     */
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
    /**
     * Opens another project file, saving the current one first if it has
     * unsaved changes.
     * @param url Local `file:` URL.
     * @returns {boolean} true on success; on any failure the previous project
     *          stays open (documentUrl is restored) and `status` shows why.
     */
    function openProject(url) {
        commitDetails()
        if (dirty && !saveDocument()) return false
        const previous = documentUrl
        documentUrl = url
        if (loadDocument()) return true
        documentUrl = previous
        return false
    }
    /**
     * Creates a new project file (refusing to overwrite an existing one via
     * boardFiles.create) and opens it.
     * @param url   Target file URL.
     * @param title Project name stored in the file.
     */
    function createProject(url, title) {
        commitDetails()
        if (dirty && !saveDocument()) return false
        const result = boardFiles.create(url, JSON.stringify(newDocumentData(title), null, 2) + "\n")
        if (!result.ok) { status = result.error; return false }
        return openProject(url)
    }
    /**
     * Appends an empty view and switches to it. The current view's undo history
     * is parked first so it is still there when the user comes back.
     * View ids are "view-<timestamp>", made unique if two are created in the same millisecond.
     */
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
    /** Applies inspector or branch-label text the user typed but has not applied yet; no-op if nothing differs. */
    function commitDetails() {
        if (edgeDirty) { applyDetails(); return }
        if (!selectedNode) return
        if (titleEdit.text !== selectedNode.text || notesEdit.text !== selectedNode.description || codeEdit.text !== selectedNode.pseudocode)
            applyDetails()
    }
    // The background colour is part of the file; recolouring counts as an edit.
    onBgColorChanged: {
        if (document && !loading) {
            document.backgroundColor = String(bgColor)
            changed()
        }
    }

    /** Reads a file through C++ and returns its text; throws Error(message) on failure so callers can use try/catch. */
    function readFile(url) {
        const result = boardFiles.read(url)
        if (!result.ok) throw new Error(result.error)
        return result.text
    }
    /** Writes a file through C++ (atomic); throws on failure. */
    function writeFile(url, text) {
        const result = boardFiles.write(url, text)
        if (!result.ok) throw new Error(result.error)
    }
    /**
     * Checks a parsed project before it is loaded or saved; throws Error with a
     * user-readable message when something is wrong.
     *
     * Rules: correct format/version; at least one view; unique view ids; at most
     * 1500 shapes and 5000 arrows per view; each shape has a unique positive
     * integer id, finite position, positive size and string text/kind/colour;
     * every arrow endpoint exists and route points are finite numbers.
     * Validating on save too means the app never writes a file it would refuse to open.
     */
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
    /**
     * Marks the project as modified and schedules the follow-up work.
     * Ignored while loading, so opening a file does not make it "dirty".
     */
    function changed() {
        if (loading || !document) return
        dirty = true
        revision++
        status = "Unsaved changes"
        syncTimer.restart()
        if (autoSave) saveTimer.restart()
    }
    /**
     * Pushes the current (possibly unsaved) state to the sync engine now.
     *
     * Builds a candidate copy of the document with the inspector's and branch
     * editor's typed-but-unapplied text merged in, so the sync report reflects
     * what the user sees. The real document is not changed.
     */
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
    /**
     * Copies the canvas contents into `document` for the current view.
     *
     * Shape fields the canvas does not know about (anything in the original
     * shape object beyond the canvas roles) are preserved by merging the
     * canvas copy over the original, so files written by newer versions do not
     * lose data. Also records viewport (pan/zoom), active view and background.
     */
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
    /**
     * Replaces the canvas with view `index` of the document.
     *
     * Runs with `loading` and the canvas's `restoring` flags set so none of
     * this counts as an edit or an undo step. After filling shapes and arrows
     * it restores that view's parked undo history, then the saved viewport, or
     * fits the view if none was saved, or centres at zoom 1 if empty.
     * @param index Position in document.views; out-of-range is ignored.
     */
    function showView(index) {
        if (!document || index < 0 || index >= document.views.length) return
        loading = true
        boardCanvas.editingIndex = -1
        boardCanvas.restoring = true
        viewIndex = index
        const view = document.views[index]
        boardCanvas.clearCanvas()
        // New ids start above the largest in the file so existing arrows stay valid.
        let maxId = 0
        for (const shape of view.shapes) {
            boardCanvas.shapesModel.append(boardCanvas.copyShape(shape))
            maxId = Math.max(maxId, shape.shapeId)
        }
        boardCanvas.nextShapeId = maxId + 1
        boardCanvas.arrows = JSON.parse(JSON.stringify(view.arrows))
        boardCanvas.rebuildArrowGeometry()
        // resetHistory() just emptied both stacks; reinstate this view's own parked history, if any.
        const history = viewHistory[view.id]
        boardCanvas.resetHistory()
        if (history) {
            boardCanvas.undoStack = history.undo
            boardCanvas.redoStack = history.redo
        }
        boardCanvas.restoring = false
        // Accept a saved viewport only if every number is finite and zoom is positive.
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
    /**
     * Saves the current view, parks its undo history and shows another view.
     * @param index Target view; ignored if it is already shown.
     */
    function switchView(index) {
        if (!document || index === viewIndex) return
        commitDetails()
        boardCanvas.editingIndex = -1
        snapshotView()
        viewHistory[document.views[viewIndex].id] = {undo: boardCanvas.undoStack, redo: boardCanvas.redoStack}
        showView(index)
        changed()
    }
    /** Jumps to the view whose id is `id` (used by a node's "Open flow" link). */
    function goToView(id) {
        const index = document.views.findIndex(v => v.id === id)
        if (index >= 0) switchView(index)
    }
    function fitView() { boardCanvas.fitView() }
    /**
     * Loads `documentUrl` from disk, replacing the open document.
     * Validates before touching any state so a bad file cannot half-load, then
     * restores the active view, clears history, tells the sync engine and updates
     * the recent list.
     * @returns {boolean} true on success; false with the reason in `status`.
     */
    function loadDocument() {
        saveTimer.stop()
        try {
            // Read and validate BEFORE changing anything so failures leave the current project untouched.
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
    /**
     * Saves the project.
     * @param target Optional destination for "Save a copy"/first save; when
     *        omitted the existing documentUrl is saved in place.
     * @returns {boolean} true if written. An untitled project opens the Save
     *          dialog and returns false (the save continues from the dialog).
     *
     * Saving in place uses saveChecked: it refuses if the file on disk no longer
     * matches `diskRevision` (changed by someone else), and keeps a .bak of
     * the previous version. If saving fails the project is written to
     * "<file>.recovery.json" so the user's work is not lost.
     */
    function saveDocument(target) {
        saveTimer.stop()
        commitDetails()
        if (!target && !String(documentUrl)) { copyDialog.open(); return false }
        // Validate first: never write a document the loader would reject.
        try {
            if (!document) throw new Error("No document is open")
            snapshotView()
            validate(document)
            const url = target ? String(target) : String(documentUrl)
            const raw = JSON.stringify(document, null, 2) + "\n"
            // In-place save is conflict-checked; saving to a new path is a plain atomic write.
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
        // Keep the work: dump the JSON next to the project and tell the user.
        } catch (error) {
            status = String(error)
            try {
                writeFile(String(documentUrl) + ".recovery.json", JSON.stringify(document, null, 2) + "\n")
                status += " Recovery saved."
            } catch (recoveryError) { status += " Recovery failed: " + recoveryError }
            return false
        }
    }
    /** Reloads the project from disk; asks for confirmation first if there are unsaved changes (they would be lost). */
    function requestReload() {
        if (dirty) reloadDialog.open()
        else loadDocument()
    }
    /**
     * Starts a PNG export of the current view.
     * @param target Destination `file:` URL.
     * @returns {boolean} false if an export is already running or could not start.
     */
    function exportPng(target) {
        if (pngExporter.busy) return false
        commitDetails()
        status = "Exporting PNG..."
        return pngExporter.exportTo(boardCanvas, target)
    }
    /**
     * Refreshes the inspector from the canvas selection.
     * Copies the selected shape (text, description, pseudocode) into the text
     * boxes, or the selected arrow's label into the branch box; clears both
     * when nothing is selected.
     */
    function updateSelection() {
        const s = boardCanvas.findShapeById(boardCanvas.selectedId)
        selectedNode = s ? boardCanvas.copyShape(s) : null
        titleEdit.text = s ? s.text : ""
        notesEdit.text = s ? s.description || "" : ""
        codeEdit.text = s ? s.pseudocode || "" : ""
        edgeEdit.text = boardCanvas.selectedArrow >= 0 ? boardCanvas.arrows[boardCanvas.selectedArrow].label || "" : ""
    }
    /**
     * Writes the inspector's text into the selected shape (or arrow label) as a
     * single undo step, then re-reads the selection.
     */
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
    /**
     * Case-insensitive search across ALL views by shape text, nodeKey and
     * description; shows the first 80 matches in a popup (empty query closes it).
     * @param query text typed in the search box.
     */
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

    // Start-up sequence, deferred one event-loop turn so every child (dialogs,
    // timers, C++ context properties) exists first. Order of preference:
    // 1) reopen the last project (GUI runs only), 2) open the project given on
    // the command line / export request, 3) start an empty untitled project.
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
        // A requested PNG export with no usable project is a hard failure: exit
        // code 1 so scripts notice.
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
    // Autosave: 1.2 s after the last change, only for projects that already
    // have a file (untitled ones would need a Save dialog).
    Timer { id: saveTimer; interval: 1200; onTriggered: if (board.dirty && String(board.documentUrl)) board.saveDocument() }
    // Debounce for informing the sync engine about edits (matches DocumentSync's own 180 ms).
    Timer { id: syncTimer; interval: 180; onTriggered: board.refreshSyncDraft() }
    // Document sync dialog (SyncPanel.qml); opened from the footer's link button.
    Archi.SyncPanel { id: syncPanel; workspace: board }
    // Any shape added, removed or edited is a document change.
    Connections {
        target: board.boardCanvas.shapesModel
        function onDataChanged() { board.changed() }
        function onCountChanged() { board.changed() }
    }
    // Canvas events: `modified` = history-recording edit; selection changes
    // flush typed inspector text first so edits are not lost; viewport changes
    // are saved too (they are stored in the file).
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
    // Keyboard shortcuts: Save, Ctrl+Shift+E export, Open (saves first),
    // Ctrl+R reload, Ctrl+0 fit, Ctrl+F focus the search box.
    Shortcut { sequences: [StandardKey.Save]; onActivated: board.saveDocument() }
    Shortcut { sequence: "Ctrl+Shift+E"; enabled: !pngExporter.busy; onActivated: pngDialog.open() }
    Shortcut { sequences: [StandardKey.Open]; onActivated: if (!board.dirty || board.saveDocument()) openDialog.open() }
    Shortcut { sequence: "Ctrl+R"; onActivated: board.requestReload() }
    Shortcut { sequence: "Ctrl+0"; onActivated: board.fitView() }
    Shortcut { sequence: "Ctrl+F"; onActivated: searchField.forceActiveFocus() }

    // Icon-only toolbar button (same pattern as Main.qml's IconTool).
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

    // Top menu bar (two rows): file/project actions, then view picker and search.
    menuBar: ToolBar {
        implicitHeight: 86
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 5
            spacing: 3
            // Row 1: new/open, background colour, recent-project picker, math dialog,
            // workflow check, save, PNG export.
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
            // Row 2: view picker, new view, node search and the details (inspector) toggle.
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

    // Search results list; clicking jumps to the node's view and centres on it.
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

    // Right-hand details drawer, sized to the area under the toolbars. Docked
    // (non-modal) on windows >= 1100 px wide; otherwise an overlay.
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
                // Header: node key (or "Connection"/"View") and a close button.
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: board.selectedNode ? board.selectedNode.nodeKey || "New node" : board.boardCanvas.selectedArrow >= 0 ? "Connection" : "View"; font.bold: true; Layout.fillWidth: true }
                    BoardTool { glyph: "window-close"; tip: "Close details"; onClicked: inspector.close() }
                }
                // With nothing selected the drawer shows the current view's notes.
                Label {
                    Layout.fillWidth: true
                    visible: !board.selectedNode && board.boardCanvas.selectedArrow < 0
                    text: board.document && board.document.views[board.viewIndex] ? board.document.views[board.viewIndex].notes || "" : ""
                    wrapMode: Text.Wrap
                }
                // Editors for the selected node: operation (title), analysis (description)
                // and pseudocode; the branch field appears for a selected arrow. They stay
                // as typed until Apply (or selection change / save) writes them back.
                Label { text: "Operation"; visible: !!board.selectedNode }
                TextArea { id: titleEdit; objectName: "nodeTitle"; Layout.fillWidth: true; visible: !!board.selectedNode; wrapMode: TextEdit.Wrap; selectByMouse: true }
                Label { text: "Analysis"; visible: !!board.selectedNode }
                TextArea { id: notesEdit; objectName: "nodeNotes"; Layout.fillWidth: true; visible: !!board.selectedNode; wrapMode: TextEdit.Wrap; selectByMouse: true }
                Label { text: "Pseudocode"; visible: !!board.selectedNode }
                TextArea { id: codeEdit; objectName: "nodeCode"; Layout.fillWidth: true; visible: !!board.selectedNode; wrapMode: TextEdit.WrapAnywhere; selectByMouse: true; font.family: "monospace" }
                Label { text: "Branch"; visible: board.boardCanvas.selectedArrow >= 0 }
                TextField { id: edgeEdit; Layout.fillWidth: true; visible: board.boardCanvas.selectedArrow >= 0 }
                // Apply writes the text into the model as one undo step.
                Button { text: "Apply"; visible: !!board.selectedNode || board.boardCanvas.selectedArrow >= 0; onClicked: board.applyDetails() }
                // Shown when the node links to a detailed sub-view (linkView).
                Button {
                    text: "Open flow"
                    visible: !!board.selectedNode && !!board.selectedNode.linkView
                    onClicked: board.goToView(board.selectedNode.linkView)
                }
            }
        }
    }

    // Name prompt, then a file chooser, then createProject().
    Dialog {
        id: newProjectDialog
        title: "New Project"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        TextField { id: projectName; placeholderText: "Project name"; text: "Untitled"; selectByMouse: true }
        onAccepted: newProjectFile.open()
    }

    // Math & Logic dialog: operation, variable and expression go to the C++
    // `mathEngine`; the result can be copied or inserted as a node.
    Dialog {
        id: mathDialog
        objectName: "mathDialog"
        // Fingerprint of the inputs at the time Calculate was pressed; the result
        // is only offered when the inputs still match it (stale results are never inserted).
        property string submittedKey: ""
        // Fingerprint of the inputs right now.
        readonly property string currentKey: JSON.stringify([mathExpression.text, mathOperation.currentText, mathVariable.text])
        // True when a finished, error-free result matches the current inputs.
        readonly property bool hasCurrentResult: submittedKey === currentKey && !mathEngine.busy && !!mathEngine.result && !mathEngine.error
        title: "Math & Logic"
        anchors.centerIn: parent
        width: Math.min(670, board.width - 24)
        height: Math.min(440, board.height - 24)
        modal: true
        standardButtons: Dialog.Close
        // Closing the dialog aborts a running calculation.
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
                    // Operation names must match the keys in src/math_engine.py exactly.
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
    // Workflow check result dialog (text from WorkflowChecks.analyze()).
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
    // File choosers: create, open, save-a-copy, and PNG export. The ones that
    // start in a folder fall back to the Documents folder for an untitled project.
    FileDialog {
        id: newProjectFile
        title: "Create Project"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Archi project (*.json)"]
        defaultSuffix: "archi.json"
        onAccepted: board.createProject(selectedFile, projectName.text)
    }
    Dialog {
        id: newViewDialog
        title: "New View"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        TextField { id: viewName; placeholderText: "View name"; text: "Main"; selectByMouse: true }
        onAccepted: board.addView(viewName.text)
    }

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
    // PNG exporter. The result handler updates the status line and shows an
    // error dialog for interactive runs; in `--export-png` mode (pngExportTarget
    // set) it instead logs and exits the whole app with code 0 or 1.
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
    // Error popup for failed interactive exports.
    MessageDialog {
        id: pngError
        title: "PNG export failed"
    }
    // Confirmation before reloading over unsaved changes.
    Dialog {
        id: reloadDialog
        title: "Discard unsaved changes and reload?"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Discard | Dialog.Cancel
        onDiscarded: board.loadDocument()
    }
    // Close prompt. onClosing first tries to save silently; only if that fails
    // (or there is no file) does the Save/Discard/Cancel dialog appear.
    Dialog {
        id: closeDialog
        title: "Save changes before closing?"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Save | Dialog.Discard | Dialog.Cancel
        onAccepted: if (board.saveDocument()) { board.allowClose = true; board.close() }
        onDiscarded: { board.allowClose = true; board.close() }
    }
    onClosing: close => {
        if (dirty && !allowClose && !saveDocument()) { close.accepted = false; closeDialog.open() }
    }

    // Footer, two rows: sync status (green when current) and the general
    // status line with node count, autosave switch, save-a-copy and reload.
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
                // Reflects typed-but-unapplied edits first, then a pending sync check, then the C++ summary.
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
            // Row 2: status text (full path in tooltip), node count, autosave, copy, reload.
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
