import QtQuick
import QtQuick.Controls

Item {
    id: root

    // World coordinate (double precision) at the top-left of the viewport.
    property double viewX: 0
    property double viewY: 0
    property double zoom: 1.0
    property color backgroundColor: "#ffffff"
    property bool showGrid: true

    property alias shapesModel: shapesModel
    property var arrows: [] // {fromId, toId}
    property var arrowLines: [] // derived render geometry, see rebuildArrowGeometry()

    property int editingIndex: -1
    property int nextShapeId: 1
    property int selectedId: -1
    property int selectedArrow: -1
    property var undoStack: []
    property var redoStack: []
    property var gestureBefore: null
    property var textBefore: null
    property bool restoring: false
    readonly property bool canUndo: undoStack.length > 0
    readonly property bool canRedo: redoStack.length > 0
    readonly property var shapeRoles: ["shapeId", "px", "py", "pw", "ph", "text", "shapeColor", "shapeKind",
                                      "nodeKey", "description", "pseudocode", "linkView"]
    signal modified()
    signal inspectShapeRequested(int id)
    clip: true
    focus: true

    function copyShape(source) {
        var result = {}
        for (const role of shapeRoles)
            result[role] = role === "shapeColor" ? String(source[role]) :
                          source[role] === undefined ? "" : source[role]
        return result
    }

    function captureState() {
        var shapes = []
        for (var i = 0; i < shapesModel.count; ++i)
            shapes.push(copyShape(shapesModel.get(i)))
        return {shapes: shapes, arrows: JSON.parse(JSON.stringify(arrows)), nextId: nextShapeId,
                selectedId: selectedId, viewX: viewX, viewY: viewY}
    }

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

    function beginChange() { gestureBefore = captureState() }
    function endChange() {
        commitBefore(gestureBefore)
        gestureBefore = null
        rebuildArrowGeometry()
    }
    function resetHistory() { undoStack = []; redoStack = []; gestureBefore = null; textBefore = null }

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

    function undo() {
        editingIndex = -1
        if (!canUndo) return
        redoStack = redoStack.concat([captureState()])
        const state = undoStack[undoStack.length - 1]
        undoStack = undoStack.slice(0, -1)
        restoreState(state)
    }
    function redo() {
        editingIndex = -1
        if (!canRedo) return
        undoStack = undoStack.concat([captureState()])
        const state = redoStack[redoStack.length - 1]
        redoStack = redoStack.slice(0, -1)
        restoreState(state)
    }

    function selectShape(id) {
        editingIndex = -1
        selectedId = id
        selectedArrow = -1
        forceActiveFocus()
    }
    function deleteSelection() {
        if (editingIndex !== -1) return false
        var before = captureState()
        if (selectedId !== -1) {
            const id = selectedId
            arrows = arrows.filter(a => a.fromId !== id && a.toId !== id)
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
    function fitView() {
        if (!shapesModel.count) return
        var left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity
        for (var i = 0; i < shapesModel.count; ++i) {
            var s = shapesModel.get(i)
            left = Math.min(left, s.px); top = Math.min(top, s.py)
            right = Math.max(right, s.px + s.pw); bottom = Math.max(bottom, s.py + s.ph)
        }
        for (const line of arrowLines) {
            for (const p of line.points) {
                left = Math.min(left, p.x); top = Math.min(top, p.y)
                right = Math.max(right, p.x); bottom = Math.max(bottom, p.y)
            }
            if (line.label) {
                const halfLabel = line.label.length * 4.5 + 8
                left = Math.min(left, line.labelX - halfLabel)
                right = Math.max(right, line.labelX + halfLabel)
                top = Math.min(top, line.labelY - 14)
                bottom = Math.max(bottom, line.labelY + 14)
            }
        }
        zoom = Math.max(0.02, Math.min(1.2, (width - 60) / (right - left), (height - 60) / (bottom - top)))
        viewX = left - (width / zoom - right + left) / 2
        viewY = top - (height / zoom - bottom + top) / 2
    }
    // Include routed connections, arrowheads and the rendered label sizes.
    // Export uses world bounds, independent of the editor's pan and zoom.
    function diagramBounds() {
        if (!shapesModel.count) return Qt.rect(0, 0, 576, 416)
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
    function focusShape(id) {
        var s = findShapeById(id)
        if (!s) return
        selectShape(id)
        zoom = Math.min(1, Math.max(0.25, (width - 60) / s.pw))
        viewX = s.px + s.pw / 2 - width / zoom / 2
        viewY = s.py + s.ph / 2 - height / zoom / 2
    }
    onEditingIndexChanged: {
        if (restoring) { textBefore = null; return }
        commitBefore(textBefore)
        textBefore = editingIndex >= 0 ? captureState() : null
    }
    Keys.onDeletePressed: event => { event.accepted = deleteSelection() }
    Keys.onBackPressed: event => { event.accepted = deleteSelection() }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Backspace && editingIndex === -1)
            event.accepted = deleteSelection()
    }

    // Size, in *screen pixels at the current zoom*, used for the next shape
    // created via double-click; the toolbar's size picker writes to these.
    // createShape() converts this to world units by dividing by zoom, so a
    // shape always looks the same on-screen size regardless of how zoomed
    // in/out you are when you place it.
    property double defaultShapeWidth: 160
    property double defaultShapeHeight: 80
    // "rect" | "ellipse" | "diamond" — the toolbar's shape-type picker writes here.
    property string defaultShapeKind: "rect"

    // State for an in-progress arrow drag (handle -> target shape).
    property bool arrowDragActive: false
    property int arrowFromId: -1
    property double arrowFromX: 0
    property double arrowFromY: 0
    property double arrowToX: 0
    property double arrowToY: 0

    // Beyond this distance from the origin, floating point precision in the
    // GPU-side (single precision) scene graph transform starts to degrade.
    // Rebase the world origin back under the viewport so rendering always
    // happens near (0,0), while viewX/viewY (double) track the true offset.
    readonly property double rebaseThreshold: 50000

    ListModel {
        id: shapesModel
    }

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

    function clearCanvas() {
        editingIndex = -1
        shapesModel.clear()
        arrows = []
        arrowLines = []
        selectedId = -1
        selectedArrow = -1
    }

    function loadSampleDiagram() {
        var before = captureState()
        restoring = true
        clearCanvas()
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

    function findShapeById(id) {
        for (var i = 0; i < shapesModel.count; i++) {
            var it = shapesModel.get(i)
            if (it.shapeId === id)
                return it
        }
        return null
    }

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

    function addArrow(fromId, toId) {
        if (fromId === toId || !findShapeById(fromId) || !findShapeById(toId)
                || arrows.some(a => a.fromId === fromId && a.toId === toId))
            return
        var before = captureState()
        arrows = arrows.concat([{ fromId: fromId, toId: toId, label: "" }])
        rebuildArrowGeometry()
        commitBefore(before)
    }

    function clipToRect(cx, cy, hw, hh, dx, dy) {
        if (dx === 0 && dy === 0)
            return { x: cx, y: cy }
        var t = 1 / Math.max(Math.abs(dx) / hw, Math.abs(dy) / hh)
        return { x: cx + dx * t, y: cy + dy * t }
    }

    function rebuildArrowGeometry() {
        var result = []
        var byId = new Map()
        for (var j = 0; j < shapesModel.count; ++j) {
            var shape = shapesModel.get(j)
            byId.set(shape.shapeId, shape)
        }
        for (var i = 0; i < arrows.length; i++) {
            var a = arrows[i]
            var from = byId.get(a.fromId)
            var to = byId.get(a.toId)
            if (!from || !to)
                continue
            var fcx = from.px + from.pw / 2, fcy = from.py + from.ph / 2
            var tcx = to.px + to.pw / 2, tcy = to.py + to.ph / 2
            var dx = tcx - fcx, dy = tcy - fcy
            var via = a.points || []
            var first = via.length ? via[0] : {x: tcx, y: tcy}
            var last = via.length ? via[via.length - 1] : {x: fcx, y: fcy}
            var start = clipToShape(from, first.x - fcx, first.y - fcy)
            var end = clipToShape(to, last.x - tcx, last.y - tcy)
            var points = [start].concat(via).concat([end])
            var prev = points[points.length - 2]
            var ang = Math.atan2(end.y - prev.y, end.x - prev.x)
            // Scale the arrowhead and stroke to the connected shapes' own
            // size (clamped to a sane range) instead of a fixed world-unit
            // constant, so a shape created tiny (high zoom) or huge (low
            // zoom) always gets a proportionate arrow, never one that dwarfs
            // or vanishes relative to it.
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

    function clipToShape(shape, dx, dy) {
        var cx = shape.px + shape.pw / 2, cy = shape.py + shape.ph / 2
        if ((shape.shapeKind === "decision" || shape.shapeKind === "diamond") && (dx || dy)) {
            var t = 1 / (Math.abs(dx) / (shape.pw / 2) + Math.abs(dy) / (shape.ph / 2))
            return {x: cx + dx * t, y: cy + dy * t}
        }
        return clipToRect(cx, cy, shape.pw / 2, shape.ph / 2, dx, dy)
    }

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

    Rectangle {
        anchors.fill: parent
        color: root.backgroundColor
    }

    // Dot grid drawn in screen space each repaint (wrapped via modulo), so it
    // reads as infinite without storing any geometry, and gives the user a
    // visual reference to actually see panning/zooming happen.
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

        Connections {
            target: root
            function onViewXChanged() { gridCanvas.repaintGrid() }
            function onViewYChanged() { gridCanvas.repaintGrid() }
            function onZoomChanged() { gridCanvas.repaintGrid() }
            function onBackgroundColorChanged() { gridCanvas.repaintGrid() }
        }
    }

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

    Item {
        id: world
        x: -root.viewX * root.zoom
        y: -root.viewY * root.zoom
        scale: root.zoom
        transformOrigin: Item.TopLeft

        ArrowLayer {
            id: arrowLayer
            lines: root.arrowLines
            selectedIndex: root.selectedArrow
            onSelected: index => {
                root.selectShape(-1)
                root.selectedArrow = index
            }
            previewLine: root.arrowDragActive
                ? { x1: root.arrowFromX, y1: root.arrowFromY, x2: root.arrowToX, y2: root.arrowToY }
                : null
        }

        Repeater {
            model: root.shapesModel
            delegate: ShapeItem {
                canvasRoot: root
                worldItem: world
            }
        }
    }

    // Consume the primary-selection paste button before any TextEdit sees it.
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
