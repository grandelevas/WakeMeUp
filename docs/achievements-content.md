# Achievements content

Wakito reads this JSON from `AchievementsContentURL` in `WakeMeUp/WakeMeUpConfig.plist`. The shipped URL is:

`https://raw.githubusercontent.com/grandelevas/wakito-content/main/achievements.json`

If that file is missing or the schema version is not 1, the app keeps the last good copy, then the copy bundled in the app. There is no donation button and no payment link.

## Schema version 1

- `schemaVersion` must be `1`.
- `currency` is a code such as `EUR`.
- `disclosure`, and every `title`, `who`, `why`, `recipient`, `method`, and `description`, has `en` and `pl`.
- `campaign` is the current card. `goalAmount` and `raisedAmount` are numbers. Use `0` until you record a real amount. Do not invent one.
- `photoURL` and `linkURL` are `https` links or empty strings. The link is a normal “read more” link, not a payment button.
- `history` is past gifts. `amount` is what was actually given. `proof` is a list of `{ "id", "title": { "en", "pl" }, "url" }`.
- The app adds the history amounts for “Together we have donated” and counts different English recipient names for “People helped”.
- No other record types. The app does not query extra indexes.

## Example

The same file is bundled at `WakeMeUp/Resources/achievements.json`.

```json
{
  "schemaVersion": 1,
  "currency": "EUR",
  "disclosure": {
    "en": "Mateusz gives 50% of the app's proceeds to causes he chooses. The app does not collect donations.",
    "pl": "Mateusz przekazuje 50% przychodu z aplikacji na wybrane cele. Nie zbieramy darowizn w aplikacji."
  },
  "campaign": {
    "id": "placeholder",
    "title": { "en": "Replace with the campaign title", "pl": "Tu wpisz nazwę zbiórki" },
    "who": { "en": "Replace with who this helps", "pl": "Tu wpisz, komu pomagamy" },
    "why": {
      "en": "Replace with why this cause was chosen. Leave raised at 0 until you record a real amount.",
      "pl": "Tu wpisz, dlaczego wybrano ten cel. Zostaw zebraną kwotę 0, dopóki nie zapiszesz prawdziwej sumy."
    },
    "photoURL": "",
    "goalAmount": 0,
    "raisedAmount": 0,
    "date": "2026-11-19",
    "linkURL": ""
  },
  "history": []
}
```

## Edit it from the iPhone

1. In the GitHub app, create a **public** repository named `wakito-content` under `grandelevas`.
2. Add a file `achievements.json` on branch `main` and paste the example. Commit.
3. Optional: add images in the same repo and set `photoURL` or a proof `url` to the raw image link.
4. The raw file is `https://raw.githubusercontent.com/grandelevas/wakito-content/main/achievements.json`. That is already the app’s `AchievementsContentURL`.
5. To change the text later, edit `achievements.json` in the GitHub app and commit. The next time Wakito is opened it downloads the new file. No app update is required.
6. Keep `raisedAmount` and every history `amount` at a number you can point to. Leave them at `0` until then.
