import AlarmKit
import SwiftUI
import WidgetKit

/// AlarmKit uses this Live Activity for the snooze countdown. The alerting UI
/// itself is drawn by the system from `AlarmPresentation`.
struct WakeMeUpAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<WakeMeUpAlarmMetadata>.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "alarm.fill")
                    .font(.title2)
                    .foregroundStyle(context.attributes.tintColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.metadata?.label ?? "WakeMeUp")
                        .font(.headline)
                    Text("WakeMeUp")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.2))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.metadata?.label ?? "WakeMeUp")
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                Image(systemName: "zzz")
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(context.attributes.tintColor)
            }
            .keylineTint(context.attributes.tintColor)
        }
    }
}

@main
struct WakeMeUpWidgetBundle: WidgetBundle {
    var body: some Widget {
        WakeMeUpAlarmLiveActivity()
    }
}
