/*****************************************************************************
 * Theme đăng nhập AniOS cho SDDM.
 *
 * Phiên live tự đăng nhập sẵn nên màn hình này chỉ xuất hiện khi người dùng
 * đăng xuất hoặc khi SDDM không tự đăng nhập được. Vì vậy nó được giữ tối
 * giản: chỉ dùng các thành phần đi kèm SDDM (SddmComponents 2.0) và một file
 * nền khai báo trong theme.conf, không phụ thuộc tài nguyên nào khác.
 *****************************************************************************/

import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
    id: root

    width: 640
    height: 480

    property string accentColor: "#2f6be8"
    property string accentHoverColor: "#6fb5f0"
    property string accentPressColor: "#1d5be0"
    property string textColor: "#eaf4fd"
    property string dimColor: "#7e97b8"
    property string surfaceColor: "#0a1626"
    property string fieldColor: "#10233c"
    property string borderColor: "#1e4266"

    property int sessionIndex: session.index

    function submit() {
        sddm.login(user_entry.text, pw_entry.text, root.sessionIndex)
    }

    TextConstants { id: textConstants }

    Connections {
        target: sddm

        function onLoginSucceeded() {
        }

        function onLoginFailed() {
            pw_entry.text = ""
        }
    }

    // Nền dùng chung với desktop; thiếu file thì nền màu vẫn đủ dùng.
    Background {
        id: background
        anchors.fill: parent
        source: Qt.resolvedUrl(config.background)
        fillMode: Image.PreserveAspectCrop
        onStatusChanged: {
            if (status === Image.Error)
                source = ""
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.surfaceColor
        opacity: background.status === Image.Ready ? 0 : 1
    }

    Rectangle {
        id: card

        anchors.centerIn: parent
        width: Math.min(520, parent.width - 60)
        height: cardContent.height + 64
        color: root.surfaceColor
        opacity: 0.94
        radius: 10

        Column {
            id: cardContent

            anchors.centerIn: parent
            spacing: 20

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "AniOS"
                    color: root.textColor
                    font.pixelSize: 46
                    font.bold: true
                    font.letterSpacing: 2
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Hyprland live gaming desktop")
                    color: root.dimColor
                    font.pixelSize: 14
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 56
                    height: 3
                    color: root.accentColor
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6

                Text {
                    text: textConstants.userName
                    color: root.dimColor
                    font.pixelSize: 12
                }

                TextBox {
                    id: user_entry

                    width: 300
                    height: 34

                    text: userModel.lastUser

                    color: root.fieldColor
                    borderColor: root.borderColor
                    focusColor: root.accentColor
                    hoverColor: root.accentHoverColor
                    textColor: root.textColor
                    font.pixelSize: 14

                    KeyNavigation.backtab: pw_entry
                    KeyNavigation.tab: pw_entry
                }

                Text {
                    text: textConstants.password
                    color: root.dimColor
                    font.pixelSize: 12
                    topPadding: 8
                }

                PasswordBox {
                    id: pw_entry

                    width: 300
                    height: 34

                    color: root.fieldColor
                    borderColor: root.borderColor
                    focusColor: root.accentColor
                    hoverColor: root.accentHoverColor
                    textColor: root.textColor
                    font.pixelSize: 14

                    tooltipBG: root.fieldColor
                    tooltipFG: root.textColor

                    KeyNavigation.backtab: user_entry
                    KeyNavigation.tab: login_button

                    Keys.onPressed: function (event) {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.submit()
                            event.accepted = true
                        }
                    }
                }
            }

            Button {
                id: login_button

                anchors.horizontalCenter: parent.horizontalCenter
                width: 300
                height: 40

                text: textConstants.login

                // Với Button của SDDM: color là nền, borderColor là viền trong
                // khi nút được chọn, activeColor/pressedColor là nền tương ứng.
                color: root.accentColor
                borderColor: root.accentHoverColor
                activeColor: root.accentHoverColor
                pressedColor: root.accentPressColor
                textColor: root.surfaceColor

                font.pixelSize: 15
                font.bold: true

                onClicked: root.submit()

                KeyNavigation.backtab: pw_entry
                KeyNavigation.tab: session
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10

                Text {
                    text: textConstants.session
                    color: root.dimColor
                    font.pixelSize: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                ComboBox {
                    id: session

                    width: 200
                    height: 30

                    model: sessionModel
                    index: sessionModel.lastIndex

                    color: root.fieldColor
                    borderColor: root.borderColor
                    focusColor: root.accentColor
                    hoverColor: root.accentHoverColor
                    menuColor: root.fieldColor
                    textColor: root.textColor
                    font.pixelSize: 13

                    KeyNavigation.backtab: login_button
                    KeyNavigation.tab: user_entry
                }

                Text {
                    text: textConstants.layout
                    color: root.dimColor
                    font.pixelSize: 12
                    anchors.verticalCenter: parent.verticalCenter
                    visible: layoutBox.visible
                }

                LayoutBox {
                    id: layoutBox

                    width: 88
                    height: 30

                    color: root.fieldColor
                    borderColor: root.borderColor
                    focusColor: root.accentColor
                    hoverColor: root.accentHoverColor
                    menuColor: root.fieldColor
                    textColor: root.textColor

                    visible: keyboard.enabled && keyboard.layouts.length > 0

                    rowDelegate: Rectangle {
                        color: "transparent"

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            verticalAlignment: Text.AlignVCenter
                            color: root.textColor
                            font.pixelSize: 13
                            text: modelItem ? modelItem.modelData.shortName : "us"
                        }
                    }

                    KeyNavigation.backtab: session
                    KeyNavigation.tab: user_entry
                }
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        spacing: 22

        Text {
            text: "\u23FB " + textConstants.shutdown
            color: root.dimColor
            font.pixelSize: 12

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: sddm.powerOff()
            }
        }

        Text {
            text: "\u21BB " + textConstants.reboot
            color: root.dimColor
            font.pixelSize: 12

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: sddm.reboot()
            }
        }
    }

    Component.onCompleted: {
        if (user_entry.text === "")
            user_entry.focus = true
        else
            pw_entry.focus = true
    }
}
