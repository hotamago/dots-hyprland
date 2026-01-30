pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ContentPage {
    id: root
    forceWidth: true

    readonly property string execsConfPath: HyprExecsConf.execsConfPath
    property var execEntries: [] // [{ label, command }]
    property int editingIndex: -1 // -1 means not editing, >= 0 means editing entry at that index

    component IconActionButton: RippleButton {
        id: iconActionButton
        required property string materialIcon
        required property string tooltipText

        implicitWidth: 36
        implicitHeight: 36
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        bottomPadding: 0
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer2

        contentItem: Item {
            MaterialSymbol {
                anchors.centerIn: parent
                text: iconActionButton.materialIcon
                iconSize: 18
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        StyledToolTip {
            text: iconActionButton.tooltipText
        }
    }

    function parseExecEntries(textContent) {
        const out = [];
        const lines = String(textContent ?? "").split("\n");

        for (let i = 0; i < lines.length; ++i) {
            const line = String(lines[i] ?? "");
            const m = line.match(/^\s*exec-once\s*=\s*(.+?)\s*$/);
            if (!m) continue;

            const command = String(m[1] ?? "").trim();
            if (!command) continue;

            let label = "";
            // Use the nearest comment directly above as label (common pattern in this repo's execs.conf)
            for (let j = i - 1; j >= 0; --j) {
                const prev = String(lines[j] ?? "").trim();
                if (!prev) continue;
                if (prev.indexOf("#") === 0) {
                    label = prev.substring(1).trim();
                }
                break;
            }
            out.push({ label, command });
        }
        return out;
    }

    function buildTextWithAddedEntry(existingText, label, command) {
        const cmd = String(command ?? "").trim();
        const lbl = String(label ?? "").trim();
        if (!cmd) return String(existingText ?? "");

        // Avoid duplicates
        const existingLines = String(existingText ?? "").split("\n");
        for (let i = 0; i < existingLines.length; ++i) {
            const line = String(existingLines[i] ?? "");
            const m = line.match(/^\s*exec-once\s*=\s*(.+?)\s*$/);
            if (m && String(m[1] ?? "").trim() === cmd) {
                let keep = String(existingText ?? "");
                if (keep.length > 0 && !keep.endsWith("\n")) keep += "\n";
                return keep;
            }
        }

        let base = String(existingText ?? "");
        base = base.replace(/\s+$/g, ""); // keep file tidy; we'll add trailing newline back

        const parts = [];
        if (base.length > 0) parts.push(base);

        // Ensure a blank line between blocks
        if (parts.length > 0) parts.push("");

        if (lbl.length > 0) parts.push("# " + lbl);
        parts.push("exec-once = " + cmd);

        return parts.join("\n") + "\n";
    }

    function buildTextWithRemovedEntry(existingText, label, command) {
        const cmd = String(command ?? "").trim();
        const lbl = String(label ?? "").trim();
        const lines = String(existingText ?? "").split("\n");

        let removeIdx = -1;
        for (let i = 0; i < lines.length; ++i) {
            const line = String(lines[i] ?? "");
            const m = line.match(/^\s*exec-once\s*=\s*(.+?)\s*$/);
            if (!m) continue;
            if (String(m[1] ?? "").trim() === cmd) {
                removeIdx = i;
                break;
            }
        }
        if (removeIdx === -1) return String(existingText ?? "");

        // Remove the exec line
        lines.splice(removeIdx, 1);

        // Optionally remove the comment directly above if it "belongs" to this entry
        const commentIdx = removeIdx - 1;
        if (commentIdx >= 0) {
            const prev = String(lines[commentIdx] ?? "").trim();
            if (prev.indexOf("#") === 0) {
                const prevLabel = prev.substring(1).trim();
                if (!lbl || prevLabel === lbl) {
                    lines.splice(commentIdx, 1);
                }
            }
        }

        // Trim excessive blank lines
        let out = lines.join("\n");
        out = out.replace(/\n{3,}/g, "\n\n").replace(/\s+$/g, "");
        if (out.length > 0) out += "\n";
        return out;
    }

    function buildTextWithUpdatedEntry(existingText, oldLabel, oldCommand, newLabel, newCommand) {
        const oldCmd = String(oldCommand ?? "").trim();
        const oldLbl = String(oldLabel ?? "").trim();
        const newCmd = String(newCommand ?? "").trim();
        const newLbl = String(newLabel ?? "").trim();
        if (!newCmd) return String(existingText ?? "");

        const lines = String(existingText ?? "").split("\n");
        let updateIdx = -1;
        for (let i = 0; i < lines.length; ++i) {
            const line = String(lines[i] ?? "");
            const m = line.match(/^\s*exec-once\s*=\s*(.+?)\s*$/);
            if (!m) continue;
            if (String(m[1] ?? "").trim() === oldCmd) {
                updateIdx = i;
                break;
            }
        }
        if (updateIdx === -1) return String(existingText ?? "");

        // Check if there's a comment line directly above
        const commentIdx = updateIdx - 1;
        const hasCommentAbove = commentIdx >= 0 && String(lines[commentIdx] ?? "").trim().indexOf("#") === 0;

        // Update the exec line
        lines[updateIdx] = "exec-once = " + newCmd;

        // Handle comment: update, add, or remove
        if (newLbl.length > 0) {
            // We want a comment
            if (hasCommentAbove) {
                // Update existing comment
                lines[commentIdx] = "# " + newLbl;
            } else {
                // Insert new comment before exec line
                lines.splice(updateIdx, 0, "# " + newLbl);
            }
        } else {
            // We don't want a comment - remove if it exists and matches
            if (hasCommentAbove) {
                const prev = String(lines[commentIdx] ?? "").trim();
                const prevLabel = prev.substring(1).trim();
                if (!oldLbl || prevLabel === oldLbl) {
                    lines.splice(commentIdx, 1);
                }
            }
        }

        // Trim excessive blank lines
        let out = lines.join("\n");
        out = out.replace(/\n{3,}/g, "\n\n").replace(/\s+$/g, "");
        if (out.length > 0) out += "\n";
        return out;
    }

    FileView {
        id: execsFileView
        path: root.execsConfPath
        watchChanges: true
        onFileChanged: reload()

        Component.onCompleted: reload()

        onLoaded: {
            root.execEntries = root.parseExecEntries(text());
        }
        onLoadFailed: _error => {
            root.execEntries = [];
        }
    }

    Timer {
        id: refreshTimer
        interval: 350
        onTriggered: execsFileView.reload()
    }

    ContentSection {
        icon: "rocket_launch"
        title: Translation.tr("Startup exec")

        NoticeBox {
            Layout.fillWidth: true
            text: Translation.tr("Edits Hyprland startup commands in %1").arg(root.execsConfPath)

            Item { Layout.fillWidth: true }

            RippleButtonWithIcon {
                id: openFileButton
                Layout.fillWidth: false
                buttonRadius: Appearance.rounding.small
                materialIcon: "file_open"
                mainText: Translation.tr("Open file")
                onClicked: Qt.openUrlExternally("file://" + root.execsConfPath)
            }

            RippleButtonWithIcon {
                id: copyPathButton
                Layout.fillWidth: false
                buttonRadius: Appearance.rounding.small
                materialIcon: "content_copy"
                mainText: Translation.tr("Copy path")
                onClicked: {
                    Quickshell.clipboardText = root.execsConfPath;
                }
            }
        }

        ContentSubsection {
            title: root.editingIndex >= 0 ? Translation.tr("Edit exec-once") : Translation.tr("Add exec-once")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialTextField {
                    id: labelField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Label (optional), e.g. Discord")
                }

                MaterialTextArea {
                    id: commandField
                    Layout.fillWidth: true
                    implicitHeight: 56
                    placeholderText: Translation.tr("Command, e.g. flatpak run com.discordapp.Discord")
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    RippleButtonWithIcon {
                        id: cancelButton
                        visible: root.editingIndex >= 0
                        Layout.fillWidth: false
                        buttonRadius: Appearance.rounding.small
                        materialIcon: "close"
                        mainText: Translation.tr("Cancel")
                        onClicked: {
                            root.editingIndex = -1;
                            labelField.text = "";
                            commandField.text = "";
                        }
                    }

                    RippleButtonWithIcon {
                        id: clearButton
                        visible: root.editingIndex < 0
                        Layout.fillWidth: false
                        buttonRadius: Appearance.rounding.small
                        materialIcon: "backspace"
                        mainText: Translation.tr("Clear")
                        enabled: (labelField.text.trim().length > 0) || (commandField.text.trim().length > 0)
                        onClicked: {
                            labelField.text = "";
                            commandField.text = "";
                        }
                    }

                    RippleButtonWithIcon {
                        id: saveButton
                        Layout.fillWidth: false
                        buttonRadius: Appearance.rounding.small
                        materialIcon: root.editingIndex >= 0 ? "check" : "add"
                        mainText: root.editingIndex >= 0 ? Translation.tr("Save") : Translation.tr("Add")
                        enabled: commandField.text.trim().length > 0
                        onClicked: {
                            const existing = execsFileView.loaded ? execsFileView.text() : "";
                            let newText;
                            
                            if (root.editingIndex >= 0 && root.editingIndex < root.execEntries.length) {
                                const oldEntry = root.execEntries[root.editingIndex];
                                newText = root.buildTextWithUpdatedEntry(
                                    existing,
                                    oldEntry.label,
                                    oldEntry.command,
                                    labelField.text,
                                    commandField.text
                                );
                            } else {
                                newText = root.buildTextWithAddedEntry(existing, labelField.text, commandField.text);
                            }
                            
                            HyprExecsConf.writeTextAndReload(newText);
                            root.editingIndex = -1;
                            labelField.text = "";
                            commandField.text = "";
                            refreshTimer.restart();
                        }
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Current entries")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    visible: root.execEntries.length === 0
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("No startup exec entries found.")
                }

                Repeater {
                    model: root.execEntries
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        color: Appearance.colors.colLayer1
                        radius: Appearance.rounding.small
                        implicitHeight: row.implicitHeight + 12

                        RowLayout {
                            id: row
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 8

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    visible: String(modelData.label ?? "").length > 0
                                    text: String(modelData.label ?? "")
                                    color: Appearance.colors.colOnLayer0
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }

                                StyledText {
                                    text: String(modelData.command ?? "")
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    wrapMode: Text.WordWrap
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: false
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                spacing: 6

                                IconActionButton {
                                    materialIcon: "edit"
                                    tooltipText: Translation.tr("Edit")
                                    onClicked: {
                                        root.editingIndex = index;
                                        labelField.text = String(modelData.label ?? "");
                                        commandField.text = String(modelData.command ?? "");
                                    }
                                }

                                IconActionButton {
                                    materialIcon: "content_copy"
                                    tooltipText: Translation.tr("Copy command")
                                    onClicked: {
                                        Quickshell.clipboardText = String(modelData.command ?? "");
                                    }
                                }

                                IconActionButton {
                                    materialIcon: "delete"
                                    tooltipText: Translation.tr("Remove")
                                    colBackground: Appearance.colors.colLayer2
                                    onClicked: {
                                        const existing = execsFileView.loaded ? execsFileView.text() : "";
                                        const newText = root.buildTextWithRemovedEntry(existing, modelData.label, modelData.command);
                                        HyprExecsConf.writeTextAndReload(newText);
                                        refreshTimer.restart();
                                    }
                                }
                            }

                        }
                    }
                }
            }
        }
    }
}

