import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Khám phá: tìm kiếm, duyệt truyện nổi bật / mới nhất, lọc theo thể loại.
Page {
    id: page
    signal mangaRequested(int index)
    signal mangaByIdRequested(string source, string id)

    function modeLabel(mode) {
        if (mode === "latest")
            return "Mới nhất"
        if (mode === "search")
            return "Kết quả tìm kiếm"
        return "Nổi bật"
    }

    Component.onCompleted: if (backend.mangaModel.count === 0) backend.refresh()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- thanh tìm kiếm ----
        RowLayout {
            Layout.leftMargin: 16
            Layout.rightMargin: 12
            Layout.topMargin: 12
            Layout.bottomMargin: 8
            spacing: 8

            TextField {
                id: searchBox
                Layout.fillWidth: true
                placeholderText: "Tìm truyện theo tên..."
                font.pixelSize: 14
                onAccepted: backend.search(text)
                Keys.onPressed: function (event) {
                    if (event.key === Qt.Key_Escape) {
                        text = ""
                        backend.setBrowseMode("popular")
                    }
                }
            }
            Button {
                text: "Tìm"
                highlighted: true
                onClicked: backend.search(searchBox.text)
            }
            ComboBox {
                id: sourceBox
                model: backend.sources
                textRole: "name"
                currentIndex: Math.max(0, backend.sources.findIndex(function (s) {
                    return s.id === backend.currentSource
                }))
                implicitWidth: 180
                onActivated: backend.setSource(backend.sources[currentIndex].id)
            }
        }

        // ---- chế độ duyệt + bộ lọc thể loại ----
        RowLayout {
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 6
            spacing: 8

            TabBar {
                id: modeBar
                Layout.fillWidth: true
                currentIndex: backend.browseMode === "latest" ? 1 : (backend.browseMode === "search" ? 2 : 0)
                Repeater {
                    model: ["popular", "latest", "search"]
                    delegate: TabButton {
                        required property string modelData
                        text: page.modeLabel(modelData)
                        enabled: modelData !== "search" || backend.query !== ""
                        onClicked: {
                            if (modelData === "search")
                                backend.search(searchBox.text)
                            else
                                backend.setBrowseMode(modelData)
                        }
                    }
                }
            }

            ComboBox {
                id: tagBox
                model: backend.tags
                textRole: "name"
                displayText: currentIndex < 0 ? "Mọi thể loại" : currentText
                implicitWidth: 170
                onActivated: backend.setExploreTag(backend.tags[currentIndex].id)
            }
        }

        // ---- lưới kết quả ----
        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 10
            model: backend.mangaModel
            cellWidth: 196
            cellHeight: 288
            clip: true
            ScrollIndicator.vertical: ScrollIndicator {}
            onAtYEndChanged: if (atYEnd) backend.loadMore()
            delegate: MangaCard {
                onClicked: page.mangaRequested(index)
            }
        }

        // ---- tải thêm / trạng thái rỗng ----
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 12
            Layout.topMargin: 4
            visible: backend.canLoadMore || (backend.mangaModel.count === 0 && !backend.busy)

            Button {
                // Nằm trong RowLayout: căn giữa bằng Layout, không dùng anchors.
                Layout.alignment: Qt.AlignHCenter
                text: "Tải thêm"
                visible: backend.canLoadMore
                onClicked: backend.loadMore()
            }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: backend.mangaModel.count === 0 ? "Không có truyện nào để hiển thị." : ""
                font.pixelSize: 14
                opacity: 0.6
            }
        }

        // Con của ColumnLayout: căn giữa bằng Layout thay vì anchors.
        BusyIndicator {
            Layout.alignment: Qt.AlignCenter
            running: backend.busy && backend.mangaModel.count === 0
            visible: running
        }
    }
}
