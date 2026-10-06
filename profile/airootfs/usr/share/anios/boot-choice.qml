import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: root

    title: "AniOS - Welcome"
    visible: true
    width: 880
    height: 600
    minimumWidth: 680
    minimumHeight: 560
    flags: Qt.Dialog

    Material.theme: Material.Dark
    Material.primary: "#aecbfa"
    Material.accent: "#aecbfa"

    // `qml6` passes arguments after `--` through Qt.application.arguments.
    // The install card stays visible but disabled in --no-aur images.
    readonly property bool installerAvailable:
        Qt.application.arguments.indexOf("--installer-unavailable") === -1
    property bool selectionMade: false

    function choose(mode) {
        if (selectionMade)
            return
        selectionMade = true
        console.log("ANIOS_BOOT_CHOICE=" + mode)
        root.close()
    }

    // Closing the window (including its title-bar close button) is equivalent
    // to choosing Live; don't leave the launcher guessing whether QML failed.
    onClosing: {
        if (!root.selectionMade) {
            root.selectionMade = true
            console.log("ANIOS_BOOT_CHOICE=live")
        }
    }

    Component.onCompleted: console.log("ANIOS_BOOT_CHOICE_READY=1")

    background: Rectangle {
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#141b27" }
            GradientStop { position: 1.0; color: "#0d1118" }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 0

        // Brand and live-system status.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            spacing: 13

            Rectangle {
                Layout.preferredWidth: 46
                Layout.preferredHeight: 46
                radius: 16
                color: "#293951"
                border.color: "#455b7c"
                border.width: 1

                Label {
                    anchors.centerIn: parent
                    text: "A"
                    color: "#c4d8ff"
                    font.pixelSize: 25
                    font.weight: Font.Bold
                }
            }

            ColumnLayout {
                spacing: 1
                Label {
                    text: "AniOS"
                    color: "#f0f3fa"
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }
                Label {
                    text: "ARCH LINUX  ·  HYPRLAND"
                    color: "#aeb8c8"
                    font.pixelSize: 10
                    font.letterSpacing: 1.1
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth: 112
                Layout.preferredHeight: 32
                radius: 16
                color: "#202d41"
                border.color: "#364b6a"
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 7
                    Rectangle {
                        Layout.preferredWidth: 7
                        Layout.preferredHeight: 7
                        radius: 4
                        color: "#a9c8ff"
                    }
                    Label {
                        text: "LIVE USB"
                        color: "#d3e1fa"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.8
                    }
                }
            }
        }

        // Welcome headline.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 23
            spacing: 0

            Label {
                text: "BẮT ĐẦU"
                color: "#a9c8ff"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 1.5
            }

            Label {
                Layout.fillWidth: true
                Layout.topMargin: 7
                text: "Bạn muốn sử dụng AniOS như thế nào?"
                color: "#f2f4fa"
                font.pixelSize: 30
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                Layout.topMargin: 8
                text: "Dùng thử trực tiếp từ USB hoặc cài AniOS lên máy tính. Ổ đĩa sẽ không bị thay đổi khi bạn chọn dùng thử."
                color: "#b7c0cf"
                font.pixelSize: 14
                wrapMode: Text.WordWrap
            }
        }

        // Two large, keyboard-accessible Material cards.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 218
            Layout.topMargin: 22
            spacing: 16

            Button {
                id: liveCard
                objectName: "liveChoice"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                implicitHeight: 236
                focus: true
                leftPadding: 21
                rightPadding: 21
                topPadding: 19
                bottomPadding: 19
                onClicked: root.choose("live")

                background: Rectangle {
                    radius: 26
                    color: liveCard.down ? "#2a3952" : liveCard.hovered ? "#243249" : "#1c2636"
                    border.color: liveCard.activeFocus ? "#aecbfa" : liveCard.hovered ? "#60779a" : "#39485f"
                    border.width: liveCard.activeFocus ? 2 : 1
                    Behavior on color { ColorAnimation { duration: 130 } }
                }

                contentItem: ColumnLayout {
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.preferredWidth: 50
                            Layout.preferredHeight: 50
                            radius: 17
                            color: "#344864"
                            Label {
                                anchors.centerIn: parent
                                text: "▶"
                                color: "#c2d8ff"
                                font.pixelSize: 21
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            Layout.preferredWidth: liveBadge.implicitWidth + 20
                            Layout.preferredHeight: 28
                            radius: 14
                            color: "#2d405c"
                            Label {
                                id: liveBadge
                                anchors.centerIn: parent
                                text: "KHUYẾN NGHỊ"
                                color: "#d5e3ff"
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.6
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.topMargin: 16
                        text: "Dùng thử AniOS Live"
                        color: "#f2f4fa"
                        font.pixelSize: 21
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.topMargin: 7
                        text: "Khởi chạy desktop từ USB/DVD và khám phá AniOS ngay. Không cần cài đặt, không ghi lên ổ đĩa."
                        color: "#b8c3d3"
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                    }

                    Item { Layout.fillHeight: true; Layout.minimumHeight: 8 }

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: "Tiếp tục vào desktop"
                            color: "#c2d8ff"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: "→"
                            color: "#c2d8ff"
                            font.pixelSize: 20
                        }
                    }
                }
            }

            Button {
                id: installCard
                objectName: "installChoice"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                implicitHeight: 236
                enabled: root.installerAvailable
                opacity: root.installerAvailable ? 1.0 : 0.55
                leftPadding: 21
                rightPadding: 21
                topPadding: 19
                bottomPadding: 19
                onClicked: root.choose("install")

                background: Rectangle {
                    radius: 26
                    color: installCard.down ? "#30313b" : installCard.hovered ? "#292b35" : "#20232c"
                    border.color: installCard.activeFocus ? "#aecbfa" : installCard.hovered ? "#697184" : "#414550"
                    border.width: installCard.activeFocus ? 2 : 1
                    Behavior on color { ColorAnimation { duration: 130 } }
                }

                contentItem: ColumnLayout {
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.preferredWidth: 50
                            Layout.preferredHeight: 50
                            radius: 17
                            color: "#393b47"
                            Label {
                                anchors.centerIn: parent
                                text: "↓"
                                color: "#d1d4df"
                                font.pixelSize: 27
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            Layout.preferredWidth: installBadge.implicitWidth + 20
                            Layout.preferredHeight: 28
                            radius: 14
                            color: "#343640"
                            Label {
                                id: installBadge
                                anchors.centerIn: parent
                                text: root.installerAvailable ? "CÀI ĐẶT" : "KHÔNG CÓ INSTALLER"
                                color: "#d2d5df"
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.5
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.topMargin: 16
                        text: "Cài đặt AniOS"
                        color: "#f2f4fa"
                        font.pixelSize: 21
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.topMargin: 7
                        text: root.installerAvailable
                            ? "Mở Calamares để chọn ngôn ngữ, phân vùng và tài khoản trước khi cài hệ thống."
                            : "Trình cài đặt Calamares không có trong bản ISO này."
                        color: "#b8c0ce"
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                    }

                    Item { Layout.fillHeight: true; Layout.minimumHeight: 8 }

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: root.installerAvailable ? "Mở trình cài đặt" : "Không khả dụng"
                            color: "#d2d5df"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: "→"
                            color: "#d2d5df"
                            font.pixelSize: 20
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 17
            Layout.preferredHeight: 1
            color: "#303744"
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 12
            spacing: 12

            Label {
                Layout.fillWidth: true
                text: "Bạn có thể đóng cửa sổ này để tiếp tục sử dụng AniOS Live."
                color: "#9faabc"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            Label {
                text: "Tab để chuyển  ·  Enter để chọn"
                color: "#9faabc"
                font.pixelSize: 11
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
