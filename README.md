# Fişlik iOS

Native SwiftUI client for [Fişlik](https://fislik.selamet.dev) — photograph receipts, let the API read amount and VAT, and share the month with your accountant.

- Bundle id: `dev.selamet.fislik` · iOS 17+
- API: `https://fislik-api.selamet.dev` (see [`docs/api-contract.md`](docs/api-contract.md))
- Design: Claude Design project "Fislik iOS v2" (37 screens)

## Development

```sh
brew install xcodegen
xcodegen            # generates Fislik.xcodeproj from project.yml
open Fislik.xcodeproj
```

Set your Apple Developer team in *Signing & Capabilities* (or `DEVELOPMENT_TEAM` in `project.yml`).

Tests:

```sh
xcodebuild test -project Fislik.xcodeproj -scheme Fislik -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```
