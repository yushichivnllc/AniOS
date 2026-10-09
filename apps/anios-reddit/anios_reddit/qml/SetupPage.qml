import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Page {
    id: page
    background: Rectangle { color: Material.background }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth

        ColumnLayout {
            width: Math.min(page.width - 48, 620)
            x: (page.width - width) / 2
            y: 32
            spacing: 16

            Label {
                text: "Kết nối Reddit"
                font.pixelSize: 26
                font.weight: Font.Medium
                color: Material.accent
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "Reddit yêu cầu ứng dụng phải đăng ký (OAuth) để đọc dữ liệu. " +
                      "AniOS Reddit chỉ đọc công khai và không cần đăng nhập tài khoản Reddit của bạn."
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "1. Mở reddit.com/prefs/apps và bấm \"create another app…\".\n" +
                      "2. Chọn loại \"installed app\", đặt tên tuỳ ý.\n" +
                      "3. Redirect URI: http://localhost:8080 (không dùng, nhưng Reddit yêu cầu).\n" +
                      "4. Sao chép chuỗi ký tự dưới tên ứng dụng (client ID) và dán vào ô bên dưới."
                lineHeight: 1.25
            }
            Button {
                text: "Mở trang đăng ký ứng dụng"
                flat: true
                onClicked: Qt.openUrlExternally("https://www.reddit.com/prefs/apps")
            }
            TextField {
                id: clientField
                Layout.fillWidth: true
                placeholderText: "Client ID"
                text: ""
                selectByMouse: true
                onAccepted: saveButton.clicked()
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button {
                    visible: backend.hasClientId
                    flat: true
                    text: "Để sau"
                    onClicked: page.StackView.view.pop()
                }
                Button {
                    id: saveButton
                    highlighted: true
                    enabled: clientField.text.trim().length >= 10
                    text: "Lưu và tải bài viết"
                    onClicked: {
                        backend.saveClientId(clientField.text)
                        if (backend.hasClientId)
                            page.StackView.view.pop(page.StackView.view.initialItem)
                    }
                }
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                opacity: 0.6
                font.pixelSize: 12
                text: "Client ID được lưu trong ~/.config/anios-reddit/config.json (chỉ người dùng hiện tại đọc được)."
            }
        }
    }
}
