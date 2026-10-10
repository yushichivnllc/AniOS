import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Trang chi tiết truyện: thông tin, mô tả, thể loại và danh sách chương.
Page {
    id: page
    signal chapterRequested(int index)
    signal continueRequested()
    signal closed()

    header: ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 10
            spacing: 4

            ToolButton {
                text: "\u2190"
                font.pixelSize: 20
                ToolTip.text: "Quay lại"
                ToolTip.visible: hovered
                onClicked: page.closed()
            }
            Label {
                Layout.fillWidth: true
                text: backend.currentManga.title || "Đang tải..."
                font.pixelSize: 17
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Button {
                text: backend.favorite ? "Bỏ khỏi kệ" : "Thêm vào kệ"
                highlighted: !backend.favorite
                onClicked: backend.toggleFavorite()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- thông tin truyện ----
        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(300, page.height * 0.45)
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: page.width
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 14
                    spacing: 14

                    Rectangle {
                        Layout.preferredWidth: 148
                        Layout.preferredHeight: 208
                        radius: 10
                        clip: true
                        color: Material.darkTheme ? "#221D2C" : "#EFE9F3"

                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 300
                            source: backend.currentManga.cover || ""
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Label {
                            Layout.fillWidth: true
                            text: backend.currentManga.title || ""
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                        }
                        Label {
                            Layout.fillWidth: true
                            text: backend.currentManga.altTitle || ""
                            font.pixelSize: 12
                            opacity: 0.55
                            wrapMode: Text.WordWrap
                            visible: text !== ""
                        }
                        Label {
                            Layout.fillWidth: true
                            text: {
                                var bits = []
                                if (backend.currentManga.author)
                                    bits.push("Tác giả: " + backend.currentManga.author)
                                if (backend.currentManga.artist && backend.currentManga.artist !== backend.currentManga.author)
                                    bits.push("Hoạ sĩ: " + backend.currentManga.artist)
                                if (backend.currentManga.statusText)
                                    bits.push(backend.currentManga.statusText)
                                if (backend.currentManga.year > 0)
                                    bits.push(String(backend.currentManga.year))
                                return bits.join(" \u00B7 ")
                            }
                            font.pixelSize: 13
                            opacity: 0.75
                            wrapMode: Text.WordWrap
                            visible: text !== ""
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: (backend.currentManga.tags || []).length > 0
                            Repeater {
                                model: backend.currentManga.tags || []
                                delegate: Rectangle {
                                    required property string modelData
                                    radius: 9
                                    implicitWidth: tagLabel.implicitWidth + 14
                                    implicitHeight: 22
                                    color: Material.darkTheme ? "#2C2637" : "#EDE4F5"
                                    Label {
                                        id: tagLabel
                                        anchors.centerIn: parent
                                        text: modelData
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: 14
                    Layout.rightMargin: 14
                    Layout.bottomMargin: 10
                    text: backend.currentManga.description || "Chưa có mô tả."
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    opacity: 0.85
                }
            }
        }

        // ---- hành động + tiêu đề danh sách chương ----
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            spacing: 8

            Label {
                text: "Chương"
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }
            Label {
                text: backend.chapterModel.count + " chương"
                font.pixelSize: 12
                opacity: 0.55
            }
            Item { Layout.fillWidth: true }
            Button {
                text: "Đọc từ đầu"
                visible: backend.chapterModel.count > 0
                onClicked: page.chapterRequested(backend.chapterModel.count - 1)
            }
            Button {
                text: "Đọc tiếp"
                highlighted: true
                visible: backend.hasProgress
                onClicked: page.continueRequested()
            }
        }

        // ---- danh sách chương (mới nhất trước) ----
        ListView {
            id: chapterList
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: backend.chapterModel
            clip: true
            spacing: 2
            ScrollIndicator.vertical: ScrollIndicator {}
            delegate: ChapterItem {
                width: chapterList.width
                onClicked: page.chapterRequested(index)
                onDownloadRequested: backend.downloadChapterById(model.id)
            }
        }
    }
}
