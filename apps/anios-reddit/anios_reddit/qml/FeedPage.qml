import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Page {
    id: page
    signal postRequested(int index)

    function sortLabel(s) {
        const names = { hot: "Nổi bật", new: "Mới", top: "Top", rising: "Đang lên", controversial: "Gây tranh cãi" }
        return names[s] || s
    }
    function timeLabel(t) {
        const names = { hour: "Giờ qua", day: "Hôm nay", week: "Tuần này", month: "Tháng này", year: "Năm nay", all: "Mọi lúc" }
        return names[t] || t
    }

    Component.onCompleted: {
        if (backend.hasClientId)
            backend.refresh()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TabBar {
            id: sortBar
            Layout.fillWidth: true
            currentIndex: Math.max(0, backend.sorts.indexOf(backend.sort))
            Repeater {
                model: backend.sorts
                TabButton {
                    required property string modelData
                    text: page.sortLabel(modelData)
                    onClicked: backend.setSort(modelData)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.topMargin: 6
            visible: backend.sort === "top" || backend.sort === "controversial"
            Label {
                text: "Khoảng thời gian"
                opacity: 0.7
            }
            ComboBox {
                id: rangeBox
                model: backend.timeRanges
                currentIndex: Math.max(0, backend.timeRanges.indexOf(backend.timeRange))
                displayText: page.timeLabel(currentText)
                onActivated: backend.setTimeRange(currentText)
            }
            Item {
                Layout.fillWidth: true
            }
        }

        Pane {
            Layout.fillWidth: true
            Layout.margins: 12
            Layout.bottomMargin: 0
            visible: backend.status !== ""
            background: Rectangle {
                radius: 8
                color: Qt.rgba(1, 0.3, 0.3, 0.18)
            }
            RowLayout {
                anchors.fill: parent
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: backend.status
                }
                Button {
                    text: "Thử lại"
                    flat: true
                    onClicked: backend.refresh()
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                spacing: 10
                topMargin: 10
                bottomMargin: 16
                model: backend.postModel
                ScrollIndicator.vertical: ScrollIndicator {}
                onAtYEndChanged: if (atYEnd && backend.canLoadMore && !backend.busy) backend.loadMore()

                delegate: Item {
                    width: list.width
                    height: card.height

                    PostCard {
                        id: card
                        width: Math.min(parent.width - 24, 860)
                        x: (parent.width - width) / 2
                        onOpenRequested: page.postRequested(index)
                    }
                }

                footer: Item {
                    width: list.width
                    height: 72
                    BusyIndicator {
                        anchors.centerIn: parent
                        running: backend.busy
                        visible: backend.busy
                    }
                    Button {
                        anchors.centerIn: parent
                        visible: !backend.busy && backend.canLoadMore
                        text: "Tải thêm"
                        onClicked: backend.loadMore()
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 12
                visible: list.count === 0 && !backend.busy
                width: Math.min(parent.width - 48, 520)

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    font.pixelSize: 18
                    text: backend.hasClientId ? "Chưa có bài viết nào để hiển thị." : "Cần kết nối Reddit để xem bài viết."
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: backend.hasClientId ? "Tải lại" : "Kết nối Reddit"
                    highlighted: true
                    onClicked: backend.hasClientId ? backend.refresh() : page.StackView.view.push(setupComponentRef)
                }
            }

            BusyIndicator {
                anchors.centerIn: parent
                running: backend.busy && list.count === 0
                visible: running
            }
        }
    }

    Component {
        id: setupComponentRef
        SetupPage {}
    }
}
