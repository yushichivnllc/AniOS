import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Page {
    id: page
    readonly property var post: backend.currentPost

    background: Rectangle { color: Material.background }

    ListView {
        id: comments
        width: Math.min(parent.width, 900)
        height: parent.height
        anchors.horizontalCenter: parent.horizontalCenter
        clip: true
        model: backend.commentModel
        bottomMargin: 24
        ScrollIndicator.vertical: ScrollIndicator {}

        header: ColumnLayout {
            width: comments.width
            spacing: 10

            Item { Layout.preferredHeight: 8 }

            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                text: page.post.title || ""
                wrapMode: Text.Wrap
                font.pixelSize: 22
                font.weight: Font.Medium
            }
            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                text: (page.post.subreddit ? "r/" + page.post.subreddit : "") +
                      (page.post.author ? "  · u/" + page.post.author : "") +
                      (page.post.ageText ? "  · " + page.post.ageText : "")
                opacity: 0.7
                wrapMode: Text.Wrap
            }
            Label {
                visible: page.post.isSelf === true && (page.post.selftext || "") !== ""
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                text: page.post.selftext || ""
                textFormat: Text.MarkdownText
                wrapMode: Text.Wrap
                onLinkActivated: function (link) { Qt.openUrlExternally(link) }
            }
            Rectangle {
                visible: (page.post.thumbnail || "") !== "" && !page.post.nsfw
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.preferredHeight: visible ? Math.min(420, width * 0.6) : 0
                radius: 12
                clip: true
                color: Qt.rgba(0, 0, 0, 0.2)
                Image {
                    anchors.fill: parent
                    source: page.post.thumbnail || ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
            }
            RowLayout {
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                spacing: 8
                Label {
                    text: "▲ " + (page.post.scoreText || "0")
                    font.weight: Font.Medium
                }
                Label {
                    text: "Bình luận " + (page.post.commentsText || "0")
                    opacity: 0.8
                }
                Item { Layout.fillWidth: true }
                Button {
                    visible: !page.post.isSelf && (page.post.url || "") !== ""
                    text: "Mở liên kết"
                    onClicked: Qt.openUrlExternally(page.post.url)
                }
                Button {
                    visible: (page.post.permalink || "") !== ""
                    text: "Mở trên Reddit"
                    flat: true
                    onClicked: Qt.openUrlExternally(page.post.permalink)
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.topMargin: 6
                color: Qt.rgba(1, 1, 1, 0.12)
            }
            Label {
                visible: page.post.commentsLoading === true
                Layout.alignment: Qt.AlignHCenter
                text: "Đang tải bình luận…"
                opacity: 0.7
            }
            Label {
                visible: (page.post.commentsError || "") !== ""
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                wrapMode: Text.Wrap
                color: "#FF8A80"
                text: page.post.commentsError || ""
            }
        }

        delegate: CommentItem {}

        footer: Item {
            width: comments.width
            height: 40
            Label {
                anchors.centerIn: parent
                visible: comments.count === 0 && page.post.commentsLoading !== true && (page.post.commentsError || "") === ""
                text: "Chưa có bình luận."
                opacity: 0.6
            }
        }
    }
}
