import QtQuick
import QtQuick.Shapes

Item {
    id: layer

    // Each entry: {x1,y1,x2,y2, ax1,ay1, ax2,ay2} in world coordinates.
    property var lines: []
    // {x1,y1,x2,y2} while a new arrow is being dragged out, or null.
    property var previewLine: null

    Repeater {
        model: layer.lines
        delegate: Shape {
            required property var modelData
            ShapePath {
                strokeColor: "#666666"
                strokeWidth: modelData.strokeWidth
                fillColor: "transparent"
                startX: modelData.x1
                startY: modelData.y1
                PathLine { x: modelData.x2; y: modelData.y2 }
            }
            ShapePath {
                fillColor: "#666666"
                strokeColor: "#666666"
                strokeWidth: modelData.strokeWidth * 0.5
                startX: modelData.ax1
                startY: modelData.ay1
                PathLine { x: modelData.x2; y: modelData.y2 }
                PathLine { x: modelData.ax2; y: modelData.ay2 }
                PathLine { x: modelData.ax1; y: modelData.ay1 }
            }
        }
    }

    Shape {
        visible: layer.previewLine !== null
        ShapePath {
            strokeColor: "#999999"
            strokeWidth: 2
            strokeStyle: ShapePath.DashLine
            dashPattern: [4, 4]
            fillColor: "transparent"
            startX: layer.previewLine ? layer.previewLine.x1 : 0
            startY: layer.previewLine ? layer.previewLine.y1 : 0
            PathLine {
                x: layer.previewLine ? layer.previewLine.x2 : 0
                y: layer.previewLine ? layer.previewLine.y2 : 0
            }
        }
    }
}
