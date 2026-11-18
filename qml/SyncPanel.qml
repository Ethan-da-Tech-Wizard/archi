// Program: archi - SyncPanel.qml
// Programmer: Ethan-da-Tech-Wizard (written with Claude, an AI assistant)
// Last Modified: 2026-11-18
// Purpose: QML dialog (Document Sync) that shows the linked notes and flow-reference documents of a project, their review state, and lets the user link, unlink, review, confirm alignment and regenerate a reference using the projectSync C++ object.

// Bound makes QML resolve ids in this file strictly, which catches mistakes earlier.
pragma ComponentBehavior: Bound

// Qt Quick basics, controls, layouts and file dialogs.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// A Dialog is a window-like panel; this one is the sync manager.
Dialog {
    id: panel
    objectName: "syncPanel"
    // The workspace (main screen) that opened this dialog; it must be supplied.
    required property var workspace
    // Path of the document row the user selected in the list.
    property string selectedPath: ""
    // Error text from the last action (shown in red).
    property string actionError: ""
    // The review token the user has ticked the agreement box for.
    property string acknowledgedToken: ""
    // The list of linked documents taken from the sync report.
    readonly property var rows: projectSync.report.files || []
    // The row for the selected path (or null).
    readonly property var selectedRow: rows.find(row => row.path === selectedPath) || null
    // Its token, a fingerprint proving the user saw current information.
    readonly property string selectedToken: selectedRow ? selectedRow.token : ""
    // The generated reference preview (current text and proposed text).
    property var preview: ({})
    // Whether a new link is for notes or a flow reference.
    property string linkRole: "notes"
    title: "Document Sync"
    // Show it on top of the window, centered, blocking the rest.
    parent: Overlay.overlay
    modal: true
    anchors.centerIn: parent
    // Size to the workspace with a 24 pixel margin, up to a maximum.
    width: Math.min(780, workspace.width - 24)
    height: Math.min(640, workspace.height - 24)
    standardButtons: Dialog.Close
    // Selecting a different row clears the agreement checkbox.
    onSelectedTokenChanged: acknowledgement.checked = false
    // When opened, save pending edits to the sync draft, refresh the report and clear errors.
    onOpened: { workspace.refreshSyncDraft(); projectSync.refresh(); actionError = "" }

    // Show an error from an action result and return whether it succeeded.
    function handle(result) {
        actionError = result.ok ? "" : result.error
        return result.ok
    }
    // Start linking a document: needs a saved project, then opens the file picker.
    function startLink(role) {
        if (!String(workspace.documentUrl)) { actionError = "Save the project first"; return }
        linkRole = role
        linkPicker.open()
    }
    // Ask for a preview of the generated reference and open the preview dialog if it works.
    function openPreview() {
        workspace.refreshSyncDraft()
        const result = projectSync.previewReference(selectedPath)
        if (!handle(result)) return
        preview = result
        replaceAcknowledgement.checked = false
        previewTabs.currentIndex = 0
        previewDialog.open()
    }

    // Reusable small icon button used in this dialog.
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

    // The dialog body, stacked vertically.
    contentItem: ColumnLayout {
        spacing: 8
        // Top row: summary text and three icon buttons (link, refresh, save).
        RowLayout {
            Layout.fillWidth: true
            Label {
                objectName: "syncSummary"
                Layout.fillWidth: true
                text: projectSync.report.summary || "Documents not linked"
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                // Green when everything is current, red otherwise.
                color: projectSync.report.state === "current" ? "#17634b" : "#9a372d"
            }
            // The link button opens a menu to choose notes or flow reference.
            SyncTool { glyph: "insert-link"; tip: "Link document"; onClicked: linkMenu.popup() }
            SyncTool { glyph: "view-refresh"; tip: "Check sync status"; onClicked: { workspace.refreshSyncDraft(); projectSync.refresh() } }
            SyncTool { glyph: "document-save"; tip: "Save diagram"; enabled: workspace.dirty || workspace.inspectorDirty || workspace.edgeDirty; onClicked: workspace.saveDocument() }
        }
        // List of linked documents, one row each.
        ListView {
            id: fileList
            objectName: "syncFileList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 76
            clip: true
            model: panel.rows
            ScrollBar.vertical: ScrollBar {}
            // Each row is clickable and highlights when selected.
            delegate: ItemDelegate {
                required property var modelData
                width: fileList.width
                height: 62
                highlighted: panel.selectedPath === modelData.path
                onClicked: { panel.selectedPath = modelData.path; panel.actionError = "" }
                background: Rectangle {
                    color: panel.selectedPath === modelData.path ? "#e6eef8" : "#f7f8fa"
                    border.width: panel.selectedPath === modelData.path ? 1 : 0
                    border.color: "#7197c1"
                }
                // Row text: file name and its review state.
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
                // Hovering shows the full path and last review time.
                ToolTip.visible: hovered
                ToolTip.text: modelData.path + "\n" + (modelData.reviewedAt ? "Last review: " + modelData.reviewedAt : "Not reviewed")
            }
            // Message shown when nothing is linked yet.
            Label { anchors.centerIn: parent; visible: panel.rows.length === 0; text: "No linked documents" }
        }
        // Shows the selected document's last review time.
        Label {
            Layout.fillWidth: true
            text: panel.selectedRow ? "Last review: " + (panel.selectedRow.reviewedAt || "None") : ""
            visible: !!panel.selectedRow
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }
        // Warning when the diagram has unsaved changes.
        Label {
            Layout.fillWidth: true
            visible: projectSync.report.unsaved || workspace.syncDraftPending
            text: "Unsaved diagram changes"
            color: "#9a372d"
        }
        // Action row for the selected document: open it, unlink it, preview a generated reference.
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
                enabled: !projectSync.report.unsaved && !workspace.syncDraftPending && !projectSync.report.error
                onClicked: panel.openPreview()
            }
            Item { Layout.fillWidth: true }
        }
        // The user must tick this box to say the diagram and document agree before confirming.
        CheckBox {
            id: acknowledgement
            objectName: "syncAcknowledgement"
            visible: !!panel.selectedRow
            text: "Diagram and document agree"
            onCheckedChanged: panel.acknowledgedToken = checked ? panel.selectedToken : ""
            enabled: !projectSync.report.unsaved && !workspace.syncDraftPending && !projectSync.report.error
                && !!panel.selectedRow && !panel.selectedRow.error
        }
        // Records the review in the manifest using the token the user saw.
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
        // Shows the most recent error message, if any.
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

    // Menu for choosing what kind of document to link.
    Menu {
        id: linkMenu
        popupType: Popup.Item
        MenuItem { text: "Link notes"; onTriggered: panel.startLink("notes") }
        MenuItem { text: "Link flow reference"; onTriggered: panel.startLink("reference") }
    }
    // File picker for Markdown and text documents; links each chosen file in turn and stops at the first error.
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
    // Confirmation dialog before unlinking.
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
    // Preview dialog with two tabs: the current document and the text generated from the diagram.
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
            // Tabs switch between the current and proposed text.
            TabBar {
                id: previewTabs
                Layout.fillWidth: true
                TabButton { text: "Current document" }
                TabButton { text: "From diagram" }
            }
            // Read-only, selectable monospace text view of the chosen tab.
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
            // The user must tick this before the document is replaced; a backup is kept by the C++ code.
            CheckBox { id: replaceAcknowledgement; text: "Replace document; keep backup" }
            Button {
                objectName: "writeReference"
                text: "Update reference"
                enabled: replaceAcknowledgement.checked
                onClicked: {
                    // Write the new reference, close the dialog either way, and clear the tick if it failed.
                    panel.workspace.refreshSyncDraft()
                    if (panel.handle(projectSync.writeReference(panel.preview.path, panel.preview.token))) previewDialog.close()
                    else { replaceAcknowledgement.checked = false; previewDialog.close() }
                }
            }
        }
    }
}
