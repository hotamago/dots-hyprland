pragma Singleton
import Quickshell
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    readonly property string homeDir: {
        const envHome = Quickshell.env("HOME");
        if (envHome && String(envHome).length > 0)
            return String(envHome);
        return FileUtils.trimFileProtocol(Directories.home);
    }

    readonly property string monitorsConfPath: `${root.homeDir}/.config/hypr/custom/monitors.conf`

    function ensureParentDir() {
        // `mkdir -p` is cheap; avoid depending on the file existing.
        Quickshell.execDetached(["bash", "-lc", `mkdir -p \"$(dirname \"${root.monitorsConfPath}\")\"`]);
    }

    function writeTextAndReload(text) {
        ensureParentDir();
        const content = String(text ?? "");
        const script = `cat > \"${root.monitorsConfPath}\" <<'QSCONFEOF'\n${content}\nQSCONFEOF\nhyprctl reload`;
        Quickshell.execDetached(["bash", "-lc", script]);
    }

    function writeMonitorLinesAndReload(lines, headerLines = null) {
        const out = [];
        if (headerLines && headerLines.length !== undefined) {
            for (let i = 0; i < headerLines.length; ++i)
                out.push(String(headerLines[i] ?? ""));
            if (headerLines.length > 0)
                out.push("");
        }
        for (let i = 0; i < (lines?.length ?? 0); ++i)
            out.push(String(lines[i] ?? ""));
        writeTextAndReload(out.join("\n"));
    }

    function keywordMonitorCommandsToMonitorLines(commands) {
        const lines = [];
        for (let i = 0; i < (commands?.length ?? 0); ++i) {
            const c = String(commands[i] ?? "").trim();
            if (!c)
                continue;
            if (c.indexOf("keyword monitor ") === 0) {
                lines.push("monitor=" + c.substring("keyword monitor ".length));
            } else {
                lines.push(c);
            }
        }
        return lines;
    }
}

