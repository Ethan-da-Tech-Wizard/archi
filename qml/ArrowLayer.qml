// Program: archi - ArrowLayer.qml
// Programmer: Ethan-da-Tech-Wizard (written with Claude, an AI assistant)
// Last Modified: 2026-11-18
// Purpose: QML component that draws all connection arrows (lines, arrow heads, labels), makes them clickable, reports which one was clicked, and shows a dashed preview line while a new arrow is being dragged.

// Qt Quick basics and the Shapes module (drawn paths).
import QtQuick
import QtQuick.Shapes

// Container item for all arrows.
Item {
    id: layer
    // Drawing data for every arrow (points, arrow head corners, label position), produced by the canvas.
    property var lines: []
    // The dashed line shown while dragging out a new arrow, or null when none.
    property var previewLine: null
    // Which arrow is selected (-1 for none); it is drawn in blue.
    property int selectedIndex: -1
    // Emitted with an arrow's index when the user clicks it.
    signal selected(int index)

    // Return the rectangle taken by an arrow's label box, so the PNG exporter can include labels.
    function labelBounds(index) {
        const edge = edges.itemAt(index)
        return edge ? edge.labelBounds : Qt.rect(0, 0, 0, 0)
    }

    // One copy of the delegate below is made for each arrow.
    Repeater {
        id: edges
        model: layer.lines
        delegate: Item {
            id: edge
            // The data for this arrow.
            required property var modelData
            // Rectangle of the label (zero size when the arrow has no label).
            readonly property rect labelBounds: Qt.rect(labelBox.x, labelBox.y,
                modelData.label.length ? labelBox.width : 0, modelData.label.length ? labelBox.height : 0)
            // Blue when selected, gray otherwise.
            readonly property color ink: layer.selectedIndex === modelData.edgeIndex ? "#2876bd" : "#687580"
            // One Shape holding two paths: the line itself and the triangular arrow head.
            Shape {
                // First path: the polyline through all the arrow's points.
                ShapePath {
                    strokeColor: edge.ink
                    strokeWidth: edge.modelData.strokeWidth
                    fillColor: "transparent"
                    PathPolyline { path: edge.modelData.points.map(p => Qt.point(p.x, p.y)) }
                }
                // Second path: a small filled triangle at the end of the line.
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
            // Invisible click targets along each line segment, so a thin line is easy to click.
            Repeater {
                model: edge.modelData.points.length - 1
                // Each target is a thin rotated rectangle laid along one segment between two neighboring points.
                delegate: MouseArea {
                    required property int index
                    readonly property var a: edge.modelData.points[index]
                    readonly property var b: edge.modelData.points[index + 1]
                    x: a.x
                    y: a.y - height / 2
                    width: Math.hypot(b.x - a.x, b.y - a.y)
                    height: 12
                    // Rotate the rectangle to match the segment's angle (radians converted to degrees).
                    transform: Rotation { origin.x: 0; origin.y: 6; angle: Math.atan2(b.y - a.y, b.x - a.x) * 180 / Math.PI }
                    cursorShape: Qt.PointingHandCursor
                    onClicked: layer.selected(edge.modelData.edgeIndex)
                }
            }
            // The label box centered on the label position, with a white background; clicking it also selects the arrow.
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
    // The dashed preview line used while dragging a new arrow.
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
