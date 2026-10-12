import QtQuick
import QtQuick.Shapes
import QtQuick.Controls

Item {
    id: shapeRoot
    objectName: "shape-" + shapeId
    readonly property alias nodeMenu: contextMenu

    required property int index
    required property int shapeId
    required property double px
    required property double py
    required property double pw
    required property double ph
    required property string text
    required property color shapeColor
    required property string shapeKind // "terminal"|"process"|"input_output"|"decision"|"internal_method"|"external_method"
    required property var canvasRoot
    required property var worldItem

    readonly property double minDim: Math.min(pw, ph)
    readonly property double borderW: Math.max(0.5, Math.min(minDim * 0.02, 2)) * (canvasRoot.editingIndex === index ? 1.5 : 1)
    readonly property color borderColor: canvasRoot.editingIndex === index || canvasRoot.selectedId === shapeId ? "#2876bd" : "#555555"
    readonly property real textInsetX: pw * ((shapeKind === "decision" || shapeKind === "diamond") ? 0.25 :
        (shapeKind === "external_method" || shapeKind === "internal_method") ? 0.23 : 0.1)
    readonly property real textInsetTop: (shapeKind === "decision" || shapeKind === "diamond") ? ph * 0.23 :
        shapeKind === "internal_method" ? ph * 0.3 : 8

    x: px
    y: py
    width: pw
    height: ph

    // The body swaps per shape type; everything else (text, drag, handles)
    // is identical regardless of which one is picked.
    Loader {
        anchors.fill: parent
        sourceComponent: (shapeRoot.shapeKind === "terminal" || shapeRoot.shapeKind === "ellipse") ? terminalVisual
            : (shapeRoot.shapeKind === "decision" || shapeRoot.shapeKind === "diamond") ? diamondVisual
            : (shapeRoot.shapeKind === "input_output" || shapeRoot.shapeKind === "io") ? ioVisual
            : shapeRoot.shapeKind === "internal_method" ? internalMethodVisual
            : shapeRoot.shapeKind === "external_method" ? externalMethodVisual
            : rectVisual
    }

    // Process / Rectangle
    Component {
        id: rectVisual
        Rectangle {
            anchors.fill: parent
            color: shapeRoot.shapeColor
            radius: Math.min(4, shapeRoot.minDim * 0.06)
            border.width: shapeRoot.borderW
            border.color: shapeRoot.borderColor
        }
    }

    // Terminal (Elongated Oval / Stadium shape)
    Component {
        id: terminalVisual
        Rectangle {
            anchors.fill: parent
            color: shapeRoot.shapeColor
            radius: Math.min(shapeRoot.pw, shapeRoot.ph) / 2
            border.width: shapeRoot.borderW
            border.color: shapeRoot.borderColor
        }
    }

    // Decision (Diamond)
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

    // Input / Output (Parallelogram)
    Component {
        id: ioVisual
        Shape {
            id: ioShape
            anchors.fill: parent
            ShapePath {
                fillColor: shapeRoot.shapeColor
                strokeColor: shapeRoot.borderColor
                strokeWidth: shapeRoot.borderW
                startX: ioShape.width * 0.2
                startY: 0
                PathLine { x: ioShape.width; y: 0 }
                PathLine { x: ioShape.width * 0.8; y: ioShape.height }
                PathLine { x: 0; y: ioShape.height }
                PathLine { x: ioShape.width * 0.2; y: 0 }
            }
        }
    }

    // Internal Method (Rectangle with horizontal line at top & vertical line on left)
    Component {
        id: internalMethodVisual
        Item {
            anchors.fill: parent
            Rectangle {
                anchors.fill: parent
                color: shapeRoot.shapeColor
                radius: Math.min(2, shapeRoot.minDim * 0.04)
                border.width: shapeRoot.borderW
                border.color: shapeRoot.borderColor
            }
            Rectangle {
                x: 0
                y: parent.height * 0.25
                width: parent.width
                height: shapeRoot.borderW
                color: shapeRoot.borderColor
            }
            Rectangle {
                x: parent.width * 0.2
                y: 0
                width: shapeRoot.borderW
                height: parent.height
                color: shapeRoot.borderColor
            }
        }
    }

    // External Method (Rectangle with vertical lines on both left and right side)
    Component {
        id: externalMethodVisual
        Item {
            anchors.fill: parent
            Rectangle {
                anchors.fill: parent
                color: shapeRoot.shapeColor
                radius: Math.min(2, shapeRoot.minDim * 0.04)
                border.width: shapeRoot.borderW
                border.color: shapeRoot.borderColor
            }
            Rectangle {
                x: parent.width * 0.18
                y: 0
                width: shapeRoot.borderW
                height: parent.height
                color: shapeRoot.borderColor
            }
            Rectangle {
                x: parent.width * 0.82 - shapeRoot.borderW
                y: 0
                width: shapeRoot.borderW
                height: parent.height
                color: shapeRoot.borderColor
            }
        }
    }

    Text {
        objectName: "shapeLabel-" + shapeRoot.shapeId
        anchors.fill: parent
        anchors.leftMargin: shapeRoot.textInsetX
        anchors.rightMargin: anchors.leftMargin
        anchors.topMargin: shapeRoot.textInsetTop
        anchors.bottomMargin: shapeRoot.shapeKind === "internal_method" ? 8 : anchors.topMargin
        visible: canvasRoot.editingIndex !== shapeRoot.index
        text: shapeRoot.text
        textFormat: Text.PlainText
        color: "#20262d"
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: Math.max(10, Math.min(shapeRoot.minDim * 0.24, 23))
        minimumPixelSize: 10
        fontSizeMode: Text.Fit
        elide: Text.ElideRight
        clip: true
    }

    TextEdit {
        id: textEdit
        objectName: "shapeEditor-" + shapeRoot.shapeId
        anchors.fill: parent
        anchors.margins: Math.max(4, shapeRoot.minDim * 0.1)
        anchors.leftMargin: shapeRoot.textInsetX
        anchors.rightMargin: shapeRoot.textInsetX
        anchors.topMargin: shapeRoot.textInsetTop
        text: shapeRoot.text
        textFormat: TextEdit.PlainText
        color: "#20262d"
        visible: canvasRoot.editingIndex === shapeRoot.index
        clip: true
        wrapMode: TextEdit.Wrap
        horizontalAlignment: TextEdit.AlignHCenter
        verticalAlignment: TextEdit.AlignVCenter
        font.pixelSize: Math.max(4, Math.min(shapeRoot.minDim * 0.22, 32))
        selectByMouse: true
        focus: canvasRoot.editingIndex === shapeRoot.index
        onTextChanged: {
            if (activeFocus && canvasRoot.editingIndex === shapeRoot.index)
                canvasRoot.shapesModel.setProperty(shapeRoot.index, "text", text)
        }
        onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
        Keys.onEscapePressed: { canvasRoot.editingIndex = -1; canvasRoot.forceActiveFocus() }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: canvasRoot.editingIndex !== shapeRoot.index
        cursorShape: Qt.SizeAllCursor
        drag.target: shapeRoot
        drag.axis: Drag.XAndYAxis
        acceptedButtons: Qt.LeftButton
        onPressed: mouse => {
            canvasRoot.selectShape(shapeRoot.shapeId)
            canvasRoot.beginChange()
        }

        onDoubleClicked: {
            canvasRoot.editingIndex = shapeRoot.index
            textEdit.forceActiveFocus()
            textEdit.selectAll()
        }
        onReleased: {
            canvasRoot.shapesModel.setProperty(shapeRoot.index, "px", shapeRoot.x)
            canvasRoot.shapesModel.setProperty(shapeRoot.index, "py", shapeRoot.y)
            canvasRoot.endChange()
        }
    }

    Menu {
        id: contextMenu
        objectName: "shapeMenu-" + shapeRoot.shapeId
        popupType: Popup.Item
        MenuItem { objectName: "editNode-" + shapeRoot.shapeId; text: "Edit text"; onTriggered: canvasRoot.editingIndex = shapeRoot.index }
        MenuItem { text: "Details"; onTriggered: canvasRoot.inspectShapeRequested(shapeRoot.shapeId) }
        MenuItem { text: "Duplicate"; onTriggered: canvasRoot.duplicateSelection() }
        MenuSeparator {}
        MenuItem { objectName: "deleteNode-" + shapeRoot.shapeId; text: "Delete"; onTriggered: canvasRoot.deleteSelection() }
    }

    MouseArea {
        anchors.fill: parent
        z: 4
        acceptedButtons: Qt.RightButton
        onClicked: mouse => {
            canvasRoot.selectShape(shapeRoot.shapeId)
            contextMenu.popup(mouse.x, mouse.y)
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
        visible: !dragArea.drag.active && canvasRoot.selectedId === shapeRoot.shapeId

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
        visible: !dragArea.drag.active && canvasRoot.selectedId === shapeRoot.shapeId
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
                canvasRoot.beginChange()
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
            onReleased: canvasRoot.endChange()
        }
    }
}
