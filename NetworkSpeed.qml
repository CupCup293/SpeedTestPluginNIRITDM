pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Services

PluginComponent {
    id: root

    readonly property string desktopPath: pluginService.getPluginPath(pluginId) + "/desktop"

    function openWindow() {
        const colors = {
            card: String(Theme.surfaceContainerHigh),
            text: String(Theme.surfaceText),
            muted: String(Theme.surfaceVariantText),
            outline: String(Theme.outlineVariant),
            accent: String(Theme.primary),
            error: String(Theme.error)
        };
        PopoutService.closeControlCenter();
        Quickshell.execDetached(["sh", desktopPath + "/launch", JSON.stringify(colors)]);
    }

    Component.onDestruction: {
        if (desktopPath.startsWith("/") && desktopPath !== "/desktop")
            Quickshell.execDetached(["qs", "ipc", "-p", desktopPath, "call", "network-speed", "shutdown"]);
    }

    IpcHandler {
        target: "network-speed"

        function openWindow(): string {
            root.openWindow();
            return "ok";
        }
    }
}
