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

    readonly property string execsConfPath: `${root.homeDir}/.config/hypr/custom/execs.conf`

    function ensureParentDir() {
        // `mkdir -p` is cheap; avoid depending on the file existing.
        Quickshell.execDetached(["bash", "-lc", `mkdir -p \"$(dirname \"${root.execsConfPath}\")\"`]);
    }

    function writeTextAndReload(text) {
        ensureParentDir();
        const content = String(text ?? "");
        const script = `cat > \"${root.execsConfPath}\" <<'QSII_EXECS_EOF'\n${content}\nQSII_EXECS_EOF\nhyprctl reload`;
        Quickshell.execDetached(["bash", "-lc", script]);
    }
}

