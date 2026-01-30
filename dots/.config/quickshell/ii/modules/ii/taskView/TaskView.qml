import qs
import qs.services
import qs.modules.common
import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: taskViewScope

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: root
            required property var modelData
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
            screen: modelData

            visible: GlobalStates.taskViewOpen

            WlrLayershell.namespace: "quickshell:taskview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusiveZone: -1 // Cover everything
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Close when clicking empty space
            MouseArea {
                anchors.fill: parent
                onClicked: GlobalStates.taskViewOpen = false
            }

            // Wallpaper Background to hide actual windows
            property bool wallpaperIsVideo: Config.options.background.wallpaperPath.endsWith(".mp4") || Config.options.background.wallpaperPath.endsWith(".webm") || Config.options.background.wallpaperPath.endsWith(".mkv") || Config.options.background.wallpaperPath.endsWith(".avi") || Config.options.background.wallpaperPath.endsWith(".mov")
            property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath

            // Solid background fallback
            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colLayer1 // Use theme background color
                z: -2
            }

            // Wallpaper - preload async immediately when component is created
            // Show fallback color while loading, then fade in when ready
            Image {
                id: bgWallpaper
                anchors.fill: parent
                source: root.wallpaperPath
                fillMode: Image.PreserveAspectCrop
                visible: false // Hidden, used as source for blur
                cache: true
                // Set sourceSize to optimize loading
                sourceSize.width: root.screen ? root.screen.width * (root.monitor?.scale || 1) : 1920
                sourceSize.height: root.screen ? root.screen.height * (root.monitor?.scale || 1) : 1080
                // Load asynchronously to avoid blocking UI
                asynchronous: true
                
                // Preload immediately when component is created (not when visible)
                // Component.onCompleted: {
                //     // Image starts loading in background immediately
                //     // Cache will make subsequent loads instant
                // }
            }
            
            // Show fallback while wallpaper is loading
            Rectangle {
                anchors.fill: bgBlur
                color: Appearance.colors.colLayer1
                z: bgBlur.z - 1
                opacity: bgWallpaper.status === Image.Loading ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }
            }
            
            // Blur effect
            GaussianBlur {
                id: bgBlur
                anchors.fill: bgWallpaper
                source: bgWallpaper
                radius: 30
                samples: 16
                z: -1
                visible: root.visible
            }

            // Dimming layer
            Rectangle {
                anchors.fill: bgBlur
                color: Qt.rgba(0, 0, 0, 0.4)
                z: bgBlur.z
            }

            // The actual content with entrance animation
            TaskViewWidget {
                id: taskViewContent
                anchors.fill: parent
                panelWindow: root
                
                // Entrance animation from top-left corner
                opacity: 0
                scale: 0.8
                transformOrigin: Item.TopLeft
                
                // Entrance animation
                SequentialAnimation {
                    id: entranceAnimation
                    running: false
                    
                    // Reset to initial state instantly
                    ScriptAction {
                        script: {
                            taskViewContent.opacity = 0;
                            taskViewContent.scale = 0.8;
                        }
                    }
                    
                    // Animate to final state
                    ParallelAnimation {
                        NumberAnimation {
                            target: taskViewContent
                            property: "opacity"
                            to: 1
                            duration: 300
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: taskViewContent
                            property: "scale"
                            to: 1
                            duration: 300
                            easing.type: Easing.OutCubic
                        }
                    }
                }
                
                // Trigger animation when TaskView opens
                Connections {
                    target: GlobalStates
                    function onTaskViewOpenChanged() {
                        if (GlobalStates.taskViewOpen) {
                            entranceAnimation.start();
                        }
                    }
                }
            }

            // Key handling to close (Escape) or navigate (Arrows - TODO)
            Item {
                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.taskViewOpen = false;
                    }
                }
            }
        }
    }
}
