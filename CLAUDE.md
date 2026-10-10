# Agent implementation contract

## Goal

Ship **NikuCue**, an iPhone-first, local-first cat companion habit app. The cat supports the person; the person is not responsible for keeping the cat alive or happy.

## Non-negotiable constraints

- No runtime AI (including on-device generative AI), backend, paid API, login, cloud database, remote push service, analytics upload, or downloaded character content.
- Only Apple StoreKit and Google AdMob/UMP are allowed network integrations in the app. User-initiated support/privacy/Files sharing is an explicit separate exception.
- Ad-free is ONE non-consumable StoreKit product. No subscriptions, coins, rewarded videos, interstitials, app-open ads, mediation, or paid habit slots.
- No guilt: no cat starvation, illness, death, sadness caused by skipped habits, loss of affection, broken-streak alarms, or compulsory care.
- No duplicate completions. Commit local data successfully BEFORE any success feedback or unlock.
- No widget, Live Activity, background presence, or notification-animation promise in v1.
- New iOS-native code: SwiftUI + SpriteKit + SwiftData. Keep domain logic pure and independent from UI/SDKs. Use latest suitable STABLE tools available at implementation time, document and pin versions. Do not invent version numbers.
- iOS 17 is the provisional minimum deployment target, not an assertion about the partner's device. Verify the actual test device and SDK minimum before TestFlight.
- All user-facing strings from localization resources. Thai glyphs/diacritics must not clip. Use Gregorian calendar for stored day keys regardless of presentation locale.
- Ads must not receive habit names, completion records, cat nickname, free-form text, or timestamps from the habit database.
- Do not claim “no data collected” or “no network” when shipping advertising SDKs.
- No store identifiers, production ad IDs, credentials, support addresses, or URLs may be guessed. Keep explicit configuration placeholders and a release blocker.
- No production upload, purchase configuration change, account modification, push, or destructive command without owner authorization.

## Work method

1. Inspect repo and environment before writing. Do not overwrite existing CLAUDE.md; merge this contract into it if needed.
2. Implement P00–P01 first, then follow task dependencies. Work in a new branch only when a repository already exists; never initialize over unrelated work.
3. Keep `docs/IMPLEMENTATION_LOG.md` with decisions, changed files, commands, results, and pending human checks.
4. Use mock ads/StoreKit configuration for development. Physical tests must use official test ads/test devices; never ask the partner to click live ads.
5. Before adding any dependency, state why built-in frameworks cannot handle it. Pin the selected stable dependency and keep a license inventory.
6. Review for data loss, timezone bugs, lifecycle races, incorrect entitlement handling, notification duplication, and accidental ad clicks.
7. Every task needs evidence: test output, screenshot, video, or explicitly “not executed: reason.” Never convert an untested assumption into a passed check.
8. Treat source/reaction JSON as build-time input. Bundle it; do not fetch updates online. Validate it in local tests.
9. Do not install third-party agent skills or run scripts from untrusted repositories without reviewing their code and permissions.

## Product name and app icon

- **NikuCue** is the owner-approved product name, not a placeholder; keep the on-screen brand, Xcode target/project naming, localization app.name, store drafts and generated documentation consistent. Do not restore the former Pix-branded product name.
- The App Store/Home Screen icon is an **original stylized cat paw print** (one central pad and four small toe pads), with no camera/photography cues, no "Pix" branding, no text, no outline resembling a third-party trademark, and no cropped paws.
- Implement the icon using `docs/14_APP_ICON.md`; preserve an editable source and produce a 1024 × 1024, opaque, square App Store icon asset. Preview at iPhone small sizes and human-review it; never treat a code-generated draft as automatically art-approved.
- The cat companion remains **Mali** (`มะลิ`/`マリ`). Do not rename the character, change mascot behavior, business model, or scopes as part of this branding update.
- Keep trademark/name availability as a release gate; brand approval here does not certify legal clearance.

## Art quality

Build an original cat, not Pawse/Finch art. A code-drawn rig is acceptable for the first prototype. It is NOT automatically a final asset. No “production-ready” claim until human review of static pose, facial expressions, seams, paws, and movement. Implement `CharacterArtProvider` so vector placeholders can become approved transparent textures without changing the state machine. Do not add Rive/Spine/Live2D as a hidden authoring requirement.

## Completion report

State implemented behavior, actual tests run, artifacts captured, known defects, and remaining owner tasks separately. “Build succeeded” is not “ready for App Store.”
