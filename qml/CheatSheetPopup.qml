// Program: archi - CheatSheetPopup.qml
// Programmer: Ethan-da-Tech-Wizard (written with Claude, an AI assistant)
// Last Modified: 2026-11-18
// Purpose: QML popup window (the Flowchart Cheat Sheet) that lists every flowchart symbol with its icon and meaning, lets the user pick a shape type, and can load a sample flowchart.

// Qt Quick basics, the standard controls (Popup, Button, Label) and layouts.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Popup shows a floating panel on top of the window; modal blocks clicks on whatever is behind it.
Popup {
    id: popup
    modal: true
    focus: true
    // Size it to 90% of the window width (max 780) and 85% of its height (max 620); "window" is the app's main window id.
    width: Math.min(window.width * 0.9, 780)
    height: Math.min(window.height * 0.85, 620)
    // Center it horizontally and vertically inside its parent.
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    padding: 24

    // Signals other files can listen to: the user chose a shape kind, or asked for the sample flowchart.
    signal selectShapeKind(string kind)
    signal loadSampleFlowchart()

    // The data behind the list: one entry per symbol with a name, a kind id (used to draw the icon), a picture description and a purpose.
    readonly property var symbols: [
        {
            name: "Terminal",
            kind: "terminal",
            shapeDesc: "Elongated oval shape",
            purpose: "Indicates the Start or End point of a program or flowchart process."
        },
        {
            name: "Flowline",
            kind: "flowline",
            shapeDesc: "Arrow pointing to the right",
            purpose: "Shows the direction of process flow connecting one shape to another."
        },
        {
            name: "Input / Output",
            kind: "input_output",
            shapeDesc: "Parallelogram shape",
            purpose: "Represents data input operations (e.g. READ input) or output operations (e.g. PRINT results)."
        },
        {
            name: "Process",
            kind: "process",
            shapeDesc: "Rectangle shape",
            purpose: "Represents an action, computation, data modification, or step in the flowchart."
        },
        {
            name: "Decision",
            kind: "decision",
            shapeDesc: "Diamond shape",
            purpose: "Represents a conditional evaluation or branching point (e.g. Yes / No paths)."
        },
        {
            name: "Internal Method",
            kind: "internal_method",
            shapeDesc: "Rectangle with horizontal line at top & vertical line on left side",
            purpose: "Represents an internal subroutine, class method, or helper function defined within the project."
        },
        {
            name: "External Method",
            kind: "external_method",
            shapeDesc: "Rectangle with vertical lines on both left and right side",
            purpose: "Represents an external library process, API service, or predefined external routine."
        }
    ]

    // The rounded white panel behind the popup contents.
    background: Rectangle {
        color: "#ffffff"
        radius: 12
        border.color: "#d0d0d0"
        // A very faint dark overlay on top of the white panel gives it a subtle tint.
        border.width: 1

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: "#000000"
            opacity: 0.02
        }
    }

    // Main vertical layout: title row, divider, scrolling list, divider, button row.
    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        // Title row: heading text on the left, close button on the right.
        RowLayout {
            Layout.fillWidth: true

            // Heading and subtitle stacked vertically.
            ColumnLayout {
                spacing: 2
                Label {
                    text: "Flowchart Cheat Sheet"
                    font.bold: true
                    font.pixelSize: 20
                    color: "#1e1e1e"
                }
                Label {
                    text: "Standard flowchart symbol definitions, shape representations, and arrow flow conventions."
                    font.pixelSize: 13
                    opacity: 0.75
                }
            }

            // An empty stretchy item pushes the close button to the right edge.
            Item { Layout.fillWidth: true }

            // Small X button that closes the popup.
            ToolButton {
                text: "✕"
                implicitWidth: 32
                implicitHeight: 32
                onClicked: popup.close()
            }
        }

        // A thin horizontal divider line.
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#e0e0e0"
        }

        // Scrollable area holding the list of symbols.
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: 12

                // Repeater creates one row for every entry of the symbols list.
                Repeater {
                    model: popup.symbols
                    // Each row alternates between two background shades so the list is easy to scan.
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: shapeRow.implicitHeight + 20
                        color: index % 2 === 0 ? "#f9fbfd" : "#ffffff"
                        radius: 8
                        border.color: "#e4e8ec"
                        border.width: 1

                        // Inside each row: icon, text details, and a Select button.
                        RowLayout {
                            id: shapeRow
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 16

                            // Icon Preview
                            Rectangle {
                                implicitWidth: 54
                                implicitHeight: 40
                                color: "#f0f4f8"
                                radius: 6
                                border.color: "#cbd5e1"
                                border.width: 1

                                // Draws the symbol's picture using the ShapeIcon component.
                                ShapeIcon {
                                    kind: modelData.kind
                                    implicitWidth: 36
                                    implicitHeight: 24
                                    anchors.centerIn: parent
                                    strokeColor: "#2f6fb0"
                                    fillColor: "#cfe3f7"
                                }
                            }

                            // Details
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                RowLayout {
                                    spacing: 8
                                    Label {
                                        text: modelData.name
                                        font.bold: true
                                        font.pixelSize: 14
                                        color: "#1e293b"
                                    }
                                    Rectangle {
                                        color: "#e2e8f0"
                                        radius: 4
                                        implicitWidth: shapeDescLabel.implicitWidth + 10
                                        implicitHeight: 18
                                        Label {
                                            id: shapeDescLabel
                                            anchors.centerIn: parent
                                            text: modelData.shapeDesc
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                            color: "#475569"
                                        }
                                    }
                                }

                                Label {
                                    text: modelData.purpose
                                    font.pixelSize: 12
                                    color: "#64748b"
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }

                            // Action Button
                            Button {
                                visible: modelData.kind !== "flowline"
                                text: "Select"
                                implicitHeight: 30
                                implicitWidth: 68
                                onClicked: {
                                    popup.selectShapeKind(modelData.kind)
                                    popup.close()
                                }
                            }
                        }
                    }
                }
            }
        }

        // Another divider line above the buttons.
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#e0e0e0"
        }

        // Bottom button row.
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Closes the sheet and asks the app to build the example flowchart.
            Button {
                text: "✨ Load Sample Flowchart"
                highlighted: true
                onClicked: {
                    popup.loadSampleFlowchart()
                    popup.close()
                }
                ToolTip.visible: hovered
                ToolTip.text: "Clears canvas and builds an example flowchart using all shape types and flowlines"
            }

            Item { Layout.fillWidth: true }

            // Plain Close button.
            Button {
                text: "Close"
                onClicked: popup.close()
            }
        }
    }
}
