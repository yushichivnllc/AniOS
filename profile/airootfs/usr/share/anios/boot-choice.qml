import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: root

    title: "AniOS - Welcome"
    visible: true
    width: 1040
    height: 620
    minimumWidth: 760
    minimumHeight: 560
    flags: Qt.Dialog

    Material.theme: Material.Dark
    Material.primary: "#aecbfa"
    Material.accent: "#aecbfa"
    property bool selectionMade: false

    function choose(mode) {
        if (selectionMade)
            return
        selectionMade = true
        console.log("ANIOS_BOOT_CHOICE=" + mode)
        root.close()
    }

    onClosing: {
        if (!root.selectionMade) {
            root.selectionMade = true
            console.log("ANIOS_BOOT_CHOICE=anios")
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
        anchors.margins: 30
        spacing: 0

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

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 24
            spacing: 0

            Label {
                text: "CHỌN CHẾ ĐỘ"
                color: "#a9c8ff"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 1.5
            }
            Label {
                Layout.fillWidth: true
                Layout.topMargin: 7
                text: "Bạn muốn sử dụng hệ điều hành nào?"
                color: "#f2f4fa"
                font.pixelSize: 29
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Label {
                Layout.fillWidth: true
                Layout.topMargin: 8
                text: "AniTails khởi động bằng mục riêng trong menu boot để bật Tor trước mạng; Anix chạy Whonix Gateway và Workstation trong VM cách ly."
                color: "#b7c0cf"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 240
            Layout.topMargin: 24
            spacing: 14

            Repeater {
                model: [
                    {
                        mode: "anios",
                        name: "AniOS thường",
                        subtitle: "Arch Linux · Hyprland",
                        description: "Tiếp tục vào desktop AniOS Live hiện tại, với các công cụ và ứng dụng đã cài sẵn.",
                        icon: "A",
                        tint: "#344864",
                        accent: "#c2d8ff"
                    },
                    {
                        mode: "anitails",
                        name: "AniTails (Tails OS)",
                        subtitle: "Tor Live · chỉ ghi tạm trong RAM",
                        description: "Firewall chặn kết nối Internet trực tiếp và chuyển TCP/DNS qua Tor. Chọn mục AniTails ở boot menu để bật trước khi mạng lên.",
                        icon: "◉",
                        tint: "#26473f",
                        accent: "#b7f0d8"
                    },
                    {
                        mode: "anix",
                        name: "Anix (Whonix)",
                        subtitle: "Whonix · Gateway + Workstation VM",
                        description: "Workstation chỉ gắn vào mạng nội bộ, Gateway có đường WAN riêng. Tải image KVM Whonix chính thức rồi chạy anix setup.",
                        icon: "◇",
                        tint: "#493b2a",
                        accent: "#f7d29a"
                    }
                ]

                delegate: Button {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 0
                    implicitHeight: 255
                    leftPadding: 17
                    rightPadding: 17
                    topPadding: 17
                    bottomPadding: 17
                    onClicked: root.choose(modelData.mode)

                    background: Rectangle {
                        radius: 23
                        color: parent.down ? "#2a3952" : parent.hovered ? "#243249" : "#1c2636"
                        border.color: parent.activeFocus ? modelData.accent : parent.hovered ? "#60779a" : "#39485f"
                        border.width: parent.activeFocus ? 2 : 1
                        Behavior on color { ColorAnimation { duration: 130 } }
                    }

                    contentItem: ColumnLayout {
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            Rectangle {
                                Layout.preferredWidth: 48
                                Layout.preferredHeight: 48
                                radius: 16
                                color: modelData.tint
                                Label {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    color: modelData.accent
                                    font.pixelSize: 23
                                    font.weight: Font.DemiBold
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Label {
                                text: "→"
                                color: modelData.accent
                                font.pixelSize: 21
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            Layout.topMargin: 18
                            text: modelData.name
                            color: "#f2f4fa"
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                        }
                        Label {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            text: modelData.subtitle
                            color: modelData.accent
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                        }
                        Label {
                            Layout.fillWidth: true
                            Layout.topMargin: 10
                            text: modelData.description
                            color: "#b8c3d3"
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                        Item { Layout.fillHeight: true; Layout.minimumHeight: 6 }
                        Label {
                            text: "Chọn chế độ"
                            color: modelData.accent
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
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
                text: "AniTails là profile Tor của AniOS, không phải Tails chính thức và không secure-erase RAM. Anix cần image Whonix KVM và VM setup."
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
