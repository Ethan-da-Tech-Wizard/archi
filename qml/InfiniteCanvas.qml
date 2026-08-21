import QtQuick

Item {
    id: root

    // World coordinate (double precision) at the top-left of the viewport.
    property double viewX: 0
    property double viewY: 0
    property double zoom: 1.0
    property color backgroundColor: "#ffffff"

    property alias shapesModel: shapesModel
    property var arrows: [] // {fromId, toId}
    property var arrowLines: [] // derived render geometry, see rebuildArrowGeometry()

    property int editingIndex: -1
    property int nextShapeId: 1

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
        var w = defaultShapeWidth / zoom, h = defaultShapeHeight / zoom
        shapesModel.append({
            shapeId: nextShapeId,
            px: wx - w / 2,
            py: wy - h / 2,
            pw: w,
            ph: h,
            text: "",
            shapeColor: "#ffffff",
            shapeKind: defaultShapeKind
        })
        editingIndex = shapesModel.count - 1
        nextShapeId += 1
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
        if (fromId === toId || fromId === -1 || toId === -1)
            return
        arrows.push({ fromId: fromId, toId: toId })
        rebuildArrowGeometry()
    }

    function clipToRect(cx, cy, hw, hh, dx, dy) {
        if (dx === 0 && dy === 0)
            return { x: cx, y: cy }
        var t = 1 / Math.max(Math.abs(dx) / hw, Math.abs(dy) / hh)
        return { x: cx + dx * t, y: cy + dy * t }
    }

    function rebuildArrowGeometry() {
        var result = []
        for (var i = 0; i < arrows.length; i++) {
            var a = arrows[i]
            var from = findShapeById(a.fromId)
            var to = findShapeById(a.toId)
            if (!from || !to)
                continue
            var fcx = from.px + from.pw / 2, fcy = from.py + from.ph / 2
            var tcx = to.px + to.pw / 2, tcy = to.py + to.ph / 2
            var dx = tcx - fcx, dy = tcy - fcy
            var start = clipToRect(fcx, fcy, from.pw / 2, from.ph / 2, dx, dy)
            var end = clipToRect(tcx, tcy, to.pw / 2, to.ph / 2, -dx, -dy)
            var ang = Math.atan2(end.y - start.y, end.x - start.x)
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
        onClicked: root.editingIndex = -1
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
}
