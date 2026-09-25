# Windows setup — expenses tracker offline

Use a Windows PC to build and run this app on an Android emulator or Android
phone. The app saves everything on the phone and needs no Laravel, XAMPP,
MySQL, or API server. Internet is needed to download development tools and
dependencies; the installed app works offline.

Run the commands below in **PowerShell**. The project folder is the folder
containing `pubspec.yaml`.

## 1. Install the development tools

Install [Git for Windows](https://git-scm.com/downloads/win), the
[Flutter SDK](https://docs.flutter.dev/install/manual), and
[Android Studio](https://developer.android.com/studio).

This project's `pubspec.yaml` requires **Dart 3.13 or newer within Dart 3.x**.
Flutter includes Dart; you do not need a separate Dart installation. The current
project was built with Flutter 3.47.0 and Dart 3.13.0.

Extract Flutter into a writable folder, for example:

```text
C:\src\flutter
```

Add `C:\src\flutter\bin` to your Windows **user Path** using **Edit environment
variables for your account → Path → Edit → New**. If you chose another folder,
use that folder's `bin` path. Close and reopen PowerShell and your editor after
changing Path. See [Flutter's Windows PATH instructions](https://docs.flutter.dev/install/add-to-path).

Check the installation:

```powershell
git --version
flutter --version
```

## 2. Set up Android Studio

Open Android Studio and finish its setup wizard. In **SDK Manager**, install:

| Location | Components |
| --- | --- |
| SDK Platforms | Android API 36 |
| SDK Tools | Android SDK Build-Tools, Platform-Tools, Command-line Tools (latest), and Android Emulator |
| SDK Tools → Show Package Details | NDK (Side by side) `28.2.13676358` and CMake |

The app uses API 36 and NDK `28.2.13676358` with its verified Flutter toolchain.
If a dependency or a later Flutter version requests additional SDK/native tool
versions, install the versions named in the build output through SDK Manager.

Then run:

```powershell
flutter doctor --android-licenses
flutter doctor -v
```

Review and accept the Android licenses, then resolve errors under **Android
toolchain** and **Android Studio**. `flutter doctor` checks your setup and
explains what needs attention. Visual Studio's Windows-desktop tools are only
needed when building a Windows desktop target; this project targets mobile.
See the [official Android setup guide](https://docs.flutter.dev/platform-integration/android/setup).

## 3. Clone the app and download its packages

Replace `YOUR_GITHUB_REPOSITORY_URL` with the HTTPS URL from your repository's
**Code** button. This command names the local folder consistently:

```powershell
git clone "YOUR_GITHUB_REPOSITORY_URL" expenses_tracker_offline
cd expenses_tracker_offline
flutter pub get
```

If you already cloned it, open PowerShell in that folder and run:

```powershell
flutter pub get
```

`flutter pub get` downloads the packages listed in `pubspec.yaml`, using the
versions in `pubspec.lock`. Run it after cloning or changing dependencies.
Flutter creates the machine-specific Android configuration during its build
workflow. Use your Windows Flutter installation; do not copy another computer's
`android/local.properties`, `.dart_tool`, or `build` folders into the clone.

## 4. Run on an Android emulator

In Android Studio's **Device Manager**, create a phone, download a compatible
Android system image, and press its **Run** button. Wait for Android to finish
booting. See [Android device setup](https://docs.flutter.dev/platform-integration/android/setup#set-up-an-android-device).

From the project folder:

```powershell
flutter devices
flutter run -d emulator-5554
```

Use the emulator's actual device ID from `flutter devices` if it differs from
`emulator-5554`. The first build can take longer while Gradle downloads its
dependencies.

You can also launch an existing emulator from PowerShell:

```powershell
flutter emulators
flutter emulators --launch YOUR_EMULATOR_ID
```

Replace `YOUR_EMULATOR_ID` with an ID from `flutter emulators`. The emulator
configuration ID used to launch it is different from the running device ID
used by `flutter run -d`. The `Medium_Phone` emulator on the original Mac is
not automatically created on your PC.

During `flutter run`, press `r` to hot reload after editing code, or `q` to
end the development session. The [Flutter CLI reference](https://docs.flutter.dev/reference/flutter-cli)
describes the available commands.

## 5. Run on a physical Android phone

Enable **Developer options → USB debugging** on the phone, connect it with a
data-capable USB cable, and accept its authorization prompt. Some phones also
need a Windows [manufacturer USB driver](https://developer.android.com/studio/run/oem-usb).

```powershell
flutter devices
flutter run -d YOUR_PHONE_DEVICE_ID
```

Replace `YOUR_PHONE_DEVICE_ID` with the phone's ID from the first command.

## 6. Build an APK for standalone installation

From the project folder:

```powershell
flutter build apk --release
```

The finished APK is here:

```text
build\app\outputs\flutter-apk\app-release.apk
```

Copy the APK to an Android phone and open it to install. Allow installation
from that file-manager or browser app if Android requests it. Once installed,
the tracker works without the PC. See [Flutter's Android build guide](https://docs.flutter.dev/deployment/android).

This project's release configuration currently uses a debug signing key for
private testing. Another PC normally has a different debug key, so an APK it
builds might not update an existing installation. Use the same signing key for
updates, and keep an exported backup before replacing an installation.
Configure your own release signing key before store distribution.

## Common setup issues

| Message or problem | What to do |
| --- | --- |
| `flutter` is not recognized | Add the Flutter SDK's `bin` folder to user Path, then reopen PowerShell. |
| Dart SDK version is too old | Install a Flutter SDK that includes Dart 3.13 or newer compatible Dart 3.x; check `flutter --version`. |
| `cmdline-tools component is missing` | Install Android SDK Command-line Tools (latest) in Android Studio's SDK Manager. |
| Android licenses are missing | Run `flutter doctor --android-licenses` after installing Command-line Tools. |
| No Android device appears | Start an emulator, or check the phone's USB debugging authorization, cable, and USB driver. |
| Emulator cannot start | Check [Windows emulator acceleration and virtualization](https://developer.android.com/studio/run/emulator-acceleration). |
| A path starts with `/Users/` or points to another computer | Use a fresh Git clone. Generated files from the original Mac are not portable; `android/local.properties`, `.dart_tool`, and `build` are excluded from Git. |
| `WARNING: A restricted method in java.lang.System has been called` | This warning alone does not mean the build failed. It also appeared during this project's successful builds. Wait for the final result. |
| `BUILD FAILED` | Read the `What went wrong:` section near the end. Use `flutter run -v` for additional details. |

For more setup diagnostics, see [Flutter installation troubleshooting](https://docs.flutter.dev/install/troubleshoot).

## Data, backups, and verification

Cloning the code creates a fresh local app; your financial records are not part
of GitHub. To move records, export a backup from **Settings → Your data &
backups** on the old device and restore it on the new one. See the main
[data and backup instructions](README.md#data-and-backups).

To check the source code from PowerShell:

```powershell
flutter analyze
flutter test
```

For iPhone development, use the [macOS/iOS instructions](README.md#run-on-the-ios-simulator)
on a Mac with Xcode.

For data from the earlier app name, follow [the migration steps](README.md#moving-from-the-earlier-app-name) before removing the earlier app.
