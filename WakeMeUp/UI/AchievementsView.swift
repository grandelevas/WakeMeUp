import SwiftUI

struct AchievementsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccent) private var appAccent
    @State private var document: AchievementsDocument?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(disclosure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    personalCard
                    if let campaign = document?.campaign {
                        campaignCard(campaign)
                    }
                    totalsCard
                    historySection
                    badgeSection
                }
                .padding(16)
            }
            .navigationTitle("tab.achievements")
            .task { await reload() }
        }
        .accessibilityIdentifier("achievements-screen")
    }

    private var languageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    private var disclosure: String {
        document?.disclosure.resolved(languageCode: languageCode)
            ?? String(localized: "achievements.disclosure")
    }

    private var personalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("achievements.together", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(appAccent)
            Text("achievements.badge")
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func campaignCard(_ campaign: AchievementCampaign) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("achievements.campaign")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(campaign.title.resolved(languageCode: languageCode))
                .font(.title3.weight(.semibold))
            Text(campaign.who.resolved(languageCode: languageCode))
            Text(campaign.why.resolved(languageCode: languageCode))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let photo = URL(string: campaign.photoURL), photo.scheme == "https" {
                AsyncImage(url: photo) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.15)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            ProgressView(value: campaign.progress)
                .tint(appAccent)
            Text(progressLabel(campaign))
                .font(.subheadline.weight(.semibold))
            Text(campaign.date)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let link = URL(string: campaign.linkURL), link.scheme == "https" {
                Link("achievements.more", destination: link)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(format: String(localized: "achievements.total"), money(document?.totalDonated ?? 0)))
                .font(.headline)
            Text(String(format: String(localized: "achievements.people"), document?.peopleHelped ?? 0))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("achievements.history")
                .font(.headline)
            if document?.history.isEmpty != false {
                Text("achievements.history.empty")
                    .foregroundStyle(.secondary)
            }
            ForEach(document?.history ?? []) { gift in
                VStack(alignment: .leading, spacing: 4) {
                    Text(gift.recipient.resolved(languageCode: languageCode))
                        .font(.headline)
                    Text("\(money(gift.amount)) · \(gift.date)")
                    Text(gift.method.resolved(languageCode: languageCode))
                        .font(.subheadline)
                    Text(gift.description.resolved(languageCode: languageCode))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(gift.proof) { item in
                        if let url = URL(string: item.url), url.scheme == "https" {
                            Link(item.title.resolved(languageCode: languageCode), destination: url)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var badgeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("achievements.yours")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                badge("achievements.badge.first", symbol: "alarm.fill", unlocked: model.localAchievements.firstAlarm)
                badge("achievements.badge.streak", symbol: "sun.max.fill", unlocked: model.localAchievements.sevenDayStreak)
                badge("achievements.badge.friend", symbol: "person.2.fill", unlocked: model.localAchievements.friendAlarm)
            }
        }
    }

    private func badge(_ title: LocalizedStringKey, symbol: String, unlocked: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: unlocked ? symbol : "lock.fill")
                .font(.title2)
                .foregroundStyle(unlocked ? appAccent : .secondary)
            Text(title)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .opacity(unlocked ? 1 : 0.55)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(unlocked ? "achievements.unlocked" : "achievements.locked"))
    }

    private func progressLabel(_ campaign: AchievementCampaign) -> String {
        if campaign.goalAmount <= 0 {
            return String(localized: "achievements.goalMissing")
        }
        return "\(money(campaign.raisedAmount)) / \(money(campaign.goalAmount))"
    }

    private func money(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = document?.currency ?? "EUR"
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount) \(document?.currency ?? "EUR")"
    }

    private func reload() async {
        if document == nil {
            document = AchievementsContentStore.startingDocument()
        }
        if let remote = await AchievementsContentStore.refresh(urlString: AppConfig.achievementsContentURL) {
            document = remote
        }
    }
}
