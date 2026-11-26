import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccent) private var appAccent
    var onFinish: () -> Void
    @State private var page = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TabView(selection: $page) {
                    welcomeCard(
                        symbol: "waveform",
                        title: "onboarding.voice.title",
                        message: "onboarding.voice.body"
                    )
                    .tag(0)
                    .accessibilityIdentifier("onboarding-card-voice")
                    welcomeCard(
                        symbol: "person.2.fill",
                        title: "onboarding.invite.title",
                        message: "onboarding.invite.body"
                    )
                    .tag(1)
                    .accessibilityIdentifier("onboarding-card-invite")
                    permissionCard
                        .tag(2)
                        .accessibilityIdentifier("onboarding-card-permission")
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                if page < 2 {
                    Button("onboarding.next") {
                        withAnimation { page += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("onboarding-next")
                } else {
                    Button("onboarding.done", action: onFinish)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("onboarding-done")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("onboarding.skip", action: onFinish)
                        .accessibilityIdentifier("onboarding-skip")
                }
            }
        }
    }

    private func welcomeCard(symbol: String, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 56))
                .foregroundStyle(appAccent)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }

    private var permissionCard: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "alarm.fill")
                .font(.system(size: 56))
                .foregroundStyle(appAccent)
                .accessibilityHidden(true)
            Text("onboarding.permission.title")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("onboarding.permission.body")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if model.authorization == .authorized {
                Label("settings.systemAlarm.on", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(appAccent)
            } else {
                Button("onboarding.permission.allow") {
                    Task { await model.allowAlarms() }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("onboarding-allow")
            }
            Spacer()
        }
        .padding(.horizontal, 8)
    }
}

struct OnboardingTip: View {
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Button("onboarding.tip.dismiss", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("onboarding-tip-dismiss")
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct HowItWorksView: View {
    @State private var replayWelcome = false

    var body: some View {
        Form {
            Section {
                Button("onboarding.replay") { replayWelcome = true }
                    .accessibilityIdentifier("onboarding-replay")
            }
            faq("onboarding.faq.group.q", "onboarding.faq.group.a")
            faq("onboarding.faq.invite.q", "onboarding.faq.invite.a")
            faq("onboarding.faq.send.q", "onboarding.faq.send.a")
            faq("onboarding.faq.nap.q", "onboarding.faq.nap.a")
            faq("onboarding.faq.siri.q", "onboarding.faq.siri.a")
        }
        .navigationTitle("onboarding.how.title")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("how-it-works")
        .fullScreenCover(isPresented: $replayWelcome) {
            WelcomeView {
                OnboardingStore.markWelcomeSeen(defaults: .standard)
                replayWelcome = false
            }
        }
    }

    private func faq(_ question: LocalizedStringKey, _ answer: LocalizedStringKey) -> some View {
        Section {
            Text(answer)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(question)
        }
    }
}
