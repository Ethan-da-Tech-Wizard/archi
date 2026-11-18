// Program: archi - Main.qml
// Programmer: Ethan-da-Tech-Wizard (written with Claude, an AI assistant)
// Last Modified: 2026-11-18
// Purpose: Original single-window QML shell for Archi: toolbar, background color presets and saved colors, shape kind and size pickers, shortcut and cheat-sheet popups, and one InfiniteCanvas filling the window.

// Qt Quick basics, controls, layouts, file/color dialogs and QtCore (for saved settings).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

// The top-level application window.
ApplicationWindow {
    id: window
    width: 1280
    height: 800
    visible: true
    title: "Archi"

    // Let other files reach the canvas through window.diagramCanvas.
    property alias diagramCanvas: canvas
    // Space on the right that the canvas leaves free (used for a side panel).
    property real canvasRightInset: 0

    // The built-in background color choices: white, dark gray and a cream tone.
    property var bgPresets: ["#ffffff", "#1e1e1e", "#f5f0e6"]
    // Which preset Ctrl+B is currently on.
    property int bgIndex: 0
    // The current background color, remembered between runs in the appearance settings.
    property color bgColor: appearance.lastBackground
    // Colors the user bookmarked, read from the saved JSON text (an empty list if it cannot be read).
    property var savedBackgrounds: {
        try { return JSON.parse(appearance.savedColors) } catch (error) { return [] }
    }
    // True when the current color is already in the saved list.
    readonly property bool backgroundSaved: savedBackgrounds.indexOf(String(bgColor)) >= 0
    // Whenever the color changes, store it in the settings.
    onBgColorChanged: appearance.lastBackground = String(bgColor)

    // Settings saves values to a small .ini file in the user's config folder under Archi.
    Settings {
        id: appearance
        location: "file://" + StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/Archi/appearance.ini"
        category: "Canvas"
        property string lastBackground: "#caffee"
        property string savedColors: '["#caffee"]'
    }

    // Add the current color to the saved list, or remove it if already saved, and write the settings.
    function toggleSavedBackground() {
        const color = String(bgColor)
        appearance.savedColors = JSON.stringify(backgroundSaved ? savedBackgrounds.filter(c => c !== color) : savedBackgrounds.concat([color]))
        appearance.sync()
    }
    // Open the color picker dialog.
    function openBackgroundChooser() { colorDialog.open() }

    // A small popup with one swatch button per preset or saved color; the current one gets a thicker border.
    Popup {
        id: colorPalette
        x: Math.max(8, window.width - width - 12)
        y: 4
        padding: 10
        GridLayout {
            columns: 4
            Repeater {
                // Presets first, then saved colors that are not already presets.
                model: window.bgPresets.concat(window.savedBackgrounds.filter(c => window.bgPresets.indexOf(c) < 0))
                delegate: ToolButton {
                    required property string modelData
                    implicitWidth: 34
                    implicitHeight: 34
                    background: Rectangle { color: modelData; radius: 3; border.color: "#687580"; border.width: window.bgColor == modelData ? 3 : 1 }
                    ToolTip.visible: hovered
                    ToolTip.text: modelData.toUpperCase()
                    // Picking a swatch sets the background and closes the popup.
                    onClicked: { window.bgColor = modelData; colorPalette.close() }
                }
            }
        }
    }

    // Move to the next preset, wrapping back to the first.
    function cycleBackground() {
        bgIndex = (bgIndex + 1) % bgPresets.length
        bgColor = bgPresets[bgIndex]
    }

    // Shape size choices (S, M, L) in canvas pixels, and the one currently picked (M).
    property var shapeSizePresets: [
        { label: "S", w: 110, h: 60 },
        { label: "M", w: 160, h: 80 },
        { label: "L", w: 220, h: 110 }
    ]
    property int shapeSizeIndex: 1

    // Shape kinds offered in the toolbar drop-down; kind is the internal id, name is what the user sees.
    property var shapeKindPresets: [
        { kind: "terminal", name: "Terminal (Elongated oval)" },
        { kind: "process", name: "Process (Rectangle)" },
        { kind: "input_output", name: "Input/Output (Parallelogram)" },
        { kind: "decision", name: "Decision (Diamond)" },
        { kind: "internal_method", name: "Internal Method (Top bar & left line)" },
        { kind: "external_method", name: "External Method (Left & right lines)" }
    ]
    property int shapeKindIndex: 0

    // Keyboard shortcuts: Ctrl+B cycles background, help key opens the shortcuts popup, F2 opens the cheat sheet.
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

    // Color chooser dialog; accepting it sets the background.
    ColorDialog {
        id: colorDialog
        title: "Choose background color"
        selectedColor: window.bgColor
        onAccepted: window.bgColor = selectedColor
    }

    // The cheat sheet; picking a symbol there selects it in the toolbar.
    CheatSheetPopup {
        id: cheatSheetPopup
        // Find the matching kind in the presets and select it.
        onSelectShapeKind: (kind) => {
            for (var i = 0; i < window.shapeKindPresets.length; i++) {
                if (window.shapeKindPresets[i].kind === kind) {
                    window.shapeKindIndex = i
                    break
                }
            }
        }
        // Ask the canvas to build the sample flowchart.
        onLoadSampleFlowchart: canvas.loadSampleDiagram()
    }

    // Popup that lists the shortcuts and mouse controls in two columns (description, action).
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

    // Undo, redo and duplicate shortcuts are disabled while a shape's text is being edited.
    Shortcut { sequences: [StandardKey.Undo]; enabled: canvas.editingIndex === -1; onActivated: canvas.undo() }
    Shortcut { sequences: [StandardKey.Redo]; enabled: canvas.editingIndex === -1; onActivated: canvas.redo() }
    Shortcut { sequence: "Ctrl+D"; enabled: canvas.editingIndex === -1; onActivated: canvas.duplicateSelection() }

    // Reusable toolbar button type that shows a themed icon and a tooltip.
    component IconTool: ToolButton {
        property string glyph
        property string tip
        implicitWidth: 36
        implicitHeight: 36
        icon.name: glyph
        // Fallback icon path on systems that have the Breeze icon theme.
        icon.source: "file:///usr/share/icons/breeze/actions/22/" + glyph + ".svg"
        display: AbstractButton.IconOnly
        ToolTip.visible: hovered
        ToolTip.text: tip
        Accessible.name: tip
    }

    // The toolbar at the top; it scrolls sideways if the window is narrow.
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
                // Undo and redo buttons turn on/off with the canvas history.
                IconTool { glyph: "edit-undo"; tip: "Undo"; enabled: canvas.canUndo; onClicked: canvas.undo() }
                IconTool { glyph: "edit-redo"; tip: "Redo"; enabled: canvas.canRedo; onClicked: canvas.redo() }
                // Delete button: stops text editing, then deletes the selected shape or arrow.
                IconTool {
                    objectName: "deleteShape"
                    glyph: "edit-delete"; tip: "Delete selection"
                    enabled: canvas.selectedId !== -1 || canvas.selectedArrow !== -1
                    onClicked: { canvas.editingIndex = -1; canvas.deleteSelection() }
                }
                // A thin vertical divider.
                ToolSeparator {}
                // Drop-down for the shape kind that new shapes will use.
                ComboBox {
                    implicitWidth: 150
                    model: window.shapeKindPresets
                    textRole: "name"
                    currentIndex: window.shapeKindIndex
                    onActivated: window.shapeKindIndex = currentIndex
                }
                // Drop-down for the size of new shapes.
                ComboBox {
                    implicitWidth: 62
                    model: window.shapeSizePresets
                    textRole: "label"
                    currentIndex: window.shapeSizeIndex
                    onActivated: window.shapeSizeIndex = currentIndex
                }
                // Fit the whole diagram in view and show the current zoom percent.
                IconTool { glyph: "zoom-fit-best"; tip: "Fit diagram"; onClicked: canvas.fitView() }
                Label { text: Math.round(canvas.zoom * 100) + "%"; Layout.preferredWidth: 48; horizontalAlignment: Text.AlignHCenter }
                IconTool { glyph: "help-contents"; tip: "Flowchart symbols"; onClicked: cheatSheetPopup.open() }
                // Button showing the current background color; opens the color dialog.
                ToolButton {
                    implicitWidth: 36; implicitHeight: 36
                    contentItem: Rectangle { implicitWidth: 22; implicitHeight: 22; color: window.bgColor; border.color: "#888888"; radius: 3 }
                    onClicked: colorDialog.open()
                    ToolTip.visible: hovered; ToolTip.text: "Background color"
                }
                // Bookmark buttons: save/remove the current color, and open the saved-colors popup.
                IconTool { glyph: window.backgroundSaved ? "bookmarks-bookmarked" : "bookmark-new"; tip: window.backgroundSaved ? "Remove saved color" : "Save current color"; onClicked: window.toggleSavedBackground() }
                IconTool { glyph: "bookmarks"; tip: "Saved background colors"; onClicked: colorPalette.open() }
            }
        }
    }

    // The drawing canvas fills the window and takes its background and new-shape defaults from the toolbar choices.
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
