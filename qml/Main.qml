// ==============================================================================
// Program: Main.qml
// Programmer: Ethan-da-Tech-Wizard
// Last Modified: November 18, 2026
// Purpose: Root application window container coordinating overall UI layout, menu bars,
//          global shortcut actions, dialog dispatchers, theme customization,
//          and project lifecycle management.
//
// How it fits: this is the BASE window type. ProjectWorkspace.qml (the window
// main.cpp loads by default) is declared as `Archi.Main { ... }`, i.e. it
// inherits everything here: the toolbar, the InfiniteCanvas (exposed as
// `diagramCanvas`), background-colour handling, shape pickers, shortcuts and
// the cheat sheet. ProjectWorkspace then adds projects, views, the inspector
// and document sync on top. Main.qml can also run alone with
// `ARCHI_ENTRY=Main ./build/archi` for a bare, unsaved board.
//
// State kept here: background colour (persisted per user in
// <config>/Archi/appearance.ini), the chosen default shape kind and size for
// new shapes (bound into the canvas at the bottom of the file).
//
// Known limits: this file alone has no open/save; the board is not persisted
// (ProjectWorkspace provides that). Toolbar icons come from the Breeze theme
// path /usr/share/icons/breeze, so on systems without it the buttons fall
// back to icon names or stay blank.
// ==============================================================================
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

// Main window. Size and title are just the first-run defaults.
ApplicationWindow {
    id: window
    width: 1280
    height: 800
    visible: true
    title: "Archi"

    // Lets other QML or tests reach the canvas by `window.diagramCanvas`.
    property alias diagramCanvas: canvas
    // Space reserved at the right edge for a side panel; the canvas shrinks by this much.
    property real canvasRightInset: 0

    // Built-in background presets (white, dark grey, warm paper) cycled by Ctrl+B.
    property var bgPresets: ["#ffffff", "#1e1e1e", "#f5f0e6"]
    // Index into bgPresets of the last preset the user cycled to.
    property int bgIndex: 0
    // Current background; initial value is the saved colour (or the default #caffee).
    property color bgColor: appearance.lastBackground
    // Saved custom colours are stored as a JSON string in the settings file;
    // a corrupt value must not break the UI, so parsing falls back to [].
    property var savedBackgrounds: {
        try { return JSON.parse(appearance.savedColors) } catch (error) { return [] }
    }
    // True when the current colour is already in the saved list (toggles the bookmark icon).
    readonly property bool backgroundSaved: savedBackgrounds.indexOf(String(bgColor)) >= 0
    // Persist every colour change immediately.
    onBgColorChanged: appearance.lastBackground = String(bgColor)

    // Per-user appearance settings in a human-editable ini file under the OS
    // config folder ("file://" form because QML Settings takes a URL).
    Settings {
        id: appearance
        location: "file://" + StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/Archi/appearance.ini"
        category: "Canvas"
        property string lastBackground: "#caffee"
        property string savedColors: '["#caffee"]'
    }

    /** Adds the current colour to the saved list, or removes it if already saved, and flushes to disk. */
    function toggleSavedBackground() {
        const color = String(bgColor)
        appearance.savedColors = JSON.stringify(backgroundSaved ? savedBackgrounds.filter(c => c !== color) : savedBackgrounds.concat([color]))
        appearance.sync()
    }
    /** Opens the system colour picker for a custom background. */
    function openBackgroundChooser() { colorDialog.open() }

    // Popup palette of presets plus saved colours (presets not repeated). Anchored near the top-right under the toolbar button.
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

    /** Steps to the next background preset, wrapping around; bound to Ctrl+B. */
    function cycleBackground() {
        bgIndex = (bgIndex + 1) % bgPresets.length
        bgColor = bgPresets[bgIndex]
    }

    // Options of the toolbar's size picker: S/M/L are the on-screen pixel size
    // (width x height) for NEW shapes, converted to world units by the canvas.
    property var shapeSizePresets: [
        { label: "S", w: 110, h: 60 },
        { label: "M", w: 160, h: 80 },
        { label: "L", w: 220, h: 110 }
    ]
    property int shapeSizeIndex: 1

    // Options of the shape-kind picker; `kind` values are the shapeKind strings
    // the canvas and ShapeItem understand, `name` is the label shown.
    property var shapeKindPresets: [
        { kind: "terminal", name: "Terminal (Elongated oval)" },
        { kind: "process", name: "Process (Rectangle)" },
        { kind: "input_output", name: "Input/Output (Parallelogram)" },
        { kind: "decision", name: "Decision (Diamond)" },
        { kind: "internal_method", name: "Internal Method (Top bar & left line)" },
        { kind: "external_method", name: "External Method (Left & right lines)" }
    ]
    property int shapeKindIndex: 0

    // Global shortcuts. Ctrl+B cycles background, F1 (StandardKey.HelpContents)
    // opens the shortcut list, F2 opens the flowchart symbol cheat sheet.
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

    // Native colour dialog used by the toolbar's colour button.
    ColorDialog {
        id: colorDialog
        title: "Choose background color"
        selectedColor: window.bgColor
        onAccepted: window.bgColor = selectedColor
    }

    // Symbol cheat sheet. Choosing a shape there selects it in the toolbar
    // picker (by matching `kind`) or loads the sample flowchart onto the canvas.
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

    // Modal help listing mouse and keyboard controls; two label columns (action, effect).
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

    // Undo/redo/duplicate shortcuts are disabled while a text box is being
    // edited so Ctrl+Z / Ctrl+D act on the text instead of the diagram.
    Shortcut { sequences: [StandardKey.Undo]; enabled: canvas.editingIndex === -1; onActivated: canvas.undo() }
    Shortcut { sequences: [StandardKey.Redo]; enabled: canvas.editingIndex === -1; onActivated: canvas.redo() }
    Shortcut { sequence: "Ctrl+D"; enabled: canvas.editingIndex === -1; onActivated: canvas.duplicateSelection() }

    // Reusable toolbar button type: icon only, with tooltip and accessible name
    // so screen readers announce it. `glyph` is a freedesktop icon name looked
    // up in the theme, falling back to the Breeze SVG with the same name.
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

    // Scrollable toolbar so it stays usable in a narrow window (horizontal flick).
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
                // Edit controls: undo/redo enable themselves from the canvas's history state.
                IconTool { glyph: "edit-undo"; tip: "Undo"; enabled: canvas.canUndo; onClicked: canvas.undo() }
                IconTool { glyph: "edit-redo"; tip: "Redo"; enabled: canvas.canRedo; onClicked: canvas.redo() }
                IconTool {
                    objectName: "deleteShape"
                    glyph: "edit-delete"; tip: "Delete selection"
                    enabled: canvas.selectedId !== -1 || canvas.selectedArrow !== -1
                    onClicked: { canvas.editingIndex = -1; canvas.deleteSelection() }
                }
                // Shape pickers: choose kind and size for the next shape placed.
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
                // View and help: fit-to-window, zoom percentage readout, cheat sheet.
                IconTool { glyph: "zoom-fit-best"; tip: "Fit diagram"; onClicked: canvas.fitView() }
                Label { text: Math.round(canvas.zoom * 100) + "%"; Layout.preferredWidth: 48; horizontalAlignment: Text.AlignHCenter }
                IconTool { glyph: "help-contents"; tip: "Flowchart symbols"; onClicked: cheatSheetPopup.open() }
                // Background colour controls: swatch opens the colour dialog; bookmark saves
                // or removes the colour; the last button opens the saved-colours palette.
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

    // The drawing surface fills the window minus any right-hand inset; its
    // colour and new-shape defaults come from the toolbar state above.
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
