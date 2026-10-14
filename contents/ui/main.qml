import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Shapes 1.15
import QtQuick.Controls 2.15 as QQC2
import QtGraphicalEffects 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PC3
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
    readonly property bool started: running || phase !== "work" || remaining < phaseSeconds(phase)
    readonly property real fractionLeft: remaining / phaseSeconds(phase)

    // Tasks from the Obsidian vault: open ones plus those done today (see code/lifeos.py)
    property var tasks: []
    property string today: ""
    property string loadError: ""
    property string actionError: ""
    readonly property int doneCount: tasks.filter(function (t) { return t.done }).length
    readonly property int openCount: tasks.length - doneCount
    property var currentTask: {
        var open = tasks.filter(function (t) { return !t.done })
        if (open.length === 0) return null
        for (var i = 0; i < open.length; i++) {
            if (open[i].text === cfg.pinnedTask) return open[i]
        }
        return open[0]
    }
    property string currentText: currentTask ? currentTask.text : ""

    // Panel text size relative to the Plasma default font
    readonly property real panelFontScale: 1.25

    readonly property string fontFamily: "Segoe UI"

    // Popup palette: Plasma theme colours, plus a teal accent (the theme's own
    // highlight is too pale to carry white icons)
    QtObject {
        id: pal
        readonly property color text: PlasmaCore.Theme.textColor
        readonly property bool dark: text.r * 0.299 + text.g * 0.587 + text.b * 0.114 > 0.5
        function tint(a) { return Qt.rgba(text.r, text.g, text.b, a) }

        readonly property color ink: text
        readonly property color inkSoft: tint(0.7)
        readonly property color eyebrow: tint(0.6)
        readonly property color muted: tint(0.45)
        readonly property color card: tint(0.05)
        readonly property color cardBorder: tint(0.10)
        readonly property color track: tint(0.15)
        readonly property color hover: tint(0.07)
        readonly property color button: tint(0.10)
        readonly property color buttonHover: tint(0.16)
        readonly property color accent: dark ? "#4a9fc2" : "#2f7d9b"
        readonly property color accentText: dark ? "#7cc0dc" : "#25657e"
        readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, 0.22)
        readonly property color accentSoftHover: Qt.rgba(accent.r, accent.g, accent.b, 0.32)
        readonly property color breakAccent: dark ? "#4cb382" : "#3a9469"
        readonly property color danger: PlasmaCore.Theme.negativeTextColor
    }
    readonly property color phaseAccent: phase === "work" ? pal.accent : pal.breakAccent
    // Brighter variants for the dark panel
    readonly property color panelAccent: phase === "work" ? "#5aa9c9" : "#5bbf8a"

    function fmt(s) {
        return Math.floor(s / 60) + ":" + ("0" + s % 60).slice(-2)
    }

    function phaseSeconds(p) {
        if (p === "break") return cfg.breakMinutes * 60
        if (p === "longbreak") return cfg.longBreakMinutes * 60
        return cfg.workMinutes * 60
    }

    function phaseName(p) {
        return p === "work" ? "Focus session" : p === "longbreak" ? "Long break" : "Short break"
    }

    function toggleTimer() {
        ticker.running ? ticker.stop() : ticker.start()
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

    function lifeos(args) {
        var cmd = "python3 -I " + shellQuote(localPath(Qt.resolvedUrl("../code/lifeos.py")))
        return cmd + " " + args.map(shellQuote).join(" ")
    }

    function vault() {
        return cfg.vaultPath || "~/LifeOS"
    }

    function refreshTasks() {
        taskSource.connectSource(lifeos(["list", vault()]))
    }

    // Append the finished session to the vault's daily note
    function logSession(start, end) {
        writer.connectSource(lifeos(["log", vault(), Math.floor(start.getTime() / 1000),
                                     Math.floor(end.getTime() / 1000), cfg.workMinutes, currentText]))
    }

    function toggleTask(t) {
        if (t.recurring) {
            // Completing a recurring task needs the Tasks plugin to create the next one
            openInObsidian(t)
            return
        }
        // Update the list right away; the reload after the write confirms it
        tasks = tasks.map(function (x) {
            return x.file === t.file && x.line === t.line ? Object.assign({}, x, { done: !x.done }) : x
        })
        writer.connectSource(lifeos(["toggle", vault(), t.file, t.line, t.raw]))
    }

    function addTask(text) {
        text = text.trim()
        if (text) writer.connectSource(lifeos(["add", vault(), text]))
    }

    function notify(msg) {
        exec.connectSource("notify-send -a PomoTodo -i " + shellQuote(localPath(Qt.resolvedUrl("../icons/pomodoro.svg")))
                           + " 'Pomodoro' " + shellQuote(msg))
        if (cfg.playSound) {
            exec.connectSource("paplay /usr/share/sounds/freedesktop/stereo/complete.oga")
        }
    }

    function isOverdue(t) {
        return t.due !== "" && today !== "" && t.due < today
    }

    function shortDate(iso) {
        var p = iso.split("-")
        return Qt.formatDate(new Date(p[0], p[1] - 1, p[2]), "MMM d")
    }

    function openInObsidian(t) {
        Qt.openUrlExternally("obsidian://open?path=" + encodeURIComponent(t.file))
    }

    // ---- Popup open/close ----
    property Item compactItem: null
    property double lastHidden: 0

    function togglePopup() {
        if (popup.visible) {
            popup.visible = false
        } else if (Date.now() - lastHidden > 250) {  // the click that closed it
            refreshTasks()
            popup.visible = true
            popup.requestActivate()
        }
    }

    // Keep the idle timer in sync when durations change in settings
    Connections {
        target: plasmoid.configuration
        function onWorkMinutesChanged() { if (!ticker.running && root.phase === "work") root.remaining = root.phaseSeconds("work") }
        function onBreakMinutesChanged() { if (!ticker.running && root.phase === "break") root.remaining = root.phaseSeconds("break") }
        function onLongBreakMinutesChanged() { if (!ticker.running && root.phase === "longbreak") root.remaining = root.phaseSeconds("longbreak") }
        function onVaultPathChanged() { root.refreshTasks() }
    }

    // The global shortcut opens our popup instead of Plasma's
    Connections {
        target: plasmoid
        function onActivated() { root.togglePopup() }
        function onExpandedChanged() {
            if (plasmoid.expanded) {
                plasmoid.expanded = false
                root.togglePopup()
            }
        }
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

    Timer {
        id: errorTimeout
        interval: 6000
        onTriggered: root.actionError = ""
    }

    // Fire-and-forget shell commands (notify-send, paplay)
    PlasmaCore.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: disconnectSource(sourceName)
    }

    // Vault writes (toggle, add, log); reload the list after each
    PlasmaCore.DataSource {
        id: writer
        engine: "executable"
        connectedSources: []
        onNewData: {
            disconnectSource(sourceName)
            if (data["exit code"] !== 0) {
                root.actionError = (data.stderr || "Couldn't update the vault").trim()
                errorTimeout.restart()
            }
            root.refreshTasks()
        }
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
    Plasmoid.toolTipMainText: currentText ? (phase === "work" ? "Working on: " : "Next up: ") + currentText : phaseName(phase)
    Plasmoid.toolTipSubText: fmt(remaining) + (running ? " remaining" : " (paused)") + " · " + completed + " pomodoros done"
    Plasmoid.preferredRepresentation: Plasmoid.compactRepresentation

    // ---- Panel view ----
    Plasmoid.compactRepresentation: MouseArea {
        id: compact
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true
        Layout.minimumWidth: pill.implicitWidth + 6
        Layout.preferredWidth: Layout.minimumWidth

        Component.onCompleted: root.compactItem = compact

        // Left click: open popup. Middle click: start/pause.
        onClicked: mouse.button === Qt.MiddleButton ? root.toggleTimer() : root.togglePopup()

        readonly property color fg: PlasmaCore.Theme.textColor

        Rectangle {
            id: pill
            anchors.fill: parent
            anchors.margins: 3
            radius: 8
            implicitWidth: pillRow.implicitWidth + 16
            color: Qt.rgba(compact.fg.r, compact.fg.g, compact.fg.b,
                           compact.containsMouse || popup.visible ? 0.14 : 0.07)
            Behavior on color { ColorAnimation { duration: 120 } }

            RowLayout {
                id: pillRow
                anchors.verticalCenter: parent.verticalCenter
                x: 8
                spacing: 10

                // Progress ring with minutes left
                Item {
                    id: ring
                    readonly property real size: Math.max(20, pill.height - 10)
                    Layout.preferredWidth: size
                    Layout.preferredHeight: size
                    opacity: root.started && !root.running ? 0.6 : 1.0

                    Shape {
                        anchors.fill: parent
                        layer.enabled: true
                        layer.samples: 4
                        ShapePath {
                            strokeColor: Qt.rgba(compact.fg.r, compact.fg.g, compact.fg.b, 0.18)
                            strokeWidth: 3
                            fillColor: "transparent"
                            PathAngleArc {
                                centerX: ring.size / 2; centerY: ring.size / 2
                                radiusX: ring.size / 2 - 2; radiusY: ring.size / 2 - 2
                                startAngle: 0; sweepAngle: 360
                            }
                        }
                        ShapePath {
                            strokeColor: root.panelAccent
                            strokeWidth: 3
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: ring.size / 2; centerY: ring.size / 2
                                radiusX: ring.size / 2 - 2; radiusY: ring.size / 2 - 2
                                startAngle: -90; sweepAngle: 360 * root.fractionLeft
                            }
                        }
                    }
                    PC3.Label {
                        anchors.centerIn: parent
                        text: Math.ceil(root.remaining / 60)
                        font.pixelSize: ring.size * 0.35
                        font.family: root.fontFamily
                    }
                }

                ColumnLayout {
                    spacing: 0
                    PC3.Label {
                        Layout.maximumWidth: PlasmaCore.Units.gridUnit * 36
                        elide: Text.ElideRight
                        text: root.phase === "work" && root.currentText ? root.currentText : root.phaseName(root.phase)
                        font.pointSize: PlasmaCore.Theme.defaultFont.pointSize * root.panelFontScale * 0.8
                        font.family: root.fontFamily
                    }
                    PC3.Label {
                        text: root.fmt(root.remaining) + "  ·  "
                              + (root.started && !root.running ? "Paused"
                                 : root.openCount + (root.openCount === 1 ? " task left" : " tasks left"))
                        Layout.bottomMargin: 2
                        font.pointSize: PlasmaCore.Theme.defaultFont.pointSize * root.panelFontScale * 0.6
                        font.family: root.fontFamily
                        opacity: 0.7
                    }
                }

                Kirigami.Icon {
                    Layout.preferredWidth: PlasmaCore.Units.iconSizes.small
                    Layout.preferredHeight: PlasmaCore.Units.iconSizes.small
                    Layout.leftMargin: 6
                    source: "arrow-down"
                    isMask: true
                    color: compact.fg
                    opacity: 0.6
                    rotation: popup.visible ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 150 } }
                }
            }
        }
    }

    // ---- Popup ----
    // Own dialog (not Plasma's expanded view) so the panel pill controls it
    PlasmaCore.Dialog {
        id: popup
        visualParent: root.compactItem
        location: plasmoid.location
        type: PlasmaCore.Dialog.AppletPopup
        flags: Qt.WindowStaysOnTopHint
        backgroundHints: PlasmaCore.Dialog.StandardBackground
        hideOnWindowDeactivate: true
        onVisibleChanged: if (!visible) root.lastHidden = Date.now()

        mainItem: Item {
            id: popupRoot
            width: card.width
            height: card.height
            focus: true
            Keys.onEscapePressed: popup.visible = false

            Item {
                id: card
                width: 360
                height: content.implicitHeight + 24

                ColumnLayout {
                    id: content
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 0

                    // Header
                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            spacing: 2
                            Eyebrow { text: "Focus space" }
                            Text {
                                text: "Make today count."
                                color: pal.ink
                                font.pixelSize: 21
                                font.family: root.fontFamily
                            }
                        }
                        Item { Layout.fillWidth: true }
                        RoundButton {
                            size: 34
                            radius: 9
                            color: hovered ? pal.buttonHover : pal.button
                            onClicked: popup.visible = false
                            Repeater {
                                model: [45, -45]
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 14; height: 2; radius: 1
                                    rotation: modelData
                                    color: pal.ink
                                }
                            }
                        }
                    }

                    // Timer card
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 16
                        implicitHeight: timerCol.implicitHeight + 36
                        radius: 14
                        color: pal.card
                        border.color: pal.cardBorder

                        ColumnLayout {
                            id: timerCol
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 0

                            RowLayout {
                                spacing: 8
                                Rectangle {
                                    implicitWidth: 12; implicitHeight: 12; radius: 6
                                    color: Qt.rgba(root.phaseAccent.r, root.phaseAccent.g, root.phaseAccent.b, 0.25)
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 6; height: 6; radius: 3
                                        color: root.phaseAccent
                                        SequentialAnimation on opacity {
                                            running: root.running
                                            loops: Animation.Infinite
                                            onRunningChanged: if (!running) parent.opacity = 1
                                            NumberAnimation { to: 0.3; duration: 900; easing.type: Easing.InOutQuad }
                                            NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                                        }
                                    }
                                }
                                Eyebrow {
                                    color: root.phase === "work" ? pal.accentText : pal.breakAccent
                                    text: !root.started ? "Ready to focus"
                                        : !root.running ? "Paused"
                                        : root.phase === "work" ? "Focusing"
                                        : root.phase === "longbreak" ? "Long break" : "Short break"
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 10
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        text: root.fmt(root.remaining)
                                        color: pal.ink
                                        font.pixelSize: 48
                                        font.family: root.fontFamily
                                        font.letterSpacing: -1
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        color: pal.inkSoft
                                        font.pixelSize: 13
                                        font.family: root.fontFamily
                                        text: root.phase === "work"
                                              ? cfg.workMinutes + " minute session" + (root.completed ? "  ·  " + root.completed + " done" : "")
                                              : (root.phase === "longbreak" ? cfg.longBreakMinutes : cfg.breakMinutes) + " minute break"
                                    }
                                }

                                RoundButton {
                                    visible: root.started
                                    size: 36
                                    iconSource: "view-refresh"
                                    tooltip: "Reset"
                                    onClicked: root.reset()
                                }
                                RoundButton {
                                    visible: root.started
                                    size: 36
                                    iconSource: "media-skip-forward"
                                    tooltip: "Skip to " + (root.phase === "work" ? "break" : "focus")
                                    onClicked: root.nextPhase(false)
                                }

                                // Play / pause
                                Rectangle {
                                    id: playButton
                                    implicitWidth: 56; implicitHeight: 56; radius: 28
                                    color: playMouse.pressed ? Qt.darker(root.phaseAccent, 1.25)
                                         : playMouse.containsMouse ? Qt.darker(root.phaseAccent, 1.1) : root.phaseAccent
                                    layer.enabled: true
                                    layer.effect: DropShadow {
                                        verticalOffset: 3
                                        radius: 10
                                        samples: 21
                                        color: Qt.rgba(root.phaseAccent.r, root.phaseAccent.g, root.phaseAccent.b, 0.45)
                                        transparentBorder: true
                                    }

                                    Shape {
                                        visible: !root.running
                                        anchors.centerIn: parent
                                        anchors.horizontalCenterOffset: 2
                                        width: 14; height: 16
                                        layer.enabled: true
                                        layer.samples: 4
                                        ShapePath {
                                            strokeColor: "white"
                                            strokeWidth: 2
                                            fillColor: "transparent"
                                            joinStyle: ShapePath.RoundJoin
                                            startX: 1; startY: 1
                                            PathLine { x: 13; y: 8 }
                                            PathLine { x: 1; y: 15 }
                                            PathLine { x: 1; y: 1 }
                                        }
                                    }
                                    Row {
                                        visible: root.running
                                        anchors.centerIn: parent
                                        spacing: 5
                                        Rectangle { width: 3.5; height: 15; radius: 1.5; color: "white" }
                                        Rectangle { width: 3.5; height: 15; radius: 1.5; color: "white" }
                                    }

                                    MouseArea {
                                        id: playMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleTimer()
                                    }
                                }
                            }

                            // Progress
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.topMargin: 16
                                implicitHeight: 4
                                radius: 2
                                color: pal.track
                                Rectangle {
                                    width: parent.width * (1 - root.fractionLeft)
                                    height: parent.height
                                    radius: 2
                                    color: root.phaseAccent
                                    Behavior on width { NumberAnimation { duration: 400 } }
                                }
                            }
                        }
                    }

                    // Tasks header
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 22
                        Layout.leftMargin: 2
                        ColumnLayout {
                            spacing: 2
                            Eyebrow { text: "Today" }
                            Text {
                                text: "Tasks"
                                color: pal.ink
                                font.pixelSize: 17
                                font.family: root.fontFamily
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            visible: root.tasks.length > 0
                            implicitWidth: countLabel.implicitWidth + 18
                            implicitHeight: 24
                            radius: 12
                            color: pal.button
                            Text {
                                id: countLabel
                                anchors.centerIn: parent
                                text: root.doneCount + " of " + root.tasks.length
                                color: pal.eyebrow
                                font.pixelSize: 12
                                font.family: root.fontFamily
                            }
                        }
                    }

                    // Task list
                    ListView {
                        id: list
                        readonly property int rowHeight: 38
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        Layout.preferredHeight: count === 0 ? 56 : Math.min(count, 6) * rowHeight
                        model: root.tasks
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                            policy: list.count > 6 ? QQC2.ScrollBar.AsNeeded : QQC2.ScrollBar.AlwaysOff
                            contentItem: Rectangle {
                                implicitWidth: 4
                                radius: 2
                                color: pal.tint(0.3)
                                opacity: parent.active ? 1 : 0.6
                            }
                            background: Item {}
                        }

                        delegate: Item {
                            id: row
                            width: list.width
                            height: list.rowHeight
                            readonly property bool isCurrent: !modelData.done && root.currentTask !== null
                                && modelData.file === root.currentTask.file && modelData.line === root.currentTask.line

                            Rectangle {
                                anchors.fill: parent
                                anchors.topMargin: 1
                                anchors.bottomMargin: 1
                                radius: 8
                                color: row.isCurrent ? pal.accentSoft : rowMouse.containsMouse ? pal.hover : "transparent"
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                // Click: focus on this task. Double-click: open its note.
                                onClicked: if (!modelData.done) cfg.pinnedTask = modelData.text
                                onDoubleClicked: root.openInObsidian(modelData)
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 12

                                // Checkbox
                                Rectangle {
                                    implicitWidth: 20; implicitHeight: 20; radius: 5
                                    color: modelData.done ? pal.accent : checkMouse.containsMouse ? pal.hover : "transparent"
                                    border.width: modelData.done ? 0 : 1.5
                                    border.color: checkMouse.containsMouse ? pal.accent : pal.tint(0.35)
                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        width: 14; height: 14
                                        visible: modelData.done
                                        source: "checkmark"
                                        isMask: true
                                        color: "white"
                                    }
                                    MouseArea {
                                        id: checkMouse
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleTask(modelData)
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: modelData.text
                                    color: modelData.done ? pal.muted : pal.ink
                                    font.pixelSize: 14
                                    font.family: root.fontFamily
                                    font.strikeout: modelData.done
                                                                    }

                                Text {
                                    visible: modelData.due !== "" && !modelData.done
                                    text: root.shortDate(modelData.due)
                                    color: root.isOverdue(modelData) ? pal.danger : pal.muted
                                    font.pixelSize: 11
                                    font.family: root.fontFamily
                                }

                                Kirigami.Icon {
                                    implicitWidth: 16; implicitHeight: 16
                                    visible: rowMouse.containsMouse || openMouse.containsMouse
                                    source: "document-open"
                                    isMask: true
                                    color: openMouse.containsMouse ? pal.accent : pal.inkSoft
                                    MouseArea {
                                        id: openMouse
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.openInObsidian(modelData)
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: list.count === 0
                            text: root.loadError || "Nothing on your list yet."
                            color: root.loadError ? pal.danger : pal.muted
                            font.pixelSize: 13
                            font.family: root.fontFamily
                        }
                    }

                    // Add a task
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        implicitHeight: 44
                        radius: 10
                        color: pal.card
                        border.color: input.activeFocus ? pal.accent : pal.cardBorder

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 6
                            spacing: 10

                            Text {
                                text: "+"
                                color: pal.inkSoft
                                font.pixelSize: 20
                                font.family: root.fontFamily
                            }
                            TextInput {
                                id: input
                                Layout.fillWidth: true
                                color: pal.ink
                                selectionColor: pal.accent
                                font.pixelSize: 14
                                font.family: root.fontFamily
                                clip: true
                                selectByMouse: true
                                onAccepted: { root.addTask(text); text = "" }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !input.text && !input.activeFocus
                                    text: "Add a task"
                                    color: pal.muted
                                    font.pixelSize: 14
                                    font.family: root.fontFamily
                                }
                            }
                            Rectangle {
                                implicitWidth: addLabel.implicitWidth + 24
                                implicitHeight: 30
                                radius: 7
                                opacity: input.text.trim() ? 1 : 0.6
                                color: addMouse.containsMouse && input.text.trim() ? pal.accentSoftHover : pal.accentSoft
                                Text {
                                    id: addLabel
                                    anchors.centerIn: parent
                                    text: "Add"
                                    color: pal.accentText
                                    font.pixelSize: 13
                                    font.family: root.fontFamily
                                }
                                MouseArea {
                                    id: addMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.addTask(input.text); input.text = "" }
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        visible: root.actionError !== ""
                        text: root.actionError
                        color: pal.danger
                        font.pixelSize: 12
                        font.family: root.fontFamily
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }

    // Small uppercase label above titles (inline components can't see `pal`)
    component Eyebrow: Text {
        color: Qt.rgba(PlasmaCore.Theme.textColor.r, PlasmaCore.Theme.textColor.g, PlasmaCore.Theme.textColor.b, 0.6)
        font.pixelSize: 11
        font.family: "Segoe UI"
        font.letterSpacing: 1.6
        font.capitalization: Font.AllUppercase
    }

    // Round icon button used in the popup
    component RoundButton: Rectangle {
        id: btn
        property int size: 36
        property string iconSource
        readonly property color fg: PlasmaCore.Theme.textColor
        property color iconColor: Qt.rgba(fg.r, fg.g, fg.b, 0.7)
        property string tooltip
        readonly property bool hovered: btnMouse.containsMouse
        signal clicked()

        implicitWidth: size
        implicitHeight: size
        radius: size / 2
        color: Qt.rgba(fg.r, fg.g, fg.b, btnMouse.pressed ? 0.22 : hovered ? 0.16 : 0.10)

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 16; height: 16
            visible: btn.iconSource !== ""
            source: btn.iconSource
            isMask: true
            color: btn.iconColor
        }
        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
        QQC2.ToolTip.visible: tooltip !== "" && hovered
        QQC2.ToolTip.text: tooltip
        QQC2.ToolTip.delay: 600
    }
}
