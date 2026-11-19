// ==============================================================================
// Program: SyncPanel.qml
// Programmer: Ethan-da-Tech-Wizard
// Last Modified: November 18, 2026
// Purpose: UI side-panel displaying file synchronization status, conflict warnings,
//          external disk change notices, and manual reconciliation action triggers.
//
// How it fits: ProjectWorkspace.qml declares it as `syncPanel` (workspace:
// board) and opens it from the sync status button. All data comes from the
// C++ object `projectSync` (DocumentSync.h): the `report` property drives the
// list and status text, and the methods linkDocument, unlinkDocument,
// confirmAlignment, previewReference and writeReference perform actions and
// return `{ok, error?}` maps that handle() turns into the red error line.
//
// Safety design: every action passes the per-row `token` the user was shown.
// If the files changed since, C++ refuses and asks for a new review. The
// "Diagram and document agree" checkbox must be ticked for the CURRENT token;
// switching rows or any change resets it (see onSelectedTokenChanged), so a
// stale tick can never confirm a different state. Writing a reference file
// needs a second explicit tick and always keeps a .sync.bak backup.
//
// `pragma ComponentBehavior: Bound` (below) binds delegates and inline
// components to the enclosing component's ids, so they can use `panel.` etc.
// safely and the Qt compiler can optimise them; per-item data must then come
// in through `required property` (see `required property var modelData`).
// ==============================================================================
// See the file header: bound ids in delegates, required properties for per-item data.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// Modal dialog sized to the workspace (never larger than 780 x 640) so it
// remains usable in a small window.
Dialog {
    id: panel
    objectName: "syncPanel"
    // The board/workspace item: used for its size, `documentUrl`, dirty flags
    // and refreshSyncDraft()/saveDocument().
    required property var workspace
    // Path of the selected linked document (key into the report's files).
    property string selectedPath: ""
    // Last action's error text shown in red; cleared when a new row is chosen.
    property string actionError: ""
    // Token the user ticked "agree" for; only this exact token is sent to C++.
    property string acknowledgedToken: ""
    // Live list of rows from the C++ report; `|| []` covers the moment before the first report.
    readonly property var rows: projectSync.report.files || []
    // Row object for selectedPath, or null if that link disappeared (e.g. unlinked elsewhere).
    readonly property var selectedRow: rows.find(row => row.path === selectedPath) || null
    // Token of the selected row; changes whenever any watched file changes.
    readonly property string selectedToken: selectedRow ? selectedRow.token : ""
    // Result of previewReference ({current, proposed, path, token}) shown in the preview dialog.
    property var preview: ({})
    // "notes" or "reference": role given to documents chosen in the link picker.
    property string linkRole: "notes"
    // Modal overlay on top of the whole window; width/height leave a 12 px margin each side.
    title: "Document Sync"
    parent: Overlay.overlay
    modal: true
    anchors.centerIn: parent
    width: Math.min(780, workspace.width - 24)
    height: Math.min(640, workspace.height - 24)
    standardButtons: Dialog.Close
    // A new token means the files changed: drop any previous "agree" tick.
    onSelectedTokenChanged: acknowledgement.checked = false
    // On open, push unsaved UI edits into the sync engine first (so "unsaved"
    // is accurate) then recompute the report.
    onOpened: { workspace.refreshSyncDraft(); projectSync.refresh(); actionError = "" }

    /**
     * Shows an action's outcome and reports success.
     * @param result `{ok:boolean, error?:string}` returned by a projectSync method.
     * @returns {boolean} the `ok` flag, so callers can stop on failure.
     */
    function handle(result) {
        actionError = result.ok ? "" : result.error
        return result.ok
    }
    /**
     * Opens the file picker for a new link.
     * @param role "notes" or "reference".
     * Refuses until the project has a file on disk, because links are stored
     * relative to the project folder.
     */
    function startLink(role) {
        if (!String(workspace.documentUrl)) { actionError = "Save the project first"; return }
        linkRole = role
        linkPicker.open()
    }
    /**
     * Asks C++ for a generated flow reference and opens the preview dialog.
     * Does nothing visible if C++ refuses (the reason appears in actionError).
     */
    function openPreview() {
        workspace.refreshSyncDraft()
        const result = projectSync.previewReference(selectedPath)
        if (!handle(result)) return
        preview = result
        replaceAcknowledgement.checked = false
        previewTabs.currentIndex = 0
        previewDialog.open()
    }

    // Small icon-only toolbar button with tooltip and accessible name; icons are
    // looked up by theme name with the Breeze SVG path as a fallback.
    component SyncTool: ToolButton {
        property string glyph
        property string tip
        implicitWidth: 34
        implicitHeight: 34
        display: AbstractButton.IconOnly
        icon.name: glyph
        icon.source: "file:///usr/share/icons/breeze/actions/22/" + glyph + ".svg"
        ToolTip.visible: hovered
        ToolTip.text: tip
        Accessible.name: tip
    }

    // Layout: summary row, file list, details, then review controls and errors.
    contentItem: ColumnLayout {
        spacing: 8
        // Top row: overall status (green when current, red otherwise) and actions:
        // link menu, manual refresh, save diagram.
        RowLayout {
            Layout.fillWidth: true
            Label {
                objectName: "syncSummary"
                Layout.fillWidth: true
                text: projectSync.report.summary || "Documents not linked"
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: projectSync.report.state === "current" ? "#17634b" : "#9a372d"
            }
            SyncTool { glyph: "insert-link"; tip: "Link document"; onClicked: linkMenu.popup() }
            SyncTool { glyph: "view-refresh"; tip: "Check sync status"; onClicked: { workspace.refreshSyncDraft(); projectSync.refresh() } }
            // Save is enabled only when something is unsaved, including edits still
            // sitting in the inspector or arrow editor.
            SyncTool { glyph: "document-save"; tip: "Save diagram"; enabled: workspace.dirty || workspace.inspectorDirty || workspace.edgeDirty; onClicked: workspace.saveDocument() }
        }
        // One row per linked document; `modelData` is the report row map.
        ListView {
            id: fileList
            objectName: "syncFileList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 76
            clip: true
            model: panel.rows
            ScrollBar.vertical: ScrollBar {}
            delegate: ItemDelegate {
                required property var modelData
                width: fileList.width
                height: 62
                highlighted: panel.selectedPath === modelData.path
                // Clicking selects the row and clears any old error.
                onClicked: { panel.selectedPath = modelData.path; panel.actionError = "" }
                background: Rectangle {
                    color: panel.selectedPath === modelData.path ? "#e6eef8" : "#f7f8fa"
                    border.width: panel.selectedPath === modelData.path ? 1 : 0
                    border.color: "#7197c1"
                }
                contentItem: ColumnLayout {
                    spacing: 2
                    Label { Layout.fillWidth: true; text: modelData.name; textFormat: Text.PlainText; elide: Text.ElideMiddle; font.bold: true }
                    Label {
                        Layout.fillWidth: true
                        text: modelData.label + (modelData.role === "reference" ? " - Flow reference" : "")
                        textFormat: Text.PlainText
                        color: modelData.state === "current" ? "#17634b" : "#9a372d"
                        elide: Text.ElideRight
                    }
                }
                // Tooltip shows the full path and when it was last reviewed.
                ToolTip.visible: hovered
                ToolTip.text: modelData.path + "\n" + (modelData.reviewedAt ? "Last review: " + modelData.reviewedAt : "Not reviewed")
            }
            // Empty-state message.
            Label { anchors.centerIn: parent; visible: panel.rows.length === 0; text: "No linked documents" }
        }
        // Details of the selected row.
        Label {
            Layout.fillWidth: true
            text: panel.selectedRow ? "Last review: " + (panel.selectedRow.reviewedAt || "None") : ""
            visible: !!panel.selectedRow
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }
        // Warns the review controls are blocked until the diagram is saved.
        Label {
            Layout.fillWidth: true
            visible: projectSync.report.unsaved || workspace.syncDraftPending
            text: "Unsaved diagram changes"
            color: "#9a372d"
        }
        // Row actions: open in the default app, unlink (asks for confirmation), and
        // preview regeneration (only for "reference" role documents).
        RowLayout {
            Layout.fillWidth: true
            visible: !!panel.selectedRow
            SyncTool {
                glyph: "document-edit"; tip: "Open linked document"
                enabled: !!panel.selectedRow && !panel.selectedRow.error
                onClicked: Qt.openUrlExternally(panel.selectedRow.url)
            }
            SyncTool { glyph: "edit-delete"; tip: "Unlink document"; onClicked: unlinkDialog.open() }
            Button {
                text: "Preview reference"
                visible: !!panel.selectedRow && panel.selectedRow.role === "reference"
                // Preview is blocked while anything is unsaved or errored: the generated
                // text must come from the saved diagram the user sees.
                enabled: !projectSync.report.unsaved && !workspace.syncDraftPending && !projectSync.report.error
                onClicked: panel.openPreview()
            }
            Item { Layout.fillWidth: true }
        }
        // Review gate: ticking records the current token; disabled whenever the
        // state is not safe to confirm (unsaved diagram, report/row errors).
        CheckBox {
            id: acknowledgement
            objectName: "syncAcknowledgement"
            visible: !!panel.selectedRow
            text: "Diagram and document agree"
            onCheckedChanged: panel.acknowledgedToken = checked ? panel.selectedToken : ""
            enabled: !projectSync.report.unsaved && !workspace.syncDraftPending && !projectSync.report.error
                && !!panel.selectedRow && !panel.selectedRow.error
        }
        // Sends the token the user ticked (captured before refresh) so that a change
        // between tick and click is detected by C++ and rejected.
        Button {
            objectName: "confirmAlignment"
            text: "Confirm alignment"
            visible: !!panel.selectedRow
            enabled: acknowledgement.checked && acknowledgement.enabled
            onClicked: {
                const reviewedToken = panel.acknowledgedToken
                workspace.refreshSyncDraft()
                panel.handle(projectSync.confirmAlignment(panel.selectedPath, reviewedToken))
                acknowledgement.checked = false
            }
        }
        // Error line: action error first, otherwise the selected row's own error.
        Label {
            Layout.fillWidth: true
            Layout.maximumHeight: 65
            visible: !!text
            text: panel.actionError || (panel.selectedRow ? panel.selectedRow.error : "")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            color: "#a32330"
        }
    }

    // Menu for the "Link document" tool button.
    Menu {
        id: linkMenu
        popupType: Popup.Item
        MenuItem { text: "Link notes"; onTriggered: panel.startLink("notes") }
        MenuItem { text: "Link flow reference"; onTriggered: panel.startLink("reference") }
    }
    // Picker limited to Markdown/text; several files can be linked at once and
    // the loop stops at the first failure so its error stays visible.
    FileDialog {
        id: linkPicker
        title: panel.linkRole === "reference" ? "Link Flow Reference" : "Link Notes"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Documents (*.md *.txt)"]
        currentFolder: boardFiles.folder(panel.workspace.documentUrl)
        onAccepted: {
            for (const file of selectedFiles)
                if (!panel.handle(projectSync.linkDocument(file, panel.linkRole))) break
        }
    }
    // Confirmation before removing a link (the document itself is not deleted).
    Dialog {
        id: unlinkDialog
        parent: Overlay.overlay
        title: "Unlink this document?"
        anchors.centerIn: parent
        width: Math.min(360, panel.workspace.width - 24)
        modal: true
        standardButtons: Dialog.Yes | Dialog.Cancel
        contentItem: Label { text: panel.selectedRow ? panel.selectedRow.name : ""; textFormat: Text.PlainText; wrapMode: Text.Wrap }
        onAccepted: panel.handle(projectSync.unlinkDocument(panel.selectedPath, panel.selectedToken))
    }
    // Preview dialog: tabs compare the document on disk against the text that
    // would replace it.
    Dialog {
        id: previewDialog
        parent: Overlay.overlay
        objectName: "referencePreview"
        title: "Flow Reference Preview"
        anchors.centerIn: parent
        width: Math.min(820, panel.workspace.width - 24)
        height: Math.min(670, panel.workspace.height - 24)
        modal: true
        standardButtons: Dialog.Close
        contentItem: ColumnLayout {
            spacing: 8
            TabBar {
                id: previewTabs
                Layout.fillWidth: true
                TabButton { text: "Current document" }
                TabButton { text: "From diagram" }
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 80
                TextArea {
                    readOnly: true
                    selectByMouse: true
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.Wrap
                    font.family: "monospace"
                    text: (previewTabs.currentIndex === 0 ? panel.preview.current : panel.preview.proposed) || ""
                }
            }
            // Second explicit consent for overwriting; the old content is kept as .sync.bak.
            CheckBox { id: replaceAcknowledgement; text: "Replace document; keep backup" }
            // Writing needs the checkbox. After either outcome the dialog closes; on
            // failure the tick is cleared so the user must consciously retry.
            Button {
                objectName: "writeReference"
                text: "Update reference"
                enabled: replaceAcknowledgement.checked
                onClicked: {
                    panel.workspace.refreshSyncDraft()
                    if (panel.handle(projectSync.writeReference(panel.preview.path, panel.preview.token))) previewDialog.close()
                    else { replaceAcknowledgement.checked = false; previewDialog.close() }
                }
            }
        }
    }
}
