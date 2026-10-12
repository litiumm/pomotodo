import QtQuick 2.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.kirigami 2.20 as Kirigami

Kirigami.FormLayout {
    property alias cfg_vaultPath: vault.text
    property alias cfg_workMinutes: work.value
    property alias cfg_breakMinutes: shortBreak.value
    property alias cfg_longBreakMinutes: longBreak.value
    property alias cfg_playSound: sound.checked

    QQC2.TextField { id: vault; Kirigami.FormData.label: "Obsidian vault:"; placeholderText: "~/LifeOS" }
    QQC2.SpinBox { id: work; from: 1; to: 180; Kirigami.FormData.label: "Work (min):" }
    QQC2.SpinBox { id: shortBreak; from: 1; to: 60; Kirigami.FormData.label: "Short break (min):" }
    QQC2.SpinBox { id: longBreak; from: 1; to: 120; Kirigami.FormData.label: "Long break (min):" }
    QQC2.CheckBox { id: sound; text: "Play sound when a session ends" }
}
