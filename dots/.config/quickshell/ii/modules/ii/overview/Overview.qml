import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false

    PanelWindow {
        id: panelWindow
        property string searchingText: ""
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
        property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
        visible: GlobalStates.overviewOpen

        WlrLayershell.namespace: "quickshell:overview"
        WlrLayershell.layer: WlrLayer.Top
        // WlrLayershell.keyboardFocus: GlobalStates.overviewOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        mask: Region {
            item: GlobalStates.overviewOpen ? columnLayout : null
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Connections {
            target: GlobalStates
            function onOverviewOpenChanged() {
                if (!GlobalStates.overviewOpen) {
                    searchWidget.disableExpandAnimation();
                    overviewScope.dontAutoCancelSearch = false;
                    // Reset drawer state
                    Qt.callLater(() => {
                        if (flickable) {
                            flickable.contentY = 0;
                        }
                        if (appDrawer) {
                            appDrawer.expanded = false;
                            appDrawer.searchText = "";
                        }
                    });
                    GlobalFocusGrab.dismiss();
                } else {
                    if (!overviewScope.dontAutoCancelSearch) {
                        searchWidget.cancelSearch();
                    }
                    // Reset drawer state on open
                    Qt.callLater(() => {
                        if (appDrawer) {
                            appDrawer.expanded = false;
                            appDrawer.searchText = "";
                        }
                        if (flickable) {
                            flickable.contentY = 0;
                        }
                    });
                    GlobalFocusGrab.addDismissable(panelWindow);
                }
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                GlobalStates.overviewOpen = false;
            }
        }
        implicitWidth: columnLayout.implicitWidth
        implicitHeight: columnLayout.implicitHeight

        function setSearchingText(text) {
            searchWidget.setSearchingText(text);
            searchWidget.focusFirstItem();
        }

        Column {
            id: columnLayout
            visible: GlobalStates.overviewOpen
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
            }
            spacing: -8

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    GlobalStates.overviewOpen = false;
                } else if (event.key === Qt.Key_Left) {
                    if (!panelWindow.searchingText)
                        Hyprland.dispatch("workspace r-1");
                } else if (event.key === Qt.Key_Right) {
                    if (!panelWindow.searchingText)
                        Hyprland.dispatch("workspace r+1");
                }
            }

            StyledFlickable {
                id: flickable
                anchors.fill: parent
                contentWidth: innerColumnLayout.implicitWidth
                contentHeight: innerColumnLayout.implicitHeight
                clip: true
                visible: GlobalStates.overviewOpen
                boundsBehavior: Flickable.DragAndOvershootBounds
                
                property real lastContentY: 0
                property bool isScrollingUp: false
                property int scrollUpAttempts: 0
                
                // Detect scroll attempts when at the top
                onMovementStarted: {
                    scrollUpAttempts = 0;
                }
                
                onMovementEnded: {
                    // If we tried to scroll up while at/near the top, collapse
                    if (appDrawer.expanded && scrollUpAttempts > 0 && contentY < 50) {
                        appDrawer.expanded = false;
                        appDrawer.searchText = "";
                        Qt.callLater(() => {
                            flickable.contentY = 0;
                        });
                    }
                    scrollUpAttempts = 0;
                    isScrollingUp = false;
                }
                
                // Track wheel events at the top to collapse
                WheelHandler {
                    id: wheelHandler
                    target: null
                    onWheel: (event) => {
                        // If expanded, at/near top, and scrolling up, collapse
                        if (appDrawer.expanded && flickable.contentY < 50 && event.angleDelta.y > 0) {
                            appDrawer.expanded = false;
                            appDrawer.searchText = "";
                            Qt.callLater(() => {
                                flickable.contentY = 0;
                            });
                        }
                    }
                }
                
                onContentYChanged: {
                    // Track scroll direction
                    if (contentY < lastContentY) {
                        isScrollingUp = true;
                        if (appDrawer.expanded && contentY < 50) {
                            scrollUpAttempts++;
                        }
                    } else {
                        isScrollingUp = false;
                    }
                    
                    // When expanded and user scrolls/overshoots past the top, collapse back to initial state
                    if (appDrawer.expanded && contentY < -10) {
                        appDrawer.expanded = false;
                        appDrawer.searchText = "";
                        Qt.callLater(() => {
                            flickable.contentY = 0;
                        });
                        lastContentY = contentY;
                        return;
                    }
                    
                    lastContentY = contentY;
                    
                    // Expand drawer when user scrolls down significantly
                    // Calculate the height of content above the drawer (when not expanded)
                    const searchWidgetHeight = appDrawer.expanded ? 0 : (searchWidget.implicitHeight || 0);
                    const overviewWidgetHeight = (appDrawer.expanded || !overviewLoader.item || !overviewLoader.item.visible) ? 
                        0 : (overviewLoader.item.implicitHeight || 0);
                    const spacing = 20; // ColumnLayout spacing
                    const topContentHeight = searchWidgetHeight + overviewWidgetHeight + (searchWidgetHeight > 0 || overviewWidgetHeight > 0 ? spacing : 0);
                    
                    // Expand when scrolled past 40% of the top content, or when near bottom
                    const scrollThreshold = Math.max(100, topContentHeight * 0.4);
                    const distanceFromBottom = contentHeight - contentY - height;
                    const nearBottom = distanceFromBottom < 250;
                    
                    const shouldExpand = (contentY > scrollThreshold) || nearBottom;
                    
                    if (shouldExpand !== appDrawer.expanded) {
                        appDrawer.expanded = shouldExpand;
                        // When expanding, scroll to position drawer at top without overlapping
                        if (shouldExpand && topContentHeight > 0) {
                            Qt.callLater(() => {
                                // Calculate proper scroll position
                                // We want to hide the collapsed content and show drawer at the top
                                // Account for the spacing to keep drawer below any UI elements
                                const targetY = topContentHeight + spacing;
                                flickable.contentY = Math.max(0, Math.min(targetY, flickable.contentHeight - flickable.height));
                            });
                        } else if (!shouldExpand) {
                            // When collapsing, return to top
                            Qt.callLater(() => {
                                flickable.contentY = 0;
                            });
                        }
                    }
                }
                
                // Also check on contentHeight change (when drawer expands/collapses)
                onContentHeightChanged: {
                    Qt.callLater(() => {
                        if (appDrawer.expanded) {
                            // When expanded, ensure we're scrolled to properly position drawer
                            const searchWidgetHeight = searchWidget.implicitHeight || 0;
                            const overviewWidgetHeight = (overviewLoader.item && overviewLoader.item.visible) ? 
                                (overviewLoader.item.implicitHeight || 0) : 0;
                            const spacing = 20;
                            const topContentHeight = searchWidgetHeight + overviewWidgetHeight;
                            
                            // Only adjust if we're not already at the right position
                            const targetY = topContentHeight + spacing;
                            const tolerance = 5;
                            if (Math.abs(contentY - targetY) > tolerance) {
                                flickable.contentY = Math.max(0, Math.min(targetY, flickable.contentHeight - flickable.height));
                            }
                        }
                    });
                }

                ColumnLayout {
                    id: innerColumnLayout
                    width: flickable.width
                    spacing: 20

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            GlobalStates.overviewOpen = false;
                        } else if (event.key === Qt.Key_Left) {
                            if (!panelWindow.searchingText)
                                Hyprland.dispatch("workspace r-1");
                        } else if (event.key === Qt.Key_Right) {
                            if (!panelWindow.searchingText)
                                Hyprland.dispatch("workspace r+1");
                        }
                    }
                    
                    // Spacer to prevent drawer from overlapping top bar when expanded
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: appDrawer.expanded ? 10 : 0
                        visible: appDrawer.expanded
                        
                        Behavior on Layout.preferredHeight {
                            NumberAnimation {
                                duration: Appearance.animation.elementResize.duration
                                easing.type: Appearance.animation.elementResize.type
                                easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                            }
                        }
                    }

                    SearchWidget {
                        id: searchWidget
                        anchors.horizontalCenter: parent.horizontalCenter
                        Layout.alignment: Qt.AlignHCenter
                        visible: !appDrawer.expanded
                        Layout.maximumHeight: appDrawer.expanded ? 0 : implicitHeight
                        opacity: appDrawer.expanded ? 0 : 1
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                        Behavior on Layout.maximumHeight {
                            NumberAnimation {
                                duration: Appearance.animation.elementResize.duration
                                easing.type: Appearance.animation.elementResize.type
                                easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                            }
                        }
                        Synchronizer on searchingText {
                            property alias source: panelWindow.searchingText
                        }
                    }

                    Loader {
                        id: overviewLoader
                        Layout.alignment: Qt.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                        active: GlobalStates.overviewOpen && (Config?.options.overview.enable ?? true) && !appDrawer.expanded
                        Layout.maximumHeight: appDrawer.expanded ? 0 : (item ? item.implicitHeight : 0)
                        opacity: appDrawer.expanded ? 0 : 1
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                        Behavior on Layout.maximumHeight {
                            NumberAnimation {
                                duration: Appearance.animation.elementResize.duration
                                easing.type: Appearance.animation.elementResize.type
                                easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                            }
                        }
                        sourceComponent: OverviewWidget {
                            screen: panelWindow.screen
                            visible: (panelWindow.searchingText == "")
                        }
                    }
                    
                    ApplicationDrawer {
                        id: appDrawer
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: appDrawer.expanded
                        Layout.preferredWidth: appDrawer.expanded ? flickable.width - 40 : Math.min(1200, flickable.width - 40)
                        visible: (panelWindow.searchingText == "")
                        // But hide it when searching and not expanded (search results take priority)
                        opacity: (panelWindow.searchingText != "" && !appDrawer.expanded) ? 0 : 1
                        Layout.maximumHeight: (panelWindow.searchingText != "" && !appDrawer.expanded) ? 0 : implicitHeight
                        
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                        Behavior on Layout.maximumHeight {
                            NumberAnimation {
                                duration: Appearance.animation.elementResize.duration
                                easing.type: Appearance.animation.elementResize.type
                                easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                            }
                        }
                        
                        availableHeight: flickable.height
                        availableWidth: flickable.width - 40
                    }
                }
            }
        }
    }

    function toggleClipboard() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.clipboard);
        GlobalStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.emojis);
        GlobalStates.overviewOpen = true;
    }

    IpcHandler {
        target: "search"

        function toggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function workspacesToggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            GlobalStates.overviewOpen = true;
        }
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
        function clipboardToggle() {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            GlobalStates.overviewOpen = false;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }
    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"

        onPressed: {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            overviewScope.toggleEmojis();
        }
    }
}
