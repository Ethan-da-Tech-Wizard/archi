import QtQuick
import QtQuick.Shapes

// Draws a small flowchart symbol glyph procedurally for toolbar & cheat sheet
Item {
    id: iconRoot

    required property string kind // "terminal"|"flowline"|"input_output"|"process"|"rect"|"decision"|"diamond"|"internal_method"|"external_method"
    property color fillColor: "transparent"
    property color strokeColor: "#555555"
    property real strokeWidth: 1.5

    // Terminal (Elongated oval shape)
    Rectangle {
        anchors.fill: parent
        visible: iconRoot.kind === "terminal" || iconRoot.kind === "ellipse"
        radius: height / 2
        color: iconRoot.fillColor
        border.color: iconRoot.strokeColor
        border.width: iconRoot.strokeWidth
    }

    // Process / Rectangle
    Rectangle {
        anchors.fill: parent
        visible: iconRoot.kind === "process" || iconRoot.kind === "rect"
        radius: 2
        color: iconRoot.fillColor
        border.color: iconRoot.strokeColor
        border.width: iconRoot.strokeWidth
    }

    // Input/Output (Parallelogram)
    Shape {
        id: ioShape
        anchors.fill: parent
        visible: iconRoot.kind === "input_output" || iconRoot.kind === "io"
        ShapePath {
            fillColor: iconRoot.fillColor
            strokeColor: iconRoot.strokeColor
            strokeWidth: iconRoot.strokeWidth
            startX: ioShape.width * 0.25
            startY: iconRoot.strokeWidth / 2
            PathLine { x: ioShape.width - iconRoot.strokeWidth / 2; y: iconRoot.strokeWidth / 2 }
            PathLine { x: ioShape.width * 0.75; y: ioShape.height - iconRoot.strokeWidth / 2 }
            PathLine { x: iconRoot.strokeWidth / 2; y: ioShape.height - iconRoot.strokeWidth / 2 }
            PathLine { x: ioShape.width * 0.25; y: iconRoot.strokeWidth / 2 }
        }
    }

    // Decision (Diamond)
    Shape {
        id: diamondShape
        anchors.fill: parent
        visible: iconRoot.kind === "decision" || iconRoot.kind === "diamond"
        ShapePath {
            fillColor: iconRoot.fillColor
            strokeColor: iconRoot.strokeColor
            strokeWidth: iconRoot.strokeWidth
            startX: diamondShape.width / 2
            startY: iconRoot.strokeWidth / 2
            PathLine { x: diamondShape.width - iconRoot.strokeWidth / 2; y: diamondShape.height / 2 }
            PathLine { x: diamondShape.width / 2; y: diamondShape.height - iconRoot.strokeWidth / 2 }
            PathLine { x: iconRoot.strokeWidth / 2; y: diamondShape.height / 2 }
            PathLine { x: diamondShape.width / 2; y: iconRoot.strokeWidth / 2 }
        }
    }

    // Internal Method (Rectangle with top horizontal line & left vertical line)
    Item {
        anchors.fill: parent
        visible: iconRoot.kind === "internal_method"

        Rectangle {
            anchors.fill: parent
            radius: 1
            color: iconRoot.fillColor
            border.color: iconRoot.strokeColor
            border.width: iconRoot.strokeWidth
        }

        // Top horizontal line
        Rectangle {
            x: 0
            y: parent.height * 0.28
            width: parent.width
            height: iconRoot.strokeWidth
            color: iconRoot.strokeColor
        }

        // Left vertical line
        Rectangle {
            x: parent.width * 0.25
            y: 0
            width: iconRoot.strokeWidth
            height: parent.height
            color: iconRoot.strokeColor
        }
    }

    // External Method (Rectangle with left and right vertical lines)
    Item {
        anchors.fill: parent
        visible: iconRoot.kind === "external_method"

        Rectangle {
            anchors.fill: parent
            radius: 1
            color: iconRoot.fillColor
            border.color: iconRoot.strokeColor
            border.width: iconRoot.strokeWidth
        }

        // Left vertical line
        Rectangle {
            x: parent.width * 0.22
            y: 0
            width: iconRoot.strokeWidth
            height: parent.height
            color: iconRoot.strokeColor
        }

        // Right vertical line
        Rectangle {
            x: parent.width * 0.78 - iconRoot.strokeWidth
            y: 0
            width: iconRoot.strokeWidth
            height: parent.height
            color: iconRoot.strokeColor
        }
    }

    // Flowline (Arrow pointing to the right)
    Shape {
        id: flowlineShape
        anchors.fill: parent
        visible: iconRoot.kind === "flowline"
        ShapePath {
            strokeColor: iconRoot.strokeColor
            strokeWidth: iconRoot.strokeWidth * 1.2
            fillColor: "transparent"
            startX: 2
            startY: flowlineShape.height / 2
            PathLine { x: flowlineShape.width - 6; y: flowlineShape.height / 2 }
        }
        ShapePath {
            fillColor: iconRoot.strokeColor
            strokeColor: iconRoot.strokeColor
            strokeWidth: 1
            startX: flowlineShape.width - 7
            startY: flowlineShape.height / 2 - 4
            PathLine { x: flowlineShape.width - 1; y: flowlineShape.height / 2 }
            PathLine { x: flowlineShape.width - 7; y: flowlineShape.height / 2 + 4 }
            PathLine { x: flowlineShape.width - 7; y: flowlineShape.height / 2 - 4 }
        }
    }
}
