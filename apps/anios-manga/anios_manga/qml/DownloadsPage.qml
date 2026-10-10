import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Truyện đã tải về máy: đọc offline và xoá bớt để giải phóng dung lượng.
Page {
    id: page
    signal mangaByIdRequested(string source, string id)

    Component.onCompleted: backend.refreshDownloads()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.leftMargin: 16
            Layout.rightMargin: 12
            Layout.topMargin: 12
            Layout.bottomMargin: 6
            spacing: 10

            Label {
                text: "Tải xuống"
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }
            Label {
                text: backend.downloadSizeText
                font.pixelSize: 13
                opacity: 0.6
            }
            Item { Layout.fillWidth: true }
            ToolButton {
                text: "\u21BB"
                font.pixelSize: 18
                ToolTip.text: "Tải lại danh sách"
                ToolTip.visible: hovered
                onClicked: backend.refreshDownloads()
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            model: backend.downloadsModel
            clip: true
            spacing: 6
            ScrollIndicator.vertical: ScrollIndicator {}
            delegate: Rectangle {
                width: list.width
                height: 84
                radius: 12
                color: Material.darkTheme ? "#221D2C" : "#FFFFFF"
                border.width: 1
                border.color: Material.darkTheme ? "#372F45" : "#E7DFEE"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Label {
                            Layout.fillWidth: true
                            text: model.title || ""
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                        Label {
                            Layout.fillWidth: true
                            text: (model.label || "") + (model.pages > 0 ? " \u00B7 " + model.pages + " trang" : "") + " \u00B7 " + (model.sizeText || "")
                            font.pixelSize: 12
                            opacity: 0.7
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    Button {
                        text: "Đọc"
                        highlighted: true
                        onClicked: backend.openMangaAndChapter(model.source, model.mangaId, model.chapterId)
                    }
                    ToolButton {
                        text: "\u2715"
                        ToolTip.text: "Xoá bản tải"
                        ToolTip.visible: hovered
                        onClicked: backend.deleteDownload(index)
                    }
                }
            }
        }

        // Con của ColumnLayout: căn giữa bằng Layout, không dùng anchors.
        Column {
            Layout.alignment: Qt.AlignCenter
            spacing: 10
            visible: backend.downloadsModel.count === 0
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Chưa tải chương nào."
                font.pixelSize: 16
                opacity: 0.7
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Bấm nút tải ở danh sách chương để đọc truyện khi không có mạng."
                font.pixelSize: 12
                opacity: 0.5
            }
        }
    }
}
