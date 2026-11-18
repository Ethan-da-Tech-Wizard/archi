// Program: archi - ShapeItem.qml
// Programmer: Ethan-da-Tech-Wizard (written with Claude, an AI assistant)
// Last Modified: 2026-11-18
// Purpose: QML delegate that draws and handles one flowchart shape on the canvas: its body by kind, its text (view and edit modes), dragging, double-click editing, right-click menu, the arrow-drawing handle and the resize handle.

// Qt Quick basics, the Shapes module (drawn paths) and standard controls (Menu).
import QtQuick
import QtQuick.Shapes
import QtQuick.Controls

// Root item: one shape in the diagram.
Item {
    id: shapeRoot
    // Unique name per shape so tests can find it.
    objectName: "shape-" + shapeId
    // Lets other files open this shape's context menu.
    readonly property alias nodeMenu: contextMenu

    // Values the canvas model supplies for this shape; they must all be provided.
    required property int index
    // The shape's id number, its position (px, py) and size (pw, ph) in world coordinates.
    required property int shapeId
    required property double px
    required property double py
    required property double pw
    required property double ph
    // The text inside the shape and its fill color.
    required property string text
    required property color shapeColor
    // Which symbol to draw (terminal, process, input_output, decision, internal_method, external_method).
    required property string shapeKind // "terminal"|"process"|"input_output"|"decision"|"internal_method"|"external_method"
    // The canvas that owns this shape and the item that holds all world content.
    required property var canvasRoot
    required property var worldItem

    // Smaller of width and height; many sizes are proportions of it so shapes scale well.
    readonly property double minDim: Math.min(pw, ph)
    // Outline thickness: scales with size, limited to 0.5-2 pixels, thicker while the text is being edited.
    readonly property double borderW: Math.max(0.5, Math.min(minDim * 0.02, 2)) * (canvasRoot.editingIndex === index ? 1.5 : 1)
    // Blue outline when selected or being edited, gray otherwise.
    readonly property color borderColor: canvasRoot.editingIndex === index || canvasRoot.selectedId === shapeId ? "#2876bd" : "#555555"
    // How far the text is pushed in from the sides; diamonds and method boxes need more room.
    readonly property real textInsetX: pw * ((shapeKind === "decision" || shapeKind === "diamond") ? 0.25 :
        (shapeKind === "external_method" || shapeKind === "internal_method") ? 0.23 : 0.1)
    // How far the text is pushed down from the top.
    readonly property real textInsetTop: (shapeKind === "decision" || shapeKind === "diamond") ? ph * 0.23 :
        shapeKind === "internal_method" ? ph * 0.3 : 8

    // Place and size this item from the model values.
    x: px
    y: py
    width: pw
    height: ph

    // The body swaps per shape type; everything else (text, drag, handles)
    // is identical regardless of which one is picked.
    // Loader shows exactly one of the visual components below, picked by shape kind (anything unknown is drawn as a rectangle).
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
            // A corner radius of half the shorter side makes the ends fully round.
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
            // Four lines connecting the midpoints of the sides form the diamond.
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
            // The top horizontal line.
            Rectangle {
                x: 0
                y: parent.height * 0.25
                width: parent.width
                height: shapeRoot.borderW
                color: shapeRoot.borderColor
            }
            // The left vertical line.
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
            // The left vertical line.
            Rectangle {
                x: parent.width * 0.18
                y: 0
                width: shapeRoot.borderW
                height: parent.height
                color: shapeRoot.borderColor
            }
            // The right vertical line.
            Rectangle {
                x: parent.width * 0.82 - shapeRoot.borderW
                y: 0
                width: shapeRoot.borderW
                height: parent.height
                color: shapeRoot.borderColor
            }
        }
    }

    // The text shown when the shape is NOT being edited; it shrinks to fit and is clipped.
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

    // The text editor shown only while editing; typing writes straight back into the canvas model.
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
        // Copy each typed change into the model while this editor has focus.
        onTextChanged: {
            if (activeFocus && canvasRoot.editingIndex === shapeRoot.index)
                canvasRoot.shapesModel.setProperty(shapeRoot.index, "text", text)
        }
        // On showing, take keyboard focus and select all text so typing replaces it.
        onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
        // Escape leaves editing mode and gives focus back to the canvas.
        Keys.onEscapePressed: { canvasRoot.editingIndex = -1; canvasRoot.forceActiveFocus() }
    }

    // Mouse area for left-click: selecting, dragging and double-click to edit.
    MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: canvasRoot.editingIndex !== shapeRoot.index
        cursorShape: Qt.SizeAllCursor
        // Dragging this area moves the shape.
        drag.target: shapeRoot
        drag.axis: Drag.XAndYAxis
        acceptedButtons: Qt.LeftButton
        // Pressing selects the shape and starts an undoable change.
        onPressed: mouse => {
            canvasRoot.selectShape(shapeRoot.shapeId)
            canvasRoot.beginChange()
        }

        // Double-click starts text editing.
        onDoubleClicked: {
            canvasRoot.editingIndex = shapeRoot.index
            textEdit.forceActiveFocus()
            textEdit.selectAll()
        }
        // On release, store the new position in the model and end the undoable change.
        onReleased: {
            canvasRoot.shapesModel.setProperty(shapeRoot.index, "px", shapeRoot.x)
            canvasRoot.shapesModel.setProperty(shapeRoot.index, "py", shapeRoot.y)
            canvasRoot.endChange()
        }
    }

    // Right-click menu for the shape: edit, details, duplicate, delete.
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

    // Separate right-button area (above others) that selects the shape and opens the menu.
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
        // Only visible when this shape is selected and not being dragged.
        visible: !dragArea.drag.active && canvasRoot.selectedId === shapeRoot.shapeId

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            // Pressing starts an arrow from this shape and records its start point in world coordinates.
            onPressed: {
                canvasRoot.arrowDragActive = true
                canvasRoot.arrowFromId = shapeRoot.shapeId
                var c = mapToItem(shapeRoot.worldItem, width / 2, height / 2)
                canvasRoot.arrowFromX = c.x
                canvasRoot.arrowFromY = c.y
                canvasRoot.arrowToX = c.x
                canvasRoot.arrowToY = c.y
            }
            // While dragging, keep updating the arrow's end point.
            onPositionChanged: (mouse) => {
                if (canvasRoot.arrowDragActive) {
                    var p = mapToItem(shapeRoot.worldItem, mouse.x, mouse.y)
                    canvasRoot.arrowToX = p.x
                    canvasRoot.arrowToY = p.y
                }
            }
            // On release, if the pointer is over another shape, create the arrow to it.
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
            // Remember the size and mouse position at the start of the drag.
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
            // While dragging, set a new size (minimum 40 by 30) from how far the mouse has moved.
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
