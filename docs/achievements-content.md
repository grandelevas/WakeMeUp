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
- These `campaign` fields are optional. Leave one out, or use an empty list, and that part of the screen stays hidden. Older app builds ignore them and still read the rest of the file. `schemaVersion` stays `1`.
  - `description` is `{ "en", "pl" }`. A blank line (`\n\n`) starts a new paragraph.
  - `goalNote` is an optional `{ "en", "pl" }` line under the raised and goal amounts. Leave it out and that line stays hidden.
  - `photos` is a list of `{ "url", "caption": { "en", "pl" } }`. `caption` may be omitted. `url` must be `https`.
  - `updates` is the newest result first: `{ "date": "YYYY-MM-DD", "title": { "en", "pl" }, "text": { "en", "pl" }, "photos": [ ... ] }`. `title` and `photos` may be omitted.
  - `thanks` is a list of `{ "from", "date": "YYYY-MM-DD", "text": { "en", "pl" }, "photoURL", "videoURL" }`. Only `text` is required. `photoURL` and `videoURL` must be `https` when present.
- `history` is past gifts. `amount` is what was actually given. `proof` is a list of `{ "id", "title": { "en", "pl" }, "url" }`.
- The app adds the history amounts for “Together we have donated” and counts different English recipient names for “People helped”.
- `userCount` is an optional whole number. The app first reads `stats/community.json` in this repository (updated by the Community count workflow). If that file is missing, it uses `userCount` from this JSON. `userCountDate` is an optional `YYYY-MM-DD`. Leave the field out, or set it to `0`, and the line stays hidden. The app never invents a number. There is no analytics SDK and no tracking.
- No other record types. The app does not query extra indexes.

## Example

The same file is bundled at `WakeMeUp/Resources/achievements.json`.

```json
{
  "schemaVersion": 1,
  "currency": "EUR",
  "disclosure": {
    "en": "Mateusz gives 50% of subscription profit to causes he chooses. The app does not collect donations.",
    "pl": "Mateusz przekazuje 50% zysku z subskrypcji na wybrane cele. Nie zbieramy darowizn w aplikacji."
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
7. To show how many people use Wakito, add `"userCount": 1234` and, if you want, `"userCountDate": "2026-11-20"`. Copy the number from App Store Connect analytics. Do not guess. If you omit `userCount` or set it to `0`, the line stays hidden.

## Liczba osób (z iPhone’a)

1. W App Store Connect sprawdź analitykę Wakito i zapisz prawdziwą liczbę użytkowników. Nie zgaduj.
2. W aplikacji GitHub otwórz publiczne repozytorium `grandelevas/wakito-content`, plik `achievements.json` na gałęzi `main`.
3. Dopisz w głównym obiekcie, obok `schemaVersion`, na przykład `"userCount": 1234` i `"userCountDate": "2026-11-20"`. `schemaVersion` zostaje `1`.
4. Zatwierdź zmianę. Przy następnym otwarciu Wakito pokaże „Jest nas już 1 234”.
5. Gdy pola nie ma albo `userCount` wynosi `0`, wiersz się nie pokazuje. Aplikacja nie wymyśla liczby, nie ma własnego serwera i nie śledzi użytkowników.
