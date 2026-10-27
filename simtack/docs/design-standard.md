# Design standard: what this UI is measured against

Written as part of the token-discipline pass, so the acceptance bar is recorded
rather than remembered. Every number below was produced by a command on this
checkout, not estimated. The enforcing tests are named at the end.

## The bar, and what each part of it is for

| Surface | Compared against | What that means concretely here |
| --- | --- | --- |
| Practitioner console | Epic, Oracle Health Cerner | Dense rows, aligned columns, one visible primary action per screen, no decorative card nesting. A clinician should be able to read a triage in one pass without scrolling past three other clinicians' findings. |
| Every visual value | Material 3, US Web Design System | Each colour, radius and size is a named token, resolved through the theme, never written inline. USWDS and M3 both publish scales; an app that ignores them is not a theme, it is a pile of literals. |
| Patient intake flow | OpenMRS, WHO mHealth guidance for low-literacy and low-connectivity settings | One decision per screen, plain language, large tap targets, no interaction that only works with a precise gesture. |
| Accessibility | WCAG 2.2 AA | 4.5:1 for body text, 3:1 for large text and non-text indicators, colour never the only channel, controls reachable by keyboard and screen reader. |

Deliberately **not** imitated: gradient-heavy consumer-fintech styling and
dashboard card mosaics. Neither survives contact with a clinic that has one
screen and eight patients.

## What was measured before this pass

| Measurement | Value (measured against the commit before this pass) |
| --- | --- |
| Hex colour literals in `lib/` | 415 across 90 distinct values; **331 of them in 21 screen/widget files** outside `core/theme/` |
| `AppPalette` members available to screens | 9 |
| Share of all colour use taken by one violet (`#6D28D9`) | 114 of 415 (27%) |
| Coverage of the 12 most-used values | 273 of 415 (66%) |
| Hardcoded numeric `BorderRadius.circular(` sites | 145 in `lib/`, 131 outside the theme — against `AppRadius` defined with **0** references |
| `BackdropFilter`, `RadialGradient`, sparkle/magic icons, emoji | 0 — the generated-UI *decor* was already absent |
| Distinct font sizes written inline | 224 `fontSize:` literals outside the theme |

The conclusion that changed the plan: the app did not look generated because of
gradients or glass. It looked generated because **90 colours existed for roughly
12 jobs, one accent did the work of a quarter of them, and nothing about any of
it was enforced.**

## What is enforced now

1. **`AppAccent` is a real scale and it is checked.** `test/app_theme_test.dart`
   asserts each accent against the surface it sits on at WCAG ratios, in both
   brightnesses. The claim that previously sat in a docstring — brand accents
   "read well on both backgrounds" — was measured and found false: violet was
   **2.06:1** and teal **2.67:1** on the dark surface, both below the 4.5:1 a
   label needs, in an app with a user-selectable theme mode. Accents now resolve
   per brightness; the failing docstring was replaced rather than left alone.
2. **No inline colour literals.** `test/no_inline_colour_test.dart` fails the
   build on `Color(0x…)` anywhere in `lib/` outside `core/theme/`. Measured
   result of the pass: **331 literals in 21 files became 0**. Two things sit
   outside the pattern because they are not widget colours and are not
   allowlisted: `PdfColor.fromInt` in the report exporter (a PDF is printed on
   white paper and has no dark mode) and `0xFFFFFFFF` as a bit mask in
   `DoctorDraft.hash`.
3. **A radius that the scale already names cannot be written as a number.** Same
   test file. The four scale values (8/12/16/24) are forbidden inline; the rest
   are counted by a ratchet: **54** numeric radii (down from 131) and **224**
   font sizes may not increase.
4. **Offline session state is visible.** `SessionTrustStrip` names, on every
   practitioner screen, whether a server vouched for this account, when, and how
   long offline sign-in continues. Cached access is never allowed to look like
   server-confirmed access.
5. **One story-shaped pattern, piloted in one place.** `StoryPager` now pages the
   pain points inside a visit on the practitioner's clinical report, instead of
   stacking every card in one long scroll. It borrows the pagination of a stories
   surface and drops the two behaviours that make that format unusable in a
   clinic: it never advances on a timer, and there is no invisible tap-to-advance
   half — the rail, the counter and the labelled chevrons are the controls, so
   the sequence works with a screen reader and with one thumb. It is not used on
   the body map, where a tap *is* the data, and not used in intake, where paging
   would hide the question being answered.
6. **The clinical store is encrypted at rest wherever the platform can keep a
   key apart from the data.** `test/local_envelope_test.dart` and
   `test/local_database_encryption_test.dart` fail the build if the document is
   ever written as plaintext once a keystore is configured, if a legacy plaintext
   store survives migration, or if an envelope that will not authenticate is
   handed back as a partly readable record. Where there is no keystore — web, and
   every widget test — the store stays plaintext and the app says so, rather than
   encrypting with a key stored beside the ciphertext and calling that a
   protection. The full asset/adversary reasoning lives in `docs/threat-model.md`.

## Known gaps, stated rather than implied

- **224 inline font sizes remain.** The `TextTheme` ramp exists and is not used
  by screens. Folding them is a per-screen visual change, not a substitution, so
  it was not done blind; the ratchet stops it getting worse, and the pager added
  to this pass takes its size from `TextTheme.labelMedium` instead of joining
  them.
- **54 off-scale radii remain** (2/4/6/10/14/20/999) for the same reason.
- **Two UI strings ship as English** in Luganda, Runyankole and Lusoga (the
  pager's Previous/Next). Kiswahili has real translations. The ceilings in
  `l10n_parity_test.dart` record the exact count and the reason.
- **Web has no keystore.** Device-bound credentials use `flutter_secure_storage`
  on Android and iOS; on web it degrades to browser storage, which is why the
  7-day trust window and the PBKDF2 cost are not optional there, and why the
  trust strip is mandatory rather than decorative. The same limit reaches the
  clinical store: `main()` opts it into at-rest encryption only on platforms that
  can hold the data key apart from the data, so on web the document is stored in
  plaintext by that same honest decision, not by omission (see
  `docs/threat-model.md`).
- **Colour is still a channel for risk.** The bands carry a text label too, which
  is what keeps this WCAG-compliant; the label is not asserted by a test yet.
- **No usability evidence.** Nothing here is a claim that the interface is easy
  for a real clinician or a low-vision patient: there is no session data, no
  screen-reader audit and no participant study in this repo. The comparison above
  is against published standards, which is a weaker claim and the only one
  available.

## Enforcing tests

| Test | Fails when |
| --- | --- |
| `test/no_inline_colour_test.dart` | an inline colour literal appears, a radius duplicates a scale value, or the radius/font-size counts grow |
| `test/app_theme_test.dart` | an accent drops below its WCAG bar on the surface it is meant for, or a palette surface drifts from the value the ratios assume |
| `test/l10n_parity_test.dart` | a key is missing in a locale, or the English-verbatim count for a locale exceeds its recorded ceiling |
| `test/offline_trust_test.dart`, `test/offline_auth_test.dart` | offline sign-in, registration, the wrong-password rejection, the HTTP-401 rejection, or the 7-day window changes behaviour |
| `test/story_pager_test.dart` | the pager gains an auto-advance timer or an invisible tap zone, an item becomes unreachable, or the end chevrons wrap instead of disabling |
| `test/local_envelope_test.dart`, `test/local_database_encryption_test.dart` | the at-rest envelope stops round-tripping or authenticating, the store writes a configured-keystore document as plaintext, migration leaves the plaintext behind, or an unreadable envelope is opened instead of quarantined |
