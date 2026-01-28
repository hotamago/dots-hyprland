import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    function formatModeOption(width, height, refresh) {
        const w = (width | 0) > 0 ? (width | 0) : 0;
        const h = (height | 0) > 0 ? (height | 0) : 0;
        const r = Number(refresh);
        if (w <= 0 || h <= 0 || !Number.isFinite(r) || r <= 0)
            return "preferred";
        const refreshStr = Math.abs(r - Math.round(r)) < 0.001 ? String(Math.round(r)) : r.toFixed(2);
        return `${w}x${h}@${refreshStr}`;
    }

    function modeForMonitor(mon) {
        return formatModeOption(mon?.width ?? 0, mon?.height ?? 0, mon?.refreshRate ?? mon?.refresh ?? 60);
    }

    property var modes: [
        { id: "mirror", name: Translation.tr("Mirror"), icon: "flip_to_front" },
        { id: "extend", name: Translation.tr("Extend"), icon: "splitscreen" },
        { id: "second-only", name: Translation.tr("Second only"), icon: "desktop_windows" },
        { id: "primary-only", name: Translation.tr("Primary only"), icon: "monitor" }
    ]

    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
    property string currentModeId: ""
    property int currentIndex: 0
    property string pendingModeId: ""
    property string lastAppliedModeId: ""
    property double lastAppliedAtMs: 0
    readonly property int applyGuardMs: 100
    property string unlockReapplyModeId: ""
    property int unlockReapplyAttempts: 0
    readonly property int unlockMaxReapplyAttempts: 6

    readonly property var availableModes: modes.filter(mode => HyprlandData.monitors.length > 1 ? true : mode.id === "primary-only" || mode.id === "extend")

    function detectModeFromMonitors(monitors) {
        if (!monitors || monitors.length === 0)
            return "primary-only";

        const enabled = monitors.filter(m => m?.disabled !== true);

        if (enabled.length <= 1) {
            const primaryMon = pickDefaultPrimaryMonitor(monitors);
            const primaryName = primaryMon?.name ?? "";
            const enabledName = enabled.length === 1 ? (enabled[0]?.name ?? "") : "";

            // "primary-only" means only the default/primary monitor is enabled.
            // "second-only" means the primary is disabled but another monitor is enabled.
            if (enabled.length === 1 && enabledName && primaryName && enabledName !== primaryName)
                return "second-only";
            return "primary-only";
        }

        // Hyprland reports `mirrorOf: "none"` when not mirrored (truthy string!),
        // so we must explicitly check for non-empty, non-"none" values.
        const mirrored = enabled.find(m => {
            const mirrorOf = m?.mirrorOf;
            return mirrorOf !== undefined
                && mirrorOf !== null
                && mirrorOf !== ""
                && mirrorOf !== "none"
                && mirrorOf !== "None";
        });
        if (mirrored)
            return "mirror";

        return "extend";
    }

    function setCurrentMode(modeId) {
        const idx = availableModes.findIndex(m => m.id === modeId);
        if (idx === -1 && availableModes.length > 0) {
            currentModeId = availableModes[0].id;
            currentIndex = 0;
            return;
        }
        currentModeId = modeId;
        currentIndex = Math.max(idx, 0);
    }

    function restoreRememberedMode() {
        const persisted = (Persistent.ready && Persistent.states?.displayMode)
            ? (Persistent.states.displayMode.lastModeId ?? "")
            : "";
        if (persisted) {
            setCurrentMode(persisted);
            return;
        }
        setCurrentMode(detectModeFromMonitors(HyprlandData.monitors));
    }

    Component.onCompleted: restoreRememberedMode()

    function showOverlay() {
        GlobalStates.displayModeOpen = true;
        if (GlobalStates.superDown) {
            hideTimer.stop();
        } else {
            hideTimer.restart();
        }
    }

    function cycleMode() {
        if (availableModes.length === 0)
            return;
        const nextIndex = (currentIndex + 1) % availableModes.length;
        requestMode(availableModes[nextIndex].id);
    }

    function requestMode(modeId) {
        // While Super is held, we only "preview" the selection and apply once on release.
        // Note: on the first Super+P press, the popup may not be open yet, so we
        // must defer whenever Super is held (not only when the window is already open).
        if (GlobalStates.superDown) {
            pendingModeId = modeId;
            setCurrentMode(modeId);
            showOverlay();
            return;
        }
        pendingModeId = "";
        applyMode(modeId, true);
    }

    function pickDefaultPrimaryMonitor(monitors) {
        if (!monitors || monitors.length === 0)
            return null;

        // Use Hyprland's numeric id for a stable "primary" definition.
        // Typically id 0 is the built-in/internal panel.
        let best = monitors[0];
        for (let i = 1; i < monitors.length; ++i) {
            const a = best?.id;
            const b = monitors[i]?.id;
            if ((b !== undefined && b !== null) && (a === undefined || a === null || b < a))
                best = monitors[i];
        }
        return best;
    }

    function pickDefaultSecondaryMonitor(monitors, primaryName) {
        if (!monitors || monitors.length === 0)
            return null;
        const candidates = monitors.filter(m => (m?.name ?? "") !== (primaryName ?? ""));
        if (candidates.length === 0)
            return null;
        let best = candidates[0];
        for (let i = 1; i < candidates.length; ++i) {
            const a = best?.id;
            const b = candidates[i]?.id;
            if ((b !== undefined && b !== null) && (a === undefined || a === null || b < a))
                best = candidates[i];
        }
        return best;
    }

    function applyMode(modeId, showUi = true) {
        const monitors = HyprlandData.monitors ?? [];
        if (monitors.length === 0)
            return;

        const primaryMon = pickDefaultPrimaryMonitor(monitors);
        const primary = primaryMon?.name ?? "";
        const secondaryMon = pickDefaultSecondaryMonitor(monitors, primary);
        const secondary = secondaryMon?.name ?? "";
        const commands = [];

        if (modeId === "mirror") {
            if (!primary || !secondary) {
                modeId = "primary-only";
            } else {
                // Keep the currently configured refresh/resolution for the primary.
                commands.push(`keyword monitor ${primary},${modeForMonitor(primaryMon)},0x0,${primaryMon?.scale ?? 1}`);
                // Hyprland mirror syntax is `monitor name,res,pos,scale,mirror,other`
                // Use preferred for the mirrored output (Hyprland will pick a compatible mode).
                commands.push(`keyword monitor ${secondary},preferred,auto,${secondaryMon?.scale ?? 1},mirror,${primary}`);
                for (let i = 0; i < monitors.length; ++i) {
                    const name = monitors[i]?.name ?? "";
                    if (name && name !== primary && name !== secondary)
                        commands.push(`keyword monitor ${name},disable`);
                }
            }
        }

        if (modeId === "extend") {
            // Enable and arrange monitors left-to-right, starting from the focused/primary monitor.
            let currentX = 0;
            const ordered = primaryMon && secondaryMon
                ? [primaryMon, secondaryMon, ...monitors.filter(m => {
                    const n = m?.name ?? "";
                    return n && n !== primary && n !== secondary;
                })]
                : monitors;
            for (let i = 0; i < ordered.length; ++i) {
                const mon = ordered[i];
                const width = (mon?.width | 0) > 0 ? (mon.width | 0) : 1920;
                const scale = (mon?.scale ?? 1) > 0 ? (mon.scale ?? 1) : 1;
                // Preserve per-monitor refresh/resolution (don't reset to preferred).
                commands.push(`keyword monitor ${mon.name},${modeForMonitor(mon)},${currentX}x0,${scale}`);
                // Hyprland monitor `x/y` are in the same coordinate space as `width/height`
                // from `hyprctl monitors -j` (unscaled pixels), so offset by pixel width.
                currentX += width;
            }
        } else if (modeId === "second-only") {
            if (!secondary) {
                modeId = "primary-only";
            } else {
                commands.push(`keyword monitor ${secondary},${modeForMonitor(secondaryMon)},0x0,${secondaryMon?.scale ?? 1}`);
                for (let i = 0; i < monitors.length; ++i) {
                    if (monitors[i].name !== secondary)
                        commands.push(`keyword monitor ${monitors[i].name},disable`);
                }
            }
        } else if (modeId === "primary-only") {
            commands.push(`keyword monitor ${primary},${modeForMonitor(primaryMon)},0x0,${primaryMon?.scale ?? 1}`);
            for (let i = 0; i < monitors.length; ++i) {
                const name = monitors[i]?.name ?? "";
                if (name && name !== primary)
                    commands.push(`keyword monitor ${name},disable`);
            }
        }

        if (commands.length === 0)
            return;

        // Persist mode by writing monitor rules to Hyprland config and reloading.
        const header = [
            "# Managed by Quickshell DisplayMode (Super+P)",
            "# Edit at your own risk; UI may overwrite."
        ];
        const lines = HyprMonitorsConf.keywordMonitorCommandsToMonitorLines(commands);
        HyprMonitorsConf.writeMonitorLinesAndReload(lines, header);

        // Remember the mode the user selected (used for cycling/highlight, especially across lock/unlock).
        root.lastAppliedModeId = modeId;
        root.lastAppliedAtMs = Date.now();
        if (Persistent.ready && Persistent.states?.displayMode)
            Persistent.states.displayMode.lastModeId = modeId;

        // `execDetached` returns immediately; refresh monitors after a short delay.
        postApplyRefreshTimer.restart();

        setCurrentMode(modeId);
        if (showUi)
            showOverlay();
    }

    Timer {
        id: postApplyRefreshTimer
        interval: 250
        repeat: false
        onTriggered: {
            HyprlandData.updateMonitors();
            postApplyRefreshTimer2.restart();
        }
    }

    Timer {
        id: postApplyRefreshTimer2
        interval: 850
        repeat: false
        onTriggered: HyprlandData.updateMonitors()
    }

    Timer {
        id: postUnlockRefreshTimer
        interval: 400
        repeat: false
        onTriggered: {
            HyprlandData.updateMonitors();
            postUnlockRefreshTimer2.restart();
        }
    }

    Timer {
        id: postUnlockRefreshTimer2
        interval: 900
        repeat: false
        onTriggered: HyprlandData.updateMonitors()
    }

    Timer {
        id: reapplyAfterUnlockTimer
        interval: 1400
        repeat: false
        onTriggered: {
            if (GlobalStates.screenLocked)
                return;
            if (!root.unlockReapplyModeId)
                return;

            const desired = root.unlockReapplyModeId;

            // Wait until monitor info is available; lock/unlock can briefly report empty/partial data.
            const monitors = HyprlandData.monitors ?? [];
            if (monitors.length === 0 && root.unlockReapplyAttempts < root.unlockMaxReapplyAttempts) {
                root.unlockReapplyAttempts += 1;
                reapplyAfterUnlockTimer.restart();
                return;
            }

            const detected = root.detectModeFromMonitors(monitors);
            if (detected !== desired) {
                // Actually enforce the remembered mode on unlock.
                root.applyMode(desired, false);
            } else {
                root.setCurrentMode(desired);
            }

            root.unlockReapplyModeId = "";
            root.unlockReapplyAttempts = 0;
        }
    }

    Timer {
        id: hideTimer
        interval: 1500
        repeat: false
        onTriggered: GlobalStates.displayModeOpen = false
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (!Persistent.ready)
                return;
            // If the user applied before Persistent finished loading, persist now.
            if (root.lastAppliedModeId && Persistent.states?.displayMode)
                Persistent.states.displayMode.lastModeId = root.lastAppliedModeId;
            // Only restore if we don't already have a mode (startup edge).
            if (!root.currentModeId)
                restoreRememberedMode();
        }
    }

    Connections {
        target: GlobalStates
        function onSuperDownChanged() {
            if (GlobalStates.displayModeOpen) {
                if (GlobalStates.superDown) {
                    hideTimer.stop();
                } else {
                    // Apply pending mode once Super is released, then hide the UI.
                    hideTimer.stop();
                    if (root.pendingModeId) {
                        const toApply = root.pendingModeId;
                        root.pendingModeId = "";
                        root.applyMode(toApply, false);
                    }
                    GlobalStates.displayModeOpen = false;
                }
            }
        }

        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                root.pendingModeId = "";
                hideTimer.stop();
                GlobalStates.displayModeOpen = false;
                root.unlockReapplyModeId = "";
                root.unlockReapplyAttempts = 0;
                return;
            }

            // On unlock, keep the remembered selection (Hyprland may transiently report a different state).
            const persisted = (Persistent.ready && Persistent.states?.displayMode)
                ? (Persistent.states.displayMode.lastModeId ?? "")
                : "";
            if (persisted) {
                setCurrentMode(persisted);
                root.lastAppliedModeId = persisted;
                root.lastAppliedAtMs = Date.now();
                root.unlockReapplyModeId = persisted;
                root.unlockReapplyAttempts = 0;
            }
            postUnlockRefreshTimer.restart();
            reapplyAfterUnlockTimer.restart();
        }
    }

    Connections {
        target: Hyprland
        function onFocusedMonitorChanged() {
            focusedScreen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
        }
    }

    Connections {
        target: HyprlandData
        function onMonitorsChanged() {
            // Lock/unlock can temporarily change what Hyprland reports (DPMS, disable flags).
            // Don't let those transient states overwrite the remembered selection.
            if (GlobalStates.screenLocked)
                return;

            // While we're in the post-unlock "reapply" window, keep the remembered selection stable.
            if (root.unlockReapplyModeId)
                return;

            // If we're previewing a selection while Super is held, don't override it.
            if (GlobalStates.displayModeOpen && GlobalStates.superDown && root.pendingModeId)
                return;

            const detected = detectModeFromMonitors(HyprlandData.monitors);

            // Right after applying (or just after unlock), ignore mismatched updates for a short window.
            if (root.lastAppliedModeId) {
                const ageMs = Date.now() - root.lastAppliedAtMs;
                if (ageMs < root.applyGuardMs && detected !== root.lastAppliedModeId)
                    return;
                root.lastAppliedModeId = "";
            }

            setCurrentMode(detected);
        }
    }

    Loader {
        id: displayModeLoader
        active: GlobalStates.displayModeOpen

        sourceComponent: PanelWindow {
            id: displayModeWindow
            // Avoid fully transparent layer surfaces (can be hard to see / compositor-dependent).
            color: Appearance.colors.colLayer0
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:displayMode"
            WlrLayershell.layer: WlrLayer.Overlay
            screen: root.focusedScreen
            visible: displayModeLoader.active
            implicitWidth: contentWrapper.implicitWidth
            implicitHeight: contentWrapper.implicitHeight
            mask: Region { item: contentWrapper }

            Item {
                id: contentWrapper
                anchors.centerIn: parent
                implicitWidth: Math.max(listLayout.implicitWidth + padding * 2, 280)
                implicitHeight: listLayout.implicitHeight + padding * 2
                property real padding: 14

                StyledRectangularShadow { target: backgroundRect }

                Rectangle {
                    id: backgroundRect
                    anchors.fill: parent
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colLayer1
                    border.color: Appearance.colors.colLayer0Border
                }

                ColumnLayout {
                    id: listLayout
                    anchors {
                        fill: parent
                        margins: contentWrapper.padding
                    }
                    spacing: 8

                    StyledText {
                        text: Translation.tr("Display modes")
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer1
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Repeater {
                        model: root.availableModes
                        delegate: Rectangle {
                            required property var modelData
                            color: modelData.id === root.currentModeId ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                            radius: Appearance.rounding.normal
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            border.color: modelData.id === root.currentModeId ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.requestMode(modelData.id)
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                MaterialSymbol {
                                    text: modelData.icon
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: modelData.id === root.currentModeId ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                                }

                                StyledText {
                                    text: modelData.name
                                    color: modelData.id === root.currentModeId ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                                    Layout.fillWidth: true
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    GlobalShortcut {
        name: "displayModeCycle"
        description: "Cycle display modes (Super+P)"

        onPressed: {
            cycleMode();
        }
    }
}

