# Yearly subscription

Product id: `com.grandelevas.wakemeup.yearly`

Subscription group name: `Wakito`

Price: about 2.99 EUR per year. Apple’s price tier is chosen in App Store Connect, not in the app.

There is no free trial and no introductory offer.

Fastlane 2.242 has no App Store Connect API call that creates a subscription group. The manual workflow `.github/workflows/subscription.yml` only checks the product id in `WakeMeUp/Wakito.storekit` and prints these steps. It does not call Apple and it does not create a certificate.

## TestFlight

A purchase in TestFlight is a sandbox purchase. Apple does not charge the tester. The paywall still appears, and Restore Purchases uses the sandbox Apple ID.

## Before the product can be created

On iPhone Safari, signed in as the Account Holder:

1. Open [App Store Connect](https://appstoreconnect.apple.com) → **Business** (or **Agreements, Tax, and Banking**).
2. Under **Paid Apps**, open the agreement. If it says **Pending**, accept the **Paid Applications Agreement**.
3. Add a bank account that can receive EUR. Complete the tax forms Apple shows (the ones for the account country). The agreement stays incomplete until bank and tax are both done.
4. Open [App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/) and enroll with the same Account Holder Apple ID if the account earned under 1 million USD in the previous year. Approval is separate from the agreement and can take a few days. Until it is approved, Apple’s commission stays at the standard rate. The 2.99 EUR price does not change.

## Create the subscription

Still in Safari:

1. App Store Connect → **Apps** → **Wakito**.
2. **Subscriptions** → **+** to create a subscription group. Name it exactly `Wakito`.
3. Inside that group, **+** to create a subscription.
4. Reference name: `Wakito Yearly`. Product ID: `com.grandelevas.wakemeup.yearly`. Duration: **1 year**. Do not add an introductory offer or a free trial.
5. Set the price. Pick the tier that is 2.99 EUR (or the closest tier Apple shows for Poland).
6. Add an English and a Polish localization. Display name and description must mention a year of Wakito and that there is no free trial.
7. Review screenshot: a picture of the paywall is enough. Status must leave **Missing Metadata** before the next version is submitted.
8. **App Information** → **License Agreement**: leave **Apple’s Standard License Agreement**.
9. **App Information** → **Privacy Policy URL**: host `docs/privacy-policy.md` at the address in `PrivacyPolicyURL` (`https://grandelevas.github.io/wakito-content/privacy`) or replace that key with the real public page. Reviewers open this link.
10. In the version’s **In-App Purchases and Subscriptions**, add `com.grandelevas.wakemeup.yearly`, then submit the version.

The paywall already links to Apple’s standard EULA, the privacy URL, Restore Purchases, the price and period, the auto-renew terms, and the Achievements content.
