# expenses tracker offline

A standalone Android and iOS version of Budget Flow. It keeps the personal
tracking screens and stores the entire ledger on your phone. It does not use
Laravel, PHP, MySQL, an API, an account, or an internet connection.

## Included

- Income and expenses with categories and transaction history
- Cash, bank, e-wallet, savings, and credit-card accounts
- Transfers, service charges, card payments, and debt tracking
- Monthly savings interest calculated locally when the app opens or refreshes
- Installment plans, down payments, and recorded monthly payments
- Weekly, monthly, yearly, and cutoff reports
- Cutoff schedules and historical budget snapshots
- Gold and jewelry inventory, your saved per-karat prices, and conversion to cash
- Light, dark, and system themes, currency and week preferences
- Settings to hide jewelry and credit-card summaries in Overview and Reports
- Backup export and restore in Settings

Joint accounts, shared expenses, deals, penalties, and server synchronization
are excluded. Gold prices are entered by you; this app does not download live
market quotes. Automatic interest runs when the app is opened/refreshed, with
catch-up for missed months, rather than while the app is closed.

## Windows setup

See [Windows setup instructions](README-WINDOWS.md) for installing Flutter and
Android Studio, cloning from GitHub, running on an emulator or phone, building
an APK, and troubleshooting common messages.

Once Flutter and the Android tools are installed, open PowerShell in the
cloned project folder and run:

```powershell
flutter doctor
flutter pub get
flutter devices
flutter run -d YOUR_ANDROID_DEVICE_ID
```

Replace `YOUR_ANDROID_DEVICE_ID` with the Android ID listed by `flutter devices`.
Windows is the development computer; the app runs on Android. Use these Flutter
commands in PowerShell; `run-mobile.sh` is a Bash helper for macOS/Linux.

## Run on the Android emulator

From this folder on the current Mac:

```bash
export PATH="$(cd ../budget_tracker/.tooling/flutter/bin && pwd):$PATH"
flutter pub get
flutter emulators --launch Medium_Phone
flutter devices
flutter run -d emulator-5554
```

Replace `emulator-5554` with the device ID shown by `flutter devices`.
No backend startup, API address, or XAMPP is needed.

Once the emulator is running, the included helper finds Flutter automatically:

```bash
./run-mobile.sh -d emulator-5554
```

On this Mac, the helper uses the Flutter SDK in the neighboring
`budget_tracker/.tooling/flutter` folder when Flutter is not on `PATH`.
This is only the development toolchain; the installed app is standalone.

On another computer, install Flutter with Dart 3.13 or later and the Android
toolchain, then run `flutter pub get` and `flutter run` from this folder.

## Run on the iOS Simulator

On a Mac with Xcode and an iOS simulator runtime:

```bash
open -a Simulator
flutter devices
flutter run -d <simulator-id>
```

An actual iPhone needs your own Apple development signing team. The app has a
separate bundle identifier (`com.expensestracker.offline`) so it can coexist
with the original app.

## Build an Android APK

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.
The inherited debug signing key is used for private installation. Configure
your own release signing key before distributing through an app store.
The release app has no internet permission; debug builds retain Flutter's
debugger permission.

## Data and backups

The first launch creates an empty ledger with a Cash account and starter
categories. Existing server data is not imported automatically. Monetary values
use integer minor units. Changes are serialized and saved by atomic file
replacement; failed operations roll back together. A previous file is retained
locally for recovery.

In **Settings → Your data & backups → Export backup**, copy the JSON to a file
you keep somewhere safe. On the destination phone, paste it into **Restore backup**, then confirm.
Restoring replaces that app's current ledger. The backup includes your financial
records and preferences for currency and reporting; theme stays device-specific.

In **Settings → Report visibility**, turn off **Show jewelry** or **Show credit
cards**, then tap **Save preferences** to hide those summaries in Overview and
Reports. These preferences are saved on your phone and included in backups.
Recorded income and expenses still count in cashflow totals.

Keep a backup before uninstalling or clearing app storage, because doing either
removes the local ledger. There is no server copy or cloud synchronization. Data
and backups are JSON, protected by the phone's app sandbox rather than separate
application encryption.

### Moving from the earlier app name

The corrected app uses `com.expensestracker.offline` on Android and iOS.
Because its identifier changed, it installs as a separate app. Keep the earlier
app installed, export its ledger with **Settings → Export backup**, and restore that
JSON in the renamed app. Check your balances before removing the earlier app.
Older backups are accepted; new exports use the corrected format name.

## Verify

```bash
flutter analyze
flutter test
```

Only the Android and iOS targets are included. The original Budget Flow project
is separate and is not required by this app at runtime.
