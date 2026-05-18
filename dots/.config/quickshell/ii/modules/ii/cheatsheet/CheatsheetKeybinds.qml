pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property real padding: 4
    property real scrollBarHeight: 14
    property real scrollBarGap: 8
    implicitWidth: QsWindow?.window?.screen.width * 0.7 ?? 0
    implicitHeight: QsWindow?.window?.screen.height * 0.7 ?? 0

    StyledFlickable {
        id: flickable
        clip: true
        anchors.fill: parent
        anchors.margins: Appearance.rounding.small
        anchors.bottomMargin: Appearance.rounding.small + root.scrollBarHeight + root.scrollBarGap
        clip: true
        flickableDirection: Flickable.HorizontalFlick
        contentHeight: height
        contentWidth: flow.implicitWidth

        ScrollBar.vertical.policy: ScrollBar.AlwaysOff
        ScrollBar.horizontal: ScrollBar {
            id: horizontalScrollBar
            parent: root
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: root.scrollBarHeight
            policy: ScrollBar.AsNeeded
            active: hovered || pressed || flickable.movingHorizontally
            opacity: size < 1.0 ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            background: Rectangle {
                implicitHeight: 6
                radius: height / 2
                color: Appearance.colors.colLayer1
                opacity: 0.55
            }

            contentItem: Rectangle {
                implicitHeight: 6
                radius: height / 2
                color: horizontalScrollBar.pressed ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                opacity: horizontalScrollBar.hovered || horizontalScrollBar.pressed ? 0.85 : 0.55

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
            }
        }

        Flow {
            id: flow
            height: flickable.height
            flow: Flow.TopToBottom
            spacing: 10
            Repeater {
                model: [...HyprlandKeybinds.keybindCategories, ""]
                delegate: CheatsheetKeybindsCategory {
                    required property var modelData
                    categoryName: modelData
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: function(wheelEvent) {
                const delta = Math.abs(wheelEvent.angleDelta.x) > Math.abs(wheelEvent.angleDelta.y) ? wheelEvent.angleDelta.x : wheelEvent.angleDelta.y;
                const maxX = Math.max(0, flickable.contentWidth - flickable.width);
                flickable.contentX = Math.max(0, Math.min(flickable.contentX - delta, maxX));
                wheelEvent.accepted = true;
            }
        }
    }

    ScrollEdgeFade {
        target: flickable
        vertical: false
        color: Appearance.colors.colLayer0Base
    }
}
