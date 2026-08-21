import QtQuick
import QtQuick.Shapes

Item {
    id: shapeRoot

    required property int index
    required property int shapeId
    required property double px
    required property double py
    required property double pw
    required property double ph
    required property string text
    required property color shapeColor
    required property string shapeKind // "rect" | "ellipse" | "diamond"
    required property var canvasRoot
    required property var worldItem

    // Every visual detail below (text, border, handles) is sized relative to
    // the shape's own world-space dimensions rather than a fixed constant.
    // Shapes can end up anywhere from a few world-units to thousands wide
    // (creation size is divided by zoom to stay screen-constant, see
    // InfiniteCanvas.createShape), so a fixed-size handle or font would look
    // right only at the zoom level it was tuned for and grotesquely
    // oversized or invisible at any other.
    readonly property double minDim: Math.min(pw, ph)
    readonly property double borderW: Math.max(0.5, Math.min(minDim * 0.02, 2)) * (canvasRoot.editingIndex === index ? 1.5 : 1)
    readonly property color borderColor: canvasRoot.editingIndex === index ? "#4a90d9" : "#555555"

    x: px
    y: py
    width: pw
    height: ph

    // The body swaps per shape type; everything else (text, drag, handles)
    // is identical regardless of which one is picked.
    Loader {
        anchors.fill: parent
        sourceComponent: shapeRoot.shapeKind === "ellipse" ? ellipseVisual
            : shapeRoot.shapeKind === "diamond" ? diamondVisual
            : rectVisual
    }

    Component {
        id: rectVisual
        Rectangle {
            anchors.fill: parent
            color: shapeRoot.shapeColor
            radius: Math.min(6, shapeRoot.minDim * 0.08)
            border.width: shapeRoot.borderW
            border.color: shapeRoot.borderColor
        }
    }

    Component {
        id: ellipseVisual
        Shape {
            id: ellipseShape
            anchors.fill: parent
            ShapePath {
                fillColor: shapeRoot.shapeColor
                strokeColor: shapeRoot.borderColor
                strokeWidth: shapeRoot.borderW
                PathAngleArc {
                    centerX: ellipseShape.width / 2
                    centerY: ellipseShape.height / 2
                    radiusX: ellipseShape.width / 2
                    radiusY: ellipseShape.height / 2
                    startAngle: 0
                    sweepAngle: 360
                }
            }
        }
    }

    Component {
        id: diamondVisual
        Shape {
            id: diamondShape
            anchors.fill: parent
            ShapePath {
                fillColor: shapeRoot.shapeColor
                strokeColor: shapeRoot.borderColor
                strokeWidth: shapeRoot.borderW
                startX: diamondShape.width / 2
                startY: 0
                PathLine { x: diamondShape.width; y: diamondShape.height / 2 }
                PathLine { x: diamondShape.width / 2; y: diamondShape.height }
                PathLine { x: 0; y: diamondShape.height / 2 }
                PathLine { x: diamondShape.width / 2; y: 0 }
            }
        }
    }

    TextEdit {
        id: textEdit
        anchors.fill: parent
        anchors.margins: Math.max(2, shapeRoot.minDim * 0.08)
        text: shapeRoot.text
        wrapMode: TextEdit.Wrap
        horizontalAlignment: TextEdit.AlignHCenter
        verticalAlignment: TextEdit.AlignVCenter
        font.pixelSize: Math.max(4, Math.min(shapeRoot.minDim * 0.22, 32))
        selectByMouse: true
        focus: canvasRoot.editingIndex === shapeRoot.index
        onTextChanged: canvasRoot.shapesModel.setProperty(shapeRoot.index, "text", text)
        Keys.onEscapePressed: canvasRoot.editingIndex = -1
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: canvasRoot.editingIndex !== shapeRoot.index
        cursorShape: Qt.SizeAllCursor
        drag.target: shapeRoot
        drag.axis: Drag.XAndYAxis

        onDoubleClicked: {
            canvasRoot.editingIndex = shapeRoot.index
            textEdit.forceActiveFocus()
            textEdit.selectAll()
        }
        onReleased: {
            canvasRoot.shapesModel.setProperty(shapeRoot.index, "px", shapeRoot.x)
            canvasRoot.shapesModel.setProperty(shapeRoot.index, "py", shapeRoot.y)
            canvasRoot.rebuildArrowGeometry()
        }
    }

    // Handle for dragging out a new arrow to another shape.
    Rectangle {
        id: handle
        width: Math.max(6, Math.min(shapeRoot.minDim * 0.16, 16))
        height: width
        radius: width / 2
        color: "#4a90d9"
        border.color: "#ffffff"
        border.width: Math.max(0.5, width * 0.15)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: -width / 2
        visible: !dragArea.drag.active

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            onPressed: {
                canvasRoot.arrowDragActive = true
                canvasRoot.arrowFromId = shapeRoot.shapeId
                var c = mapToItem(shapeRoot.worldItem, width / 2, height / 2)
                canvasRoot.arrowFromX = c.x
                canvasRoot.arrowFromY = c.y
                canvasRoot.arrowToX = c.x
                canvasRoot.arrowToY = c.y
            }
            onPositionChanged: (mouse) => {
                if (canvasRoot.arrowDragActive) {
                    var p = mapToItem(shapeRoot.worldItem, mouse.x, mouse.y)
                    canvasRoot.arrowToX = p.x
                    canvasRoot.arrowToY = p.y
                }
            }
            onReleased: (mouse) => {
                var p = mapToItem(shapeRoot.worldItem, mouse.x, mouse.y)
                var targetId = canvasRoot.shapeIdAtWorldPoint(p.x, p.y, shapeRoot.shapeId)
                if (targetId !== -1) {
                    canvasRoot.addArrow(canvasRoot.arrowFromId, targetId)
                }
                canvasRoot.arrowDragActive = false
            }
        }
    }

    // Handle for resizing the shape from its bottom-right corner.
    Rectangle {
        id: resizeHandle
        width: Math.max(6, Math.min(shapeRoot.minDim * 0.14, 14))
        height: width
        color: "#888888"
        border.color: "#ffffff"
        border.width: Math.max(0.5, width * 0.1)
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -width / 3
        anchors.bottomMargin: -width / 3
        visible: !dragArea.drag.active
        z: 2

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.SizeFDiagCursor
            property double startW: 0
            property double startH: 0
            property double pressWorldX: 0
            property double pressWorldY: 0

            onPressed: (mouse) => {
                startW = shapeRoot.pw
                startH = shapeRoot.ph
                var p = mapToItem(shapeRoot.worldItem, mouse.x, mouse.y)
                pressWorldX = p.x
                pressWorldY = p.y
            }
            onPositionChanged: (mouse) => {
                if (pressed) {
                    var p = mapToItem(shapeRoot.worldItem, mouse.x, mouse.y)
                    var newW = Math.max(40, startW + (p.x - pressWorldX))
                    var newH = Math.max(30, startH + (p.y - pressWorldY))
                    canvasRoot.shapesModel.setProperty(shapeRoot.index, "pw", newW)
                    canvasRoot.shapesModel.setProperty(shapeRoot.index, "ph", newH)
                }
            }
            onReleased: canvasRoot.rebuildArrowGeometry()
        }
    }
}
