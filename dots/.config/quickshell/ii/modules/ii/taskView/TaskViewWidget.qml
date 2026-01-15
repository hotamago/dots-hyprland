pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: root
    required property var panelWindow
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
    property var windowByAddress: HyprlandData.windowByAddress

    // Background blur/dim settings
    property real padding: 40
    property real spacing: 20

    // Smart Packing Logic - macOS-like grid layout
    property var layoutMap: ({})
    property bool layoutRecalculationPending: false
    property var pendingWindowList: null

    function recalculateLayout(windowList) {
        // Debounce layout recalculation to avoid excessive calculations
        pendingWindowList = windowList; // Store the latest window list
        if (layoutRecalculationPending) {
            return;
        }
        layoutRecalculationPending = true;
        Qt.callLater(() => {
            layoutRecalculationPending = false;
            if (pendingWindowList !== null) {
                recalculateLayoutImmediate(pendingWindowList);
                pendingWindowList = null;
            }
        });
    }

    function recalculateLayoutImmediate(windowList) {
        if (!windowList || windowList.length === 0) {
            root.layoutMap = {};
            return;
        }

        const count = windowList.length;
        const availableWidth = root.width - (root.padding * 2);
        const availableHeight = root.height - (root.padding * 2);

        // Calculate optimal grid dimensions (rows x cols)
        // Similar to macOS Mission Control
        let cols, rows;
        
        if (count === 1) {
            cols = 1;
            rows = 1;
        } else if (count === 2) {
            cols = 2;
            rows = 1;
        } else if (count <= 4) {
            cols = 2;
            rows = 2;
        } else if (count <= 6) {
            cols = 3;
            rows = 2;
        } else if (count <= 9) {
            cols = 3;
            rows = 3;
        } else if (count <= 12) {
            cols = 4;
            rows = 3;
        } else if (count <= 16) {
            cols = 4;
            rows = 4;
        } else if (count <= 20) {
            cols = 5;
            rows = 4;
        } else if (count <= 25) {
            cols = 5;
            rows = 5;
        } else {
            // For many windows, calculate based on aspect ratio
            const aspectRatio = availableWidth / availableHeight;
            cols = Math.ceil(Math.sqrt(count * aspectRatio));
            rows = Math.ceil(count / cols);
        }

        // Get aspect ratios for all windows
        const ratios = windowList.map(w => {
            const address = `0x${w.HyprlandToplevel?.address}`;
            const winData = root.windowByAddress[address];
            if (winData && winData.size && winData.size[1] > 0) {
                return winData.size[0] / winData.size[1];
            }
            return 16 / 9; // Fallback
        });

        // Calculate average aspect ratio for uniform sizing
        const avgAspectRatio = ratios.reduce((sum, ar) => sum + ar, 0) / ratios.length;

        // Calculate cell size that fits all windows
        // We need: cols * cellWidth + (cols - 1) * spacing <= availableWidth
        // And: rows * cellHeight + (rows - 1) * spacing <= availableHeight
        // Where cellWidth = cellHeight * avgAspectRatio
        
        // Try to fit based on width constraint
        const maxCellWidthFromWidth = (availableWidth - (cols - 1) * root.spacing) / cols;
        const maxCellHeightFromWidth = maxCellWidthFromWidth / avgAspectRatio;
        
        // Try to fit based on height constraint
        const maxCellHeightFromHeight = (availableHeight - (rows - 1) * root.spacing) / rows;
        const maxCellWidthFromHeight = maxCellHeightFromHeight * avgAspectRatio;
        
        // Use the smaller constraint to ensure everything fits
        let cellHeight, cellWidth;
        if (maxCellHeightFromWidth <= maxCellHeightFromHeight) {
            cellHeight = maxCellHeightFromWidth;
            cellWidth = maxCellWidthFromWidth;
        } else {
            cellHeight = maxCellHeightFromHeight;
            cellWidth = maxCellWidthFromHeight;
        }

        // Ensure minimum size for usability
        // If cells would be too small, we enforce minimum but may need to adjust grid
        const minCellSize = 120;
        if (cellWidth < minCellSize || cellHeight < minCellSize) {
            // Enforce minimum size
            if (cellWidth < minCellSize) {
                cellWidth = minCellSize;
                cellHeight = minCellSize / avgAspectRatio;
            }
            if (cellHeight < minCellSize) {
                cellHeight = minCellSize;
                cellWidth = minCellSize * avgAspectRatio;
            }
            
            // Recalculate grid dimensions
            const newGridWidth = cols * cellWidth + (cols - 1) * root.spacing;
            const newGridHeight = rows * cellHeight + (rows - 1) * root.spacing;
            
            // If grid exceeds available space, scale down proportionally
            const widthScale = newGridWidth > availableWidth ? availableWidth / newGridWidth : 1;
            const heightScale = newGridHeight > availableHeight ? availableHeight / newGridHeight : 1;
            const scale = Math.min(widthScale, heightScale);
            
            if (scale < 1) {
                cellWidth *= scale;
                cellHeight *= scale;
            }
        }

        // Calculate total grid dimensions
        const gridWidth = cols * cellWidth + (cols - 1) * root.spacing;
        const gridHeight = rows * cellHeight + (rows - 1) * root.spacing;

        // Center the grid
        const startX = root.padding + (availableWidth - gridWidth) / 2;
        const startY = root.padding + (availableHeight - gridHeight) / 2;

        // Layout windows in grid
        let newLayout = {};
        for (let i = 0; i < count && i < cols * rows; i++) {
            const col = i % cols;
            const row = Math.floor(i / cols);
            
            const w = windowList[i];
            const address = `0x${w.HyprlandToplevel?.address}`;
            const ar = ratios[i];
            
            // Use individual aspect ratio for each window
            // Scale to fit within cell while maintaining aspect ratio
            let finalWidth = cellHeight * ar;
            let finalHeight = cellHeight;
            
            // If window is too wide for cell, scale down to fit width
            if (finalWidth > cellWidth) {
                finalWidth = cellWidth;
                finalHeight = cellWidth / ar;
            }
            // If window is too tall for cell, scale down to fit height
            if (finalHeight > cellHeight) {
                finalHeight = cellHeight;
                finalWidth = cellHeight * ar;
            }
            
            // Center within cell
            const cellX = startX + col * (cellWidth + root.spacing);
            const cellY = startY + row * (cellHeight + root.spacing);
            const xOffset = (cellWidth - finalWidth) / 2;
            const yOffset = (cellHeight - finalHeight) / 2;

            newLayout[address] = {
                x: cellX + xOffset,
                y: cellY + yOffset,
                width: finalWidth,
                height: finalHeight
            };
        }

        root.layoutMap = newLayout;
    }

    // Helper to get active windows on current monitor & workspace
    // Cache the computation to avoid recalculating on every access
    property var _cachedActiveWorkspaceId: null
    property var _cachedActiveWindows: []
    
    function updateActiveWindows() {
        const activeWorkspaceId = monitor.activeWorkspace?.id;
        if (!activeWorkspaceId) {
            _cachedActiveWindows = [];
            _cachedActiveWorkspaceId = null;
            return;
        }

        // Always recalculate the windows list to catch closed windows
        // Cache is still used to avoid unnecessary layout recalculations
        const newActiveWindows = ToplevelManager.toplevels.values.filter(toplevel => {
            const address = `0x${toplevel.HyprlandToplevel?.address}`;
            const win = windowByAddress[address];
            return win && win.workspace.id === activeWorkspaceId;
        });

        // Check if windows actually changed by comparing sets of addresses
        const workspaceChanged = _cachedActiveWorkspaceId !== activeWorkspaceId;
        const cachedAddresses = new Set(_cachedActiveWindows.map(w => `0x${w.HyprlandToplevel?.address}`));
        const newAddresses = new Set(newActiveWindows.map(w => `0x${w.HyprlandToplevel?.address}`));
        const addressesEqual = cachedAddresses.size === newAddresses.size && 
            [...cachedAddresses].every(addr => newAddresses.has(addr));
        const windowsChanged = workspaceChanged || !addressesEqual;

        if (windowsChanged) {
            _cachedActiveWorkspaceId = activeWorkspaceId;
            _cachedActiveWindows = newActiveWindows;
        }
    }

    property var activeWindows: {
        // Only update when task view is open to avoid unnecessary calculations
        if (GlobalStates.taskViewOpen) {
            updateActiveWindows();
        }
        return _cachedActiveWindows;
    }

    // Watch for workspace changes - invalidate cache when workspace changes
    onMonitorChanged: {
        _cachedActiveWorkspaceId = null;
        updateActiveWindows();
        recalculateLayout(activeWindows);
    }

    // Use a Timer to periodically check for changes (more reliable than signals)
    Timer {
        id: refreshTimer
        interval: 100 // Check every 100ms when visible
        running: root.panelWindow.visible && GlobalStates.taskViewOpen
        repeat: true
        onTriggered: {
            const oldWindowsLength = _cachedActiveWindows.length;
            const oldWorkspaceId = _cachedActiveWorkspaceId;
            updateActiveWindows();
            // If windows changed (count or workspace), recalculate layout
            if (oldWindowsLength !== _cachedActiveWindows.length || 
                oldWorkspaceId !== _cachedActiveWorkspaceId) {
                recalculateLayout(activeWindows);
            }
        }
    }

    onActiveWindowsChanged: {
        recalculateLayout(activeWindows);
    }

    onWidthChanged: recalculateLayout(activeWindows)
    onHeightChanged: recalculateLayout(activeWindows)

    // Cache monitor lookups to avoid repeated find() calls
    property var cachedWidgetMonitor: null
    property var monitorCache: ({})

    function getMonitorById(monitorId) {
        if (!monitorId) return null;
        if (monitorCache[monitorId]) {
            return monitorCache[monitorId];
        }
        const found = HyprlandData.monitors.find(m => m.id === monitorId);
        if (found) {
            monitorCache[monitorId] = found;
        }
        return found;
    }

    Component.onCompleted: {
        cachedWidgetMonitor = getMonitorById(root.monitor.id);
        // Initial update
        updateActiveWindows();
    }

    // Update immediately when task view opens
    Connections {
        target: GlobalStates
        function onTaskViewOpenChanged() {
            if (GlobalStates.taskViewOpen) {
                _cachedActiveWorkspaceId = null;
                updateActiveWindows();
                recalculateLayout(activeWindows);
            }
        }
    }

    Connections {
        target: HyprlandData
        function onMonitorsChanged() {
            monitorCache = {};
            cachedWidgetMonitor = getMonitorById(root.monitor.id);
        }
    }

    // The windows
    Repeater {
        model: activeWindows
        delegate: TaskViewWindow {
            id: taskWindow
            required property var modelData
            property var address: `0x${modelData.HyprlandToplevel.address}`

            toplevel: modelData
            windowData: root.windowByAddress[address]
            monitorData: root.getMonitorById(windowData?.monitor)
            scale: 1 // We want 1:1 scale for previews in the grid

            widgetMonitor: root.cachedWidgetMonitor

            // Layout props
            targetX: (root.layoutMap[address]?.x || 0)
            targetY: (root.layoutMap[address]?.y || 0)
            targetWidth: (root.layoutMap[address]?.width || 100)
            targetHeight: (root.layoutMap[address]?.height || 100)

            // Initial position (animate from real window position?)
            // For now let's just appear. Can improve enter animation later.

            // Z-index handling
            z: hovered ? 100 : 1
        }
    }

    // Empty state message
    Text {
        anchors.centerIn: parent
        text: "No windows implemented"
        color: Appearance.colors.colOnSurface
        font.pixelSize: 24
        visible: activeWindows.length === 0
        opacity: 0.5
    }
}
