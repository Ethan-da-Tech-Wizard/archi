// ==============================================================================
// Program: ArrowLayer.qml
// Programmer: Ethan-da-Tech-Wizard
// Last Modified: November 18, 2026
// Purpose: Canvas overlay rendering directional connector arrows between diagram nodes.
//          Calculates geometric intersection points between shape perimeters, computes
//          curved or orthogonal Bézier paths, and positions branch text labels dynamically.
//
// How it fits: InfiniteCanvas.qml instantiates one ArrowLayer inside its
// `world` item (so it shares pan/zoom) and feeds it `arrowLines`, the
// geometry computed by rebuildArrowGeometry(). This file only DRAWS and
// reports clicks; it does no geometry itself.
//
// Each element of `lines` is an object: points (polyline vertices),
// ax1/ay1/ax2/ay2 (the two outer corners of the arrowhead) with x2/y2 as its
// tip, strokeWidth, label, labelX/labelY (label centre) and edgeIndex (index
// in the canvas's `arrows` array, used as the selection id).
//
// Known limits: arrows are straight segments between waypoints (the file
// header's "Bézier" wording is aspirational; there is no curve fitting).
// ==============================================================================
import QtQuick
import QtQuick.Shapes

// Container for all connection visuals; sized by its parent, not by content.
Item {
    id: layer
    // Drawable geometry from the canvas (see header); replacing the array
    // rebuilds every delegate.
    property var lines: []
    // Dashed line while the user drags a new arrow: {x1,y1,x2,y2} or null to hide.
    property var previewLine: null
    // edgeIndex of the highlighted connection (-1 none); drawn in the accent blue.
    property int selectedIndex: -1
    // Emitted when a line or its label is clicked; the canvas selects that arrow.
    signal selected(int index)

    /** Screen-independent rectangle of arrow `index`'s label in world units; zero-size if it has none or the delegate is not built yet. Used by diagramBounds() so exports include labels. */
    function labelBounds(index) {
        const edge = edges.itemAt(index)
        return edge ? edge.labelBounds : Qt.rect(0, 0, 0, 0)
    }

    // One delegate per arrow.
    Repeater {
        id: edges
        model: layer.lines
        delegate: Item {
            id: edge
            required property var modelData
            // Label box rectangle, or zero size when no label text, so empty labels do
            // not enlarge export bounds.
            readonly property rect labelBounds: Qt.rect(labelBox.x, labelBox.y,
                modelData.label.length ? labelBox.width : 0, modelData.label.length ? labelBox.height : 0)
            // Blue when selected, neutral grey otherwise.
            readonly property color ink: layer.selectedIndex === modelData.edgeIndex ? "#2876bd" : "#687580"
            // Shape layer: first path is the polyline body (no fill), second the filled
            // triangular arrowhead (tip x2,y2; base corners ax1/ay1 and ax2/ay2).
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
            // Click targets: Shape ignores the mouse, so each segment gets an invisible
            // 12-unit-thick MouseArea, rotated to lie along the segment, which makes thin
            // lines easy to click.
            Repeater {
                model: edge.modelData.points.length - 1
                delegate: MouseArea {
                    required property int index
                    readonly property var a: edge.modelData.points[index]
                    readonly property var b: edge.modelData.points[index + 1]
                    // Segment start; the area is centred vertically on it (y - height/2).
                    x: a.x
                    y: a.y - height / 2
                    // Segment length via hypot.
                    width: Math.hypot(b.x - a.x, b.y - a.y)
                    height: 12
                    // Rotate about the area's left-middle point (origin y = half the height 12)
                    // by the segment's angle converted from radians to degrees.
                    transform: Rotation { origin.x: 0; origin.y: 6; angle: Math.atan2(b.y - a.y, b.x - a.x) * 180 / Math.PI }
                    cursorShape: Qt.PointingHandCursor
                    onClicked: layer.selected(edge.modelData.edgeIndex)
                }
            }
            // Edge label: white pill on top of the line so the text stays readable,
            // centred on labelX/labelY, padded 12 x 6 around the text.
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
    // Dashed preview of an arrow being dragged out of a shape; drawn only while previewLine is set.
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
