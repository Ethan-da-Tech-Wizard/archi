// ==============================================================================
// Program: CheatSheetPopup.qml
// Programmer: Ethan-da-Tech-Wizard
// Last Modified: November 18, 2026
// Purpose: Modal reference popup listing the standard flowchart symbols (shape,
//          meaning, when to use it), with buttons to pick a symbol for new
//          shapes and to load a sample flowchart.
//
// How it fits: instantiated once by Main.qml (id `cheatSheetPopup`; the
// ProjectWorkspace window inherits it from Main), opened
// with F2 or the toolbar help button. It is a reference card for the seven
// flowchart symbols (drawn with ShapeIcon.qml) with two actions reported
// through signals: `selectShapeKind(kind)` makes Main.qml's toolbar pick that
// shape for new nodes, and `loadSampleFlowchart()` replaces the canvas with
// the demo diagram. It holds no diagram state itself.
//
// Dependency to know about: the size bindings read `window` (the id of the
// ApplicationWindow in Main.qml) and `parent`, so the popup must be declared
// inside that window.
// ==============================================================================
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Modal so clicks outside do not reach the canvas; focus so Esc closes it.
Popup {
    id: popup
    modal: true
    focus: true
    // Up to 90 % x 85 % of the window but capped at 780 x 620 px so it stays
    // readable on large screens; centred below.
    width: Math.min(window.width * 0.9, 780)
    height: Math.min(window.height * 0.85, 620)
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    padding: 24

    // Emitted with a shapeKind string when the user presses "Select" on a symbol row.
    signal selectShapeKind(string kind)
    // Emitted by the "Load Sample Flowchart" button; the owner clears and fills the canvas.
    signal loadSampleFlowchart()

    // Content table, one object per symbol: `name` (title), `kind` (the
    // shapeKind / ShapeIcon kind string), `shapeDesc` (how it looks) and
    // `purpose` (when to use it in a flowchart). Edit this list to change the sheet.
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

    // Rounded white card with a hairline border; the inner 2 % black rectangle
    // adds a faint tint so the card separates from white window backgrounds.
    background: Rectangle {
        color: "#ffffff"
        radius: 12
        border.color: "#d0d0d0"
        border.width: 1

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: "#000000"
            opacity: 0.02
        }
    }

    // Layout: header row, divider, scrolling symbol list, divider, footer buttons.
    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        // Header: title and subtitle on the left, close button on the right.
        RowLayout {
            Layout.fillWidth: true

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

            Item { Layout.fillWidth: true }

            ToolButton {
                text: "✕"
                implicitWidth: 32
                implicitHeight: 32
                onClicked: popup.close()
            }
        }

        // Thin divider line (1 px).
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#e0e0e0"
        }

        // Scrollable list so the popup works on small windows; clip keeps rows inside it.
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: 12

                // One row per symbol, with alternating background (even rows tinted) for readability.
                Repeater {
                    model: popup.symbols
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: shapeRow.implicitHeight + 20
                        color: index % 2 === 0 ? "#f9fbfd" : "#ffffff"
                        radius: 8
                        border.color: "#e4e8ec"
                        border.width: 1

                        RowLayout {
                            id: shapeRow
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 16

                            // Icon preview: the same glyph the toolbar/canvas uses, in a light tile.
                            // Icon Preview
                            Rectangle {
                                implicitWidth: 54
                                implicitHeight: 40
                                color: "#f0f4f8"
                                radius: 6
                                border.color: "#cbd5e1"
                                border.width: 1

                                ShapeIcon {
                                    kind: modelData.kind
                                    implicitWidth: 36
                                    implicitHeight: 24
                                    anchors.centerIn: parent
                                    strokeColor: "#2f6fb0"
                                    fillColor: "#cfe3f7"
                                }
                            }

                            // Name, look-alike badge and purpose text.
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

                            // "Select" is hidden for the flowline: it is an arrow, not a node kind that
                            // can be chosen for new shapes. Selecting reports the kind and closes.
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

        // Divider above the footer.
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#e0e0e0"
        }

        // Footer: load-sample action on the left, close on the right.
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Button {
                text: "✨ Load Sample Flowchart"
                highlighted: true
                onClicked: {
                    popup.loadSampleFlowchart()
                    popup.close()
                }
                // The tooltip warns that loading REPLACES the current canvas content.
                ToolTip.visible: hovered
                ToolTip.text: "Clears canvas and builds an example flowchart using all shape types and flowlines"
            }

            Item { Layout.fillWidth: true }

            Button {
                text: "Close"
                onClicked: popup.close()
            }
        }
    }
}
