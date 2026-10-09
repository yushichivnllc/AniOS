import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Pane {
    id: card
    signal openRequested()

    padding: 0
    Material.elevation: hover.hovered ? 6 : 1
    background: Rectangle {
        radius: 14
        color: backend.darkTheme ? "#2B2930" : "#FFFFFF"
    }

    HoverHandler {
        id: hover
    }
    TapHandler {
        onTapped: card.openRequested()
    }

    contentItem: ColumnLayout {
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.topMargin: 14
            spacing: 6

            Label {
                text: "r/" + model.subreddit
                font.weight: Font.Medium
                color: Material.accent
            }
            Label {
                text: "· u/" + model.author
                opacity: 0.7
                elide: Text.ElideRight
                Layout.maximumWidth: 200
            }
            Label {
                text: "· " + model.ageText
                opacity: 0.7
            }
            Item {
                Layout.fillWidth: true
            }
            Label {
                visible: model.stickied
                text: "Ghim"
                color: Material.accent
                font.pixelSize: 12
            }
            Label {
                visible: model.nsfw
                text: "18+"
                color: "#E57373"
                font.weight: Font.Bold
                font.pixelSize: 12
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            text: model.title
            wrapMode: Text.Wrap
            font.pixelSize: 17
            font.weight: Font.Medium
        }

        Rectangle {
            visible: model.flair !== ""
            Layout.leftMargin: 16
            Layout.preferredHeight: 22
            Layout.preferredWidth: flairLabel.implicitWidth + 16
            radius: 11
            color: Qt.rgba(Material.accent.r, Material.accent.g, Material.accent.b, 0.18)
            Label {
                id: flairLabel
                anchors.centerIn: parent
                text: model.flair
                font.pixelSize: 12
            }
        }

        Rectangle {
            id: thumbFrame
            visible: model.thumbnail !== "" && !model.nsfw
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.preferredHeight: visible ? Math.min(320, width * 0.6) : 0
            radius: 10
            clip: true
            color: Qt.rgba(0, 0, 0, 0.2)
            Image {
                anchors.fill: parent
                source: model.thumbnail
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
            }
        }

        Label {
            visible: model.isSelf && model.selftext !== ""
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            text: model.selftext
            maximumLineCount: 3
            elide: Text.ElideRight
            wrapMode: Text.Wrap
            opacity: 0.8
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 12
            Layout.bottomMargin: 8
            spacing: 4

            ToolButton {
                text: "\u25B2"
                font.pixelSize: 14
                enabled: false  // chỉ đọc: bỏ phiếu cần đăng nhập
                ToolTip.text: "Bỏ phiếu cần đăng nhập (chưa hỗ trợ)"
                ToolTip.visible: hovered
            }
            Label {
                text: model.scoreText
                font.weight: Font.Medium
            }
            ToolButton {
                text: "\u25BC"
                font.pixelSize: 14
                enabled: false
            }
            ToolButton {
                text: "Bình luận " + model.commentsText
                onClicked: card.openRequested()
            }
            Item {
                Layout.fillWidth: true
            }
            Label {
                visible: !model.isSelf && model.domain !== ""
                text: model.domain
                opacity: 0.6
                font.pixelSize: 12
                elide: Text.ElideRight
                Layout.maximumWidth: 220
            }
            ToolButton {
                visible: !model.isSelf && model.url !== ""
                text: "Mở liên kết"
                flat: true
                onClicked: Qt.openUrlExternally(model.url)
            }
        }
    }
}
