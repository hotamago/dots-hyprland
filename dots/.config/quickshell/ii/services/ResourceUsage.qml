pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Simple polled resource usage service with RAM, Swap, CPU usage, and Network speed.
 */
Singleton {
    id: root
	property real memoryTotal: 1
	property real memoryFree: 0
	property real memoryUsed: memoryTotal - memoryFree
    property real memoryUsedPercentage: memoryUsed / memoryTotal
    property real swapTotal: 1
	property real swapFree: 0
	property real swapUsed: swapTotal - swapFree
    property real swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0
    property real cpuUsage: 0
    property var previousCpuStats
    
    // Network speed properties (in bytes per second)
    property real networkDownloadSpeed: 0  // bytes/sec
    property real networkUploadSpeed: 0    // bytes/sec
    property var previousNetworkStats

    // Temperature properties (in Celsius)
    property real temperatureAvg: 0
    property real temperatureMax: 0
    property real temperatureMin: 0
    property var temperatures: []  // Array of {zone: string, name: string, temp: real}
    property var thermalZones: []  // Array of thermal zone paths

    property string maxAvailableMemoryString: kbToGbString(ResourceUsage.memoryTotal)
    property string maxAvailableSwapString: kbToGbString(ResourceUsage.swapTotal)
    property string maxAvailableCpuString: "--"

    readonly property int historyLength: Config?.options.resources.historyLength ?? 60
    property list<real> cpuUsageHistory: []
    property list<real> memoryUsageHistory: []
    property list<real> swapUsageHistory: []

    function kbToGbString(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    function updateMemoryUsageHistory() {
        memoryUsageHistory = [...memoryUsageHistory, memoryUsedPercentage]
        if (memoryUsageHistory.length > historyLength) {
            memoryUsageHistory.shift()
        }
    }
    function updateSwapUsageHistory() {
        swapUsageHistory = [...swapUsageHistory, swapUsedPercentage]
        if (swapUsageHistory.length > historyLength) {
            swapUsageHistory.shift()
        }
    }
    function updateCpuUsageHistory() {
        cpuUsageHistory = [...cpuUsageHistory, cpuUsage]
        if (cpuUsageHistory.length > historyLength) {
            cpuUsageHistory.shift()
        }
    }
    function updateHistories() {
        updateMemoryUsageHistory()
        updateSwapUsageHistory()
        updateCpuUsageHistory()
    }

    function updateTemperatures() {
        // Only start if not already running
        if (!readTemperaturesProc.running) {
            readTemperaturesProc.running = true
        }
    }

    function parseTemperatureData(output) {
        const lines = output.trim().split('\n')
        let temps = []
        let sum = 0
        let max = -Infinity
        let min = Infinity
        
        for (const line of lines) {
            if (!line) continue
            // Format: zone|name|temp (temp in millidegrees)
            const parts = line.split('|')
            if (parts.length >= 3) {
                const zone = parts[0]
                const name = parts[1]
                const temp = parseFloat(parts[2]) / 1000.0  // Convert millidegrees to Celsius
                
                if (!isNaN(temp) && temp > 0) {
                    temps.push({
                        zone: zone,
                        name: name,
                        temp: temp
                    })
                    
                    sum += temp
                    max = Math.max(max, temp)
                    min = Math.min(min, temp)
                }
            }
        }
        
        temperatures = temps
        temperatureAvg = temps.length > 0 ? sum / temps.length : 0
        temperatureMax = max !== -Infinity ? max : 0
        temperatureMin = min !== Infinity ? min : 0
    }

    function discoverThermalZones() {
        findThermalZonesProc.running = true
    }

	Timer {
		interval: 1
        running: true 
        repeat: true
		onTriggered: {
            // Reload files
            fileMeminfo.reload()
            fileStat.reload()
            fileNetDev.reload()
            
            // Update temperatures
            updateTemperatures()

            // Parse memory and swap usage
            const textMeminfo = fileMeminfo.text()
            memoryTotal = Number(textMeminfo.match(/MemTotal: *(\d+)/)?.[1] ?? 1)
            memoryFree = Number(textMeminfo.match(/MemAvailable: *(\d+)/)?.[1] ?? 0)
            swapTotal = Number(textMeminfo.match(/SwapTotal: *(\d+)/)?.[1] ?? 1)
            swapFree = Number(textMeminfo.match(/SwapFree: *(\d+)/)?.[1] ?? 0)

            // Parse CPU usage
            const textStat = fileStat.text()
            const cpuLine = textStat.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)
            if (cpuLine) {
                const stats = cpuLine.slice(1).map(Number)
                const total = stats.reduce((a, b) => a + b, 0)
                const idle = stats[3]

                if (previousCpuStats) {
                    const totalDiff = total - previousCpuStats.total
                    const idleDiff = idle - previousCpuStats.idle
                    cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0
                }

                previousCpuStats = { total, idle }
            }

            // Parse network statistics
            const textNetDev = fileNetDev.text()
            let totalBytesReceived = 0
            let totalBytesTransmitted = 0
            
            // Parse /proc/net/dev - skip first 2 lines (header)
            const lines = textNetDev.split('\n').slice(2)
            for (const line of lines) {
                const match = line.match(/^\s*(\w+):\s*(\d+)\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+(\d+)/)
                if (match) {
                    const interfaceName = match[1]
                    // Skip loopback interface
                    if (interfaceName !== 'lo') {
                        totalBytesReceived += Number(match[2])
                        totalBytesTransmitted += Number(match[3])
                    }
                }
            }
            
            const updateInterval = Config.options?.resources?.updateInterval ?? 3000
            
            if (previousNetworkStats) {
                const timeDiff = updateInterval / 1000.0 // Convert ms to seconds
                const bytesReceivedDiff = totalBytesReceived - previousNetworkStats.bytesReceived
                const bytesTransmittedDiff = totalBytesTransmitted - previousNetworkStats.bytesTransmitted
                
                networkDownloadSpeed = timeDiff > 0 ? bytesReceivedDiff / timeDiff : 0
                networkUploadSpeed = timeDiff > 0 ? bytesTransmittedDiff / timeDiff : 0
            }
            
            previousNetworkStats = {
                bytesReceived: totalBytesReceived,
                bytesTransmitted: totalBytesTransmitted
            }

            root.updateHistories()
            interval = updateInterval
        }
	}

	FileView { id: fileMeminfo; path: "/proc/meminfo" }
    FileView { id: fileStat; path: "/proc/stat" }
    FileView { id: fileNetDev; path: "/proc/net/dev" }

    Process {
        id: findCpuMaxFreqProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["bash", "-c", "lscpu | grep 'CPU max MHz' | awk '{print $4}'"]
        running: true
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                root.maxAvailableCpuString = (parseFloat(outputCollector.text) / 1000).toFixed(0) + " GHz"
            }
        }
    }

    Process {
        id: findThermalZonesProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["bash", "-c", "find /sys/class/thermal -name 'thermal_zone*' -type d | sort -V"]
        running: true
        stdout: StdioCollector {
            id: thermalZonesCollector
            onStreamFinished: {
                const output = thermalZonesCollector.text.trim()
                if (output) {
                    root.thermalZones = output.split('\n').filter(zone => zone.length > 0)
                    // Start reading temperatures once zones are discovered
                    if (root.thermalZones.length > 0) {
                        root.updateTemperatures()
                    }
                }
            }
        }
    }

    Process {
        id: readTemperaturesProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["bash", "-c", "for hwmon in /sys/class/hwmon/hwmon*/; do if [ -d \"$hwmon\" ]; then name=$(cat \"$hwmon/name\" 2>/dev/null || basename \"$hwmon\"); for temp in \"$hwmon\"/temp*_input; do if [ -f \"$temp\" ]; then label_file=\"${temp/_input/_label}\"; label=$(cat \"$label_file\" 2>/dev/null || basename \"$temp\"); temp_val=$(cat \"$temp\" 2>/dev/null || echo \"0\"); if [ \"$temp_val\" != \"0\" ] && [ -n \"$temp_val\" ]; then echo \"${name}|${label}|${temp_val}\"; fi; fi; done; fi; done"]
        stdout: StdioCollector {
            id: temperaturesCollector
            onStreamFinished: {
                root.parseTemperatureData(temperaturesCollector.text)
            }
        }
    }

    Component.onCompleted: {
        discoverThermalZones()
        // Also try to read temperatures immediately (hwmon sensors don't need discovery)
        updateTemperatures()
    }
}
