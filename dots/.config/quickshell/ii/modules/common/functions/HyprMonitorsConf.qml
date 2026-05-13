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

    readonly property string monitorsLuaPath: `${root.homeDir}/.config/hypr/custom/monitors.lua`
    readonly property string monitorsConfPath: root.monitorsLuaPath

    function ensureParentDir() {
        // `mkdir -p` is cheap; avoid depending on the file existing.
        Quickshell.execDetached(["bash", "-lc", `mkdir -p \"$(dirname \"${root.monitorsLuaPath}\")\"`]);
    }

    function writeTextAndReload(text) {
        ensureParentDir();
        const content = String(text ?? "");
        const script = `cat > \"${root.monitorsLuaPath}\" <<'QSCONFEOF'\n${content}\nQSCONFEOF\nhyprctl reload`;
        Quickshell.execDetached(["bash", "-lc", script]);
    }

    function luaQuote(value) {
        return "\"" + String(value ?? "")
            .replace(/\\/g, "\\\\")
            .replace(/"/g, "\\\"")
            .replace(/\r/g, "\\r")
            .replace(/\n/g, "\\n") + "\"";
    }

    function normalizeLuaComment(line) {
        const s = String(line ?? "");
        const trimmed = s.replace(/^\s+/, "");
        if (trimmed.indexOf("#") === 0)
            return s.substring(0, s.length - trimmed.length) + "--" + trimmed.substring(1);
        return s;
    }

    function monitorRuleToLua(line) {
        let s = String(line ?? "").trim();
        if (!s)
            return "";
        if (s.indexOf("--") === 0 || s.indexOf("#") === 0)
            return normalizeLuaComment(s);
        if (s.indexOf("hl.monitor(") === 0)
            return s;
        if (s.indexOf("keyword monitor ") === 0)
            s = s.substring("keyword monitor ".length).trim();
        else if (s.indexOf("monitor=") === 0)
            s = s.substring("monitor=".length).trim();
        else if (s.indexOf("monitor =") === 0)
            s = s.substring("monitor =".length).trim();
        else
            return s;

        const parts = s.split(",").map(part => String(part ?? "").trim());
        const output = parts[0] ?? "";
        if (parts.length >= 2 && parts[1] === "disable")
            return `hl.monitor({ output = ${luaQuote(output)}, disabled = true })`;

        const mode = parts[1] && parts[1].length > 0 ? parts[1] : "preferred";
        const position = parts[2] && parts[2].length > 0 ? parts[2] : "auto";
        const scale = parts[3] && parts[3].length > 0 ? parts[3] : "1";
        let out = `hl.monitor({ output = ${luaQuote(output)}, mode = ${luaQuote(mode)}, position = ${luaQuote(position)}, scale = ${scale}`;

        for (let i = 4; i < parts.length - 1; i += 2) {
            const key = parts[i];
            const value = parts[i + 1];
            if (!key || value === undefined)
                continue;
            if (key === "mirror" || key === "cm" || key === "sdr_eotf" || key === "icc")
                out += `, ${key} = ${luaQuote(value)}`;
            else
                out += `, ${key} = ${value}`;
        }

        return out + " })";
    }

    function writeMonitorLinesAndReload(lines, headerLines = null) {
        const out = [];
        if (headerLines && headerLines.length !== undefined) {
            for (let i = 0; i < headerLines.length; ++i)
                out.push(normalizeLuaComment(headerLines[i]));
            if (headerLines.length > 0)
                out.push("");
        }
        for (let i = 0; i < (lines?.length ?? 0); ++i)
            out.push(monitorRuleToLua(lines[i]));
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
