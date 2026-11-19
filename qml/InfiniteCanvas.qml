// ==============================================================================
// Program: InfiniteCanvas.qml
// Programmer: Ethan-da-Tech-Wizard
// Last Modified: November 18, 2026
// Purpose: Core infinite interactive workspace component managing pan, zoom, grid rendering,
//          multi-selection bounding boxes, drag-and-drop shape manipulation, and complete
//          undo/redo state snapshots for all diagram elements.
//
// How it fits: ProjectWorkspace.qml instantiates one InfiniteCanvas per open
// board (id `board`) and drives it through the functions below (undo, redo,
// fitView, createShape, captureState/restoreState ...). PngExporter.qml
// creates a second, hidden instance to render exports. Each shape is drawn by
// a ShapeItem delegate and all arrows by one ArrowLayer, both children of the
// `world` item that pan/zoom transform.
//
// Coordinate systems: "world" units are what is stored in project files
// (px, py, pw, ph, arrow points). "Screen" pixels = (world - viewX/viewY)
// * zoom. Only `world` below applies that transform, so shapes never need to
// know the zoom level.
//
// Data model: shapes live in the ListModel `shapesModel` (one row per shape,
// roles listed in `shapeRoles`); arrows are a plain JS array of
// {fromId, toId, label, optional points/labelX/labelY} in `arrows`.
// `arrowLines` is derived geometry (clipped endpoints, arrowheads) rebuilt by
// rebuildArrowGeometry(); never edit it directly.
//
// Undo/redo: snapshots (captureState) are pushed onto `undoStack` (max 50)
// by commitBefore() only when something actually changed. Gestures that
// change state continuously (drag, resize, typing) call beginChange() at the
// start and endChange() at the end so one gesture = one undo step.
//
// Signals: `modified()` tells the workspace to mark the document dirty;
// `inspectShapeRequested(id)` asks it to open the shape inspector.
//
// Known limits: undo history holds whole-state copies (fine for diagrams of
// hundreds of shapes, not tens of thousands) and is not saved to disk.
// ==============================================================================
import QtQuick
import QtQuick.Controls

Item {
    id: root

    // Viewport: viewX/viewY are the world coordinates of the top-left corner,
    // kept as doubles; zoom is screen pixels per world unit (wheel clamps it to
    // 0.02..50). Changing any of them moves `world` and repaints the dot grid.
    // World coordinate (double precision) at the top-left of the viewport.
    property double viewX: 0
    property double viewY: 0
    property double zoom: 1.0
    // Fill behind everything; also decides whether grid dots are dark or light.
    property color backgroundColor: "#ffffff"
    // Off for PNG export so the picture has no editor dots.
    property bool showGrid: true

    // Exposed so other QML (ProjectWorkspace, PngExporter) can read/append rows.
    property alias shapesModel: shapesModel
    property var arrows: [] // {fromId, toId}
    property var arrowLines: [] // derived render geometry, see rebuildArrowGeometry()

    // Row index (not id) of the shape whose text box is open for editing; -1 = none.
    property int editingIndex: -1
    // Next unused shapeId; ids are never reused within a session, so arrows
    // cannot silently attach to a different shape after delete + create.
    property int nextShapeId: 1
    // Selection: at most one of a shape (by id) or an arrow (by index in
    // `arrows`) is selected; -1 means none.
    property int selectedId: -1
    property int selectedArrow: -1
    // Snapshots for undo/redo. Arrays are replaced, never mutated, so QML
    // bindings on canUndo/canRedo update.
    property var undoStack: []
    property var redoStack: []
    // Snapshot taken at the start of a drag/resize/arrow-edit gesture.
    property var gestureBefore: null
    // Snapshot taken when text editing starts (see onEditingIndexChanged).
    property var textBefore: null
    // True while state is being rebuilt (undo, redo, export setup) so the
    // resulting changes are not recorded as new history and do not emit signals.
    property bool restoring: false
    readonly property bool canUndo: undoStack.length > 0
    readonly property bool canRedo: redoStack.length > 0
    // Per-shape fields persisted in the project file and copied by copyShape().
    // px/py/pw/ph = position and size in world units; the rest are content.
    readonly property var shapeRoles: ["shapeId", "px", "py", "pw", "ph", "text", "shapeColor", "shapeKind",
                                      "nodeKey", "description", "pseudocode", "linkView"]
    // Document changed; the workspace listens to schedule autosave and sync checks.
    signal modified()
    // Raised by a shape's "edit details" action; `id` is its shapeId.
    signal inspectShapeRequested(int id)
    // Clip children to the item bounds so panned-away content never paints over
    // toolbars; focus lets the canvas receive keyboard shortcuts (delete, etc.).
    clip: true
    focus: true

    /**
     * Copies the persistable fields of a shape row into a plain object.
     *
     * Missing roles become "" so every snapshot has the same keys, and the
     * colour is converted to a string because ListModel may hold a color object.
     * @param source A shapesModel row or any object with shape fields.
     * @returns {object} Plain copy, safe to store or JSON-serialise.
     */
    function copyShape(source) {
        var result = {}
        for (const role of shapeRoles)
            result[role] = role === "shapeColor" ? String(source[role]) :
                          source[role] === undefined ? "" : source[role]
        return result
    }

    /**
     * Captures everything undo needs: shapes, arrows, id counter, selection and
     * pan position (zoom is deliberately excluded so undo never changes the
     * zoom level). Arrows are deep-copied via JSON so later edits cannot alias.
     * @returns {{shapes:Array, arrows:Array, nextId:number, selectedId:number, viewX:number, viewY:number}}
     */
    function captureState() {
        var shapes = []
        for (var i = 0; i < shapesModel.count; ++i)
            shapes.push(copyShape(shapesModel.get(i)))
        return {shapes: shapes, arrows: JSON.parse(JSON.stringify(arrows)), nextId: nextShapeId,
                selectedId: selectedId, viewX: viewX, viewY: viewY}
    }

    /**
     * Records `before` as an undo step if the diagram differs from it now.
     *
     * Compares shapes and arrows by value so selecting, panning or an edit that
     * ends up unchanged does not create empty history entries. A new change
     * clears the redo stack (standard linear-history behaviour) and keeps only
     * the last 50 snapshots to bound memory.
     * @param before Snapshot from captureState(), or null (ignored).
     * Emits `modified()` when a step is recorded. Does nothing while `restoring`.
     */
    function commitBefore(before) {
        if (restoring || !before)
            return
        var after = captureState()
        if (JSON.stringify(before.shapes) === JSON.stringify(after.shapes)
                && JSON.stringify(before.arrows) === JSON.stringify(after.arrows))
            return
        undoStack = undoStack.slice(-49).concat([before])
        redoStack = []
        modified()
    }

    /** Starts a multi-event gesture: remembers the state to undo back to. */
    function beginChange() { gestureBefore = captureState() }
    /** Ends the gesture started by beginChange(): records history and refreshes arrow geometry. */
    function endChange() {
        commitBefore(gestureBefore)
        gestureBefore = null
        rebuildArrowGeometry()
    }
    /** Forgets all undo/redo steps (used when a different document is loaded). */
    function resetHistory() { undoStack = []; redoStack = []; gestureBefore = null; textBefore = null }

    /**
     * Replaces the whole canvas with a snapshot (used by undo/redo).
     *
     * `restoring` suppresses history recording during the rebuild; arrow
     * geometry is recomputed because it is derived data. Always ends by
     * emitting `modified()`: undo is itself a change to the saved document.
     * @param state Object shaped like captureState()'s result.
     */
    function restoreState(state) {
        restoring = true
        editingIndex = -1
        shapesModel.clear()
        for (const shape of state.shapes)
            shapesModel.append(shape)
        arrows = JSON.parse(JSON.stringify(state.arrows))
        nextShapeId = state.nextId
        selectedId = state.selectedId
        selectedArrow = -1
        viewX = state.viewX
        viewY = state.viewY
        rebuildArrowGeometry()
        restoring = false
        forceActiveFocus()
        modified()
    }

    /** Steps back one change; the current state goes onto the redo stack first. No-op if nothing to undo. */
    function undo() {
        editingIndex = -1
        if (!canUndo) return
        redoStack = redoStack.concat([captureState()])
        const state = undoStack[undoStack.length - 1]
        undoStack = undoStack.slice(0, -1)
        restoreState(state)
    }
    /** Re-applies the most recently undone change; mirror image of undo(). */
    function redo() {
        editingIndex = -1
        if (!canRedo) return
        undoStack = undoStack.concat([captureState()])
        const state = redoStack[redoStack.length - 1]
        redoStack = redoStack.slice(0, -1)
        restoreState(state)
    }

    /** Selects a shape by id (-1 clears) and gives the canvas keyboard focus so shortcuts work. */
    function selectShape(id) {
        editingIndex = -1
        selectedId = id
        selectedArrow = -1
        forceActiveFocus()
    }
    /**
     * Deletes the selected shape (and every arrow touching it) or the selected arrow.
     * @returns {boolean} true if something was deleted. false when nothing is
     *          selected or a text box is being edited (Delete/Backspace must
     *          then edit text instead of deleting the shape).
     */
    function deleteSelection() {
        if (editingIndex !== -1) return false
        var before = captureState()
        // Removing a shape must also remove its arrows, otherwise they would point
        // at a missing endpoint (the workflow checker reports those as errors).
        if (selectedId !== -1) {
            const id = selectedId
            arrows = arrows.filter(a => a.fromId !== id && a.toId !== id)
            // Iterate backwards because remove(i) shifts later rows down.
            for (var i = shapesModel.count - 1; i >= 0; --i)
                if (shapesModel.get(i).shapeId === id) shapesModel.remove(i)
            selectedId = -1
        } else if (selectedArrow >= 0) {
            arrows = arrows.filter((a, i) => i !== selectedArrow)
            selectedArrow = -1
        } else return false
        rebuildArrowGeometry()
        commitBefore(before)
        return true
    }
    /** Duplicates the selected shape, offset 40 world units down-right, selected. The copy's nodeKey is cleared because keys must stay unique. */
    function duplicateSelection() {
        var source = findShapeById(selectedId)
        if (!source) return
        var before = captureState()
        var copy = copyShape(source)
        copy.shapeId = nextShapeId++
        copy.nodeKey = ""
        copy.px += 40; copy.py += 40
        shapesModel.append(copy)
        selectedId = copy.shapeId
        commitBefore(before)
    }
    /**
     * Zooms and pans so every shape, arrow and label is visible with a 30 px
     * margin. Zoom is clamped to 0.02..1.2 (never magnifies small diagrams past
     * 120 %). No-op on an empty canvas.
     */
    function fitView() {
        if (!shapesModel.count) return
        var left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity
        for (var i = 0; i < shapesModel.count; ++i) {
            var s = shapesModel.get(i)
            left = Math.min(left, s.px); top = Math.min(top, s.py)
            right = Math.max(right, s.px + s.pw); bottom = Math.max(bottom, s.py + s.ph)
        }
        // Include routed arrow points: arrows can leave the shapes' bounding box.
        for (const line of arrowLines) {
            for (const p of line.points) {
                left = Math.min(left, p.x); top = Math.min(top, p.y)
                right = Math.max(right, p.x); bottom = Math.max(bottom, p.y)
            }
            // Label size is estimated (about 4.5 px per character plus padding) because
            // text metrics are not available for every label here.
            if (line.label) {
                const halfLabel = line.label.length * 4.5 + 8
                left = Math.min(left, line.labelX - halfLabel)
                right = Math.max(right, line.labelX + halfLabel)
                top = Math.min(top, line.labelY - 14)
                bottom = Math.max(bottom, line.labelY + 14)
            }
        }
        // Fit by the tighter of the two axes, then centre the box in the viewport.
        zoom = Math.max(0.02, Math.min(1.2, (width - 60) / (right - left), (height - 60) / (bottom - top)))
        viewX = left - (width / zoom - right + left) / 2
        viewY = top - (height / zoom - bottom + top) / 2
    }
    /**
     * World-space rectangle enclosing everything that should appear in an export.
     *
     * Includes shapes (+2 units for their border), routed arrow points and
     * arrowheads (+ stroke width) and measured label boxes. Independent of the
     * current pan and zoom so exports always show the whole diagram.
     * @returns {rect} Empty diagrams return a fixed 576x416 area (the exporter
     *          adds 2x32 px margins, giving a 640x480 image).
     */
    function diagramBounds() {
        if (!shapesModel.count) return Qt.rect(0, 0, 576, 416)
        // Local helper that grows the box to include an x,y,w,h rectangle.
        let left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity
        function include(x, y, w, h) {
            left = Math.min(left, x); top = Math.min(top, y)
            right = Math.max(right, x + w); bottom = Math.max(bottom, y + h)
        }
        for (let i = 0; i < shapesModel.count; ++i) {
            const s = shapesModel.get(i)
            include(s.px - 2, s.py - 2, s.pw + 4, s.ph + 4)
        }
        for (let i = 0; i < arrowLines.length; ++i) {
            const line = arrowLines[i]
            const padding = Math.max(1, line.strokeWidth)
            for (const p of line.points.concat([{x: line.ax1, y: line.ay1}, {x: line.ax2, y: line.ay2}]))
                include(p.x - padding, p.y - padding, padding * 2, padding * 2)
            const label = arrowLayer.labelBounds(i)
            if (label.width > 0) include(label.x - 1, label.y - 1, label.width + 2, label.height + 2)
        }
        return Qt.rect(left, top, right - left, bottom - top)
    }
    /** Selects shape `id` and centres it, zooming so it is about as wide as the view (zoom 0.25..1). */
    function focusShape(id) {
        var s = findShapeById(id)
        if (!s) return
        selectShape(id)
        zoom = Math.min(1, Math.max(0.25, (width - 60) / s.pw))
        viewX = s.px + s.pw / 2 - width / zoom / 2
        viewY = s.py + s.ph / 2 - height / zoom / 2
    }
    // Finish the previous text edit as one history step, then start tracking the
    // next one. While restoring, the editor is being torn down and no history
    // should be written.
    onEditingIndexChanged: {
        if (restoring) { textBefore = null; return }
        commitBefore(textBefore)
        textBefore = editingIndex >= 0 ? captureState() : null
    }
    // Delete and Backspace both delete the selection; Backspace needs its own
    // handler for keyboards/OSes that report it as Key_Backspace or Key_Back.
    Keys.onDeletePressed: event => { event.accepted = deleteSelection() }
    Keys.onBackPressed: event => { event.accepted = deleteSelection() }
    // Backspace deletes only when no text box is open.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Backspace && editingIndex === -1)
            event.accepted = deleteSelection()
    }

    // Defaults for new shapes: screen-pixel size and kind chosen in the
    // toolbar. createShape() divides the size by zoom so a new shape looks the
    // same size on screen whether the user is zoomed in or out.
    property double defaultShapeWidth: 160
    property double defaultShapeHeight: 80
    // One of "rect", "ellipse", "diamond", "terminal", ... (see ShapeItem).
    property string defaultShapeKind: "rect"

    // Live state of the arrow being dragged out of a shape's handle; consumed by
    // the dashed preview line in ArrowLayer. Coordinates are world units.
    property bool arrowDragActive: false
    property int arrowFromId: -1
    property double arrowFromX: 0
    property double arrowFromY: 0
    property double arrowToX: 0
    property double arrowToY: 0

    // Single-precision GPU transforms lose accuracy far from the origin, so when
    // the viewport drifts more than this many world units away, maybeRebase()
    // shifts everything back (see there). 50000 is well before visible jitter.
    readonly property double rebaseThreshold: 50000

    ListModel {
        id: shapesModel
    }

    /**
     * Adds an empty shape centred on a world point and opens its text editor.
     * Called by double-clicking the background. The new shape is one undo step.
     * @param wx,wy World coordinates of the shape's centre.
     */
    function createShape(wx, wy) {
        editingIndex = -1
        var before = captureState()
        var w = defaultShapeWidth / zoom, h = defaultShapeHeight / zoom
        shapesModel.append({
            shapeId: nextShapeId,
            px: wx - w / 2,
            py: wy - h / 2,
            pw: w,
            ph: h,
            text: "",
            shapeColor: "#ffffff",
            shapeKind: defaultShapeKind,
            nodeKey: "", description: "", pseudocode: "", linkView: ""
        })
        selectedId = nextShapeId
        nextShapeId += 1
        commitBefore(before)
        editingIndex = shapesModel.count - 1
    }

    /** Removes all shapes and arrows without recording history (used before loading or sampling). */
    function clearCanvas() {
        editingIndex = -1
        shapesModel.clear()
        arrows = []
        arrowLines = []
        selectedId = -1
        selectedArrow = -1
    }

    /**
     * Replaces the canvas with a demo flowchart centred in the view (every
     * shape kind plus branching arrows) for first-time users. One undo step.
     * Coordinates are offsets from the view centre `cx,cy`; sizes are world units.
     */
    function loadSampleDiagram() {
        var before = captureState()
        restoring = true
        clearCanvas()
        // Fall back to 640x400 when the item has no size yet (called before layout).
        var cx = viewX + (width > 0 ? width / 2 : 640) / zoom
        var cy = viewY + (height > 0 ? height / 2 : 400) / zoom

        var s1 = nextShapeId++; shapesModel.append({ shapeId: s1, px: cx - 80, py: cy - 220, pw: 160, ph: 55, text: "Start", shapeColor: "#e6f4ea", shapeKind: "terminal" })
        var s2 = nextShapeId++; shapesModel.append({ shapeId: s2, px: cx - 90, py: cy - 135, pw: 180, ph: 55, text: "Input: User Query", shapeColor: "#feefc3", shapeKind: "input_output" })
        var s3 = nextShapeId++; shapesModel.append({ shapeId: s3, px: cx - 85, py: cy - 50, pw: 170, ph: 55, text: "Process: Parse Data", shapeColor: "#e8f0fe", shapeKind: "process" })
        var s4 = nextShapeId++; shapesModel.append({ shapeId: s4, px: cx - 90, py: cy + 30, pw: 180, ph: 75, text: "Decision:\nValid?", shapeColor: "#fce8e6", shapeKind: "decision" })
        var s5 = nextShapeId++; shapesModel.append({ shapeId: s5, px: cx - 210, py: cy + 140, pw: 180, ph: 60, text: "Internal Method:\nExecuteLogic()", shapeColor: "#f3e8fd", shapeKind: "internal_method" })
        var s6 = nextShapeId++; shapesModel.append({ shapeId: s6, px: cx + 30, py: cy + 140, pw: 180, ph: 60, text: "External Method:\nFetchAPI()", shapeColor: "#e0f2fe", shapeKind: "external_method" })
        var s7 = nextShapeId++; shapesModel.append({ shapeId: s7, px: cx - 80, py: cy + 240, pw: 160, ph: 55, text: "End", shapeColor: "#e6f4ea", shapeKind: "terminal" })

        addArrow(s1, s2)
        addArrow(s2, s3)
        addArrow(s3, s4)
        addArrow(s4, s5)
        addArrow(s4, s6)
        addArrow(s5, s7)
        addArrow(s6, s7)
        restoring = false
        commitBefore(before)
    }

    /** Returns the shapesModel row with this shapeId, or null. Linear scan; fine for diagram sizes. */
    function findShapeById(id) {
        for (var i = 0; i < shapesModel.count; i++) {
            var it = shapesModel.get(i)
            if (it.shapeId === id)
                return it
        }
        return null
    }

    /**
     * Hit test: id of the first shape containing world point (wx,wy), skipping
     * `excludeId` (used so an arrow dropped on its own source does not connect
     * to itself). Returns -1 if none. Overlaps resolve to the earliest shape.
     */
    function shapeIdAtWorldPoint(wx, wy, excludeId) {
        for (var i = 0; i < shapesModel.count; i++) {
            var it = shapesModel.get(i)
            if (it.shapeId === excludeId)
                continue
            if (wx >= it.px && wx <= it.px + it.pw && wy >= it.py && wy <= it.py + it.ph)
                return it.shapeId
        }
        return -1
    }

    /**
     * Adds an arrow fromId -> toId as one undo step.
     * Ignored for self-loops, missing shapes and duplicates of an existing
     * identical arrow, so the diagram never holds meaningless connections.
     */
    function addArrow(fromId, toId) {
        if (fromId === toId || !findShapeById(fromId) || !findShapeById(toId)
                || arrows.some(a => a.fromId === fromId && a.toId === toId))
            return
        var before = captureState()
        arrows = arrows.concat([{ fromId: fromId, toId: toId, label: "" }])
        rebuildArrowGeometry()
        commitBefore(before)
    }

    /**
     * Point where the ray from a rectangle's centre in direction (dx,dy) leaves
     * the rectangle (half-width hw, half-height hh).
     *
     * The ray reaches an edge when t*|dx| = hw or t*|dy| = hh; the smaller t
     * wins, which is 1 / max(|dx|/hw, |dy|/hh). A zero direction returns the centre.
     */
    function clipToRect(cx, cy, hw, hh, dx, dy) {
        if (dx === 0 && dy === 0)
            return { x: cx, y: cy }
        var t = 1 / Math.max(Math.abs(dx) / hw, Math.abs(dy) / hh)
        return { x: cx + dx * t, y: cy + dy * t }
    }

    /**
     * Recomputes `arrowLines`, the drawable form of `arrows`.
     *
     * For each arrow whose two shapes exist: finds start/end on the shape
     * borders (aimed at the first/last user route point, or at the other shape's
     * centre when there are none), builds the polyline, and computes the two
     * arrowhead corner points ah/ay at +-(PI/7) from the final segment. Label
     * position defaults to the midpoint of the first segment. Call after any
     * change to shapes or arrows.
     */
    function rebuildArrowGeometry() {
        var result = []
        var byId = new Map()
        for (var j = 0; j < shapesModel.count; ++j) {
            var shape = shapesModel.get(j)
            byId.set(shape.shapeId, shape)
        }
        // Skip arrows with a missing endpoint instead of throwing; they are left in
        // `arrows` so the workflow checker can report them.
        for (var i = 0; i < arrows.length; i++) {
            var a = arrows[i]
            var from = byId.get(a.fromId)
            var to = byId.get(a.toId)
            if (!from || !to)
                continue
            var fcx = from.px + from.pw / 2, fcy = from.py + from.ph / 2
            var tcx = to.px + to.pw / 2, tcy = to.py + to.ph / 2
            var dx = tcx - fcx, dy = tcy - fcy
            // Optional user-dragged waypoints between the two shapes.
            var via = a.points || []
            var first = via.length ? via[0] : {x: tcx, y: tcy}
            var last = via.length ? via[via.length - 1] : {x: fcx, y: fcy}
            // Border points aim at the nearest waypoint so routed arrows leave a shape
            // facing their first bend, not the far shape.
            var start = clipToShape(from, first.x - fcx, first.y - fcy)
            var end = clipToShape(to, last.x - tcx, last.y - tcy)
            var points = [start].concat(via).concat([end])
            var prev = points[points.length - 2]
            var ang = Math.atan2(end.y - prev.y, end.x - prev.x)
            // minDim = smallest of the four dimensions; arrowhead length is 25 % of it
            // clamped 3..10, stroke 3 % clamped 0.5..2 (world units).
            var minDim = Math.min(from.pw, from.ph, to.pw, to.ph)
            var ah = Math.max(3, Math.min(minDim * 0.25, 10))
            var awAngle = Math.PI / 7
            var strokeWidth = Math.max(0.5, Math.min(minDim * 0.03, 2))
            result.push({
                edgeIndex: i, points: points, label: a.label || "",
                labelX: a.labelX === undefined ? (start.x + points[1].x) / 2 : a.labelX,
                labelY: a.labelY === undefined ? (start.y + points[1].y) / 2 : a.labelY,
                x1: start.x, y1: start.y, x2: end.x, y2: end.y,
                ax1: end.x - ah * Math.cos(ang - awAngle),
                ay1: end.y - ah * Math.sin(ang - awAngle),
                ax2: end.x - ah * Math.cos(ang + awAngle),
                ay2: end.y - ah * Math.sin(ang + awAngle),
                strokeWidth: strokeWidth
            })
        }
        arrowLines = result
    }

    /**
     * Border point of `shape` in direction (dx,dy) from its centre.
     * Diamonds ("decision"/"diamond") use the diamond equation |x|/hw + |y|/hh = 1
     * so arrows touch the pointed outline; every other kind uses the rectangle.
     */
    function clipToShape(shape, dx, dy) {
        var cx = shape.px + shape.pw / 2, cy = shape.py + shape.ph / 2
        if ((shape.shapeKind === "decision" || shape.shapeKind === "diamond") && (dx || dy)) {
            var t = 1 / (Math.abs(dx) / (shape.pw / 2) + Math.abs(dy) / (shape.ph / 2))
            return {x: cx + dx * t, y: cy + dy * t}
        }
        return clipToRect(cx, cy, shape.pw / 2, shape.ph / 2, dx, dy)
    }

    /**
     * Moves the world origin back to the viewport when it has drifted past
     * `rebaseThreshold`: subtracts the current viewX/viewY from every shape,
     * arrow waypoint and label position, then zeroes the viewport. Nothing
     * visibly moves (shapes shift by exactly what the view shifts) but numbers
     * stay small so the GPU transform keeps precision. Saved files record the
     * rebased coordinates, which is harmless because layout is relative.
     */
    function maybeRebase() {
        if (Math.abs(viewX) <= rebaseThreshold && Math.abs(viewY) <= rebaseThreshold)
            return
        var shiftX = viewX
        var shiftY = viewY
        for (var i = 0; i < shapesModel.count; i++) {
            var it = shapesModel.get(i)
            shapesModel.setProperty(i, "px", it.px - shiftX)
            shapesModel.setProperty(i, "py", it.py - shiftY)
        }
        viewX -= shiftX
        viewY -= shiftY
        arrows = arrows.map(a => {
            var copy = JSON.parse(JSON.stringify(a))
            if (copy.points) copy.points = copy.points.map(p => ({x: p.x - shiftX, y: p.y - shiftY}))
            if (copy.labelX !== undefined) copy.labelX -= shiftX
            if (copy.labelY !== undefined) copy.labelY -= shiftY
            return copy
        })
        rebuildArrowGeometry()
    }

    // Opaque base layer carrying the board colour.
    Rectangle {
        anchors.fill: parent
        color: root.backgroundColor
    }

    // Dot grid: spacing 60 world units, doubled while it would be denser than
    // 16 screen pixels so zooming out never fills the screen with dots. Dot
    // colour picks black or white from the background's luminance (Rec. 601
    // weights 0.299/0.587/0.114) to stay visible on dark boards.
    Canvas {
        id: gridCanvas
        visible: root.showGrid
        anchors.fill: parent
        property double spacing: 60
        property color dotColor: {
            var c = root.backgroundColor
            var lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
            return lum > 0.5 ? Qt.rgba(0, 0, 0, 0.16) : Qt.rgba(1, 1, 1, 0.18)
        }

        function repaintGrid() { requestPaint() }

        // offset = where the first dot lands on screen: the negated view origin
        // modulo the step, made non-negative, so dots appear to belong to the world.
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var step = spacing * root.zoom
            while (step < 16) step *= 2
            var offsetX = (-root.viewX * root.zoom) % step
            var offsetY = (-root.viewY * root.zoom) % step
            if (offsetX < 0) offsetX += step
            if (offsetY < 0) offsetY += step
            ctx.fillStyle = dotColor
            for (var x = offsetX; x < width; x += step) {
                for (var y = offsetY; y < height; y += step) {
                    ctx.beginPath()
                    ctx.arc(x, y, 1.5, 0, Math.PI * 2)
                    ctx.fill()
                }
            }
        }

        // Repaint the dots whenever anything that affects them changes.
        Connections {
            target: root
            function onViewXChanged() { gridCanvas.repaintGrid() }
            function onViewYChanged() { gridCanvas.repaintGrid() }
            function onZoomChanged() { gridCanvas.repaintGrid() }
            function onBackgroundColorChanged() { gridCanvas.repaintGrid() }
        }
    }

    // Background interaction: left-drag pans, click clears selection and any
    // open text box, double-click creates a shape, wheel zooms about the cursor.
    MouseArea {
        id: panArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        property real lastX: 0
        property real lastY: 0

        onPressed: (mouse) => {
            lastX = mouse.x
            lastY = mouse.y
        }
        // Pan: moving the cursor right moves the world left, hence the minus signs.
        onPositionChanged: (mouse) => {
            if (pressed) {
                var dx = mouse.x - lastX
                var dy = mouse.y - lastY
                root.viewX -= dx / root.zoom
                root.viewY -= dy / root.zoom
                lastX = mouse.x
                lastY = mouse.y
                root.maybeRebase()
            }
        }
        // Plain click on empty space: deselect everything and refocus for shortcuts.
        onClicked: {
            root.editingIndex = -1
            root.selectedId = -1
            root.selectedArrow = -1
            root.forceActiveFocus()
        }
        onDoubleClicked: (mouse) => {
            var wx = root.viewX + mouse.x / root.zoom
            var wy = root.viewY + mouse.y / root.zoom
            root.createShape(wx, wy)
        }
        // Zoom: exponential in wheel delta (1.0015^-delta) so equal wheel turns give
        // equal zoom ratios; clamped to 0.02..50. The world point under the cursor
        // (wx,wy) is held fixed by re-solving viewX/viewY after the zoom changes.
        onWheel: (wheel) => {
            var oldZoom = root.zoom
            var factor = Math.pow(1.0015, -wheel.angleDelta.y)
            var newZoom = Math.max(0.02, Math.min(50, oldZoom * factor))
            var mx = wheel.x
            var my = wheel.y
            var wx = root.viewX + mx / oldZoom
            var wy = root.viewY + my / oldZoom
            root.zoom = newZoom
            root.viewX = wx - mx / newZoom
            root.viewY = wy - my / newZoom
            root.maybeRebase()
        }
    }

    // The transformed layer: translate by -view*zoom and scale by zoom (from the
    // top-left corner), so children use plain world coordinates.
    Item {
        id: world
        x: -root.viewX * root.zoom
        y: -root.viewY * root.zoom
        scale: root.zoom
        transformOrigin: Item.TopLeft

        // All arrows are drawn below shapes (declaration order = paint order).
        ArrowLayer {
            id: arrowLayer
            lines: root.arrowLines
            selectedIndex: root.selectedArrow
            onSelected: index => {
                root.selectShape(-1)
                root.selectedArrow = index
            }
            // Dashed line shown while dragging a new arrow from a shape handle; null hides it.
            previewLine: root.arrowDragActive
                ? { x1: root.arrowFromX, y1: root.arrowFromY, x2: root.arrowToX, y2: root.arrowToY }
                : null
        }

        // One ShapeItem per shapesModel row; it reads its own row via model roles
        // and uses `canvasRoot` / `worldItem` to talk back to this canvas.
        Repeater {
            model: root.shapesModel
            delegate: ShapeItem {
                canvasRoot: root
                worldItem: world
            }
        }
    }

    // Middle-button pan. A separate overlay at z:100 so it sits above shapes and
    // text editors and swallows the middle click: on Linux that button pastes
    // the primary selection into any TextEdit under the cursor.
    MouseArea {
        objectName: "middlePan"
        anchors.fill: parent
        z: 100
        acceptedButtons: Qt.MiddleButton
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor
        property real lastX: 0
        property real lastY: 0
        onPressed: mouse => {
            root.editingIndex = -1
            root.forceActiveFocus()
            lastX = mouse.x; lastY = mouse.y
        }
        onPositionChanged: mouse => {
            if (!pressed) return
            root.viewX -= (mouse.x - lastX) / root.zoom
            root.viewY -= (mouse.y - lastY) / root.zoom
            lastX = mouse.x; lastY = mouse.y
            root.maybeRebase()
        }
    }
}
