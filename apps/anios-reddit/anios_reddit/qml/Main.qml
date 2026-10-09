import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 1120
    height: 780
    minimumWidth: 380
    minimumHeight: 480
    visible: true
    title: "r/" + backend.subreddit

    Material.theme: backend.darkTheme ? Material.Dark : Material.Light
    Material.accent: "#FF4500"
    Material.primary: backend.darkTheme ? "#1C1B1F" : "#F3EDF7"

    header: ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 8
            spacing: 4

            ToolButton {
                text: "\u2190"
                font.pixelSize: 20
                visible: stack.depth > 1
                onClicked: stack.pop()
                ToolTip.text: "Quay lại"
                ToolTip.visible: hovered
            }
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: 19
                font.weight: Font.Medium
                text: stack.depth > 1 ? "Bài viết" : "r/" + backend.subreddit
            }
            ToolButton {
                text: "\u21BB"
                font.pixelSize: 20
                visible: stack.depth === 1 && backend.hasClientId
                onClicked: backend.refresh()
                ToolTip.text: "Tải lại (F5)"
                ToolTip.visible: hovered
            }
            ToolButton {
                text: "\u2699"
                font.pixelSize: 20
                visible: stack.depth === 1
                onClicked: stack.push(setupComponent)
                ToolTip.text: "Cài đặt"
                ToolTip.visible: hovered
            }
        }
    }

    Shortcut {
        sequence: "F5"
        onActivated: if (stack.depth === 1 && backend.hasClientId) backend.refresh()
    }

    Component {
        id: postComponent
        PostPage {}
    }

    Component {
        id: setupComponent
        SetupPage {}
    }

    StackView {
        id: stack
        anchors.fill: parent
        initialItem: FeedPage {
            onPostRequested: function (index) {
                backend.openPost(index)
                stack.push(postComponent)
            }
        }
        Component.onCompleted: {
            if (!backend.hasClientId)
                stack.push(setupComponent)
        }
    }
}
