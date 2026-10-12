import QtQuick
import QtQuick.Shapes

Item {
    id: layer
    property var lines: []
    property var previewLine: null
    property int selectedIndex: -1
    signal selected(int index)

    function labelBounds(index) {
        const edge = edges.itemAt(index)
        return edge ? edge.labelBounds : Qt.rect(0, 0, 0, 0)
    }

    Repeater {
        id: edges
        model: layer.lines
        delegate: Item {
            id: edge
            required property var modelData
            readonly property rect labelBounds: Qt.rect(labelBox.x, labelBox.y,
                modelData.label.length ? labelBox.width : 0, modelData.label.length ? labelBox.height : 0)
            readonly property color ink: layer.selectedIndex === modelData.edgeIndex ? "#2876bd" : "#687580"
            Shape {
                ShapePath {
                    strokeColor: edge.ink
                    strokeWidth: edge.modelData.strokeWidth
                    fillColor: "transparent"
                    PathPolyline { path: edge.modelData.points.map(p => Qt.point(p.x, p.y)) }
                }
                ShapePath {
                    fillColor: edge.ink
                    strokeColor: edge.ink
                    strokeWidth: 0.5
                    startX: edge.modelData.ax1
                    startY: edge.modelData.ay1
                    PathLine { x: edge.modelData.x2; y: edge.modelData.y2 }
                    PathLine { x: edge.modelData.ax2; y: edge.modelData.ay2 }
                    PathLine { x: edge.modelData.ax1; y: edge.modelData.ay1 }
                }
            }
            Repeater {
                model: edge.modelData.points.length - 1
                delegate: MouseArea {
                    required property int index
                    readonly property var a: edge.modelData.points[index]
                    readonly property var b: edge.modelData.points[index + 1]
                    x: a.x
                    y: a.y - height / 2
                    width: Math.hypot(b.x - a.x, b.y - a.y)
                    height: 12
                    transform: Rotation { origin.x: 0; origin.y: 6; angle: Math.atan2(b.y - a.y, b.x - a.x) * 180 / Math.PI }
                    cursorShape: Qt.PointingHandCursor
                    onClicked: layer.selected(edge.modelData.edgeIndex)
                }
            }
            Rectangle {
                id: labelBox
                visible: edge.modelData.label.length > 0
                x: edge.modelData.labelX - width / 2
                y: edge.modelData.labelY - height / 2
                width: label.implicitWidth + 12
                height: label.implicitHeight + 6
                color: "#ffffff"
                border.color: layer.selectedIndex === edge.modelData.edgeIndex ? "#2876bd" : "#d6dce0"
                radius: 3
                Text { id: label; anchors.centerIn: parent; text: edge.modelData.label; textFormat: Text.PlainText; color: "#394651"; font.pixelSize: 16 }
                MouseArea { anchors.fill: parent; onClicked: layer.selected(edge.modelData.edgeIndex) }
            }
        }
    }
    Shape {
        visible: layer.previewLine !== null
        ShapePath {
            strokeColor: "#2876bd"
            strokeWidth: 2
            strokeStyle: ShapePath.DashLine
            fillColor: "transparent"
            startX: layer.previewLine ? layer.previewLine.x1 : 0
            startY: layer.previewLine ? layer.previewLine.y1 : 0
            PathLine { x: layer.previewLine ? layer.previewLine.x2 : 0; y: layer.previewLine ? layer.previewLine.y2 : 0 }
        }
    }
}
