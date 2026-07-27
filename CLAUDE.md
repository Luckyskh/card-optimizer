# Card Optimizer — Project Brief

## What this app does

Indian credit card users hold multiple cards with byzantine reward structures.
This app answers one question: **"Which of my cards should I use for this purchase?"**

User picks a category or merchant (Swiggy, fuel, Amazon), the app shows which of
*their* cards earns the most, accounting for rates, caps, exclusions and minimum
transaction values.

## Who is building this

The owner is a **complete beginner with no prior coding experience**. When working
with them:

- Explain what each file does and why, in plain language
- Don't assume familiarity with Dart, state management patterns, or CLI conventions
- Prefer simple, readable code over idiomatic-but-dense solutions
- When something breaks, explain the cause, not just the fix

## Tech stack

- **Flutter** (Dart), developed in VS Code
- Targets Android and iOS
- **No backend.** No server, no database, no user accounts in v1
- User's own card list stored on-device (`shared_preferences`)
- Reward rules loaded from a bundled JSON asset

## Critical constraint: no PCI scope

The app **never** collects card numbers, CVVs, expiry dates, or any credentials.
Users select cards by *name* from a list ("HDFC Millennia"). This is deliberate —
it keeps the app entirely out of financial regulation and security compliance.
Do not add any feature that would change this.

## Data model

`assets/rules.json` is the heart of the app. It contains a `categories` taxonomy
and a `cards` array. Each card has an id, bank, name, fees, a base rate, and a
`category_rates` array.

### Non-obvious structures the engine must handle

These are real behaviours in the Indian market, not hypotheticals:

1. **Shared caps across categories.** Axis ACE's 5% and 4% categories share a
   single ₹500 monthly ceiling. See `shared_cap_group` and the `shared_caps`
   array. A naive per-category cap will overestimate earnings badly.

2. **Mixed cap periods.** Some caps are monthly, some quarterly (Flipkart Axis
   uses `quarterly_cap_inr`). The engine needs both.

3. **Minimum transaction values.** Swiggy cards require a ₹249 minimum for the
   accelerated rate (`min_transaction_inr`). A ₹150 order earns nothing.

4. **Conditional tiers.** Amazon Pay ICICI pays 5% to Amazon Prime members and
   3% to non-members. Needs a user-level flag, not just a card id.

5. **Spend-tiered rates.** IDFC FIRST Select pays 3 points per ₹200 up to ₹20,000
   per cycle, then 10 points per ₹200 above that. The applicable rate depends on
   where the user already is in their billing cycle. This is the hardest case.

6. **Points vs cashback.** Normalise everything to effective % back in rupees
   using `point_value_inr`. "4 points per ₹150" where a point is worth ₹0.25 is
   0.67% — not "4x rewards". Never compare raw point counts across cards.

## Data accuracy

Reward rules change constantly — eight of the eleven seeded cards changed in the
first seven months of 2026. Rules were compiled from web sources and **fields
marked `_verify` have not been checked against issuer MITC documents.** Treat
`rules.json` as authoritative for app logic, but flag to the owner when a value
looks stale. Never invent or "remember" a reward rate; if a number isn't in the
JSON, ask.

## Roadmap

**v1 (built)** — bundled rules.json, add cards, pick a category, see ranked
recommendation. Offline only.

**v2 (partly built)** — a scheduled GitHub Action re-reads the issuers' terms
documents twice a month and publishes `alerts.json`; the app fetches it on
launch and shows a banner. See `tools/terms_watch/` and the README.

Still outstanding from v2: fetching `rules.json` itself from the repo so rate
corrections reach users without an app update, and Firebase Cloud Messaging so
alerts arrive without the user opening the app. The alerts pipeline was built
without FCM deliberately — it keeps the "no backend, no accounts" constraint
intact, and FCM can be layered on later without reworking it.

**Later** — milestone tracker, annual-fee-vs-rewards-earned analysis, "which card
should I get next" recommender (this is the monetisation path via card issuer
affiliate programmes).

## Working on the reward engine

`lib/engine/recommendation_engine.dart` is where the six awkward behaviours
listed above are handled, and `test/engine_test.dart` has one group per
behaviour. Change the maths, run `flutter test`, and the tests will tell you
which real card you just broke.

Two decisions in there worth knowing about, both flagged in comments:

- **Spend tiers are read out of the row's English label.** IDFC FIRST Select's
  Rs 20,000 threshold only exists in the text `"Spends up to Rs 20,000 per
  statement cycle"`. If that wording changes the engine adds a visible warning
  rather than silently picking one tier. An explicit numeric field in
  `rules.json` would be more robust.
- **Spend beyond a cap is assumed to earn nothing**, rather than dropping to
  the base rate. That matches most of these cards but is worth confirming
  against the MITCs.

Where the dataset cannot give a firm number — Regalia Gold's "up to 10X on
SmartBuy" — the engine falls back to the base rate and says so on screen. It
does not guess. Same rule as the data accuracy note above.
