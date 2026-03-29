import SwiftUI

/// Compose and send a message to the outside world via a mesh gateway node.
///
/// One device in the mesh with internet connectivity relays messages for the
/// entire network. This view lets the user compose an SMS or email message
/// and queue it for gateway delivery.
struct GatewayMessageView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var messageText: String = ""
    @State private var recipientValue: String = ""
    @State private var deliveryMode: DeliveryMode = .sms
    @State private var countryCode: String = "+1"
    @State private var showCountryPicker: Bool = false
    @State private var showSentConfirmation: Bool = false

    private let gateway = MeshGateway.shared
    private let localPeerID: String
    private let localPeerName: String

    private let amber = Constants.Colors.amber
    private let hotRed = Constants.Colors.hotRed
    private let green = Constants.Colors.electricGreen

    enum DeliveryMode: String, CaseIterable {
        case sms = "SMS"
        case email = "Email"

        var icon: String {
            switch self {
            case .sms: return "message.fill"
            case .email: return "envelope.fill"
            }
        }

        var placeholder: String {
            switch self {
            case .sms: return "Phone number"
            case .email: return "Email address"
            }
        }

        var keyboardType: UIKeyboardType {
            switch self {
            case .sms: return .phonePad
            case .email: return .emailAddress
            }
        }
    }

    // MARK: - Init

    init(localPeerID: String, localPeerName: String) {
        self.localPeerID = localPeerID
        self.localPeerName = localPeerName
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Gateway status banner
                        gatewayStatusCard

                        // Delivery mode toggle
                        deliveryModePicker

                        // Recipient input
                        recipientInput

                        // Message input
                        messageInput

                        // Send button
                        sendButton

                        // Queue info
                        if !gateway.pendingOutbound.isEmpty || gateway.sentCount > 0 {
                            queueStats
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Gateway Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(amber)
                }
            }
            .sheet(isPresented: $showCountryPicker) {
                CountryCodePicker(selected: $countryCode)
            }
            .overlay {
                if showSentConfirmation {
                    sentConfirmationOverlay
                }
            }
        }
    }

    // MARK: - Gateway Status

    private var gatewayStatusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(gateway.gatewayAvailable ? green.opacity(0.15) : hotRed.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: gateway.gatewayAvailable ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(gateway.gatewayAvailable ? green : hotRed)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(gateway.gatewayAvailable ? "Gateway Available" : "No Gateway in Mesh")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(gatewayStatusSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            if gateway.isGatewayNode {
                Text("YOU")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(green)
                    )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            gateway.gatewayAvailable ? green.opacity(0.2) : Color.white.opacity(0.06),
                            lineWidth: 0.5
                        )
                )
        )
    }

    private var gatewayStatusSubtitle: String {
        if gateway.isGatewayNode {
            return "This device has internet — relaying for mesh"
        } else if !gateway.knownGateways.isEmpty {
            let count = gateway.knownGateways.count
            let name = gateway.knownGateways.values.first?.peerName ?? "unknown"
            if count == 1 {
                return "Via \(name)"
            }
            return "\(count) gateways available"
        }
        return "Messages will queue until a gateway appears"
    }

    // MARK: - Delivery Mode

    private var deliveryModePicker: some View {
        HStack(spacing: 0) {
            ForEach(DeliveryMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        deliveryMode = mode
                        recipientValue = ""
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 13, weight: .semibold))

                        Text(mode.rawValue)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(deliveryMode == mode ? .black : .white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        deliveryMode == mode
                            ? AnyShapeStyle(amber)
                            : AnyShapeStyle(Color.clear)
                    )
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Recipient Input

    private var recipientInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(deliveryMode == .sms ? "Recipient Phone" : "Recipient Email")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .textCase(.uppercase)

            HStack(spacing: 10) {
                if deliveryMode == .sms {
                    // Country code picker
                    Button {
                        showCountryPicker = true
                    } label: {
                        Text(countryCode)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(amber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.ultraThinMaterial)
                                    .environment(\.colorScheme, .dark)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(amber.opacity(0.2), lineWidth: 0.5)
                                    )
                            )
                    }
                }

                TextField(deliveryMode.placeholder, text: $recipientValue)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .keyboardType(deliveryMode.keyboardType)
                    .textContentType(deliveryMode == .sms ? .telephoneNumber : .emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                            )
                    )
            }
        }
    }

    // MARK: - Message Input

    private var messageInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Message")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .textCase(.uppercase)

                Spacer()

                Text("\(messageText.count)/160")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(messageText.count > 160 ? hotRed : .white.opacity(0.3))
            }

            TextEditor(text: $messageText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100, maxHeight: 160)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                )
        }
    }

    // MARK: - Send Button

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !recipientValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendButton: some View {
        Button {
            sendMessage()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .semibold))

                Text(gateway.gatewayAvailable ? "Send via Gateway" : "Queue for Gateway")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundStyle(canSend ? .black : .white.opacity(0.3))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(canSend ? amber : Color.white.opacity(0.06))
            )
        }
        .disabled(!canSend)
    }

    // MARK: - Queue Stats

    private var queueStats: some View {
        HStack(spacing: 20) {
            if !gateway.pendingOutbound.isEmpty {
                Label {
                    Text("\(gateway.pendingOutbound.count) pending")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                } icon: {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12))
                }
                .foregroundStyle(amber.opacity(0.7))
            }

            if gateway.sentCount > 0 {
                Label {
                    Text("\(gateway.sentCount) sent")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                }
                .foregroundStyle(green.opacity(0.7))
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
        )
    }

    // MARK: - Sent Confirmation

    private var sentConfirmationOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: gateway.gatewayAvailable ? "checkmark.circle.fill" : "clock.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(gateway.gatewayAvailable ? green : amber)

            Text(gateway.gatewayAvailable ? "Sent!" : "Queued")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(gateway.gatewayAvailable
                 ? "Message delivered via gateway"
                 : "Message queued for next gateway")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Actions

    private func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRecipient = recipientValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty, !trimmedRecipient.isEmpty else { return }

        let phone: String? = deliveryMode == .sms ? "\(countryCode)\(trimmedRecipient)" : nil
        let email: String? = deliveryMode == .email ? trimmedRecipient : nil

        let gatewayMessage = MeshGateway.GatewayMessage(
            id: UUID(),
            fromPeerID: localPeerID,
            fromPeerName: localPeerName,
            recipientPhone: phone,
            recipientEmail: email,
            message: trimmedMessage,
            timestamp: Date()
        )

        gateway.queueOutbound(gatewayMessage)

        // Show confirmation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showSentConfirmation = true
        }

        // Dismiss after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                showSentConfirmation = false
            }
            messageText = ""
            recipientValue = ""
        }
    }
}

// MARK: - Country Code Picker

/// Minimal country code picker with common codes.
private struct CountryCodePicker: View {

    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss

    private let amber = Constants.Colors.amber

    private let codes: [(flag: String, name: String, code: String)] = [
        ("US", "United States", "+1"),
        ("CA", "Canada", "+1"),
        ("GB", "United Kingdom", "+44"),
        ("AU", "Australia", "+61"),
        ("DE", "Germany", "+49"),
        ("FR", "France", "+33"),
        ("JP", "Japan", "+81"),
        ("IN", "India", "+91"),
        ("BR", "Brazil", "+55"),
        ("MX", "Mexico", "+52"),
        ("KR", "South Korea", "+82"),
        ("IT", "Italy", "+39"),
        ("ES", "Spain", "+34"),
        ("NL", "Netherlands", "+31"),
        ("SE", "Sweden", "+46"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List(codes, id: \.code) { item in
                    Button {
                        selected = item.code
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            Text(item.flag)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 32)

                            Text(item.name)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)

                            Spacer()

                            Text(item.code)
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(selected == item.code ? amber : .white.opacity(0.5))
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.white.opacity(0.03))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Country Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(amber)
                }
            }
        }
    }
}
