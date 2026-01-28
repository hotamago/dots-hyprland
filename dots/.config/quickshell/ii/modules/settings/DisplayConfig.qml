import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ContentPage {
    id: root
    forceWidth: true

    readonly property var monitors: HyprlandData.monitors ? HyprlandData.monitors : []

    function sanitizeModeOption(option) {
        if (option === undefined || option === null)
            return "";
        let s = String(option).trim();
        // Hyprland `availableModes` often includes a trailing "Hz" for display.
        s = s.replace(/\s*Hz$/i, "");
        return s;
    }

    function parseModeOption(option) {
        const s = sanitizeModeOption(option);
        const m = /^(\d+)x(\d+)@([0-9.]+)/.exec(s);
        if (!m)
            return null;
        return {
            width: parseInt(m[1], 10),
            height: parseInt(m[2], 10),
            refresh: parseFloat(m[3])
        };
    }

    function formatModeOption(width, height, refresh) {
        const w = Math.max(1, width | 0);
        const h = Math.max(1, height | 0);
        const r = Number(refresh);
        const refreshStr = Number.isFinite(r)
            ? (Math.abs(r - Math.round(r)) < 0.001 ? String(Math.round(r)) : r.toFixed(2))
            : "60";
        return `${w}x${h}@${refreshStr}`;
    }

    function modeOptionsForMonitor(mon) {
        const raw = mon?.availableModes;
        if (!raw || raw.length === undefined)
            return [];

        const out = [];
        const seen = ({});

        for (let i = 0; i < raw.length; ++i) {
            const entry = raw[i];
            let opt = "";
            let displayName = "";
            if (typeof entry === "string") {
                displayName = entry;
                opt = sanitizeModeOption(entry);
            } else if (entry && typeof entry === "object") {
                displayName = entry.displayName ?? entry.name ?? entry.option ?? "";
                opt = sanitizeModeOption(entry.option ?? entry.value ?? entry.name ?? "");
            }

            if (!opt)
                continue;

            if (seen[opt] === true)
                continue;
            seen[opt] = true;

            const parsed = parseModeOption(opt);
            out.push({
                displayName: displayName ? String(displayName) : `${opt}Hz`,
                option: opt,
                width: parsed?.width ?? 0,
                height: parsed?.height ?? 0,
                refresh: parsed?.refresh ?? 0
            });
        }

        return out;
    }

    function pickCurrentModeOption(mon) {
        const modes = modeOptionsForMonitor(mon);
        const width = mon?.width ?? 0;
        const height = mon?.height ?? 0;
        const refresh = mon?.refreshRate ?? mon?.refresh ?? 0;

        if (modes && modes.length > 0) {
            for (let i = 0; i < modes.length; ++i) {
                const m = modes[i];
                if (!m)
                    continue;
                const mr = Number(m.refresh ?? 0);
                if (m.width === width && m.height === height && Math.abs(mr - Number(refresh)) < 0.05) {
                    const opt = m.option ?? "";
                    if (opt)
                        return opt;
                }
            }
            return modes[0]?.option ?? "";
        }
        return formatModeOption(width, height, refresh);
    }

    function refreshMonitors() {
        HyprlandData.updateMonitors();
    }

    function buildMonitorConfLine(m) {
        const name = m?.name ?? "";
        if (!name)
            return "";

        const disabled = m?.disabled === true;
        if (disabled)
            return `monitor=${name},disable`;

        const mirrorOf = String(m?.mirrorOf ?? "").trim();
        if (mirrorOf && mirrorOf !== "none" && mirrorOf !== "None") {
            const width = Math.max(1, (m?.width ?? 0) | 0);
            const height = Math.max(1, (m?.height ?? 0) | 0);
            const refresh = Math.max(1, Number(m?.refreshRate ?? m?.refresh ?? 60));
            const scale = (m?.scale ?? 1) > 0 ? (m.scale ?? 1) : 1;
            const modeOption = sanitizeModeOption(m?.modeOption ?? "");
            const mode = modeOption.length > 0 ? modeOption : formatModeOption(width, height, refresh);
            // Hyprland mirror syntax: monitor=name,res,pos,scale,mirror,other
            return `monitor=${name},${mode},auto,${scale},mirror,${mirrorOf}`;
        }

        const width = Math.max(1, (m?.width ?? 0) | 0);
        const height = Math.max(1, (m?.height ?? 0) | 0);
        const refresh = Math.max(1, Number(m?.refreshRate ?? m?.refresh ?? 60));
        const scale = (m?.scale ?? 1) > 0 ? (m.scale ?? 1) : 1;
        const x = (m?.x ?? 0) | 0;
        const y = (m?.y ?? 0) | 0;

        const modeOption = sanitizeModeOption(m?.modeOption ?? "");
        const mode = modeOption.length > 0 ? modeOption : formatModeOption(width, height, refresh);

        return `monitor=${name},${mode},${x}x${y},${scale}`;
    }

    function writeHyprMonitorsConf(monitorsArray) {
        const lines = [];
        const header = [
            "# Managed by Quickshell DisplayConfig",
            "# Edit at your own risk; UI may overwrite."
        ];

        for (let i = 0; i < (monitorsArray?.length ?? 0); ++i) {
            const line = buildMonitorConfLine(monitorsArray[i]);
            if (line)
                lines.push(line);
        }

        HyprMonitorsConf.writeMonitorLinesAndReload(lines, header);
    }

    Timer {
        id: postApplyRefreshTimer
        interval: 350
        repeat: false
        onTriggered: refreshMonitors()
    }

    function applyMonitorConfig(m) {
        if (!m || !m.name)
            return;

        // Persist by rewriting monitors config and reloading Hyprland.
        const merged = [];
        for (let i = 0; i < (root.monitors?.length ?? 0); ++i) {
            const base = root.monitors[i];
            if ((base?.name ?? "") === m.name) {
                const obj = ({});
                for (const k in base)
                    obj[k] = base[k];
                for (const k in m)
                    obj[k] = m[k];
                merged.push(obj);
            } else {
                merged.push(base);
            }
        }
        writeHyprMonitorsConf(merged);
        postApplyRefreshTimer.restart();
    }

    function applyArrangement() {
        if (!monitors || monitors.length === 0)
            return;

        const merged = [];
        let currentX = 0;

        for (let i = 0; i < monitors.length; ++i) {
            const m = monitors[i];
            const width = Math.max(1, m.width | 0);
            const height = Math.max(1, m.height | 0);
            const refresh = Math.max(1, Number(m.refreshRate ?? m.refresh ?? 60));
            const scale = m.scale > 0 ? m.scale : 1;
            const mode = pickCurrentModeOption(m);

            if (m.disabled) {
                const obj = ({});
                for (const k in m)
                    obj[k] = m[k];
                obj.disabled = true;
                merged.push(obj);
            } else {
                const obj = ({});
                for (const k in m)
                    obj[k] = m[k];
                obj.disabled = false;
                obj.modeOption = mode;
                obj.x = currentX;
                obj.y = 0;
                obj.scale = scale;
                merged.push(obj);
                currentX += width;
            }
        }

        if (merged.length === 0)
            return;

        writeHyprMonitorsConf(merged);
        postApplyRefreshTimer.restart();
    }

    Component.onCompleted: refreshMonitors()

    ContentSection {
        icon: "desktop_windows"
        title: Translation.tr("Displays")

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Configure Hyprland monitors.\nToggle usage, focus a screen, and adjust resolution / refresh rate.\nChanges are applied immediately via hyprctl, so be careful.")
            }

            RippleButtonWithIcon {
                materialIcon: "refresh"
                mainText: Translation.tr("Rescan")
                onClicked: refreshMonitors()
            }
        }

        // Monitor cards container
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12

            Repeater {
                model: root.monitors
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    Layout.fillWidth: true

                    property string monName: modelData && modelData.name ? modelData.name : ""
                    property bool monDisabled: modelData && modelData.disabled === true
                    property int monWidth: modelData && modelData.width ? modelData.width : 1920
                    property int monHeight: modelData && modelData.height ? modelData.height : 1080
                    property real monRefresh: modelData && modelData.refreshRate ? modelData.refreshRate : 60
                    property real monScale: modelData && modelData.scale ? modelData.scale : 1.0
                    property var monModes: root.modeOptionsForMonitor(modelData)
                    property string monModeOption: root.pickCurrentModeOption(modelData)
                    property string monMirrorOf: {
                        const v = String(modelData?.mirrorOf ?? "").trim();
                        return (v && v !== "none" && v !== "None") ? v : "";
                    }

                    readonly property var mirrorOptions: {
                        const out = [];
                        out.push({ displayName: Translation.tr("None"), value: "" });
                        for (let i = 0; i < (root.monitors?.length ?? 0); ++i) {
                            const other = root.monitors[i];
                            const name = other?.name ?? "";
                            if (!name || name === card.monName)
                                continue;
                            out.push({ displayName: name, value: name });
                        }
                        return out;
                    }

                    function refreshLabel() {
                        const r = Number(card.monRefresh);
                        if (!Number.isFinite(r))
                            return "60Hz";
                        return (Math.abs(r - Math.round(r)) < 0.001 ? String(Math.round(r)) : r.toFixed(2)) + "Hz";
                    }

                    function syncToSelectedMode(entry) {
                        if (!entry)
                            return;
                        card.monModeOption = entry.option ?? "";
                        if ((entry.width | 0) > 0)
                            card.monWidth = entry.width | 0;
                        if ((entry.height | 0) > 0)
                            card.monHeight = entry.height | 0;
                        if (Number.isFinite(Number(entry.refresh)) && Number(entry.refresh) > 0)
                            card.monRefresh = Number(entry.refresh);
                    }

                    function syncModeFromResolution() {
                        const modes = card.monModes;
                        if (!modes || modes.length === undefined || modes.length === 0) {
                            card.monModeOption = root.formatModeOption(card.monWidth, card.monHeight, card.monRefresh);
                            return;
                        }
                        for (let i = 0; i < modes.length; ++i) {
                            const m = modes[i];
                            if (!m)
                                continue;
                            const mr = Number(m.refresh ?? 0);
                            if (m.width === card.monWidth && m.height === card.monHeight && Math.abs(mr - Number(card.monRefresh)) < 0.05) {
                                if (m.option) {
                                    card.monModeOption = m.option;
                                    return;
                                }
                            }
                        }

                        for (let i = 0; i < modes.length; ++i) {
                            const m = modes[i];
                            if (!m)
                                continue;
                            if (m.width === card.monWidth && m.height === card.monHeight) {
                                card.syncToSelectedMode(m);
                                return;
                            }
                        }
                        // Keep a best-effort manual mode string if the resolution isn't listed.
                        card.monModeOption = root.formatModeOption(card.monWidth, card.monHeight, card.monRefresh);
                    }

                    implicitHeight: cardLayout.implicitHeight + 20
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.normal
                    border.color: Appearance.colors.colLayer0Border

                    ColumnLayout {
                        id: cardLayout
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                text: card.monName || Translation.tr("Unknown")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            MaterialSymbol {
                                text: "monitor"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            text: card.monWidth + "x" + card.monHeight + "@" + card.refreshLabel() + " · " + Translation.tr("scale") + " " + card.monScale.toFixed(2)
                        }

                        ConfigRow {
                            uniform: true
                            ConfigSwitch {
                                buttonIcon: card.monDisabled ? "visibility_off" : "visibility"
                                text: card.monDisabled
                                      ? Translation.tr("Disabled")
                                      : Translation.tr("Enabled")
                                checked: !card.monDisabled
                                onCheckedChanged: {
                                    card.monDisabled = !checked;
                                    root.applyMonitorConfig({
                                        name: card.monName,
                                        disabled: card.monDisabled,
                                        width: card.monWidth,
                                        height: card.monHeight,
                                        refreshRate: card.monRefresh,
                                        modeOption: card.monModeOption,
                                        mirrorOf: card.monMirrorOf,
                                        scale: card.monScale,
                                        x: modelData && modelData.x ? modelData.x : 0,
                                        y: modelData && modelData.y ? modelData.y : 0
                                    });
                                }
                            }
                            RippleButtonWithIcon {
                                materialIcon: "center_focus_strong"
                                mainText: Translation.tr("Focus")
                                onClicked: {
                                    if (!card.monName)
                                        return;
                                    Quickshell.execDetached(["hyprctl", "dispatch", "focusmonitor", card.monName]);
                                }
                            }
                        }

                        ContentSubsection {
                            title: Translation.tr("Resolution")

                            ConfigRow {
                                uniform: true

                                ConfigSpinBox {
                                    icon: "straighten"
                                    text: Translation.tr("Width")
                                    value: card.monWidth
                                    from: 320
                                    to: 7680
                                    stepSize: 8
                                    onValueChanged: {
                                        card.monWidth = value;
                                        card.syncModeFromResolution();
                                    }
                                }
                                ConfigSpinBox {
                                    icon: "height"
                                    text: Translation.tr("Height")
                                    value: card.monHeight
                                    from: 240
                                    to: 4320
                                    stepSize: 8
                                    onValueChanged: {
                                        card.monHeight = value;
                                        card.syncModeFromResolution();
                                    }
                                }
                            }
                        }

                        ContentSubsection {
                            title: Translation.tr("Refresh & scale")

                            ConfigRow {
                                uniform: true

                                StyledComboBox {
                                    id: refreshSelector
                                    buttonIcon: "av_timer"
                                    textRole: "displayName"
                                    model: card.monModes

                                    currentIndex: {
                                        const modes = card.monModes;
                                        if (!modes || modes.length === undefined)
                                            return -1;
                                        for (let i = 0; i < modes.length; ++i) {
                                            const opt = modes[i]?.option ?? "";
                                            if (opt === card.monModeOption)
                                                return i;
                                        }
                                        return -1;
                                    }

                                    enabled: card.monModes && card.monModes.length !== undefined && card.monModes.length > 0
                                    displayText: enabled
                                        ? (currentIndex >= 0
                                            ? (card.monModes[currentIndex]?.displayName ?? Translation.tr("Refresh (auto)"))
                                            : `${root.formatModeOption(card.monWidth, card.monHeight, card.monRefresh)}Hz`)
                                        : Translation.tr("Refresh (auto)")

                                    onActivated: index => {
                                        const entry = refreshSelector.model?.[index];
                                        card.syncToSelectedMode(entry);
                                    }
                                }

                                ConfigSpinBox {
                                    icon: "zoom_in"
                                    text: Translation.tr("Scale (%)")
                                    value: card.monScale * 100
                                    from: 50
                                    to: 300
                                    stepSize: 5
                                    onValueChanged: {
                                        card.monScale = value / 100.0;
                                    }
                                }
                            }

                            ConfigRow {
                                uniform: true

                                StyledComboBox {
                                    id: mirrorSelector
                                    buttonIcon: "flip_to_front"
                                    textRole: "displayName"
                                    model: card.mirrorOptions

                                    currentIndex: {
                                        const opts = card.mirrorOptions;
                                        for (let i = 0; i < (opts?.length ?? 0); ++i) {
                                            if ((opts[i]?.value ?? "") === (card.monMirrorOf ?? ""))
                                                return i;
                                        }
                                        return 0;
                                    }

                                    displayText: {
                                        const idx = currentIndex;
                                        return idx >= 0 ? (card.mirrorOptions[idx]?.displayName ?? Translation.tr("None")) : Translation.tr("None");
                                    }

                                    onActivated: index => {
                                        const v = mirrorSelector.model?.[index]?.value ?? "";
                                        card.monMirrorOf = String(v);
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            RippleButtonWithIcon {
                                Layout.fillWidth: true
                                materialIcon: "done"
                                mainText: Translation.tr("Apply monitor")
                                onClicked: {
                                    root.applyMonitorConfig({
                                        name: card.monName,
                                        disabled: card.monDisabled,
                                        width: card.monWidth,
                                        height: card.monHeight,
                                        refreshRate: card.monRefresh,
                                        modeOption: card.monModeOption,
                                        mirrorOf: card.monMirrorOf,
                                        scale: card.monScale,
                                        x: modelData && modelData.x ? modelData.x : 0,
                                        y: modelData && modelData.y ? modelData.y : 0
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Apply layout")

            ConfigRow {
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                    text: Translation.tr("Monitors are applied left-to-right based on card order.\nTo change layout, reorder monitors in your Hyprland config or use the shell's display mode popup (Super+P).")
                }

                RippleButtonWithIcon {
                    materialIcon: "tune"
                    mainText: Translation.tr("Apply all (inline)")
                    onClicked: root.applyArrangement()
                }
            }
        }
    }

    // Test display config content
    // ContentSection {
    //     icon: "desktop_windows"
    //     title: Translation.tr("Display")

    //     StyledText {
    //         text: Translation.tr("Display configuration")
    //     }
    // }
}