# Internet Speed Test for Dux Shell

The plugin opens a separate 936 × 460 desktop window. Download and upload
gauges sweep on startup, then follow live readings. The gauge range
adjusts to the measured speeds. The window highlights the active server. Measurements try Cloudflare
first and switch to Selectel if the Cloudflare test fails. A successful run transfers about 16 MB on
Cloudflare or 33 MB on Selectel.

## Install

Requires Dux Shell 2.1, Quickshell, Python 3 and curl. Extract the
`NetworkSpeed` folder into `${XDG_CONFIG_HOME:-$HOME/.config}/dms/plugins/`.
Then run:

```sh
dms ipc call plugin-scan scan
dms ipc call plugins enable networkSpeed
dms ipc call network-speed openWindow
```

The last command opens the window and can also be used in a keyboard
binding. Disable the plugin from DMS settings or with
`dms ipc call plugins disable networkSpeed`.

## Button beside the Wi-Fi switch

Dux Shell 2.1 does not expose a plugin slot beside its Wi-Fi switches.
The included patch adds the speedometer beside the Wi-Fi switch in
both Control Center and Settings. It appears while Wi-Fi is connected and the plugin is enabled.
Settings also has a speedometer in the Available networks header.
Opening the window or pressing Retry resets both readings and starts a fresh measurement.

From the root of a writable copy of the DMS 2.1.0 UI, apply the patch with
`patch -p1 < /path/to/NetworkSpeed/wifi-row-dms-2.1.0.patch` and configure
DMS to use that UI directory via `dms --config /path/to/ui run --session`.
Review the patch against the new UI when updating DMS. The IPC launcher
works with the standard interface.

The bundled JetBrains Mono font files are licensed under the SIL Open Font
License. See `desktop/fonts/OFL.txt`.
