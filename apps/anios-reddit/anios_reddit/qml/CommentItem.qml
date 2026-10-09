import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Item {
    id: item
    width: ListView.view.width
    height: body.implicitHeight + 20

    readonly property int indent: 16 + model.depth * 18

    // Thanh dọc theo độ sâu bình luận
    Rectangle {
        x: indent - 10
        y: 4
        width: 3
        radius: 2
        height: item.height - 8
        color: Material.accent
        opacity: Math.max(0.15, 0.9 - model.depth * 0.15)
    }

    ColumnLayout {
        id: body
        x: indent
        y: 8
        width: item.width - indent - 16
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Label {
                text: "u/" + model.author
                font.weight: Font.Medium
                font.pixelSize: 13
                elide: Text.ElideRight
                Layout.maximumWidth: 240
            }
            Label {
                visible: model.isOp
                text: "OP"
                color: Material.accent
                font.pixelSize: 11
                font.weight: Font.Bold
            }
            Label {
                text: "· " + model.score + " điểm"
                opacity: 0.6
                font.pixelSize: 12
            }
        }
        Label {
            Layout.fillWidth: true
            text: model.body
            textFormat: Text.MarkdownText
            wrapMode: Text.Wrap
            font.pixelSize: 14
            onLinkActivated: function (link) { Qt.openUrlExternally(link) }
        }
    }
}
