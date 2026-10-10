import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Cài đặt: nguồn truyện, ngôn ngữ chương, chế độ đọc, bộ lọc 18+ và nơi lưu dữ liệu.
Page {
    id: page

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: Math.min(page.width - 40, 720)
            x: 20
            spacing: 4

            Label {
                text: "Cài đặt"
                font.pixelSize: 22
                font.weight: Font.DemiBold
                Layout.bottomMargin: 10
            }

            GroupBox {
                title: "Nguồn truyện"
                Layout.fillWidth: true
                ColumnLayout {
                    spacing: 10
                    ComboBox {
                        Layout.fillWidth: true
                        model: backend.sources
                        textRole: "name"
                        currentIndex: Math.max(0, backend.sources.findIndex(function (s) {
                            return s.id === backend.currentSource
                        }))
                        onActivated: backend.setSource(backend.sources[currentIndex].id)
                    }
                    Label {
                        Layout.fillWidth: true
                        text: "MangaDex cần kết nối Internet. \"Thư viện cục bộ\" đọc file CBZ/ZIP có sẵn trên máy, không cần mạng."
                        font.pixelSize: 12
                        opacity: 0.6
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Thư mục CBZ/ZIP"; font.pixelSize: 13 }
                        TextField {
                            Layout.fillWidth: true
                            text: backend.localDir
                            font.pixelSize: 13
                            onEditingFinished: backend.setLocalDir(text)
                        }
                        Button {
                            text: "Mở"
                            onClicked: backend.openLocalDir()
                        }
                    }
                }
            }

            GroupBox {
                title: "Đọc truyện"
                Layout.fillWidth: true
                ColumnLayout {
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Ngôn ngữ chương ưu tiên"; font.pixelSize: 13 }
                        Item { Layout.fillWidth: true }
                        ComboBox {
                            model: ["vi", "en", "ja", "pt-br", "es-la", "id", "th", "de", "fr", "ru"]
                            currentIndex: Math.max(0, find(backend.language))
                            implicitWidth: 140
                            onActivated: backend.setLanguage(currentText)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Chế độ đọc mặc định"; font.pixelSize: 13 }
                        Item { Layout.fillWidth: true }
                        ComboBox {
                            model: backend.readerModeOptions
                            textRole: "name"
                            currentIndex: Math.max(0, backend.readerModeOptions.findIndex(function (o) {
                                return o.id === backend.readerMode
                            }))
                            implicitWidth: 180
                            onActivated: backend.setReaderMode(backend.readerModeOptions[currentIndex].id)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Ảnh nén (tiết kiệm dữ liệu)"; font.pixelSize: 13 }
                        Item { Layout.fillWidth: true }
                        Switch {
                            checked: backend.dataSaver
                            onToggled: backend.setDataSaver(checked)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Hiện nội dung 18+"; font.pixelSize: 13 }
                        Item { Layout.fillWidth: true }
                        Switch {
                            checked: backend.nsfw
                            onToggled: backend.setNsfw(checked)
                        }
                    }
                }
            }

            GroupBox {
                title: "Giao diện"
                Layout.fillWidth: true
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "Chủ đề"; font.pixelSize: 13 }
                    Item { Layout.fillWidth: true }
                    ComboBox {
                        model: [
                            { id: "dark", name: "Tối" },
                            { id: "light", name: "Sáng" }
                        ]
                        textRole: "name"
                        currentIndex: backend.darkTheme ? 0 : 1
                        implicitWidth: 140
                        onActivated: backend.setTheme(currentIndex === 0 ? "dark" : "light")
                    }
                }
            }

            GroupBox {
                title: "Dữ liệu"
                Layout.fillWidth: true
                ColumnLayout {
                    spacing: 10
                    Label {
                        Layout.fillWidth: true
                        text: "Kệ sách, lịch sử đọc và truyện tải về nằm trong thư mục dữ liệu của ứng dụng."
                        font.pixelSize: 12
                        opacity: 0.6
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            Layout.fillWidth: true
                            text: backend.dataDir
                            font.pixelSize: 12
                            elide: Text.ElideMiddle
                        }
                        Button {
                            text: "Mở thư mục"
                            onClicked: backend.openDataDir()
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: "Đã tải về: " + backend.downloadSizeText + " \u00B7 " + backend.favoriteCount + " truyện trong kệ"
                        font.pixelSize: 12
                        opacity: 0.6
                    }
                }
            }

            Label {
                Layout.topMargin: 14
                text: "AniOS Manga " + backend.version + " \u00B7 viết bằng Python + PySide6/QML"
                font.pixelSize: 11
                opacity: 0.45
            }

            Item { Layout.fillHeight: true }
        }
    }
}
