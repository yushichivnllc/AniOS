import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Kệ sách: các truyện đã lưu, lọc theo thể loại kệ, có tiến độ đọc gần nhất.
Page {
    id: page
    signal mangaRequested(int index)
    signal mangaByIdRequested(string source, string id)

    property var categoryItems: buildCategories()

    function buildCategories() {
        var items = [{ name: "Tất cả", value: "" }]
        var cats = backend.categories
        for (var i = 0; i < cats.length; i++)
            items.push({ name: cats[i], value: cats[i] })
        return items
    }

    Connections {
        target: backend
        function onCategoriesChanged() { page.categoryItems = page.buildCategories() }
        function onLibraryChanged() { page.categoryItems = page.buildCategories() }
    }

    Component.onCompleted: backend.refreshLibrary()

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
                text: "Kệ sách"
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }
            Label {
                text: backend.favoriteCount + " truyện"
                font.pixelSize: 13
                opacity: 0.6
            }
            Item { Layout.fillWidth: true }
            ComboBox {
                id: categoryBox
                model: page.categoryItems
                textRole: "name"
                currentIndex: 0
                implicitWidth: 170
                onActivated: backend.setLibraryCategory(page.categoryItems[currentIndex].value)
            }
            ToolButton {
                text: "\u21BB"
                font.pixelSize: 18
                ToolTip.text: "Tải lại kệ sách"
                ToolTip.visible: hovered
                onClicked: backend.refreshLibrary()
            }
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 10
            model: backend.libraryModel
            cellWidth: 196
            cellHeight: 288
            clip: true
            ScrollIndicator.vertical: ScrollIndicator {}
            delegate: MangaCard {
                onClicked: page.mangaRequested(index)
                onContextMenuRequested: {
                    cardMenu.index = index
                    cardMenu.popup()
                }
            }
        }

    }

    // Thông báo rỗng nằm trên lưới (không nằm trong ColumnLayout, nên không bị ép về chiều cao 0).
    Column {
        anchors.centerIn: parent
        spacing: 14
        visible: grid.count === 0
        width: Math.min(page.width - 60, 420)

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: 17
            text: "Kệ sách đang trống."
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: 13
            opacity: 0.65
            text: "Mở một truyện ở trang Khám phá rồi bấm Thêm vào kệ để lưu vào đây."
        }
    }

    Menu {
        id: cardMenu
        property int index: -1
        MenuItem {
            text: "Mở truyện"
            onTriggered: page.mangaRequested(cardMenu.index)
        }
        MenuItem {
            text: "Đọc tiếp"
            onTriggered: {
                var row = backend.libraryModel.row(cardMenu.index)
                if (row)
                    backend.openMangaAndChapter(row.source, row.id, row.progressChapterId)
            }
        }
        MenuItem {
            text: "Bỏ khỏi kệ"
            onTriggered: {
                var row = backend.libraryModel.row(cardMenu.index)
                if (row) {
                    backend.openMangaById(row.source, row.id)
                    backend.toggleFavorite()
                }
            }
        }
    }
}
