# Getting TERRAX TECH onto your iPhone (TestFlight → App Store)

The repo lives on Windows and **iOS binaries can only be built on a Mac**, so the
pipeline is: this repo → GitHub → **Codemagic** (cloud Mac, free tier is plenty) →
**TestFlight** on your iPhone. The App Store proper comes after TestFlight testing.

Everything in the repo is already prepared:

- Bundle ID `com.terrax.terrax`, display name **TERRAX TECH**, deployment target iOS 13
- Both Bluetooth usage descriptions (App Review rejects without them)
- App icons with alpha removed (App Store requirement)
- `ITSAppUsesNonExemptEncryption = false` (skips the export-compliance question per build)
- `codemagic.yaml` — builds, signs, tests, uploads to TestFlight automatically

## Step 1 — Apple Developer Program (you; ~$99/yr; 24–48 h approval)

1. Go to <https://developer.apple.com/programs/enroll> and sign in with the Apple ID
   you use on the iPhone (or a dedicated TERRAX one).
2. Enroll as **Individual** (fastest) or **Organization** (shows "TERRAX" as the seller
   on the store, but needs a D-U-N-S number — takes longer). Individual is fine for
   TestFlight; you can migrate later.
3. Pay the fee and wait for the approval email.

## Step 2 — Put the repo on GitHub (you, ~5 min)

The local git repo is already initialized and committed. Create an empty **private**
repository on <https://github.com/new> (e.g. `terrax-tech`), then from
`Documents/TERRAX/terrax_app` run:

```bash
git remote add origin https://github.com/<your-username>/terrax-tech.git
git push -u origin master
```

## Step 3 — App Store Connect API key (you, ~5 min, after Step 1 approval)

1. <https://appstoreconnect.apple.com> → **Users and Access** → **Integrations** →
   **App Store Connect API** → Team Keys → **+**.
2. Name: `codemagic`, Access: **App Manager**.
3. Download the `.p8` file — **it can only be downloaded once**, keep it safe.
4. Note the **Issuer ID** (top of the page) and the key's **Key ID**.

## Step 4 — Codemagic (you, ~10 min)

1. Sign up at <https://codemagic.io> **with your GitHub account**, add the
   `terrax-tech` repository.
2. **Teams → Personal Account → Integrations → Developer Portal → Manage keys**:
   add the API key from Step 3 — Issuer ID, Key ID, upload the `.p8`.
   **Name it exactly `terrax-asc-key`** (that name is referenced in `codemagic.yaml`).
3. Open the app in Codemagic — it detects `codemagic.yaml` → workflow
   **"iOS → TestFlight"**.

## Step 5 — Create the app record (you, ~5 min)

1. <https://developer.apple.com/account> → **Identifiers** → **+** → App ID →
   Bundle ID **explicit**: `com.terrax.terrax`. (Codemagic can also auto-create this
   on the first build; doing it manually avoids surprises.)
2. App Store Connect → **My Apps** → **+** → New App: platform iOS, name
   **TERRAX TECH** (if taken, e.g. "TERRAX TECH BLE"), language, bundle ID from
   above, any SKU (e.g. `terrax-tech-001`).

## Step 6 — Build (either of us)

Press **Start new build** in Codemagic (workflow `ios-testflight`). It runs
`flutter analyze` + all tests, builds a signed IPA, and uploads it to TestFlight
(~15–25 min). When it fails, copy the log here and we fix it — that's the normal
loop for a first iOS build.

## Step 7 — Install on your iPhone (you)

1. App Store Connect → your app → **TestFlight** tab: the build appears after a
   few minutes of processing.
2. **Internal Testing** → create a group, add yourself (your Apple ID email).
3. On the iPhone: install **TestFlight** from the App Store, open the invite
   email, install TERRAX TECH. Updates arrive automatically on every new build.

## Step 8 — Later: the public App Store

TestFlight needs none of this; the public listing does:

- Screenshots (6.7" and 6.5" iPhone at minimum) — we can generate these
- Description, keywords, support URL
- **Privacy policy URL** — trivial for this app (no accounts, no backend, no data
  collection; everything stays on the phone). We can generate the page and host it
  on the TOS site.
- App Review notes: mention it controls TERRAX-installed BLE car accessories and
  that reviewers without the hardware will only see the scan screen.

Then App Store Connect → version → **Submit for Review**.

## Fee summary

- Apple Developer Program: **$99/year** (the only mandatory cost)
- Codemagic: free tier (500 Mac minutes/month ≈ 20–30 builds)
- GitHub private repo: free
