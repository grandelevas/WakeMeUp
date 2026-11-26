import SwiftUI

struct AchievementsView: View {
    @Environment(\.appAccent) private var appAccent
    @State private var document: AchievementsDocument?
    @State private var firstUse = Date()
    @State private var readingCampaign = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(disclosure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    userCountRow
                    personalCard
                    if let campaign = document?.campaign {
                        campaignCard(campaign)
                        CampaignPhotoStrip(photos: campaign.gallery, title: "achievements.photos")
                        CampaignUpdatesSection(updates: campaign.visibleUpdates)
                        CampaignThanksSection(notes: campaign.visibleThanks)
                    }
                    totalsCard
                    historySection
                    badgeSection
                }
                .padding(16)
            }
            .navigationTitle("tab.achievements")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    OpenSettingsLink()
                }
            }
            .navigationDestination(isPresented: $readingCampaign) {
                if let campaign = document?.campaign {
                    CampaignDetailView(campaign: campaign)
                }
            }
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

    @ViewBuilder
    private var userCountRow: some View {
        if let count = document?.visibleUserCount {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: String(localized: "achievements.userCount"), formattedCount(count)))
                    .font(.headline)
                if let date = formattedUserCountDate {
                    Text(String(format: String(localized: "achievements.userCountDate"), date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("achievements-user-count")
        }
    }

    private func formattedCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: count)) ?? String(count)
    }

    private var formattedUserCountDate: String? {
        let raw = document?.userCountDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private var personalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("achievements.together", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(appAccent)
            Text("achievements.support")
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
            if let photo = SecureLink.url(from: campaign.photoURL) {
                CachedRemoteImage(url: photo)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            ProgressView(value: campaign.progress)
                .tint(appAccent)
            Text(progressLabel(campaign))
                .font(.subheadline.weight(.semibold))
            if let note = campaign.visibleGoalNote?.resolved(languageCode: languageCode) {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(campaign.date)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let link = SecureLink.url(from: campaign.linkURL) {
                Link("achievements.more", destination: link)
            }
            if campaign.hasStory {
                Button("achievements.readMore") {
                    readingCampaign = true
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("achievements-read-more")
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
                        if let url = SecureLink.url(from: item.url) {
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
                badge("achievements.support", symbol: "heart.fill", unlocked: true)
                ForEach(SupportMilestone.allCases) { milestone in
                    badge(
                        tenureTitle(milestone),
                        symbol: "calendar",
                        unlocked: milestone.isUnlocked(firstUse: firstUse, now: .now)
                    )
                }
            }
        }
    }

    private func tenureTitle(_ milestone: SupportMilestone) -> LocalizedStringKey {
        switch milestone {
        case .oneMonth: "achievements.tenure.month"
        case .sixMonths: "achievements.tenure.sixMonths"
        case .oneYear: "achievements.tenure.year"
        case .twoYears: "achievements.tenure.twoYears"
        case .threeYears: "achievements.tenure.threeYears"
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
        AchievementMoney.format(amount, currencyCode: document?.currency ?? "EUR")
    }

    private func reload() async {
        firstUse = LaunchConfiguration.seedDemo
            ? DemoTenure.firstUse()
            : SupportTenureStore.ensureFirstUse()
        if document == nil {
            document = AchievementsContentStore.startingDocument()
        }
        if LaunchConfiguration.seedDemo { return }
        if let remote = await AchievementsContentStore.refresh(urlString: AppConfig.achievementsContentURL) {
            document = remote
        }
        if let current = document,
           let community = await AchievementsContentStore.communityCount(urlString: AppConfig.communityCountURL) {
            document = current.applying(community: community)
        }
    }
}
