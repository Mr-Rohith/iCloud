# iCloud Notes Wrapper (Android) — with Widget

This repo is set up so you can get an APK **without coding** by using GitHub Actions.

## How the CI works
- The workflow will:
  1) Install Flutter
  2) Run `flutter create .` to scaffold the project
  3) Copy everything from `overlay/` over the scaffold
  4) Build a **debug APK**
  5) Upload it as an artifact you can download

## Steps
1. Create a new **GitHub repository** and upload everything in this zip.
2. Go to the **Actions** tab on GitHub. It will start **Build Android APK** automatically (or click "Run workflow").
3. Wait for it to finish, then open the latest run → **Artifacts** → download `app-debug.apk`.
4. Install that APK on your Android phone (enable "Install unknown apps" if prompted).

## Optional: Release signing
If you want a signed **release** APK/AAB later:
- Create a keystore:
  ```bash
  keytool -genkey -v -keystore notes-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias noteskey
  ```
- Add GitHub **Secrets**: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.
- Update the workflow to decode and use the keystore and build `--release`.
