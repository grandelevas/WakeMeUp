import AlarmKit

/// Metadata AlarmKit hands to the Live Activity. Compiled into both the app and the widget.
struct WakeMeUpAlarmMetadata: AlarmMetadata {
    var alarmID: String
    var label: String
    var songURL: String?
}
