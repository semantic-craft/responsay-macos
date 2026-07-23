import SwiftUI
import ResponsayCore

struct SettingsGeneralPane: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    @Binding var micDeviceID: String
    @Binding var avoidBluetoothMic: Bool
    @Binding var showCapsule: Bool
    @Binding var muteWhileRecording: Bool
    @Binding var startSound: Bool
    @Binding var interactionSoundStyle: String
    @Binding var restoreClipboard: Bool
    @Binding var copyToClipboard: Bool
    @Binding var launchAtLogin: Bool
    @Binding var startMinimized: Bool
    let audioInputDevices: [(id: String, name: String)]
    let updateLaunchAtLogin: (Bool) -> Void
    let previewCaptureCues: () -> Void

    var body: some View {
        SettingsPaneColumn {
            SettingsPaneHeader(title: "通用", desc: "法言如何启动、录音与上屏。")

            WarmCard {
                GroupLabel(text: "录音与输入")
                SettingsRow(title: "首选麦克风", desc: "用于听写与提问的输入设备。") {
                    Picker("", selection: $micDeviceID) {
                        Text("系统默认").tag("")
                        ForEach(audioInputDevices, id: \.id) { dev in
                            Text(dev.name).tag(dev.id)
                        }
                    }
                    .labelsHidden().frame(maxWidth: 240)
                }
                WarmDivider()
                SettingsRow(title: "蓝牙耳机时改用内置麦克风",
                            desc: "戴 AirPods 等蓝牙耳机时用 Mac 内置麦克风录音：听歌不被切成通话音质，结束时音量也不会突然变大。") {
                    Toggle("", isOn: $avoidBluetoothMic).labelsHidden().toggleStyle(.switch)
                }
                WarmDivider()
                SettingsRow(title: "显示录音浮窗", desc: "录音时在屏幕上显示悬浮胶囊。") {
                    Toggle("", isOn: $showCapsule).labelsHidden().toggleStyle(.switch)
                }
                WarmDivider()
                SettingsRow(title: "录音时静音其他声音",
                            desc: "录音期间静音系统输出（音乐 / 视频等其他应用的声音），结束自动恢复。") {
                    Toggle("", isOn: $muteWhileRecording).labelsHidden().toggleStyle(.switch)
                }
                WarmDivider()
                SettingsRow(title: "录音开始 / 结束提示音", desc: "开始与结束录音时播放轻提示音。") {
                    HStack(spacing: 10) {
                        Button("试听") { previewCaptureCues() }
                            .controlSize(.small)
                            .disabled(!startSound)
                        Toggle("", isOn: $startSound).labelsHidden().toggleStyle(.switch)
                    }
                }
                WarmDivider()
                SettingsRow(title: "提示音音色", desc: "选择提示音的音色。") {
                    Picker("", selection: $interactionSoundStyle) {
                        ForEach(InteractionSoundStyle.allCases, id: \.rawValue) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .labelsHidden().fixedSize()
                    .disabled(!startSound)
                }
                footnote("按一下 Fn 或右 Option 开始说话，再按同一个键结束并出结果——不用按住，也没有双击。")
            }

            WarmCard {
                GroupLabel(text: "结果上屏与剪贴板")
                SettingsRow(title: "插入后恢复原剪贴板",
                            desc: "上屏完成后，把剪贴板还原成你之前的内容。") {
                    Toggle("", isOn: $restoreClipboard).labelsHidden().toggleStyle(.switch)
                }
                WarmDivider()
                SettingsRow(title: "插入完成后复制结果到剪贴板",
                            desc: "把这次上屏的结果同时留在剪贴板里。") {
                    Toggle("", isOn: $copyToClipboard).labelsHidden().toggleStyle(.switch)
                }
                footnote("「上屏」指把生成结果写进当前光标处的输入框，整段一次性插入；以上两项只决定插入完成后剪贴板里留什么。")
            }

            WarmCard {
                GroupLabel(text: "启动")
                SettingsRow(title: "登录时启动应用", desc: "开机自动运行法言并常驻菜单栏。") {
                    Toggle("", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, enabled in
                            updateLaunchAtLogin(enabled)
                        }
                }
                WarmDivider()
                SettingsRow(title: "启动即最小化", desc: "启动时不显示主窗口，仅在菜单栏待命。") {
                    Toggle("", isOn: $startMinimized).labelsHidden().toggleStyle(.switch)
                }
            }
        }
        .navigationTitle("通用")
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(SettingsTheme.footnote)
            .foregroundStyle(appearanceStore.palette.ink3)
            .fixedSize(horizontal: false, vertical: true)
    }
}
