# LumaPass

**Create a pass that feels like yours.**

LumaPass is an open-source, iPhone-first SwiftUI starter for creating legitimate Apple Wallet generic, membership, loyalty, coupon, and event passes. It is designed to make the useful parts of Wallet passes easier to create; it does not generate payment cards, emulate Apple Pay, or reproduce passes issued by banks or other organizations.

[Try the interactive preview](./preview.html) · [Apple Wallet implementation](./backend/app/wallet.py) · [API reference](./backend/app/main.py) · [Architecture](#architecture) · [Production signing](#production-apple-wallet-signing)

The preview is a local, self-contained interface demo; it does not create a signed `.pkpass` file, send an image, or add anything to Wallet. A real pass is signed only by the production backend with Apple-issued Pass Type ID credentials. In demo mode, the server refuses to issue an unsigned pass.

> **One honest requirement:** Xcode, the iOS simulator, and the Apple signing services only run on a Mac with the relevant Apple developer account. A Windows PC cannot compile or launch an iOS app or register an Apple Pass Type ID. This repository includes the native SwiftUI sources, an XcodeGen specification, backend, demo, tests, and step-by-step production guide.

## Preview

Open `preview.html` in any recent web browser. Try the five tabs, change a pass type or color, edit native Wallet fields, search demo templates, and save a draft for the current browser session. It uses original CSS-generated artwork; it contains no Apple, banking, or third-party artwork. This preview is not an iOS build and never displays the real **Add to Apple Wallet** button.

## What works in the iOS app

- Five SwiftUI areas: **Inicio**, **Crear**, **Explorar**, **Mis diseños**, and **Perfil**.
- Five legitimate pass types: generic, membership, loyalty, coupon, and ticket.
- Eight original abstract demo collections, categories, searchable gallery, saved designs, author/license/use labels, report actions, and creator blocking.
- A visual editor with live pass preview, approximate safe area, iPhone and Apple Watch presentation, name and organization, primary/secondary/additional fields, optional expiry, QR and Code 128, palette and contrast feedback, and brightness, contrast, blur, gradient, crop, position, and zoom controls.
- Photos and Files pickers with bounded memory use, oversized-photo rejection, resolution notices, orientation-correct JPEG normalization, and metadata-free rendering.
- Private device-only drafts, file protection, and saved favorites.
- Native Sign in with Apple. Identity tokens exist only in memory on the device and are verified by Apple’s public signing keys on the server; passwords and Wallet credentials are never requested.
- `.pkpass` generation on a separate backend with Apple’s pass signer, standard legacy pass styles and `posterGeneric`, Apple’s official PassKit “Add Passes” sheet, and the Wallet web-service routes used for device registration, refresh, APNs notifications, update checks, and removal.
- A moderation-ready PostgreSQL API, private S3-compatible object storage, file validation and EXIF removal, favorites, creator blocking, abuse limits, private drafts, reports, deletion, an admin queue, and English localization scaffolding.

The preview is illustrative: Apple can rearrange or omit artwork and fields depending on the pass type, iOS/watchOS version, device, and language. Poster generic passes are an option on current supported software; a conventional generic or the matching existing pass style remains as the older-OS fallback.

## Screenshot

No simulator, Xcode, or iPhone is installed on the current Windows machine, so an authentic simulator screenshot is not checked into this repository or represented as a real iOS screenshot. The interactive browser preview is the honest visual preview to use until a Mac is available.

## Architecture

```text
Sources/LumaPassApp/           SwiftUI iPhone app, Sign in with Apple, PassKit
Sources/LumaPassCore/          Pass models, artwork rules, validation
Tests/LumaPassCoreTests/       iOS-independent Swift unit tests
preview.html                   Local interactive app preview; never issues passes
backend/app/                   FastAPI, Apple authentication, `.pkpass`, PassKit
backend/sql/                   PostgreSQL production schema
backend/tests/                 API, barcode, image/privacy, and pass-format tests
docker-compose.yml             Local demo PostgreSQL + private MinIO + API
project.yml                    XcodeGen iOS project specification
```

- **iPhone and iPad app:** Swift 6, SwiftUI, AuthenticationServices, PhotosUI, ImageIO/Core Image, UIKit, PassKit.
- **API:** Python, FastAPI, Pydantic, psycopg 3, PostgreSQL, PyJWT and Apple’s published identity JWKS, boto3, and S3-compatible object storage.
- **Pass generation:** Apple pass JSON and native image resources, a SHA-1 image manifest, and Apple’s WWDR/pass certificate chain, packaged and signed on the server. Production `.pkpass` files are delivered with `application/vnd.apple.pkpass` and `Cache-Control: no-store`.
- **Wallet updates:** Authenticated Apple Wallet registration, retrieval, device check, and unregister routes live under the pass’s HTTPS `webServiceURL`. Updates use Apple Wallet registration tokens, hashed in PostgreSQL, APNs pass-specific push tokens, a monotonically increasing change tag, and the official refresh endpoint.
- **Privacy boundary:** Local app drafts are stored under file protection. Apple Wallet data and creator drafts never enter public community records. Public gallery images are metadata-free, reviewed before publication, stored privately, and accessed using expiring signed URLs.
- **Administrator UI:** `/admin` has an authenticated, explicitly entered administrative bearer token; it does not write credentials into browser storage.

### Apple Wallet compatibility

The backend generates `posterGeneric` alongside the type-appropriate legacy pass style, preserves the same information across both, uses native Wallet field dictionaries for text, and makes the standard layout the fallback. Apple’s current guide explicitly describes this style priority and the poster/legacy compatibility pairing. Poster passes use separately rendered image resources; the pass does not place private field values into a flattened picture.

The poster pass uses the artwork resources appropriate to its style; the compatibility pass supplies its own icon and standard field layout. PNG artwork uses Wallet's 1x raster dimensions (29 × 29 icon, 160 × 50 logo, 375 × 123 strip, and 90 × 90 thumbnail where supported), with matching 2x and 3x variants. Generic passes include a square thumbnail for the legacy layout. Event tickets use a strip and omit background and thumbnail images, following Apple's event-ticket image guidance. Every `.pkpass` includes an icon, Apple’s signed `manifest.json`, and `signature`. **Open the actual simulator preview on every minimum supported iOS version before publishing:** Wallet owns the layout; the app’s editor preview is never presented as an exact OS render.

## Requirements

### Browser preview

- Any modern browser. Double-click `preview.html`; no installation or server is needed.

### Local API and database

- Docker Desktop with Docker Compose v2.
- Python 3.12 or newer for tests outside Docker.

### Native iOS app

- A Mac with Xcode 16 or newer, a current iOS simulator, XcodeGen (`brew install xcodegen`), and an Apple Developer Program account for device-signing, Sign in with Apple, Pass Type IDs, and production Wallet passes.
- An iPhone running a supported iOS release to add and scan a pass. An Apple Watch is optional.

## Run the API in local demo mode

The demo exercises the API, original editorial collection, upload review, and Apple-pass JSON and format validations. It deliberately **cannot sign or add a pass**. Never upload production certificates to make the demo issue a real user pass.

```powershell
Copy-Item backend\.env.example .env
docker compose up --build
```

Open the versioned API schema at `http://localhost:8000/api/docs`, check `/api/v1/health/live`, and browse `/api/v1/gallery/templates`. The moderator page is `http://localhost:8000/admin`.

The sample Docker credentials exist only for an **isolated local workstation**. They are not production defaults. `postgres` and MinIO publish ports only to `127.0.0.1`; change the example values before sharing or exposing services. `docker-compose.yml` disables pass signing in the demo. Do not tunnel the unauthenticated editorial preview or use local demo credentials on an internet-facing host.

Apply subsequent database changes with a documented, reviewed migration; never drop an existing database or remove a production volume to reset demo data.

### Run backend tests on Windows

From the project folder:

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r backend\requirements-dev.txt
.\.venv\Scripts\python.exe -m pytest
.\.venv\Scripts\ruff.exe check backend
.\.venv\Scripts\ruff.exe format --check backend
```

Python 3.12 is recommended for dependency compatibility. Local Python versions older or newer than the CI target can require additional native wheels.

### Build and run iOS unit tests on macOS

```sh
brew install xcodegen
xcodegen generate --spec project.yml
xcodebuild -project LumaPass.xcodeproj -scheme LumaPass \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO test
```

Change the simulator destination to one installed in Xcode. To make the app use your HTTPS test API, set the Xcode scheme’s `LUMAPASS_API_BASE_URL`. An iPhone cannot reach your Mac using `localhost`; use a trusted, HTTPS development endpoint. App Transport Security is not weakened to make plaintext Wi-Fi work.

## Production Apple Wallet signing

**Only configure production signing after enrolling an Apple Developer account and creating a legitimate Pass Type ID in Apple’s Certificates, Identifiers & Profiles.** Wallet passes are not signed with a development iOS app certificate. The API rejects all requests with HTTP `503` in demo/unconfigured mode; it does not provide a fake `.pkpass`, placeholder signature, or success-shaped fallback.

1. Register the app bundle identifier and `Sign in with Apple` capability in the Apple Developer portal.
2. Register the matching Wallet Pass Type ID; issue its Pass Type ID signing certificate and download Apple’s current WWDR intermediate certificate.
3. On an isolated, access-controlled **macOS signing host**, export the pass signing certificate and its matching private key as a password-protected PKCS#12 bundle. Protect and verify the WWDR certificate from Apple’s official certificate site.
4. Upload the certificate, WWDR certificate, and private key directly to a production secret manager or a permissions-restricted, non-public secret mount. Provide readable file paths to the backend through the production secret manager. **Never commit certificates, private keys, their password, provisioning profiles, production APNs keys, identity tokens, `.pkpass` files, or contents of `.env` files.** `.gitignore` and CI secret scanning exist as an additional safeguard, not a substitute for access control.
5. Set `LUMAPASS_ENV=production`, the matching `APPLE_APP_ID`, `APPLE_AUTH_AUDIENCE`, `PASS_TYPE_IDENTIFIER`, `APPLE_TEAM_IDENTIFIER`, verified `APPLE_WWDR_CERTIFICATE_PATH`, `PASS_CERTIFICATE_PATH`, `PASS_PRIVATE_KEY_PATH`, and an HTTPS `PUBLIC_BASE_URL`. If the private key is encrypted, supply its password through a runtime secret as `PASS_PRIVATE_KEY_PASSPHRASE`, never as a committed literal.
6. Provision TLS, access-controlled PostgreSQL, server-side-encrypted private S3 storage, a strong unique `ADMIN_BEARER_TOKEN`, least-privilege service accounts, backups, log retention, backups/deletion policy, network restrictions, and monitoring before exposing the service. Limit production origins to your approved HTTPS UI.
7. Test certificate/key matching, `passTypeIdentifier` / team ID, signed pass validation, current Apple signature chains, barcode scans, Wallet install and removal, push environment, pass updates, and final layouts against real test devices. Keep signing keys out of source control, app binaries, CI logs, and screenshots.

Apple controls certificate validity and Wallet’s acceptance of the complete signed package. Obtain current production signing and WWDR requirements from the Apple Developer portal before provisioning. When changing certificates, rotate via the server’s secrets manager and test pass updates on devices first.

### Official Wallet protocol endpoints

With `webServiceURL` set to `https://your-host/apple-wallet`, the Apple Wallet web service endpoints are:

```text
POST   /apple-wallet/v1/devices/{deviceLibraryIdentifier}/registrations/{passTypeIdentifier}/{serialNumber}
GET    /apple-wallet/v1/devices/{deviceLibraryIdentifier}/registrations/{passTypeIdentifier}?passesUpdatedSince={tag}
GET    /apple-wallet/v1/passes/{passTypeIdentifier}/{serialNumber}
DELETE /apple-wallet/v1/devices/{deviceLibraryIdentifier}/registrations/{passTypeIdentifier}/{serialNumber}
POST   /apple-wallet/v1/log
```

The service authenticates these requests using the per-pass `ApplePass` token, stores only a SHA-256 hash, stores registered Wallet push tokens privately, and pushes updates using APNs HTTP/2 with Apple’s pass topic. Set the APNs `.p8` signing key and correct sandbox/production environment using the secret manager; those routes are not advertised as live until they are configured.

## Safety, privacy, and production launch

- The app is not affiliated with or endorsed by Apple. Apple, Apple Wallet, Apple Pay and their related trademarks belong to their respective owners; their appearance in this README identifies Apple platform technology only. LumaPass does not use Apple logos, copied Wallet artwork or Apple Pay marks.
- Do not create or upload payment cards, bank cards, payment credentials, a false issuer identity, a duplicate of a third party’s pass, an impersonating brand, fraudulent event admission, copyrighted art without permission, illegal or explicitly sexual material, abusive content, or material that violates another person's rights.
- Never enter bank or payment credentials, private API secrets, or third-party personal data into a pass.
- Public creator images require a rights confirmation and an accepted CC0 1.0 or CC BY 4.0 license, strict byte/pixel/format checks, metadata removal, private storage, and human approval. Uploads are not published automatically.
- Private drafts, personal identity tokens, passwords, Payment credentials, and completed passes never belong in a community record. Server logs must not include request bodies, identity tokens, raw image data, pass authentication tokens, APNs secrets, or administrative credentials.
- Apple’s pass certificates and production signer are absent from source, the mobile application, Docker image, and repository. Restrict signing service network routes, filesystem mounts, secret access, rate limits, and privileges. Signer-key leakage is a production incident.
- Publish an accurate production privacy notice, copyright-takedown contact, terms, data controller identity, deletion timeframes, retention, subprocessors, legal basis, and user-rights process before inviting actual users. The in-app sample disclosures are engineering scaffolding and **not a substitute for a lawyer-reviewed, GDPR/consumer-law-compliant notice or moderation operation**.
- Public contributions require actual human moderation capacity, escalation and appeal routes, a copyright removal contact, creator blocks, abuse handling, and lawful content-removal records. The admin page is an operational starter, not a staffed trust-and-safety team.
- A pass can be installed, refreshed, removed or invalidated by its legitimate issuer; installed passes are not retroactively under LumaPass’s control once a Wallet owner stores them. Account deletion preserves a minimal revocation record when needed to notify Wallet devices that an issuer-owned pass has been revoked.

## API

OpenAPI is served at `/api/openapi.json`; interactive local documentation is available at `/api/docs` in demo mode. Production signing keys and admin access are required for restricted operations. There is no production data, public creator account, global search, CDN, malware scanner, image-detection model, or Apple merchant account bundled with the sample.

## Static analysis, dependencies, and CI

`.github/workflows/quality.yml` runs Swift/iOS simulator tests on macOS; Python tests, Ruff lint and formatting, Bandit static security analysis, dependency advisories with `pip-audit`, and Gitleaks; and weekly Dependabot updates for Python, Docker, and GitHub Actions. Keep GitHub Actions pinned and review dependency/lockfile changes before merging. A successful scan does not prove an Apple pass is acceptable or a public content workflow is legally compliant.

## Contributing

1. Fork the project, open an issue for significant API or design changes, and make a branch.
2. Never check in signing material, production data, real user images, Pass Type ID secrets or screenshots containing personal details.
3. Run the relevant Python test suite and Ruff checks; on macOS, regenerate XcodeGen and run the simulator tests.
4. Describe test results, API or data migration impact, accessibility behavior, user-visible changes, and any licensing or Apple Wallet change in your pull request.
5. Agree to contribute under Apache-2.0. Community user-uploaded artwork remains under the author's declared license and is not implied to be included in the source-code license.

## GitHub publication from Windows

Git for Windows is installed, and this folder has a cleanly initialized, **uncommitted** local Git repository on branch `main`. The GitHub CLI is not installed and no authenticated GitHub account is available in this environment. No public GitHub repository has been created; no collaborators or invitations were sent. Xcode, Swift, XcodeGen, and a Mac are still required to build and test the iOS app.

When ready, restart VS Code so the installed Git command is available, install the GitHub CLI, sign in to **your own GitHub account**, review the generated files and all `.env` files, then run:

```powershell
Set-Location "$HOME\Downloads\LumaPass"
git status --short
git add .
git diff --cached
git commit -m "Build LumaPass iOS and secure Wallet backend"
gh auth status
gh repo create LumaPass --public --source . --remote origin --push
```

Review the staged diff and the GitHub CLI account shown by `gh auth status` before creating the public repository. The GitHub CLI command publishes under the already signed-in account and does not invite collaborators. Run the iOS build and simulator test suite on a Mac before treating this iPhone-only application as release-ready.

## License

Application code is provided under the [Apache License, Version 2.0](./LICENSE). Original demo artwork is generated in this repository. The owner of each future community upload retains the rights described by that upload's declared license.

## Apple documentation consulted

- [Wallet Passes](https://developer.apple.com/documentation/walletpasses)
- [Creating a Poster Generic Pass](https://developer.apple.com/documentation/walletpasses/creating-a-poster-generic-pass)
- [Creating the Source for a Pass](https://developer.apple.com/documentation/walletpasses/creating-the-source-for-a-pass)
- [Distributing and updating a pass](https://developer.apple.com/documentation/walletpasses/distributing-and-updating-a-pass)
- [PKAddPassesViewController](https://developer.apple.com/documentation/passkit/pkaddpassesviewcontroller)
- [Sign in with Apple](https://developer.apple.com/documentation/signinwithapple)
