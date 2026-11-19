// ==============================================================================
// Program: ShapeItem.qml
// Programmer: Ethan-da-Tech-Wizard
// Last Modified: November 18, 2026
// Purpose: Reusable interactive canvas node component representing diagram shapes.
//          Handles rich-text editing, resizable grab handles, selection states,
//          geometry transformations, color themes, and anchor connection points.
//
// How it fits: InfiniteCanvas.qml's Repeater creates one ShapeItem per
// `shapesModel` row. The `required property` lines below receive that row's
// roles by name (shapeId, px, py, pw, ph, text, shapeColor, shapeKind) plus
// two references the canvas passes explicitly: `canvasRoot` (to call its
// functions such as selectShape/beginChange/addArrow) and `worldItem` (the
// transformed layer, used to convert mouse positions into world units).
//
// Responsibilities: draw the body for the shape kind, show/edit its label,
// drag to move, bottom-right handle to resize, right-edge handle to drag out
// an arrow, right-click context menu. It never stores state itself: every
// change is written back into the model with setProperty so the canvas stays
// the single source of truth (and undo can snapshot it).
//
// objectName values ("shape-<id>", "shapeEditor-<id>", "editNode-<id>" ...)
// exist so automated tests (LogicTest.qml) can find the items.
// ==============================================================================
import QtQuick
import QtQuick.Shapes
import QtQuick.Controls

Item {
    id: shapeRoot
    // Stable, id-based name for test lookups.
    objectName: "shape-" + shapeId
    // Public handle on the context menu (declared for external callers such as
    // tests; nothing in the current QML references it).
    readonly property alias nodeMenu: contextMenu

    // Row index inside shapesModel (changes when rows are removed), needed to
    // call setProperty; shapeId is the permanent identity.
    required property int index
    // Geometry in WORLD units; the canvas's `world` item turns it into pixels.
    required property int shapeId
    required property double px
    required property double py
    required property double pw
    required property double ph
    required property string text
    required property color shapeColor
    // Kind drives both the body drawn (Loader below) and the text inset. Unknown
    // kinds fall back to a plain rectangle, so old files never fail to render.
    required property string shapeKind // "terminal"|"process"|"input_output"|"decision"|"internal_method"|"external_method"
    required property var canvasRoot
    required property var worldItem

    // Smallest side; border width, corner radius and font size scale with it so
    // tiny or huge shapes keep proportions at any zoom.
    readonly property double minDim: Math.min(pw, ph)
    // Border 2 % of minDim, clamped 0.5..2 world units; 1.5x thicker while the
    // text editor is open as an "editing" cue.
    readonly property double borderW: Math.max(0.5, Math.min(minDim * 0.02, 2)) * (canvasRoot.editingIndex === index ? 1.5 : 1)
    // Blue ring for the selected or edited shape, dark grey otherwise.
    readonly property color borderColor: canvasRoot.editingIndex === index || canvasRoot.selectedId === shapeId ? "#2876bd" : "#555555"
    // Text must stay inside the visible body: a diamond's usable width is about
    // half its box, parallel lines of method shapes take ~20 %, others 10 %.
    readonly property real textInsetX: pw * ((shapeKind === "decision" || shapeKind === "diamond") ? 0.25 :
        (shapeKind === "external_method" || shapeKind === "internal_method") ? 0.23 : 0.1)
    // Diamonds need top padding because their corners are empty; the "internal
    // method" rule line at 25 % height pushes text down further.
    readonly property real textInsetTop: (shapeKind === "decision" || shapeKind === "diamond") ? ph * 0.23 :
        shapeKind === "internal_method" ? ph * 0.3 : 8

    // Position/size come straight from the model; while dragging, `x`/`y` are
    // overwritten by the drag and written back to px/py on release (see dragArea).
    x: px
    y: py
    width: pw
    height: ph

    // Body renderer chosen by kind (aliases such as "ellipse"/"io"/"diamond" are
    // accepted for older files). A Loader only instantiates the one component
    // used, instead of keeping all six alive per shape.
    Loader {
        anchors.fill: parent
        sourceComponent: (shapeRoot.shapeKind === "terminal" || shapeRoot.shapeKind === "ellipse") ? terminalVisual
            : (shapeRoot.shapeKind === "decision" || shapeRoot.shapeKind === "diamond") ? diamondVisual
            : (shapeRoot.shapeKind === "input_output" || shapeRoot.shapeKind === "io") ? ioVisual
            : shapeRoot.shapeKind === "internal_method" ? internalMethodVisual
            : shapeRoot.shapeKind === "external_method" ? externalMethodVisual
            : rectVisual
    }

    // Visual: process / plain rectangle (also the fallback for unknown kinds).
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

    // Visual: terminal, a stadium shape (corner radius = half the shorter side).
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

    // Visual: decision diamond, four lines from edge midpoints. Drawn with Shape
    // (vector) rather than rotated Rectangle so the stroke stays crisp.
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

    // Visual: input/output parallelogram, slanted 20 % each side.
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

    // Visual: internal method (rectangle + rule at 25 % height + rule at 20 % width).
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

    // Visual: external method (rectangle + vertical rules at 18 % and 82 % width).
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

    // Read-only label shown when not editing. Fit mode shrinks the font to a
    // 10 px minimum, then elides, so long text never overflows the shape.
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

    // Inline editor swapped in on double-click (visible only while this row is
    // the canvas's editingIndex). Plain text only: no markup can enter the file.
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
        // Write each keystroke into the model so the label and saved data follow;
        // guarded by activeFocus so programmatic text assignment does not loop back.
        onTextChanged: {
            if (activeFocus && canvasRoot.editingIndex === shapeRoot.index)
                canvasRoot.shapesModel.setProperty(shapeRoot.index, "text", text)
        }
        // Entering edit mode: take focus and select everything so typing replaces the text.
        onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
        // Escape leaves edit mode; the canvas regains focus so shortcuts work again.
        Keys.onEscapePressed: { canvasRoot.editingIndex = -1; canvasRoot.forceActiveFocus() }
    }

    // Move/select area. Disabled during text editing so the mouse can place the
    // caret instead of dragging the shape.
    MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: canvasRoot.editingIndex !== shapeRoot.index
        cursorShape: Qt.SizeAllCursor
        drag.target: shapeRoot
        drag.axis: Drag.XAndYAxis
        acceptedButtons: Qt.LeftButton
        // Press selects and snapshots state so the whole drag is one undo step.
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
        // Commit the dragged position (world units) into the model, then record the
        // undo step and rebuild arrows, which follow the shape.
        onReleased: {
            canvasRoot.shapesModel.setProperty(shapeRoot.index, "px", shapeRoot.x)
            canvasRoot.shapesModel.setProperty(shapeRoot.index, "py", shapeRoot.y)
            canvasRoot.endChange()
        }
    }

    // Right-click menu; "Details" asks the workspace to open the inspector.
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

    // z:4 puts this above the drag area so right-clicks open the menu and left
    // clicks fall through to the drag area.
    MouseArea {
        anchors.fill: parent
        z: 4
        acceptedButtons: Qt.RightButton
        onClicked: mouse => {
            canvasRoot.selectShape(shapeRoot.shapeId)
            contextMenu.popup(mouse.x, mouse.y)
        }
    }

    // Arrow handle on the right edge of the selected shape: press records the
    // start, dragging updates the dashed preview (ArrowLayer), and release over
    // another shape creates the arrow. Hidden while dragging or when unselected.
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
            // Preview line starts at the handle's centre, in world coordinates.
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
            // Releasing over empty space cancels the arrow; releasing on a shape other
            // than this one connects them (addArrow also rejects duplicates).
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

    // Resize handle at the bottom-right corner; sizes clamp to at least 40x30
    // world units so a shape cannot be shrunk to nothing.
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

            // Remember the starting size and mouse position so the new size is computed
            // from the total drag distance (no accumulated rounding drift).
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
                    // Delta is measured in world units, so resizing works at any zoom level.
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
