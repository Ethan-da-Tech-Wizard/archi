import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: popup
    modal: true
    focus: true
    width: Math.min(window.width * 0.9, 780)
    height: Math.min(window.height * 0.85, 620)
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    padding: 24

    signal selectShapeKind(string kind)
    signal loadSampleFlowchart()

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

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

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

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#e0e0e0"
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: 12

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

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#e0e0e0"
        }

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
