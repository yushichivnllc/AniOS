import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Một dòng trong danh sách chương. ItemDelegate đã có sẵn tín hiệu clicked() nên
// chỉ cần thêm tín hiệu cho nút tải xuống.
ItemDelegate {
    id: item
    property bool downloaded: model.downloaded === true

    signal downloadRequested()

    contentItem: RowLayout {
        spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Label {
                Layout.fillWidth: true
                text: model.label || "Chương"
                font.pixelSize: 14
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            Label {
                Layout.fillWidth: true
                text: {
                    var bits = []
                    if (model.pages > 0)
                        bits.push(model.pages + " trang")
                    if (model.language)
                        bits.push(model.language.toUpperCase())
                    if (model.publishedAt)
                        bits.push(String(model.publishedAt).slice(0, 10))
                    return bits.join(" \u00B7 ")
                }
                font.pixelSize: 11
                opacity: 0.6
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        ToolButton {
            text: item.downloaded ? "\u2713" : "\u2913"
            font.pixelSize: 16
            enabled: !item.downloaded
            ToolTip.text: item.downloaded ? "Đã tải về máy" : "Tải chương này về máy"
            ToolTip.visible: hovered
            onClicked: item.downloadRequested()
        }
    }
}
