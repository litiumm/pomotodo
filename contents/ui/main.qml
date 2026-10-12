import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PC3
import org.kde.plasma.extras 2.0 as PlasmaExtras
import org.kde.kirigami 2.20 as Kirigami

Item {
    id: root

    property var cfg: plasmoid.configuration
    // "work", "break" or "longbreak"
    property string phase: "work"
    property int completed: 0
    // When the current focus session was first started (null when none)
    property var sessionStart: null
    property int remaining: cfg.workMinutes * 60
    property bool running: ticker.running

    // Open tasks from the Obsidian vault (see code/lifeos_tasks.py)
    property var tasks: []
    property string today: ""
    property string loadError: ""
    property var currentTask: {
        if (tasks.length === 0) return null
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].text === cfg.pinnedTask) return tasks[i]
        }
        return tasks[0]
    }
    property string currentText: currentTask ? currentTask.text : ""

    readonly property color workColor: "#e5484d"
    readonly property color breakColor: "#30a46c"
    readonly property color stateColor: !running ? PlasmaCore.Theme.textColor
                                       : phase === "work" ? workColor : breakColor
    // Nerd Font clock faces (12, 1, 2 … 10 o'clock); the hand advances as the session elapses
    readonly property var clockGlyphs: ["󱑊", "󱑀", "󱑁", "󱑂", "󱑃", "󱑄", "󱑅", "󱑆", "󱑇", "󱑈", "󱑉"]
    readonly property string clockFont: "Symbols Nerd Font Mono"
    readonly property real panelFontSize: PlasmaCore.Theme.defaultFont.pointSize * 1.50
    readonly property real progress: 1 - remaining / phaseSeconds(phase)
    readonly property string clockGlyph: clockGlyphs[Math.min(clockGlyphs.length - 1,
                                                     Math.floor(progress * clockGlyphs.length))]

    function fmt(s) {
        return Math.floor(s / 60) + ":" + ("0" + s % 60).slice(-2)
    }

    function phaseSeconds(p) {
        if (p === "break") return cfg.breakMinutes * 60
        if (p === "longbreak") return cfg.longBreakMinutes * 60
        return cfg.workMinutes * 60
    }

    function reset() {
        ticker.stop()
        sessionStart = null
        phase = "work"
        remaining = phaseSeconds(phase)
    }

    function nextPhase(notifyUser) {
        if (phase === "work") {
            // Only sessions that ran to the end are logged; Skip doesn't count
            if (notifyUser && sessionStart) logSession(sessionStart, new Date())
            sessionStart = null
            completed++
            phase = completed % 4 === 0 ? "longbreak" : "break"
        } else {
            phase = "work"
        }
        remaining = phaseSeconds(phase)
        if (phase === "work" && ticker.running) sessionStart = new Date()
        if (notifyUser) {
            notify(phase === "work" ? (currentText ? "Back to work: " + currentText : "Back to work!")
                 : phase === "longbreak" ? "Long break! " + completed + " pomodoros done."
                 : "Short break! Pomodoro #" + completed + " done.")
        }
    }

    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    function localPath(url) {
        return decodeURIComponent(url.toString().replace(/^file:\/\//, ""))
    }

    // Append the finished session to the vault's daily note (see code/log_session.py)
    function logSession(start, end) {
        exec.connectSource("python3 -I " + shellQuote(localPath(Qt.resolvedUrl("../code/log_session.py")))
                           + " " + shellQuote(cfg.vaultPath || "~/LifeOS")
                           + " " + Math.floor(start.getTime() / 1000) + " " + Math.floor(end.getTime() / 1000)
                           + " " + cfg.workMinutes + " " + shellQuote(currentText))
    }

    function notify(msg) {
        exec.connectSource("notify-send -a PomoTodo -i " + shellQuote(localPath(Qt.resolvedUrl("../icons/pomodoro.svg")))
                           + " 'Pomodoro' " + shellQuote(msg))
        if (cfg.playSound) {
            exec.connectSource("paplay /usr/share/sounds/freedesktop/stereo/complete.oga")
        }
    }

    function refreshTasks() {
        taskSource.connectSource("python3 -I " + shellQuote(localPath(Qt.resolvedUrl("../code/lifeos_tasks.py")))
                                 + " " + shellQuote(cfg.vaultPath || "~/LifeOS"))
    }

    function isOverdue(t) {
        return t.due !== "" && today !== "" && t.due < today
    }

    function openInObsidian(t) {
        Qt.openUrlExternally("obsidian://open?path=" + encodeURIComponent(t.file))
    }

    // Keep the idle timer in sync when durations change in settings
    Connections {
        target: plasmoid.configuration
        function onWorkMinutesChanged() { if (!ticker.running && root.phase === "work") root.remaining = root.phaseSeconds("work") }
        function onBreakMinutesChanged() { if (!ticker.running && root.phase === "break") root.remaining = root.phaseSeconds("break") }
        function onLongBreakMinutesChanged() { if (!ticker.running && root.phase === "longbreak") root.remaining = root.phaseSeconds("longbreak") }
        function onVaultPathChanged() { root.refreshTasks() }
    }

    Timer {
        id: ticker
        interval: 1000
        repeat: true
        onRunningChanged: if (running && root.phase === "work" && !root.sessionStart) root.sessionStart = new Date()
        onTriggered: {
            root.remaining--
            if (root.remaining <= 0) root.nextPhase(true)
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refreshTasks()
    }

    // Fire-and-forget shell commands (notify-send, paplay)
    PlasmaCore.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: disconnectSource(sourceName)
    }

    PlasmaCore.DataSource {
        id: taskSource
        engine: "executable"
        connectedSources: []
        onNewData: {
            disconnectSource(sourceName)
            try {
                var result = JSON.parse(data.stdout)
                root.today = result.today
                root.loadError = result.error || ""
                root.tasks = result.tasks
            } catch (e) {
                root.loadError = data.stderr || String(e)
                root.tasks = []
            }
        }
    }

    Plasmoid.icon: localPath(Qt.resolvedUrl("../icons/pomodoro.svg"))
    Plasmoid.toolTipMainText: currentText ? (phase === "work" ? "Working on: " : "Next up: ") + currentText : "Pomodoro"
    Plasmoid.toolTipSubText: fmt(remaining) + (running ? " remaining" : " (paused)") + " · " + completed + " pomodoros done"
                             + (tasks.length ? " · " + tasks.length + " open tasks" : "")
    Plasmoid.preferredRepresentation: Plasmoid.compactRepresentation

    // ---- Panel view ----
    Plasmoid.compactRepresentation: MouseArea {
        id: compact
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        Layout.minimumWidth: row.implicitWidth + PlasmaCore.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth

        // Left click: open popup. Middle click: start/pause.
        onClicked: {
            if (mouse.button === Qt.MiddleButton) {
                ticker.running ? ticker.stop() : ticker.start()
            } else {
                plasmoid.expanded = !plasmoid.expanded
            }
        }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: PlasmaCore.Units.smallSpacing

            PC3.Label {
                text: root.clockGlyph
                font.family: root.clockFont
                font.pixelSize: Math.round(PlasmaCore.Units.iconSizes.smallMedium * 1.0)
                color: root.stateColor
                opacity: root.running ? 1.0 : 0.6
            }
            PC3.Label {
                font.pointSize: root.panelFontSize
                text: root.fmt(root.remaining)
                opacity: root.running ? 1.0 : 0.6
            }
            PC3.Label {
                font.pointSize: root.panelFontSize
                visible: root.currentText !== ""
                text: "·"
                opacity: 0.5
            }
            PC3.Label {
                font.pointSize: root.panelFontSize
                visible: root.currentText !== ""
                Layout.maximumWidth: PlasmaCore.Units.gridUnit * 16
                elide: Text.ElideRight
                text: root.currentText
                opacity: root.running ? 1.0 : 0.6
            }
        }
    }

    // ---- Popup view ----
    Plasmoid.fullRepresentation: ColumnLayout {
        Layout.preferredWidth: PlasmaCore.Units.gridUnit * 22
        Layout.preferredHeight: PlasmaCore.Units.gridUnit * 26
        spacing: PlasmaCore.Units.smallSpacing

        Connections {
            target: plasmoid
            function onExpandedChanged() { if (plasmoid.expanded) root.refreshTasks() }
        }

        PC3.Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: PlasmaCore.Units.largeSpacing
            text: root.clockGlyph
            font.family: root.clockFont
            font.pixelSize: PlasmaCore.Units.iconSizes.large
            color: root.phase === "work" ? root.workColor : root.breakColor
        }
        PC3.Label {
            Layout.alignment: Qt.AlignHCenter
            font.pointSize: 28
            font.bold: true
            text: root.fmt(root.remaining)
        }
        PC3.Label {
            Layout.alignment: Qt.AlignHCenter
            opacity: 0.7
            text: (root.phase === "work" ? "Focus" : root.phase === "longbreak" ? "Long break" : "Short break")
                  + "  ·  " + root.completed + " done"
        }

        PC3.Label {
            visible: root.currentText !== ""
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: parent.width - PlasmaCore.Units.gridUnit * 2
            elide: Text.ElideRight
            font.bold: true
            text: root.currentText
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: PlasmaCore.Units.smallSpacing
            Layout.bottomMargin: PlasmaCore.Units.smallSpacing
            PC3.Button {
                icon.name: ticker.running ? "media-playback-pause" : "media-playback-start"
                text: ticker.running ? "Pause" : "Start"
                onClicked: ticker.running ? ticker.stop() : ticker.start()
            }
            PC3.Button {
                icon.name: "media-skip-forward"
                text: "Skip"
                onClicked: root.nextPhase(false)
            }
            PC3.Button {
                icon.name: "view-refresh"
                text: "Reset"
                onClicked: root.reset()
            }
        }

        PlasmaCore.SvgItem {
            Layout.fillWidth: true
            Layout.preferredHeight: lineSvg.elementSize("horizontal-line").height
            elementId: "horizontal-line"
            svg: PlasmaCore.Svg { id: lineSvg; imagePath: "widgets/line" }
        }

        RowLayout {
            PlasmaExtras.Heading {
                Layout.fillWidth: true
                level: 5
                text: "LifeOS tasks"
            }
            PC3.ToolButton {
                icon.name: "view-refresh"
                onClicked: root.refreshTasks()
                PC3.ToolTip.text: "Reload tasks from the vault"
                PC3.ToolTip.visible: hovered
            }
        }

        PC3.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list
                model: root.tasks
                clip: true
                spacing: 2

                delegate: RowLayout {
                    width: list.width

                    PC3.RadioButton {
                        Layout.fillWidth: true
                        checked: root.currentTask !== null && modelData.text === root.currentTask.text
                        text: modelData.text
                        onClicked: cfg.pinnedTask = modelData.text
                        PC3.ToolTip.text: "Focus on this task · from " + modelData.note
                        PC3.ToolTip.visible: hovered
                        PC3.ToolTip.delay: 800
                    }
                    PC3.Label {
                        visible: modelData.due !== ""
                        text: modelData.due.slice(5)
                        font: PlasmaCore.Theme.smallestFont
                        color: root.isOverdue(modelData) ? root.workColor : PlasmaCore.Theme.textColor
                        opacity: root.isOverdue(modelData) ? 1.0 : 0.6
                    }
                    PC3.ToolButton {
                        icon.name: "document-open"
                        onClicked: root.openInObsidian(modelData)
                        PC3.ToolTip.text: "Open " + modelData.note + " in Obsidian"
                        PC3.ToolTip.visible: hovered
                    }
                }

                PlasmaExtras.PlaceholderMessage {
                    parent: list
                    anchors.centerIn: list
                    width: list.width - PlasmaCore.Units.gridUnit * 2
                    visible: list.count === 0
                    iconName: root.loadError ? "dialog-warning" : "checkmark"
                    text: root.loadError ? "Couldn't read tasks" : "No open tasks in LifeOS"
                    explanation: root.loadError || "Add “- [ ] something” to any note and it'll show up here."
                }
            }
        }
    }
}
