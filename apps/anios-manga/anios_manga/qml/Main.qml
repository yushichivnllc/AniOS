import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Cửa sổ chính: thanh điều hướng bên trái + StackView chứa các trang.
// Điều hướng giữa các trang dùng tín hiệu do mỗi trang phát ra và Main.qml xử lý,
// đúng kiểu apps/anios-reddit (không phụ thuộc id xuyên file).
ApplicationWindow {
    id: win
    width: 1280
    height: 860
    minimumWidth: 420
    minimumHeight: 560
    visible: true
    title: "AniOS Manga"

    Material.theme: backend.darkTheme ? Material.Dark : Material.Light
    Material.accent: "#7C4DFF"
    Material.primary: backend.darkTheme ? "#1B1725" : "#F6F1FA"
    Material.background: backend.darkTheme ? "#131019" : "#FDFBFF"
    Material.foreground: backend.darkTheme ? "#E9E3F2" : "#1C1B1F"

    property string section: "library"
    readonly property var sections: [
        { id: "library", label: "Kệ sách", glyph: "\u25A6" },
        { id: "explore", label: "Khám phá", glyph: "\u2315" },
        { id: "history", label: "Lịch sử", glyph: "\u25F7" },
        { id: "downloads", label: "Tải xuống", glyph: "\u2913" },
        { id: "settings", label: "Cài đặt", glyph: "\u2699" }
    ]

    function sectionLabel(id) {
        for (var i = 0; i < sections.length; i++)
            if (sections[i].id === id)
                return sections[i].label
        return id
    }

    function showSection(id) {
        section = id
        while (stack.depth > 1)
            stack.pop()
        stack.replace(stack.initialItem, sectionComponent(id))
    }

    function sectionComponent(id) {
        if (id === "explore")
            return exploreComponent
        if (id === "history")
            return historyComponent
        if (id === "downloads")
            return downloadsComponent
        if (id === "settings")
            return settingsComponent
        return libraryComponent
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---- thanh điều hướng: chỉ hiện ở trang cấp một ----
        Rectangle {
            id: nav
            Layout.fillHeight: true
            Layout.preferredWidth: 212
            visible: stack.depth === 1
            color: Material.primary

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 4

                Label {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 10
                    text: "AniOS Manga"
                    font.pixelSize: 19
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Repeater {
                    model: win.sections
                    delegate: ItemDelegate {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 46
                        highlighted: win.section === modelData.id
                        text: modelData.glyph + "   " + modelData.label
                        font.pixelSize: 15
                        onClicked: win.showSection(modelData.id)
                    }
                }

                Item { Layout.fillHeight: true }

                Label {
                    Layout.fillWidth: true
                    text: "Nguồn: " + backend.sources.filter(function (s) {
                        return s.id === backend.currentSource
                    }).map(function (s) { return s.name })[0]
                    font.pixelSize: 12
                    opacity: 0.65
                    elide: Text.ElideRight
                }
            }
        }

        // ---- nội dung ----
        StackView {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            initialItem: LibraryPage {
                onMangaRequested: function (index) {
                    backend.openManga(index)
                    stack.push(detailsComponent)
                }
                onMangaByIdRequested: function (source, id) {
                    backend.openMangaById(source, id)
                    stack.push(detailsComponent)
                }
            }
        }
    }

    // Trạng thái tải/đang chạy hiện ở thanh trạng thái dưới cùng.
    footer: Rectangle {
        height: 30
        color: Material.primary
        visible: backend.status !== "" || backend.busy
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 10
            BusyIndicator {
                implicitWidth: 18
                implicitHeight: 18
                running: backend.busy
                visible: backend.busy
            }
            Label {
                Layout.fillWidth: true
                text: backend.busy && backend.status === "" ? "Đang tải..." : backend.status
                font.pixelSize: 12
                elide: Text.ElideRight
                opacity: 0.85
            }
        }
    }

    Component { id: libraryComponent; LibraryPage {
            onMangaRequested: function (index) {
                backend.openManga(index)
                stack.push(detailsComponent)
            }
            onMangaByIdRequested: function (source, id) {
                backend.openMangaById(source, id)
                stack.push(detailsComponent)
            }
        } }

    Component { id: exploreComponent; ExplorePage {
            onMangaRequested: function (index) {
                backend.openManga(index)
                stack.push(detailsComponent)
            }
            onMangaByIdRequested: function (source, id) {
                backend.openMangaById(source, id)
                stack.push(detailsComponent)
            }
        } }

    Component { id: historyComponent; HistoryPage {
            onMangaRequested: function (index) {
                backend.openManga(index)
                stack.push(detailsComponent)
            }
            onMangaByIdRequested: function (source, id) {
                backend.openMangaById(source, id)
                stack.push(detailsComponent)
            }
        } }

    Component { id: downloadsComponent; DownloadsPage {
            onMangaByIdRequested: function (source, id) {
                backend.openMangaById(source, id)
                stack.push(detailsComponent)
            }
        } }

    Component { id: settingsComponent; SettingsPage {} }

    Component { id: detailsComponent; DetailsPage {
            onChapterRequested: function (index) { backend.openChapter(index) }
            onContinueRequested: backend.openContinue()
            onClosed: stack.pop()
        } }

    Component { id: readerComponent; ReaderPage {
            readonly property bool isReaderPage: true
            onClosed: stack.pop()
        } }

    // Trang ảnh tải xong (luồng nền) mới đẩy trang đọc lên, nên lỗi mạng chỉ báo
    // ở thanh trạng thái chứ không hiện trang đọc rỗng.
    Connections {
        target: backend
        function onReaderOpened() {
            if (!stack.currentItem || stack.currentItem.isReaderPage !== true)
                stack.push(readerComponent)
        }
    }

    Shortcut { sequence: "Ctrl+Q"; onActivated: win.close() }
    Shortcut {
        sequence: "Escape"
        onActivated: if (stack.depth > 1) stack.pop()
    }
}
