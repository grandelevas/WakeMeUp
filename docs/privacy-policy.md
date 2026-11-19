# Wakito privacy policy

This is a draft the owner can host (for example on GitHub Pages) and paste into App Store Connect. Replace the contact address before submission.

**Last updated:** 19 November 2026

Wakito is an alarm app. It does not run its own server and it does not sell data.

## Data on this iPhone

Alarm times, labels, repeat days, group names, snooze settings, and song links are stored on the device. Imported audio is stored in the app's local `Library/Sounds` folder. None of that leaves the phone unless you turn on iCloud sharing.

## Song links

A Spotify, YouTube, or Apple Music link is only opened after you tap **Play my song**. Wakito does not read your music library and does not upload the link to a developer server.

## iCloud sharing

Remote alarms are optional. When CloudKit is configured and you accept an invite, alarm commands (time, label, and an optional song link) sync through **your** iCloud account, in a private database zone that you share with the person you invited. Apple hosts that data under your Apple ID. Wakito's developer cannot read it.

You can revoke a person at any time. Revoking stops new commands. It does not delete alarms that were already created.

## Notifications and alarms

If you allow alarms, iOS schedules them with AlarmKit so they can ring while the phone is locked or silenced. If you deny that and allow notifications instead, iOS shows ordinary notifications, which do not override the silent switch. Wakito does not request tracking permission and does not include advertising.

## Contact

Replace this line with a real address before App Store submission: privacy@example.com
