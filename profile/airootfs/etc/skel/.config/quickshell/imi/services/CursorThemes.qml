pragma Singleton
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

// Enumerates installed cursor themes (via scripts/cursor/scan-cursor-themes.py)
// and applies one (via scripts/cursor/apply-cursor-theme.sh) for the Cursor
// settings page. Detection lives in the python scanner so it is unit-testable;
// this singleton just runs it and parses the JSON, mirroring IconThemes.
Singleton {
    id: root

    property var themes: []
    property bool loading: false
    readonly property bool available: themes.length > 0

    // Marks the active card in Settings > Cursor. The config default is Adwaita,
    // the theme the adwaita-cursors package installs, so no live probe is needed
    // on a fresh image. A config carried over from a machine that had another
    // theme is reconciled against the scan instead (see reconcileActiveTheme).
    readonly property string activeId: Config.options.hyprland.cursor.theme

    signal refreshed()

    // Where the scanner drops per-theme pointer previews - PNGs it extracts
    // from each theme's own Xcursor file, since Qt cannot decode that
    // container. The scanner creates the directory itself.
    readonly property string previewDir: FileUtils.trimFileProtocol(`${Directories.cache}/cursor-previews`)

    function load() {
        if (scanProcess.running) return;
        root.loading = true;
        scanProcess.command = ["python3", Directories.cursorThemeScanScriptPath,
            "--preview-dir", root.previewDir];
        scanProcess.running = true;
    }

    // Theme and size apply together: hyprctl setcursor takes both, and GTK
    // stores them as two keys of one choice. The values are validated again
    // inside the script; config is recorded only on success, so a failed
    // apply cannot persist a theme or size the system never adopted.
    function apply(themeId, size) {
        if (applyProcess.running) return;
        applyProcess.pendingTheme = themeId;
        applyProcess.pendingSize = size;
        applyProcess.command = [Directories.cursorThemeApplyScriptPath, themeId, String(size)];
        applyProcess.running = true;
    }

    // A persisted theme that is not installed any more (a config carried over
    // from a machine that had another theme) would be marked active here while
    // apply_saved_cursor.sh fell back to Adwaita at startup. Adopt the same
    // fallback once the scan says what is really installed, so Settings shows
    // the pointer the compositor actually has rather than one that cannot load.
    function reconcileActiveTheme() {
        if (root.themes.length === 0)
            return;
        const current = Config.options.hyprland.cursor.theme;
        if (root.themes.some(theme => theme.id === current))
            return;
        Config.options.hyprland.cursor.theme =
            root.themes.some(theme => theme.id === "Adwaita") ? "Adwaita" : root.themes[0].id;
    }

    Process {
        id: scanProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    root.themes = Array.isArray(parsed) ? parsed : [];
                } catch (e) {
                    root.themes = [];
                }
            }
        }
        onExited: exitCode => {
            root.loading = false;
            root.reconcileActiveTheme();
            root.refreshed();
        }
    }

    Process {
        id: applyProcess
        property string pendingTheme: ""
        property int pendingSize: 24
        onExited: exitCode => {
            if (exitCode === 0) {
                Config.options.hyprland.cursor.theme = applyProcess.pendingTheme;
                Config.options.hyprland.cursor.size = applyProcess.pendingSize;
            }
            applyProcess.pendingTheme = "";
        }
    }

    Component.onCompleted: root.load()
}
