import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Thẻ truyện dùng chung cho lưới Kệ sách / Khám phá / kết quả tìm kiếm.
// Lưu ý: tên vai trò "cover" trùng với id của Image nên phải gọi qua `model.cover`.
Item {
    id: card
    signal clicked(int index)
    signal contextMenuRequested(int index)

    implicitWidth: 176
    implicitHeight: 268

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Material.darkTheme ? "#241F2E" : "#FFFFFF"
        border.width: 1
        border.color: Material.darkTheme ? "#3A3346" : "#E4DCEA"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                color: Material.darkTheme ? "#17131F" : "#EFE9F3"
                clip: true

                Image {
                    id: cover
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 260
                    source: model.cover || ""

                    Rectangle {
                        anchors.fill: parent
                        color: Material.darkTheme ? "#17131F" : "#EFE9F3"
                        visible: cover.status === Image.Loading
                        BusyIndicator {
                            anchors.centerIn: parent
                            running: cover.status === Image.Loading
                        }
                    }

                    // Đánh dấu truyện đã có trong kệ.
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 6
                        width: 22
                        height: 22
                        radius: 11
                        color: "#7C4DFF"
                        visible: model.inLibrary === true
                        Label {
                            anchors.centerIn: parent
                            text: "\u2713"
                            color: "white"
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                text: model.title || ""
                font.pixelSize: 13
                font.weight: Font.Medium
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Label {
                Layout.fillWidth: true
                text: model.progressText || model.statusText || ""
                font.pixelSize: 11
                opacity: 0.65
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: text !== ""
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton)
                card.contextMenuRequested(index)
            else
                card.clicked(index)
        }
    }
}
