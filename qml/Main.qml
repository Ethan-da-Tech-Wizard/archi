import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

ApplicationWindow {
    id: window
    width: 1280
    height: 800
    visible: true
    title: "Archi"

    property var bgPresets: ["#ffffff", "#1e1e1e", "#f5f0e6"]
    property int bgIndex: 0
    property color bgColor: bgPresets[0]

    function cycleBackground() {
        bgIndex = (bgIndex + 1) % bgPresets.length
        bgColor = bgPresets[bgIndex]
    }

    property var shapeSizePresets: [
        { label: "S", w: 110, h: 60 },
        { label: "M", w: 160, h: 80 },
        { label: "L", w: 220, h: 110 }
    ]
    property int shapeSizeIndex: 1

    property var shapeKindPresets: [
        { icon: "▭", kind: "rect", name: "Rectangle" },
        { icon: "◯", kind: "ellipse", name: "Ellipse" },
        { icon: "◇", kind: "diamond", name: "Diamond" }
    ]
    property int shapeKindIndex: 0

    Shortcut {
        sequence: "Ctrl+B"
        onActivated: window.cycleBackground()
    }
    Shortcut {
        sequence: StandardKey.HelpContents
        onActivated: shortcutsPopup.open()
    }

    ColorDialog {
        id: colorDialog
        title: "Choose background color"
        selectedColor: window.bgColor
        onAccepted: window.bgColor = selectedColor
    }

    Popup {
        id: shortcutsPopup
        modal: true
        focus: true
        x: (window.width - width) / 2
        y: (window.height - height) / 2
        padding: 20

        ColumnLayout {
            spacing: 8
            Label { text: "Shortcuts & Controls"; font.bold: true; font.pixelSize: 18 }
            GridLayout {
                columns: 2
                columnSpacing: 16
                rowSpacing: 4
                Label { text: "Double-click empty canvas"; opacity: 0.7 }
                Label { text: "New shape (using the toolbar's size/shape pick)" }
                Label { text: "Double-click a shape"; opacity: 0.7 }
                Label { text: "Edit its text" }
                Label { text: "Esc"; opacity: 0.7 }
                Label { text: "Exit text editing" }
                Label { text: "Drag a shape"; opacity: 0.7 }
                Label { text: "Move it" }
                Label { text: "Drag the blue dot on a shape"; opacity: 0.7 }
                Label { text: "Draw an arrow to another shape" }
                Label { text: "Drag empty canvas"; opacity: 0.7 }
                Label { text: "Pan" }
                Label { text: "Scroll wheel"; opacity: 0.7 }
                Label { text: "Zoom in/out (centered on cursor)" }
                Label { text: "Ctrl+B"; opacity: 0.7 }
                Label { text: "Cycle background presets" }
                Label { text: "F1 / ?"; opacity: 0.7 }
                Label { text: "Show this popup" }
            }
            Button {
                text: "Close"
                Layout.alignment: Qt.AlignRight
                onClicked: shortcutsPopup.close()
            }
        }
    }

    header: ToolBar {
        implicitHeight: 48

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 16

            Label {
                text: "Archi"
                font.bold: true
                font.pixelSize: 15
            }

            ToolSeparator { Layout.fillHeight: true; Layout.topMargin: 6; Layout.bottomMargin: 6 }

            RowLayout {
                spacing: 8
                Label { text: "Size"; opacity: 0.65 }
                Row {
                    spacing: 1
                    Repeater {
                        model: window.shapeSizePresets
                        delegate: ToolButton {
                            required property var modelData
                            required property int index
                            text: modelData.label
                            implicitWidth: 32
                            implicitHeight: 30
                            checkable: true
                            checked: window.shapeSizeIndex === index
                            onClicked: window.shapeSizeIndex = index
                        }
                    }
                }
            }

            ToolSeparator { Layout.fillHeight: true; Layout.topMargin: 6; Layout.bottomMargin: 6 }

            RowLayout {
                spacing: 8
                Label { text: "Shape"; opacity: 0.65 }
                Row {
                    spacing: 1
                    Repeater {
                        model: window.shapeKindPresets
                        delegate: ToolButton {
                            id: shapeKindButton
                            required property var modelData
                            required property int index
                            implicitWidth: 36
                            implicitHeight: 30
                            checkable: true
                            checked: window.shapeKindIndex === index
                            onClicked: window.shapeKindIndex = index
                            ToolTip.visible: hovered
                            ToolTip.text: modelData.name
                            contentItem: ShapeIcon {
                                kind: shapeKindButton.modelData.kind
                                implicitWidth: 18
                                implicitHeight: 14
                                anchors.centerIn: parent
                                strokeColor: shapeKindButton.checked ? "#2f6fb0" : "#555555"
                                fillColor: shapeKindButton.checked ? "#cfe3f7" : "transparent"
                            }
                        }
                    }
                }
            }

            ToolSeparator { Layout.fillHeight: true; Layout.topMargin: 6; Layout.bottomMargin: 6 }

            RowLayout {
                spacing: 8
                Label { text: "Background"; opacity: 0.65 }
                Button {
                    id: bgSwatch
                    implicitWidth: 30
                    implicitHeight: 30
                    background: Rectangle {
                        color: window.bgColor
                        border.color: "#8a8a8a"
                        border.width: 1
                        radius: 4
                    }
                    onClicked: colorDialog.open()
                    ToolTip.visible: hovered
                    ToolTip.text: "Pick any background color"
                }
                ToolButton {
                    text: "↻"
                    implicitWidth: 30
                    implicitHeight: 30
                    ToolTip.visible: hovered
                    ToolTip.text: "Cycle preset backgrounds (Ctrl+B)"
                    onClicked: window.cycleBackground()
                }
            }

            Item { Layout.fillWidth: true }

            Label {
                text: "Zoom " + Math.round(canvas.zoom * 100) + "%"
                opacity: 0.75
            }

            ToolButton {
                text: "?"
                implicitWidth: 30
                implicitHeight: 30
                ToolTip.visible: hovered
                ToolTip.text: "Shortcuts & controls"
                onClicked: shortcutsPopup.open()
            }
        }
    }

    InfiniteCanvas {
        id: canvas
        anchors.fill: parent
        backgroundColor: window.bgColor
        defaultShapeWidth: window.shapeSizePresets[window.shapeSizeIndex].w
        defaultShapeHeight: window.shapeSizePresets[window.shapeSizeIndex].h
        defaultShapeKind: window.shapeKindPresets[window.shapeKindIndex].kind
    }
}
