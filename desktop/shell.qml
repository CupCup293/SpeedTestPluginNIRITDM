//@ pragma AppId local.network-speed
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Io

ShellRoot {
    Window {
        id: window

        title: "Internet Speed Test"
        width: 936
        height: 460
        minimumWidth: 936
        maximumWidth: 936
        minimumHeight: 460
        maximumHeight: 460
        visible: true
        color: "transparent"
        flags: Qt.FramelessWindowHint

        readonly property var defaultColors: ({
            card: "#28252f", text: "#ede8f3",
            muted: "#ccc4d4", outline: "#686375", accent: "#d0bcff",
            error: "#ffb4ab"
        })
        readonly property string fontFamily: monoRegular.status === FontLoader.Ready ? monoRegular.name : "monospace"

        FontLoader {
            id: monoRegular
            source: "fonts/JetBrainsMono-Regular.ttf"
        }

        FontLoader {
            source: "fonts/JetBrainsMono-SemiBold.ttf"
        }
        property var colors: paletteFrom(Quickshell.env("NETWORK_SPEED_COLORS"))

        function paletteFrom(value) {
            return Object.assign({}, defaultColors, JSON.parse(value || "{}"));
        }

        onActiveChanged: {
            if (!active && visible && !closing)
                hide();
        }
        Component.onCompleted: Qt.callLater(() => {
            window.requestActivate();
            window.start();
        })

        property var result: null
        property string activeServer: ""
        property bool failed: false
        property bool closing: false
        property bool restartPending: false
        signal measurementStarted()
        property real ceiling: 100
        property real downloadMbps: -1
        property real uploadMbps: -1

        function updateScale(value) {
            const stops = [100, 250, 500, 1000, 2500, 5000, 10000];
            const next = stops.find(stop => value <= stop * 0.92) ?? stops[stops.length - 1];
            ceiling = Math.max(ceiling, next, value);
        }

        onClosing: shutdown()

        function shutdown() {
            closing = true;
            if (test.running)
                test.running = false;
            else
                Qt.quit();
        }

        IpcHandler {
            target: "network-speed"
            function shutdown(): string {
                window.shutdown();
                return "ok";
            }

            function reveal(colors: string): string {
                window.colors = window.paletteFrom(colors);
                window.show();
                window.requestActivate();
                window.start();
                return "ok";
            }
        }

        Process {
            id: test

            command: ["/usr/bin/python3", decodeURIComponent(Qt.resolvedUrl("measure.py").toString().slice(7))]
            stdout: SplitParser {
                onRead: line => {
                    if (window.restartPending || window.closing)
                        return;
                    const update = JSON.parse(line);
                    if (update.result) {
                        window.result = update.result;
                        window.updateScale(Math.max(update.result.down, update.result.up));
                        window.downloadMbps = update.result.down;
                        window.uploadMbps = update.result.up;
                    } else if (update.server) {
                        window.activeServer = update.server;
                        window.ceiling = 100;
                        window.downloadMbps = 0;
                        window.uploadMbps = 0;
                    } else {
                        window.updateScale(update.mbps);
                        if (update.phase === "down")
                            window.downloadMbps = update.mbps;
                        else
                            window.uploadMbps = update.mbps;
                    }
                }
            }
            onExited: exitCode => {
                if (window.closing) {
                    Qt.quit();
                    return;
                }
                if (window.restartPending) {
                    Qt.callLater(() => {
                        if (window.closing)
                            return;
                        window.restartPending = false;
                        window.start();
                    });
                    return;
                }
                if (exitCode !== 0) {
                    window.failed = true;
                    window.activeServer = "";
                    window.downloadMbps = -1;
                    window.uploadMbps = -1;
                }
            }
        }

        Shortcut {
            sequence: "Escape"
            onActivated: window.hide()
        }

        function start() {
            if (closing || restartPending)
                return;
            result = null;
            activeServer = "";
            failed = false;
            ceiling = 100;
            downloadMbps = 0;
            uploadMbps = 0;
            if (test.running) {
                restartPending = true;
                test.running = false;
                return;
            }
            measurementStarted();
            test.running = true;
        }

        Rectangle {
            anchors.fill: parent
            radius: 20
            color: Qt.alpha(Qt.darker(window.colors.card, 1.14), 0.97)
            border.color: Qt.alpha(window.colors.outline, 0.55)
        }

        Item {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            height: 62

            DragHandler {
                target: null
                onActiveChanged: if (active) window.startSystemMove()
            }

            Label {
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                text: window.title
                font.family: window.fontFamily
                font.pixelSize: 21
                font.weight: Font.DemiBold
                color: window.colors.text
            }

            Button {
                id: closeButton
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 34
                text: "×"
                Accessible.name: "Close"
                background: Rectangle {
                    radius: width / 2
                    color: closeButton.hovered || closeButton.activeFocus ? window.colors.card : "transparent"
                }
                contentItem: Label {
                    text: closeButton.text
                    font.family: window.fontFamily
                    font.pixelSize: 23
                    color: window.colors.muted
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: window.hide()
            }
        }

        Row {
            anchors.top: header.bottom
            anchors.topMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 80

            SpeedDial {
                label: "Download"
                speed: window.downloadMbps
                limit: window.ceiling
                colors: window.colors
            }

            SpeedDial {
                label: "Upload"
                speed: window.uploadMbps
                limit: window.ceiling
                colors: window.colors
            }
        }

        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 22
            height: 45

            Label {
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                text: window.failed ? "Speed test servers unavailable"
                    : window.result ? "Latency to " + window.result.server + " · " + Math.round(window.result.latency) + " ms"
                    : ""
                font.family: window.fontFamily
                font.pixelSize: 14
                color: window.failed ? window.colors.error : window.colors.muted
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Label {
                    text: "Auto"
                    font.family: window.fontFamily
                    font.pixelSize: 13
                    color: window.colors.muted
                }

                Repeater {
                    model: ["Cloudflare", "Selectel"]
                    delegate: Label {
                        required property string modelData
                        readonly property bool selected: window.activeServer === modelData
                        text: modelData
                        Accessible.name: selected ? modelData + " (active)" : modelData
                        font.family: window.fontFamily
                        font.pixelSize: 13
                        font.weight: selected ? Font.DemiBold : Font.Normal
                        color: selected ? window.colors.accent : window.colors.muted
                    }
                }
            }

            Button {
                id: retry
                anchors.horizontalCenter: parent.horizontalCenter
                width: 116
                height: 42
                text: "Retry"
                background: Rectangle {
                    radius: height / 2
                    color: retry.enabled ? window.colors.accent : window.colors.card
                    opacity: retry.down ? 0.8 : retry.hovered ? 0.9 : 1
                    border.color: retry.activeFocus ? window.colors.text : "transparent"
                }
                contentItem: Label {
                    text: retry.text
                    font.family: window.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    color: retry.enabled ? Qt.darker(window.colors.accent, 5) : window.colors.muted
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: window.start()
            }
        }

        Shortcut {
            sequence: "Return"
            onActivated: window.start()
        }
    }

    component SpeedDial: Item {
        id: dial

        required property string label
        required property var colors
        required property real speed
        required property real limit
        property real needleSweep: 0
        readonly property real measuredSweep: 260 * Math.min(1, Math.max(0, speed) / limit)

        Behavior on needleSweep {
            enabled: !ignition.running
            NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
        }

        onMeasuredSweepChanged: {
            if (!ignition.running)
                needleSweep = measuredSweep;
        }

        Connections {
            target: window

            function onMeasurementStarted() {
                ignition.restart();
            }
        }

        SequentialAnimation {
            id: ignition

            PropertyAction { target: dial; property: "needleSweep"; value: 0 }

            NumberAnimation {
                target: dial
                property: "needleSweep"
                to: 260
                duration: 550
                easing.type: Easing.InOutCubic
            }

            NumberAnimation {
                target: dial
                property: "needleSweep"
                to: 0
                duration: 650
                easing.type: Easing.OutCubic
            }

            onFinished: dial.needleSweep = dial.measuredSweep
        }

        width: 292
        height: width

        Shape {
            id: arc

            width: 262
            height: width
            anchors.centerIn: parent

            ShapePath {
                strokeWidth: 4
                strokeColor: dial.colors.outline
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: arc.width / 2
                    centerY: arc.height / 2
                    radiusX: arc.width / 2 - 6
                    radiusY: radiusX
                    startAngle: 140
                    sweepAngle: 260
                }
            }

            ShapePath {
                strokeWidth: 3
                strokeColor: dial.colors.accent
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: arc.width / 2
                    centerY: arc.height / 2
                    radiusX: arc.width / 2 - 6
                    radiusY: radiusX
                    startAngle: 140
                    sweepAngle: dial.needleSweep
                }
            }

            Repeater {
                model: 27
                delegate: Item {
                    id: tick
                    required property int index
                    anchors.fill: arc
                    rotation: -130 + index * 10

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 12
                        width: 1
                        height: tick.index % 5 === 0 ? 10 : 5
                        color: tick.index % 5 === 0 ? dial.colors.muted : dial.colors.outline
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: ignition.running || dial.speed >= 0
                rotation: -130 + dial.needleSweep

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 20
                    width: 2
                    height: 104
                    gradient: Gradient {
                        GradientStop { position: 0; color: dial.colors.accent }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
            }

            Column {
                y: 137
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 5

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: dial.speed < 0 ? "—" : dial.speed.toLocaleString(Qt.locale("en_US"), "f", 1)
                    color: window.failed ? dial.colors.error : dial.colors.text
                    font.family: window.fontFamily
                    font.pixelSize: 42
                    font.weight: Font.DemiBold
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Mbps"
                    color: dial.colors.muted
                    font.family: window.fontFamily
                    font.pixelSize: 14
                }
            }
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 258
            text: dial.label.toUpperCase()
            font.letterSpacing: 1.5
            color: dial.colors.muted
            font.family: window.fontFamily
            font.pixelSize: 17
            font.weight: Font.DemiBold
        }
    }
}
