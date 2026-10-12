pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

Dialog {
    id: panel
    objectName: "syncPanel"
    required property var workspace
    property string selectedPath: ""
    property string actionError: ""
    property string acknowledgedToken: ""
    readonly property var rows: projectSync.report.files || []
    readonly property var selectedRow: rows.find(row => row.path === selectedPath) || null
    readonly property string selectedToken: selectedRow ? selectedRow.token : ""
    property var preview: ({})
    property string linkRole: "notes"
    title: "Document Sync"
    parent: Overlay.overlay
    modal: true
    anchors.centerIn: parent
    width: Math.min(780, workspace.width - 24)
    height: Math.min(640, workspace.height - 24)
    standardButtons: Dialog.Close
    onSelectedTokenChanged: acknowledgement.checked = false
    onOpened: { workspace.refreshSyncDraft(); projectSync.refresh(); actionError = "" }

    function handle(result) {
        actionError = result.ok ? "" : result.error
        return result.ok
    }
    function startLink(role) {
        if (!String(workspace.documentUrl)) { actionError = "Save the project first"; return }
        linkRole = role
        linkPicker.open()
    }
    function openPreview() {
        workspace.refreshSyncDraft()
        const result = projectSync.previewReference(selectedPath)
        if (!handle(result)) return
        preview = result
        replaceAcknowledgement.checked = false
        previewTabs.currentIndex = 0
        previewDialog.open()
    }

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

    contentItem: ColumnLayout {
        spacing: 8
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
            SyncTool { glyph: "document-save"; tip: "Save diagram"; enabled: workspace.dirty || workspace.inspectorDirty || workspace.edgeDirty; onClicked: workspace.saveDocument() }
        }
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
                ToolTip.visible: hovered
                ToolTip.text: modelData.path + "\n" + (modelData.reviewedAt ? "Last review: " + modelData.reviewedAt : "Not reviewed")
            }
            Label { anchors.centerIn: parent; visible: panel.rows.length === 0; text: "No linked documents" }
        }
        Label {
            Layout.fillWidth: true
            text: panel.selectedRow ? "Last review: " + (panel.selectedRow.reviewedAt || "None") : ""
            visible: !!panel.selectedRow
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }
        Label {
            Layout.fillWidth: true
            visible: projectSync.report.unsaved || workspace.syncDraftPending
            text: "Unsaved diagram changes"
            color: "#9a372d"
        }
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
        CheckBox {
            id: acknowledgement
            objectName: "syncAcknowledgement"
            visible: !!panel.selectedRow
            text: "Diagram and document agree"
            onCheckedChanged: panel.acknowledgedToken = checked ? panel.selectedToken : ""
            enabled: !projectSync.report.unsaved && !workspace.syncDraftPending && !projectSync.report.error
                && !!panel.selectedRow && !panel.selectedRow.error
        }
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

    Menu {
        id: linkMenu
        popupType: Popup.Item
        MenuItem { text: "Link notes"; onTriggered: panel.startLink("notes") }
        MenuItem { text: "Link flow reference"; onTriggered: panel.startLink("reference") }
    }
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
            CheckBox { id: replaceAcknowledgement; text: "Replace document; keep backup" }
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
