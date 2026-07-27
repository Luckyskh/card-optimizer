# Card Optimizer

Answers one question: **which of my credit cards should I use for this purchase?**

You tell it which cards you have. You pick a category and an amount. It ranks
your cards by how many rupees each would actually earn — after caps, exclusions
and minimum transaction values, not the headline rate on the marketing page.

The app works entirely offline. It never asks for a card number.

---

## Running it

```bash
flutter run
```

Two tabs. **My cards** is where you tick the cards you own. **Which card?** is
where you pick what you are buying.

## Running the tests

```bash
flutter test
```

The interesting ones are in [test/engine_test.dart](test/engine_test.dart).
There is one group per item in the "non-obvious structures" list in
[CLAUDE.md](CLAUDE.md) — shared caps, quarterly caps, minimum transaction
values, Prime tiers, spend tiers, and points-versus-cashback. If you change the
reward maths, these tell you what you broke.

---

## How the app is put together

```
assets/rules.json          the reward dataset - the heart of the app
lib/
  models/                  Dart versions of what is in rules.json
  data/                    loading rules, saving your cards, fetching alerts
  engine/                  the ranking logic
  screens/                 the two tabs
  widgets/                 the "terms changed" banner
```

Start with [lib/engine/recommendation_engine.dart](lib/engine/recommendation_engine.dart).
It reads top to bottom and every awkward rule has a comment saying which real
card it exists for.

### Merchants

`rules.json` also carries a merchant directory — around 100 places across
shopping, food delivery, quick commerce, groceries, dining, travel, cabs,
movies and streaming, recharges, utilities, fuel, insurance, education, rent,
wallets and UPI. Pick the category, then tap the shop.

This is not decoration. Several accelerated rates only apply at named
merchants: Axis ACE pays 4% at Swiggy, Zomato and Ola but its base 1.5%
anywhere else in food delivery. Until the app could tell the engine *where* you
were spending, those rows could never fire.

Two things to know if you add merchants:

- The `id` is matched against the `merchants` lists inside `category_rates`, so
  it must stay lowercase and must not be renamed casually. Rename one and it
  silently stops matching the rate row that names it — which is why
  `engine_test.dart` has a test that every merchant named in a rate row exists
  in the directory. That test is what caught `sony liv` being filed as
  `sonyliv`.
- Adding a merchant never changes what a card pays. It only lets the engine see
  a rate row that was already in the dataset.

### The card pictures

Each card gets a small drawn mock — see
[lib/widgets/card_art.dart](lib/widgets/card_art.dart). Co-branded cards take
their partner's colours, because that is how people recognise them: the Swiggy
card is orange and the Swiggy BLCK is black, not two identical HDFC blues.

They are drawn rather than downloaded, for three reasons. The issuers' terms
PDFs contain no card artwork at all — they are legal documents, and the only
images inside them are alpha-mask blobs a millimetre across. Real artwork from
a bank's website is their trademarked brand asset. And five of the eleven cards
are HDFC ones whose pages refuse automated requests anyway, so half the list
would have had no picture.

### One thing worth understanding

Never compare cards by their advertised multiplier. "10X rewards" on a card
whose points are worth ₹0.25 is 1.25%, which loses to a plain 1.625% card. The
engine converts everything into rupees before comparing, and there is a test
that fails if that ever stops happening.

---

## The terms monitor

Indian issuers change their reward rules constantly — eight of the eleven cards
in `rules.json` changed in the first seven months of 2026. So the numbers in the
app go stale on their own.

`tools/terms_watch/` is a small program that re-reads the issuers' own published
terms documents, compares them with the copies in `snapshots/`, and writes
`alerts.json` when the wording moves. The app downloads that file on launch and
shows a banner.

There is no server anywhere in this. GitHub runs the check on a schedule and
commits the result; the app reads a plain file.

### Running it yourself

```bash
dart run tools/terms_watch/bin/check_terms.dart --dry-run
```

`--dry-run` fetches and compares but writes nothing, which is the safe way to
see what it would do. Drop the flag to actually update `snapshots/` and
`alerts.json`. Add `--only sbi-mitc` to check a single document.

To check PDF documents you need `pdftotext`:

- **Ubuntu / GitHub Actions:** `sudo apt-get install poppler-utils` (the
  workflow already does this)
- **Windows:** install poppler and put its `bin` folder on your PATH. Without
  it the script still checks every HTML document and tells you it skipped
  the PDFs.

### Adding a document to watch

Edit [tools/terms_watch/sources.json](tools/terms_watch/sources.json). Each
entry needs a `doc_id`, the `card_ids` it covers, a `label` and a `url`. There is
no "is it a PDF" field — the fetcher works that out from the response, because
ICICI serves a real PDF from a URL ending in `.page`.

### What it will not do

**It never edits `rules.json`.** Spotting that a document's text moved is not
the same as knowing the new reward rate. When an alert appears, you read the
document yourself, update `assets/rules.json` by hand, and bump its `version`.
Automating that step would put invented numbers in front of users.

### Documents that do not work

Two honest gaps, both found by actually trying:

- **HDFC blocks its own PDFs.** `mitc-in-english.pdf`, the Millennia page and
  the Regalia Gold page return 403 to every HTTP client tried. They are marked
  `known_blocked` in `sources.json`, which means the monitor still attempts
  them each run but a failure does not mark the scheduled job as broken. Those
  cards need checking by hand. If a run reports one of them working again,
  remove the flag.
- **Two documents have no URL yet** — the card-specific terms for Flipkart Axis
  and Axis Atlas. They are listed with `"url": null` so the monitor reports them
  as unconfigured rather than silently watching nothing. Paste in a link when
  you find one.

---

## Before the alerts will reach anyone

The app fetches `alerts.json` over plain HTTPS, so the repository has to be
public. Two steps:

1. Push this repository to GitHub as a **public** repository.
2. In [lib/data/alerts_service.dart](lib/data/alerts_service.dart), replace
   `OWNER` and `REPO` in `defaultAlertsUrl` with your GitHub username and
   repository name.

Until you do step 2 the app skips the download entirely rather than throwing
network errors, so it is safe to leave as-is while you are still building.

The schedule lives in
[.github/workflows/check-terms.yml](.github/workflows/check-terms.yml) and runs
on the 1st and 16th of each month. GitHub's cron has no "every 15 days", so
twice a month is as close as the format gets. You can also run it yourself from
the Actions tab at any time.
