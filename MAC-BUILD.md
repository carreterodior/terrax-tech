# Building for iPhone on the Mac

With a Mac you can put TERRAX TECH on an iPhone **today, without the $99 account**
(7-day installs), and later upload to TestFlight directly — no Codemagic needed.

## One-time Mac setup (~1 h, mostly Xcode downloading)

1. **Xcode** — install from the Mac App Store (large download). Open it once,
   accept the license, and let it install the **iOS platform** when asked.
   Then in Terminal:

   ```bash
   sudo xcode-select -s /Applications/Xcode.app
   sudo xcodebuild -runFirstLaunch
   ```

2. **Flutter** (stable):

   ```bash
   # Apple Silicon:
   curl -o ~/flutter.zip https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64-stable.zip
   unzip ~/flutter.zip -d ~/dev && rm ~/flutter.zip
   echo 'export PATH="$HOME/dev/flutter/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
   ```

3. **CocoaPods**:

   ```bash
   brew install cocoapods   # or: sudo gem install cocoapods
   ```

4. **Get the code.** Best: push this repo to GitHub from the Windows PC
   (see IOS-RELEASE.md step 2), then on the Mac:

   ```bash
   git clone https://github.com/<your-username>/terrax-tech.git
   cd terrax-tech
   flutter pub get
   flutter doctor        # everything except Android can be ignored here
   ```

   (No GitHub yet? Zip `Documents/TERRAX/terrax_app` — minus `build/` — and
   AirDrop/USB it over. But git is what keeps the Mac and PC in sync.)

## Install on the iPhone (free Apple ID, 7-day signing)

1. Plug the iPhone into the Mac with a cable → tap **Trust** on the phone.
2. Open the iOS project once to set signing:

   ```bash
   open ios/Runner.xcworkspace
   ```

   In Xcode: **Runner** target → **Signing & Capabilities** →
   *Automatically manage signing* on → **Team**: Add Account… → sign in with
   your Apple ID → pick the "(Personal Team)" entry. Xcode creates the free
   provisioning profile by itself.
3. First install only: the phone will ask for **Developer Mode**
   (Settings → Privacy & Security → Developer Mode → on, restarts the phone)
   and to trust the developer certificate
   (Settings → General → VPN & Device Management → your Apple ID → Trust).
4. Build and install:

   ```bash
   flutter devices                 # confirm the iPhone shows up
   flutter run --release -d <device-id>
   ```

   `--release` matters: a debug build stops working the moment the cable is
   unplugged; a release build runs standalone.

**Free-account limits:** the install expires after **7 days** (rerun step 4 to
renew), max 3 apps, no TestFlight. Fine for testing the BLE drivers on real
hardware; the paid account removes all of it.

## With the paid Developer account: TestFlight from the Mac

1. In Xcode Signing & Capabilities, switch **Team** to the paid team.
2. Create the app record in App Store Connect (IOS-RELEASE.md step 5).
3. Then either:

   ```bash
   flutter build ipa --release
   ```

   and upload `build/ios/ipa/*.ipa` with Xcode's **Transporter** app, or in
   Xcode: **Product → Archive → Distribute App → TestFlight & App Store**.
4. The build appears in App Store Connect → TestFlight (see IOS-RELEASE.md
   steps 7–8 for testers and the later public release).

## Day-to-day loop

Code changes happen on the Windows PC → commit + push → on the Mac:
`git pull && flutter run --release -d <iphone>`. Errors from the Mac build?
Paste them into the Claude session on the PC — or install Claude Code on the
Mac (`https://claude.com/claude-code`), open this repo there, and let it drive
the build directly.
