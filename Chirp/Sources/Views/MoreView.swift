import SwiftUI

struct MoreView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            // MARK: - Communication

            Section {
                NavigationLink {
                    BabelView(
                        babelService: appState.babelService,
                        localPeerID: appState.localPeerID,
                        localPeerName: appState.localPeerName,
                        channelID: appState.channelManager.activeChannel?.id ?? ""
                    )
                } label: {
                    moreRow(
                        icon: "globe",
                        iconColor: Constants.Colors.blue500,
                        title: String(localized: "more.babel.title"),
                        description: String(localized: "more.babel.description")
                    )
                }

                NavigationLink {
                    VoiceMessagesView()
                } label: {
                    moreRow(
                        icon: "waveform.circle",
                        iconColor: Constants.Colors.amber,
                        title: String(localized: "more.voiceMessages.title"),
                        description: String(localized: "more.voiceMessages.description")
                    )
                }

                NavigationLink {
                    GatewayMessageView(
                        localPeerID: appState.localPeerID,
                        localPeerName: appState.localPeerName
                    )
                } label: {
                    moreRow(
                        icon: "antenna.radiowaves.left.and.right",
                        iconColor: Constants.Colors.electricGreen,
                        title: String(localized: "more.gateway.title"),
                        description: String(localized: "more.gateway.description")
                    )
                }
            } header: {
                sectionHeader(String(localized: "more.section.communication"))
            }

            // MARK: - Security

            Section {
                NavigationLink {
                    ProtectTabView()
                } label: {
                    moreRow(
                        icon: "shield.fill",
                        iconColor: Constants.Colors.electricGreen,
                        title: String(localized: "more.protect.title"),
                        description: String(localized: "more.protect.description")
                    )
                }

                NavigationLink {
                    WitnessCaptureView(
                        channelID: appState.channelManager.activeChannel?.id ?? ""
                    )
                } label: {
                    moreRow(
                        icon: "checkmark.seal.fill",
                        iconColor: Constants.Colors.blue500,
                        title: String(localized: "more.witness.title"),
                        description: String(localized: "more.witness.description")
                    )
                }

                NavigationLink {
                    DarkroomInboxView()
                } label: {
                    moreRow(
                        icon: "eye.slash.fill",
                        iconColor: Constants.Colors.slate400,
                        title: String(localized: "more.darkroom.title"),
                        description: String(localized: "more.darkroom.description")
                    )
                }

                NavigationLink {
                    DeadDropMapView(channelID: appState.channelManager.activeChannel?.id ?? "")
                } label: {
                    moreRow(
                        icon: "mappin.and.ellipse",
                        iconColor: Constants.Colors.hotRed,
                        title: String(localized: "more.deadDrop.title"),
                        description: String(localized: "more.deadDrop.description")
                    )
                }
            } header: {
                sectionHeader(String(localized: "more.section.security"))
            }

            // MARK: - Network

            Section {
                NavigationLink {
                    MeshMapView()
                } label: {
                    moreRow(
                        icon: "point.3.connected.trianglepath.dotted",
                        iconColor: Constants.Colors.amber,
                        title: String(localized: "more.meshMap.title"),
                        description: String(localized: "more.meshMap.description")
                    )
                }

                NavigationLink {
                    MeshCloudView()
                } label: {
                    moreRow(
                        icon: "cloud.fill",
                        iconColor: Constants.Colors.blue500,
                        title: String(localized: "more.meshCloud.title"),
                        description: String(localized: "more.meshCloud.description")
                    )
                }

                NavigationLink {
                    SwarmView()
                } label: {
                    moreRow(
                        icon: "cpu",
                        iconColor: Constants.Colors.electricGreen,
                        title: String(localized: "more.swarm.title"),
                        description: String(localized: "more.swarm.description")
                    )
                }

                NavigationLink {
                    ChorusView()
                } label: {
                    moreRow(
                        icon: "waveform.path",
                        iconColor: Constants.Colors.amberLight,
                        title: String(localized: "more.chorus.title"),
                        description: String(localized: "more.chorus.description")
                    )
                }
            } header: {
                sectionHeader(String(localized: "more.section.network"))
            }

            // MARK: - Settings

            Section {
                NavigationLink {
                    SettingsView()
                } label: {
                    moreRow(
                        icon: "gearshape.fill",
                        iconColor: Constants.Colors.slate400,
                        title: String(localized: "more.settings.title"),
                        description: String(localized: "more.settings.description")
                    )
                }
            } header: {
                sectionHeader(String(localized: "more.section.settings"))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Constants.Colors.slate900)
    }

    // MARK: - Row Builder

    private func moreRow(
        icon: String,
        iconColor: Color,
        title: String,
        description: String
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)

                Text(description)
                    .font(Constants.Typography.caption)
                    .foregroundStyle(Constants.Colors.slate400)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Constants.Colors.slate800.opacity(0.6))
    }

    // MARK: - Section Header

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(Constants.Typography.caption)
            .foregroundStyle(Constants.Colors.slate400)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}
