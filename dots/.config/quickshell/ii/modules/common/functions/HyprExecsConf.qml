pragma Singleton
import qs.modules.common
import qs.modules.common.functions
import Quickshell

Singleton {
    id: root

    readonly property string homeDir: {
        const envHome = Quickshell.env("HOME");
        if (envHome && String(envHome).length > 0)
            return String(envHome);
        return FileUtils.trimFileProtocol(Directories.home);
    }

    readonly property string execsLuaPath: `${root.homeDir}/.config/hypr/custom/execs.lua`
    readonly property string execsConfPath: root.execsLuaPath

    function ensureParentDir() {
        // `mkdir -p` is cheap; avoid depending on the file existing.
        Quickshell.execDetached(["bash", "-lc", `mkdir -p \"$(dirname \"${root.execsLuaPath}\")\"`]);
    }

    function writeTextAndReload(text) {
        ensureParentDir();
        const content = String(text ?? "");
        const script = `cat > \"${root.execsLuaPath}\" <<'QSII_EXECS_EOF'\n${content}\nQSII_EXECS_EOF\nhyprctl reload`;
        Quickshell.execDetached(["bash", "-lc", script]);
    }
}
