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
    title: "AniOS Reddit"

    Material.theme: backend.darkTheme ? Material.Dark : Material.Light
    Material.accent: "#FF4500"
    Material.primary: backend.darkTheme ? "#1C1B1F" : "#F3EDF7"

    property bool wide: width >= 900

    header: ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 8
            spacing: 4

            ToolButton {
                text: "\u2630"
                font.pixelSize: 20
                visible: stack.depth === 1
                onClicked: drawer.open()
                ToolTip.text: "Danh sách subreddit"
                ToolTip.visible: hovered
            }
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
                text: stack.depth > 1 ? "Bài viết" : (backend.subreddit ? "r/" + backend.subreddit : "AniOS Reddit")
            }
            TextField {
                id: searchField
                visible: stack.depth === 1 && backend.hasClientId && win.wide
                Layout.preferredWidth: 280
                placeholderText: "Tìm kiếm trên Reddit"
                selectByMouse: true
                onAccepted: backend.search(text)
            }
            ToolButton {
                text: "\u21BB"
                font.pixelSize: 20
                visible: stack.depth === 1 && backend.hasClientId
                onClicked: backend.refresh()
                ToolTip.text: "Tải lại (F5)"
                ToolTip.visible: hovered
            }
        }
    }

    Shortcut {
        sequence: "F5"
        onActivated: if (stack.depth === 1 && backend.hasClientId) backend.refresh()
    }

    Drawer {
        id: drawer
        width: Math.min(320, win.width * 0.85)
        height: win.height
        edge: Qt.LeftEdge

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            Label {
                text: "AniOS Reddit"
                font.pixelSize: 22
                font.weight: Font.Medium
                color: Material.accent
            }
            Label {
                text: "Subreddit"
                opacity: 0.7
            }
            ListView {
                id: subList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: backend.subreddits
                ScrollIndicator.vertical: ScrollIndicator {}
                delegate: ItemDelegate {
                    required property var modelData
                    width: ListView.view.width
                    highlighted: backend.subreddit === modelData
                    onClicked: {
                        backend.loadSubreddit(modelData, backend.sort)
                        stack.pop(stack.initialItem)
                        drawer.close()
                    }
                    contentItem: RowLayout {
                        Label {
                            Layout.fillWidth: true
                            text: "r/" + modelData
                            elide: Text.ElideRight
                            font.weight: parent.parent.highlighted ? Font.Medium : Font.Normal
                        }
                        ToolButton {
                            text: "\u2715"
                            onClicked: backend.removeSubreddit(modelData)
                            ToolTip.text: "Bỏ khỏi danh sách"
                            ToolTip.visible: hovered
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                TextField {
                    id: addField
                    Layout.fillWidth: true
                    placeholderText: "Tên subreddit"
                    onAccepted: addButton.clicked()
                }
                Button {
                    id: addButton
                    text: "Thêm"
                    onClicked: {
                        backend.addSubreddit(addField.text)
                        addField.clear()
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    text: "Chế độ tối"
                }
                Switch {
                    checked: backend.darkTheme
                    onToggled: backend.setTheme(checked ? "dark" : "light")
                }
            }
            Button {
                Layout.fillWidth: true
                flat: true
                text: "Cài đặt client ID"
                onClicked: {
                    drawer.close()
                    stack.pop(stack.initialItem)
                    stack.push(setupComponent)
                }
            }
        }
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
