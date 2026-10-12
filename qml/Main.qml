import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

ApplicationWindow {
    id: window
    width: 1280
    height: 800
    visible: true
    title: "Archi"

    property alias diagramCanvas: canvas
    property real canvasRightInset: 0

    property var bgPresets: ["#ffffff", "#1e1e1e", "#f5f0e6"]
    property int bgIndex: 0
    property color bgColor: appearance.lastBackground
    property var savedBackgrounds: {
        try { return JSON.parse(appearance.savedColors) } catch (error) { return [] }
    }
    readonly property bool backgroundSaved: savedBackgrounds.indexOf(String(bgColor)) >= 0
    onBgColorChanged: appearance.lastBackground = String(bgColor)

    Settings {
        id: appearance
        location: "file://" + StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/Archi/appearance.ini"
        category: "Canvas"
        property string lastBackground: "#caffee"
        property string savedColors: '["#caffee"]'
    }

    function toggleSavedBackground() {
        const color = String(bgColor)
        appearance.savedColors = JSON.stringify(backgroundSaved ? savedBackgrounds.filter(c => c !== color) : savedBackgrounds.concat([color]))
        appearance.sync()
    }
    function openBackgroundChooser() { colorDialog.open() }

    Popup {
        id: colorPalette
        x: Math.max(8, window.width - width - 12)
        y: 4
        padding: 10
        GridLayout {
            columns: 4
            Repeater {
                model: window.bgPresets.concat(window.savedBackgrounds.filter(c => window.bgPresets.indexOf(c) < 0))
                delegate: ToolButton {
                    required property string modelData
                    implicitWidth: 34
                    implicitHeight: 34
                    background: Rectangle { color: modelData; radius: 3; border.color: "#687580"; border.width: window.bgColor == modelData ? 3 : 1 }
                    ToolTip.visible: hovered
                    ToolTip.text: modelData.toUpperCase()
                    onClicked: { window.bgColor = modelData; colorPalette.close() }
                }
            }
        }
    }

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
        { kind: "terminal", name: "Terminal (Elongated oval)" },
        { kind: "process", name: "Process (Rectangle)" },
        { kind: "input_output", name: "Input/Output (Parallelogram)" },
        { kind: "decision", name: "Decision (Diamond)" },
        { kind: "internal_method", name: "Internal Method (Top bar & left line)" },
        { kind: "external_method", name: "External Method (Left & right lines)" }
    ]
    property int shapeKindIndex: 0

    Shortcut {
        sequence: "Ctrl+B"
        onActivated: window.cycleBackground()
    }
    Shortcut {
        sequences: [StandardKey.HelpContents]
        onActivated: shortcutsPopup.open()
    }
    Shortcut {
        sequence: "F2"
        onActivated: cheatSheetPopup.open()
    }

    ColorDialog {
        id: colorDialog
        title: "Choose background color"
        selectedColor: window.bgColor
        onAccepted: window.bgColor = selectedColor
    }

    CheatSheetPopup {
        id: cheatSheetPopup
        onSelectShapeKind: (kind) => {
            for (var i = 0; i < window.shapeKindPresets.length; i++) {
                if (window.shapeKindPresets[i].kind === kind) {
                    window.shapeKindIndex = i
                    break
                }
            }
        }
        onLoadSampleFlowchart: canvas.loadSampleDiagram()
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
                Label { text: "New shape (using selected toolbar shape/size)" }
                Label { text: "Double-click a shape"; opacity: 0.7 }
                Label { text: "Edit its text" }
                Label { text: "Esc"; opacity: 0.7 }
                Label { text: "Exit text editing" }
                Label { text: "Drag a shape"; opacity: 0.7 }
                Label { text: "Move it" }
                Label { text: "Drag the blue dot on a shape"; opacity: 0.7 }
                Label { text: "Draw a flowline arrow to another shape" }
                Label { text: "Drag empty canvas"; opacity: 0.7 }
                Label { text: "Pan" }
                Label { text: "Scroll wheel"; opacity: 0.7 }
                Label { text: "Zoom in/out (centered on cursor)" }
                Label { text: "Ctrl+B"; opacity: 0.7 }
                Label { text: "Cycle background presets" }
                Label { text: "F2"; opacity: 0.7 }
                Label { text: "Open Flowchart Cheat Sheet" }
                Label { text: "F1 / ?"; opacity: 0.7 }
                Label { text: "Show shortcuts popup" }
            }
            Button {
                text: "Close"
                Layout.alignment: Qt.AlignRight
                onClicked: shortcutsPopup.close()
            }
        }
    }

    Shortcut { sequences: [StandardKey.Undo]; enabled: canvas.editingIndex === -1; onActivated: canvas.undo() }
    Shortcut { sequences: [StandardKey.Redo]; enabled: canvas.editingIndex === -1; onActivated: canvas.redo() }
    Shortcut { sequence: "Ctrl+D"; enabled: canvas.editingIndex === -1; onActivated: canvas.duplicateSelection() }

    component IconTool: ToolButton {
        property string glyph
        property string tip
        implicitWidth: 36
        implicitHeight: 36
        icon.name: glyph
        icon.source: "file:///usr/share/icons/breeze/actions/22/" + glyph + ".svg"
        display: AbstractButton.IconOnly
        ToolTip.visible: hovered
        ToolTip.text: tip
        Accessible.name: tip
    }

    header: ToolBar {
        implicitHeight: 44
        Flickable {
            anchors.fill: parent
            contentWidth: toolbarRow.width
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            RowLayout {
                id: toolbarRow
                height: parent.height
                spacing: 3
                Label { text: "Archi"; font.bold: true; font.pixelSize: 16; leftPadding: 10; rightPadding: 8 }
                IconTool { glyph: "edit-undo"; tip: "Undo"; enabled: canvas.canUndo; onClicked: canvas.undo() }
                IconTool { glyph: "edit-redo"; tip: "Redo"; enabled: canvas.canRedo; onClicked: canvas.redo() }
                IconTool {
                    objectName: "deleteShape"
                    glyph: "edit-delete"; tip: "Delete selection"
                    enabled: canvas.selectedId !== -1 || canvas.selectedArrow !== -1
                    onClicked: { canvas.editingIndex = -1; canvas.deleteSelection() }
                }
                ToolSeparator {}
                ComboBox {
                    implicitWidth: 150
                    model: window.shapeKindPresets
                    textRole: "name"
                    currentIndex: window.shapeKindIndex
                    onActivated: window.shapeKindIndex = currentIndex
                }
                ComboBox {
                    implicitWidth: 62
                    model: window.shapeSizePresets
                    textRole: "label"
                    currentIndex: window.shapeSizeIndex
                    onActivated: window.shapeSizeIndex = currentIndex
                }
                IconTool { glyph: "zoom-fit-best"; tip: "Fit diagram"; onClicked: canvas.fitView() }
                Label { text: Math.round(canvas.zoom * 100) + "%"; Layout.preferredWidth: 48; horizontalAlignment: Text.AlignHCenter }
                IconTool { glyph: "help-contents"; tip: "Flowchart symbols"; onClicked: cheatSheetPopup.open() }
                ToolButton {
                    implicitWidth: 36; implicitHeight: 36
                    contentItem: Rectangle { implicitWidth: 22; implicitHeight: 22; color: window.bgColor; border.color: "#888888"; radius: 3 }
                    onClicked: colorDialog.open()
                    ToolTip.visible: hovered; ToolTip.text: "Background color"
                }
                IconTool { glyph: window.backgroundSaved ? "bookmarks-bookmarked" : "bookmark-new"; tip: window.backgroundSaved ? "Remove saved color" : "Save current color"; onClicked: window.toggleSavedBackground() }
                IconTool { glyph: "bookmarks"; tip: "Saved background colors"; onClicked: colorPalette.open() }
            }
        }
    }

    InfiniteCanvas {
        id: canvas
        anchors.fill: parent
        anchors.rightMargin: window.canvasRightInset
        backgroundColor: window.bgColor
        defaultShapeWidth: window.shapeSizePresets[window.shapeSizeIndex].w
        defaultShapeHeight: window.shapeSizePresets[window.shapeSizeIndex].h
        defaultShapeKind: window.shapeKindPresets[window.shapeKindIndex].kind
    }
}
