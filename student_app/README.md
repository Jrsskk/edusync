# EduSync Student

Flutter client for the EduSync student API. Configure `API_BASE_URL` in `.env`
to point to the Laravel `/api/v1` endpoint before running the app.

## Learning materials

Materials stay grouped by Subject. **Open** fetches the file from the Laravel
API and opens it with an installed Android app using the API-provided MIME type;
in a browser, supported files open in a new tab. **Download** saves a local
device copy on Android or downloads through the browser. PDF, image, video,
PowerPoint, and Word files use compatible apps or viewers available on the
device.

## Offline quizzes and synchronization

Download a quiz while connected. The app saves its questions and required images
locally and then offers **Take Quiz Offline**; quiz answers and completed
attempts are saved on the device even without a connection. A completed local
attempt appears in Grades and is removed from Available Quizzes immediately.

The sync icon in the app bar opens **Data Synchronization**, with local Pending,
Syncing, Synced, and Failed counts, the last successful sync time, and retry
controls. The app attempts synchronization when connectivity returns and when
the app resumes. A quiz attempt is marked Synced only after the authenticated
Laravel `/api/v1/sync` endpoint confirms the same `sync_uuid` as `synced`.
Attempts remain in local storage after upload; replaying a UUID is idempotent
on the server.

## Development and API configuration

The mobile API base URL is the Laravel `/api/v1` prefix. Android debug builds
read `API_BASE_URL` from `.env` or accept it as a build-time define; a build-time
define takes precedence. The `/login` request is `POST /api/v1/login` with
`email`, `password`, and optional `device_name`.

Start Laravel so it accepts connections from a phone on the same private Wi-Fi:

```powershell
php artisan serve --host=0.0.0.0 --port=8000
php artisan route:list --path=api
```

For an Android emulator, use `http://10.0.2.2:8000/api/v1`. For a physical
Android device, find the development PC's current LAN IPv4 address with
`ipconfig`, then set `API_BASE_URL` to
`http://<PC-LAN-IP>:8000/api/v1` (for example,
`http://192.168.1.15:8000/api/v1`). Ensure the phone and PC are on the same
Wi-Fi and allow inbound TCP port 8000 through the PC's private-network
firewall. Android debug builds allow cleartext HTTP for local testing; release
builds do not.

Confirm the phone can reach the server by opening
`http://<PC-LAN-IP>:8000/up` in its browser. Rebuild/restart the debug app after
changing `.env` because the file is bundled into the app. For example:

```powershell
Set-Location student_app
flutter run --dart-define=API_BASE_URL=http://192.168.1.15:8000/api/v1
```

Replace the sample LAN IP with the PC's current address. `API_BASE_URL_WEB` is
separate and remains the local browser URL.

Release APKs require the real deployed HTTPS backend URL, supplied at build
time; the app intentionally has no assumed production host and does not fall
back to `.env` in release mode:

```powershell
Set-Location student_app
flutter clean
flutter pub get
flutter build apk --release --dart-define=API_BASE_URL=https://<your-deployed-host>/api/v1
```

Replace the placeholder with the deployed backend URL before building. Do not
use `localhost`, `127.0.0.1`, `10.0.2.2`, or a PC LAN IP in a production APK.
The release network policy permits HTTPS only. The APK is written to
`build/app/outputs/flutter-apk/app-release.apk`.
