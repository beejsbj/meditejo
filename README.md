# About Medito

## About

Meditation can positively transform people's lives, and we believe no one should have to pay for it. We are the [Medito Foundation](https://meditofoundation.org), and we've built the Medito App for people who have never meditated before or want to deepen their meditation practice.

The app is free, forever: no ads, no spam, no need to sign up or pay. Medito App is a Flutter project available on Android and iOS maintained by the Medito Foundation and its community.

## Download

- Play Store: [Download on Google Play](https://play.google.com/store/apps/details?id=meditofoundation.medito)
- App Store: [Download on the App Store](https://apps.apple.com/us/app/medito/id1500780518)
- APK:

**NOTE:** If you install the Medito app using the APK file, please make sure to verify that the APK file is signed by Medito Foundation. See [VERIFY_APK](docs/VERIFY_APK.md) for more information.

### Local development

This checkout uses local state and has no account or app-service credentials to configure. The catalogue is currently empty; the timer works offline. Source integration is tracked in [the fork brief](docs/fork/BRIEF.md).

1. Install the Flutter version pinned in `.github/workflows/ci-develop.yml`, then install dependencies:
   ```sh
   flutter pub get
   ```
2. Generate native bridges and Riverpod/model code:
   ```sh
   for f in pigeon_conf.dart pigeons/*.dart; do [ -f "$f" ] || continue; flutter pub run pigeon --input "$f" --package_name=medito || exit 1; done
   dart run build_runner build --delete-conflicting-outputs
   ```
3. For Android, copy the signing template and enter your own keystore details:
   ```sh
   cp android/keystore.properties.example android/keystore.properties
   ```
   The default Android debug keystore is `~/.android/debug.keystore`: store/key password `android`, alias `androiddebugkey`. Set `storeFile` to its absolute path and retain the application ID from the template.
4. Run locally:
   ```sh
   # Android
   flutter run --flavor dev -d <android-device-id>
   # iOS
   flutter run -d <ios-device-id>
   ```

### Editor configurations

For VS Code, use the following `.vscode/launch.json` (ignored by git, so each developer keeps their own):

```json
{
  "version": "0.2.0",
  "configurations": [
    { "name": "Flutter (Dev)", "request": "launch", "type": "dart", "args": ["--flavor", "dev"] },
    { "name": "Flutter (Prod)", "request": "launch", "type": "dart", "args": ["--flavor", "prod"] },
    { "name": "Flutter (iOS)", "request": "launch", "type": "dart" }
  ]
}
```

In Android Studio, create a Flutter run configuration with `--flavor dev` or `--flavor prod` as its additional arguments for Android. Use the default Flutter configuration for iOS.

### Smoke checks

The Maestro flows cover local navigation, stats access, and timer playback. They require an installed app and Maestro, with the existing application ID passed as `APP_ID`:

```sh
.maestro/run_flow.sh /tmp/maestro-debug -e APP_ID=meditofoundation.medito .maestro/smoke.yaml
```

Use `org.meditofoundation` for the current iOS bundle. Upgrade jobs keep the previous release's seed flow and skip until a previous release includes the local timer flow. Store signing and upload credentials are still required for release workflows.

## Android Setup

For Android APK signing, you need to create a `keystore.properties` file in the `android/` directory:

1. Copy `android/keystore.properties.example` to `android/keystore.properties`
2. Fill in your actual keystore information
3. Generate or obtain a keystore file (`.jks`) for signing APKs

**Note:** Never commit `keystore.properties` or your `.jks` files to version control.

## License

- App: [GNU AFFERO GENERAL PUBLIC LICENSE](https://github.com/meditohq/medito-app/blob/master/LICENSE).
- The content available within the Medito app is subject to a custom license. For more information, please refer to [meditofoundation.org/license](https://meditofoundation.org/license).
- Sometimes we aggregate content from other sources that do not have the same license. This content is generally not published under "Medito." Make sure to respect the original copyright.

Medito Foundation: https://meditofoundation.org/.
