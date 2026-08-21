import QtQuick
import QtQuick.Shapes

// Draws a small rect/ellipse/diamond glyph procedurally instead of relying
// on Unicode characters, whose stroke weight and size vary wildly between
// fonts/platforms and don't match each other visually in a toolbar.
Item {
    id: iconRoot

    required property string kind // "rect" | "ellipse" | "diamond"
    property color fillColor: "transparent"
    property color strokeColor: "#555555"
    property real strokeWidth: 1.6

    Rectangle {
        anchors.fill: parent
        visible: iconRoot.kind === "rect"
        radius: 2
        color: iconRoot.fillColor
        border.color: iconRoot.strokeColor
        border.width: iconRoot.strokeWidth
    }

    Shape {
        anchors.fill: parent
        visible: iconRoot.kind === "ellipse"
        ShapePath {
            fillColor: iconRoot.fillColor
            strokeColor: iconRoot.strokeColor
            strokeWidth: iconRoot.strokeWidth
            PathAngleArc {
                centerX: iconRoot.width / 2
                centerY: iconRoot.height / 2
                radiusX: iconRoot.width / 2 - iconRoot.strokeWidth / 2
                radiusY: iconRoot.height / 2 - iconRoot.strokeWidth / 2
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    Shape {
        id: diamondShape
        anchors.fill: parent
        visible: iconRoot.kind === "diamond"
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
}
