import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Lịch sử đọc: mở lại truyện đang đọc dở hoặc xoá lịch sử.
Page {
    id: page
    signal mangaRequested(int index)
    signal mangaByIdRequested(string source, string id)

    Component.onCompleted: backend.refreshHistory()

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
                text: "Lịch sử đọc"
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }
            Item { Layout.fillWidth: true }
            Button {
                text: "Xoá hết"
                flat: true
                enabled: backend.historyModel.count > 0
                onClicked: backend.clearHistory()
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            model: backend.historyModel
            clip: true
            spacing: 6
            ScrollIndicator.vertical: ScrollIndicator {}
            delegate: Rectangle {
                width: list.width
                height: 92
                radius: 12
                color: Material.darkTheme ? "#221D2C" : "#FFFFFF"
                border.width: 1
                border.color: Material.darkTheme ? "#372F45" : "#E7DFEE"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 56
                        Layout.preferredHeight: 76
                        radius: 6
                        clip: true
                        color: Material.darkTheme ? "#17131F" : "#EFE9F3"
                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 120
                            source: model.cover || ""
                        }
                    }

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
                            text: model.chapterLabel || "Chưa đọc chương nào"
                            font.pixelSize: 12
                            opacity: 0.7
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                        Label {
                            text: (model.updatedText || "") + (model.page > 0 ? " \u00B7 trang " + (model.page + 1) : "")
                            font.pixelSize: 11
                            opacity: 0.5
                        }
                    }

                    Button {
                        text: "Đọc tiếp"
                        highlighted: true
                        onClicked: {
                            backend.openMangaById(model.source, model.mangaId)
                            backend.openContinue()
                        }
                    }
                    ToolButton {
                        text: "\u2715"
                        ToolTip.text: "Xoá khỏi lịch sử"
                        ToolTip.visible: hovered
                        onClicked: backend.removeHistory(index)
                    }
                }
            }
        }

        // Con của ColumnLayout: căn giữa bằng Layout, không dùng anchors.
        Column {
            Layout.alignment: Qt.AlignCenter
            spacing: 10
            visible: backend.historyModel.count === 0
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Chưa có truyện nào trong lịch sử."
                font.pixelSize: 16
                opacity: 0.7
            }
        }
    }
}
