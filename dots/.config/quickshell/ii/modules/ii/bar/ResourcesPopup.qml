import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    // Helper function to format KB to GB
    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    // Helper function to format bytes/sec to human-readable speed
    function formatSpeed(bytesPerSec) {
        if (bytesPerSec < 1024) {
            return bytesPerSec.toFixed(0) + " B/s";
        } else if (bytesPerSec < 1024 * 1024) {
            return (bytesPerSec / 1024).toFixed(1) + " KB/s";
        } else {
            return (bytesPerSec / (1024 * 1024)).toFixed(2) + " MB/s";
        }
    }

    // Helper function to format temperature
    function formatTemp(celsius) {
        return celsius.toFixed(1) + "°C";
    }

    // Calculate number of visible info groups
    readonly property int visibleGroups: {
        let count = 3  // RAM, CPU, Network (always visible)
        if (ResourceUsage.swapTotal > 0) count++
        if (ResourceUsage.temperatures.length > 0) count++
        return count
    }

    // Calculate optimal grid layout (columns x rows) to be as square as possible
    readonly property int gridColumns: {
        const count = visibleGroups
        if (count <= 1) return 1
        if (count <= 2) return 2
        if (count <= 4) return 2
        if (count <= 6) return 3
        if (count <= 9) return 3
        return Math.ceil(Math.sqrt(count))
    }

    readonly property int gridRows: Math.ceil(visibleGroups / gridColumns)

    Column {
        anchors.centerIn: parent
        spacing: 12

        Grid {
            columns: root.gridColumns
            rows: root.gridRows
            spacing: 12

            // RAM
            Column {
                spacing: 8

                StyledPopupHeaderRow {
                    icon: "memory"
                    label: "RAM"
                }
                Column {
                    spacing: 4
                    StyledPopupValueRow {
                        icon: "clock_loader_60"
                        label: Translation.tr("Used:")
                        value: root.formatKB(ResourceUsage.memoryUsed)
                    }
                    StyledPopupValueRow {
                        icon: "check_circle"
                        label: Translation.tr("Free:")
                        value: root.formatKB(ResourceUsage.memoryFree)
                    }
                    StyledPopupValueRow {
                        icon: "empty_dashboard"
                        label: Translation.tr("Total:")
                        value: root.formatKB(ResourceUsage.memoryTotal)
                    }
                }
            }

            // Swap
            Column {
                visible: ResourceUsage.swapTotal > 0
                spacing: 8

                StyledPopupHeaderRow {
                    icon: "swap_horiz"
                    label: "Swap"
                }
                Column {
                    spacing: 4
                    StyledPopupValueRow {
                        icon: "clock_loader_60"
                        label: Translation.tr("Used:")
                        value: root.formatKB(ResourceUsage.swapUsed)
                    }
                    StyledPopupValueRow {
                        icon: "check_circle"
                        label: Translation.tr("Free:")
                        value: root.formatKB(ResourceUsage.swapFree)
                    }
                    StyledPopupValueRow {
                        icon: "empty_dashboard"
                        label: Translation.tr("Total:")
                        value: root.formatKB(ResourceUsage.swapTotal)
                    }
                }
            }

            // CPU
            Column {
                spacing: 8

                StyledPopupHeaderRow {
                    icon: "planner_review"
                    label: "CPU"
                }
                Column {
                    spacing: 4
                    StyledPopupValueRow {
                        icon: "bolt"
                        label: Translation.tr("Load:")
                        value: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
                    }
                }
            }

            // Network
            Column {
                spacing: 8

                StyledPopupHeaderRow {
                    icon: "network_check"
                    label: Translation.tr("Network")
                }
                Column {
                    spacing: 4
                    StyledPopupValueRow {
                        icon: "download"
                        label: Translation.tr("Download:")
                        value: root.formatSpeed(ResourceUsage.networkDownloadSpeed)
                    }
                    StyledPopupValueRow {
                        icon: "upload"
                        label: Translation.tr("Upload:")
                        value: root.formatSpeed(ResourceUsage.networkUploadSpeed)
                    }
                }
            }

            // Temperature
            Column {
                visible: ResourceUsage.temperatures.length > 0
                spacing: 8

                StyledPopupHeaderRow {
                    icon: "device_thermostat"
                    label: Translation.tr("Temperature")
                }
                Column {
                    spacing: 4
                    StyledPopupValueRow {
                        icon: "thermostat"
                        label: Translation.tr("Avg:")
                        value: root.formatTemp(ResourceUsage.temperatureAvg)
                    }
                    StyledPopupValueRow {
                        icon: "arrow_upward"
                        label: Translation.tr("Max:")
                        value: root.formatTemp(ResourceUsage.temperatureMax)
                    }
                    StyledPopupValueRow {
                        icon: "arrow_downward"
                        label: Translation.tr("Min:")
                        value: root.formatTemp(ResourceUsage.temperatureMin)
                    }
                }
            }
        }
    }
}
