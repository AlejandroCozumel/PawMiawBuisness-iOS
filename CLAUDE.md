# PawMiaw Negocios (iOS)

The business app ("PawMiaw for Business"): the web's business workspace (`/provider`) as a
native SwiftUI app. Read `PORTING.md` first: its conventions are the owner's standing rules.

- Web (source of truth for screens): `/Users/usuario1/code/pawmiaw-web` (`src/routes/provider*.tsx`,
  `src/components/app/`, `src/hooks/use-provider-*.ts`).
- Backend: `/Users/usuario1/code/paw-miaw-backend` (Hono, `/api`, Bearer auth; feature docs in `docs/`).
- Family iOS app (patterns, tokens): `/Users/usuario1/code/PawMiawIos`. Don't edit it from here.
- Bundle id `com.pawmiaw.business`, team `XVMB5B3F2Y`. iOS 18+. iPhone and iPad.
- Names: **PawMiaw Business** in English (primary), **PawMiaw Negocios** in Spanish (Mexico) — the
  home-screen name comes from `{en,es}.lproj/InfoPlist.strings`.
- App Store Connect: app "PawMiaw Business", Apple ID 6830697697, SKU `pawmiaw-negocios-ios`,
  primary language English (U.S.), Spanish (Mexico) localization added (name only). App ID
  registered in Certificates, Identifiers & Profiles (no capabilities yet). Category, privacy,
  screenshots and the rest of the listing are not filled in.

## Build
- Build only: `./build.sh` (generic iOS Simulator destination). Never boot or create a simulator;
  reuse a booted one if a run is needed. `xcodebuild test` only with `-parallel-testing-enabled NO`.

## Left for the owner
- Push notifications (APNs entitlement, device registration), RevenueCat, env files, Apple/Google
  sign-in client ids. Plans are bought on the web (Stripe); the app only reads the plan.
