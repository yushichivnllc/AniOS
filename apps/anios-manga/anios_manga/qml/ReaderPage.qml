import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Trình đọc: ba chế độ như Kotatsu — cuộn dọc (webtoon), từng trang trái sang phải,
// và từng trang phải sang trải (manga Nhật). Tiến độ đọc được ghi lại khi lật trang.
Page {
    id: readerPage
    signal closed()
    signal chapterRequested(int index)

    readonly property bool webtoon: backend.readerMode === "webtoon"
    readonly property bool rtl: backend.readerMode === "rtl"
    // Ở chế độ phải sang trái, trang hiển thị là trang "ngược" của tiến độ.
    readonly property int displayIndex: rtl
        ? Math.max(0, backend.readerCount - 1 - backend.readerIndex)
        : backend.readerIndex
    property real zoom: 1.0

    function nextPage() {
        backend.readerSetPage(rtl ? backend.readerIndex - 1 : backend.readerIndex + 1)
    }

    function prevPage() {
        backend.readerSetPage(rtl ? backend.readerIndex + 1 : backend.readerIndex - 1)
    }

    function modeLabel(mode) {
        if (mode === "webtoon")
            return "Cuộn dọc"
        if (mode === "rtl")
            return "Phải sang trái"
        return "Từng trang"
    }

    header: ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 10
            spacing: 4

            ToolButton {
                text: "\u2190"
                font.pixelSize: 20
                ToolTip.text: "Đóng trình đọc"
                ToolTip.visible: hovered
                onClicked: readerPage.closed()
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label {
                    Layout.fillWidth: true
                    text: backend.readerTitle
                    font.pixelSize: 15
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    text: backend.readerLabel + (backend.readerProgressText !== "" ? " \u00B7 " + backend.readerProgressText : "")
                    font.pixelSize: 11
                    opacity: 0.65
                    elide: Text.ElideRight
                }
            }
            ComboBox {
                model: backend.readerModeOptions
                textRole: "name"
                currentIndex: Math.max(0, backend.readerModeOptions.findIndex(function (o) {
                    return o.id === backend.readerMode
                }))
                implicitWidth: 180
                onActivated: backend.setReaderMode(backend.readerModeOptions[currentIndex].id)
            }
            ToolButton {
                text: "\u2913"
                font.pixelSize: 17
                ToolTip.text: "Tải chương này về máy"
                ToolTip.visible: hovered
                onClicked: backend.downloadCurrentChapter()
            }
        }
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: readerPage.webtoon ? 0 : 1

        // ---- chế độ cuộn dọc ----
        ListView {
            id: scrollList
            model: backend.readerPages
            spacing: 4
            cacheBuffer: 900
            clip: true
            ScrollIndicator.vertical: ScrollIndicator {}
            // Tiến độ = trang nằm giữa màn hình, ghi lại khi người dùng cuộn.
            onContentYChanged: {
                var idx = indexAt(contentX, contentY + height / 2)
                if (idx >= 0 && idx !== backend.readerIndex)
                    backend.readerSetPage(idx)
            }
            delegate: Image {
                width: scrollList.width
                height: Math.max(180, implicitHeight * (width / Math.max(1, implicitWidth)))
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                sourceSize.width: scrollList.width
                source: model.url
            }
            Component.onCompleted: if (backend.readerIndex > 0)
                positionViewAtIndex(backend.readerIndex, ListView.Beginning)
        }

        // ---- chế độ từng trang ----
        ColumnLayout {
            // Là con của StackLayout (một layout) nên phải khai báo bằng Layout.*
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 8
            spacing: 6

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 8
                color: "black"
                clip: true

                Image {
                    id: pageImage
                    anchors.centerIn: parent
                    width: parent.width * readerPage.zoom
                    height: parent.height * readerPage.zoom
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    source: {
                        if (backend.readerCount <= 0)
                            return ""
                        var row = backend.readerPages.row(readerPage.displayIndex)
                        return row ? row.url || "" : ""
                    }
                }

                BusyIndicator {
                    anchors.centerIn: parent
                    running: pageImage.status === Image.Loading
                    visible: running
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button {
                    text: "\u25C0  Trang trước"
                    enabled: backend.readerIndex > 0
                    onClicked: readerPage.prevPage()
                }
                Slider {
                    Layout.fillWidth: true
                    from: 0
                    to: Math.max(0, backend.readerCount - 1)
                    value: backend.readerIndex
                    onMoved: backend.readerSetPage(value)
                }
                Button {
                    text: "Trang sau  \u25B6"
                    enabled: backend.readerIndex < backend.readerCount - 1
                    onClicked: readerPage.nextPage()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Label { text: "Thu phóng"; font.pixelSize: 12; opacity: 0.7 }
                Slider {
                    from: 0.5
                    to: 3.0
                    stepSize: 0.1
                    value: 1.0
                    onValueChanged: readerPage.zoom = value
                }
                Label {
                    text: Math.round(readerPage.zoom * 100) + "%"
                    font.pixelSize: 12
                    opacity: 0.7
                }
            }
        }
    }

    footer: ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            Button {
                text: "\u25C0  Chương trước"
                enabled: backend.canPrevChapter
                onClicked: backend.readerPrevChapter()
            }
            Item { Layout.fillWidth: true }
            Label { text: backend.readerProgressText; font.pixelSize: 12; opacity: 0.7 }
            Item { Layout.fillWidth: true }
            Button {
                text: "Chương sau  \u25B6"
                enabled: backend.canNextChapter
                onClicked: backend.readerNextChapter()
            }
        }
    }

    // Phím tắt chỉ dùng ở chế độ từng trang; ở chế độ cuộn thì để ListView xử lý.
    Shortcut { sequence: "Right"; enabled: !readerPage.webtoon; onActivated: readerPage.nextPage() }
    Shortcut { sequence: "Left"; enabled: !readerPage.webtoon; onActivated: readerPage.prevPage() }
    Shortcut { sequence: "Space"; enabled: !readerPage.webtoon; onActivated: readerPage.nextPage() }
    Shortcut { sequence: "PgDown"; enabled: !readerPage.webtoon; onActivated: readerPage.nextPage() }
    Shortcut { sequence: "PgUp"; enabled: !readerPage.webtoon; onActivated: readerPage.prevPage() }
}
