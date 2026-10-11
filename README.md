# EduSync

**EduSync** is a web-based educational management system with interactive quizzes, assignment management, and offline synchronization for students. Built with Laravel 12, PHP 8.2+, MySQL 8, Blade, Tailwind CSS, Alpine.js, and Chart.js.

## Features

- Role-based access control (Administrator, Teacher, Student)
- Admin dashboard with analytics and user management
- Teacher quiz builder with multiple question types and automatic grading
- Assignment management with manual grading
- Student mobile-first PWA interface with bottom navigation
- Offline quiz/assignment support via IndexedDB and service workers
- UUID-based idempotent synchronization
- Database notifications, audit logs, and reports

### Student offline mode

The student portal registers a same-origin Service Worker and uses the Cache API
for previously opened student pages and learning-material files. IndexedDB stores
enrolled classes and subjects, assignment and material catalogs, explicitly
downloaded quizzes and assignments, assignment drafts/files, quiz answers, and
the submission sync queue. The browser retries queued submissions when it comes
back online; students can also retry them from **Sync**.

Offline content is limited to data already saved on that device. Students must
open the pages they need while online, select **Download Offline** for each quiz,
and open or download learning materials before disconnecting. An assignment can
be drafted and submitted offline after its page has been opened or downloaded.
Pages and files never visited or downloaded cannot be made available offline by
the Service Worker. Browser storage can also be cleared or evicted, so offline
work should be synchronized as soon as connectivity returns.

Service Workers require HTTPS in production (localhost is supported for local
development). Synchronization uses the signed-in student's Laravel session and
the existing API authorization and validation.

## Requirements

- PHP 8.2+
- Composer
- MySQL 8+
- Node.js 18+

## Installation

```bash
composer install
cp .env.example .env
php artisan key:generate
```

Configure MySQL in `.env`:

```env
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=edusync
DB_USERNAME=root
DB_PASSWORD=
```

Then run:

```bash
php artisan migrate --seed
php artisan storage:link
npm install
npm run build
php artisan serve
php artisan reverb:start
```

### Supabase Storage file uploads

New learning materials, assignment attachments, student assignment submissions,
and teacher profile photos are stored in private Supabase Storage buckets. EduSync
uses the existing relational records and file paths; no duplicate file tables are
created. Authenticated Laravel routes proxy downloads and retain the existing
class/teacher/student access checks. The Supabase service-role key is only used by
Laravel and must never be added to a `VITE_` variable or frontend code.

```env
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_KEY=your-project-anon-or-publishable-key
SUPABASE_SERVICE_ROLE_KEY=your-server-only-service-role-secret
```

To connect a Supabase project:

1. Create or select a Supabase project and copy its project URL, anon/publishable
   key, and service-role secret from **Project Settings → API**.
2. Put those values in the Laravel `.env` file shown above. Keep the service-role
   secret server-side and do not commit `.env`.
3. Run `php artisan migrate` to add nullable storage-disk metadata to existing
   material, assignment, submission, and user records. Existing records and their
   relationships are preserved.
4. Run `php artisan config:clear` and `php artisan supabase:storage-setup`. This
   creates the private `materials`, `assignments`, and `profiles` buckets and
   makes existing buckets private; the command is safe to rerun.

The app also ensures the corresponding private bucket exists before uploads. Files
are stored in `materials` (learning materials), `assignments` (assignment
attachments and student submissions), and `profiles` (profile images). Uploads,
replacements, and deletes update existing database records and clean up old/new
objects on failures. Existing Google Drive and Laravel-disk files remain readable;
new uploads use Supabase Storage.

### Firebase Cloud Messaging

Push notifications use Firebase Cloud Messaging HTTP v1 and Laravel's existing
database notifications. The Firebase service-account credential is server-only;
prefer an absolute path to a protected JSON file outside the public directory.
Alternatively, provide the service-account JSON directly through a secret manager
environment variable. Never use a `VITE_` prefix for service-account values.

```env
FIREBASE_PROJECT_ID=your-firebase-project-id
FIREBASE_CREDENTIALS=/secure/path/firebase-service-account.json
# Or set FIREBASE_CREDENTIALS_JSON to the service-account JSON secret.

FIREBASE_WEB_API_KEY=your-web-app-api-key
FIREBASE_WEB_AUTH_DOMAIN=your-project.firebaseapp.com
FIREBASE_WEB_PROJECT_ID=your-firebase-project-id
FIREBASE_WEB_MESSAGING_SENDER_ID=your-messaging-sender-id
FIREBASE_WEB_APP_ID=your-web-app-id
FIREBASE_WEB_VAPID_KEY=your-web-push-certificate-public-key
```

Create a Firebase web app, enable Cloud Messaging, and generate a Web Push
certificate key pair in Firebase Console → Project Settings → Cloud Messaging.
The web app values and VAPID public key are used by the student browser; only the
service-account credential is privileged. Serve the app over HTTPS (localhost is
allowed for development), then run `php artisan migrate`, `php artisan
config:clear`, and `npm run build`. Students can enable or disable browser push
from the notification bell. The existing Sanctum student API also accepts
authenticated `POST` and `DELETE /api/v1/device-tokens` requests for `web`,
`android`, or `ios` tokens.

Announcements, published assignments and quizzes, changes to published
assignments/quizzes and learning materials, deadlines, grades, and synchronization
updates are persisted in the student's database notification inbox and sent to
registered devices. Class-specific content is sent only to active students
enrolled in that active class when its subject matches the content subject.
Expired Firebase registrations are automatically removed. To verify a live push,
configure Firebase, sign in as a student on an HTTPS browser, enable push, and
have a teacher publish or update content for that student's class.

### Legacy Google Drive files

Existing learning materials stored in Google Drive continue to be served through
the existing protected routes. Configure the Google Drive environment variables
only if you still need to access or migrate those files. New material uploads no
longer require Google Drive configuration.

Visit [http://127.0.0.1:8000](http://127.0.0.1:8000)

### Deploying to Vercel

This repository includes a Vercel configuration for the full Laravel app. It
builds the Vite assets into `public/build`, serves them as static files, and
sends application requests to Laravel through the community `vercel-php`
runtime. It does not use Vercel's default Vite `dist` output directory.

In Vercel, set the Framework Preset to **Other** and leave Output Directory
empty so `vercel.json` controls the build. Add production environment variables
in Project Settings, including a generated `APP_KEY`, `APP_URL`, and credentials
for a persistent external database. Do not use the default local SQLite database
or file-backed sessions, cache, queues, and uploads in production; Vercel
functions have ephemeral, read-only application filesystems. Configure suitable
production drivers and persistent storage before serving real users.

## Development Login Credentials

> **Development only — change in production**

| Role        | Email                 | Password |
|-------------|-----------------------|----------|
| Admin       | admin@edusync.test    | password |
| Teacher     | teacher@edusync.test  | password |
| Student     | student@edusync.test  | password |

## API (Offline Sync)

Authenticate via Sanctum:

```http
POST /api/v1/login
```

Endpoints:

- `POST /api/v1/register` (Student registration; sends a signed email verification link)
- `POST /api/v1/email/verification-notification` (resend the Student verification email)
- `GET /api/v1/email/verify/{id}/{hash}` (signed email verification link)
- `POST /api/v1/login`, `GET /api/v1/me`, and `POST /api/v1/logout`
- `GET /api/v1/classes`
- `GET /api/v1/quizzes` and `GET /api/v1/quizzes/{id}/download` (quiz questions/options)
- `GET /api/v1/assignments` and `GET /api/v1/assignments/{id}/download` (assignment instructions and attachment URL)
- `GET /api/v1/assignments/{id}/attachment` (authenticated assignment attachment download)
- `GET /api/v1/materials/{id}/download` and `GET /api/v1/materials/{id}/file` (material metadata and authenticated file download)
- `POST /api/v1/submissions/quiz` and `POST /api/v1/submissions/assignment` (validated submissions; assignment files use multipart field `file`)
- `GET /api/v1/sync` (pull updated student activities, announcements, materials, and grades; accepts an optional `since` timestamp)
- `GET /api/v1/sync/status` (per-student pending, syncing, synced, and failed counts with last successful sync time)
- `POST /api/v1/sync` (submit one UUID-idempotent activity; accepts `quiz_attempt` or `assignment_submission`)
- `POST /api/v1/sync/batch` (retry pending/failed server-side queue entries)
- `GET /api/v1/grades`
- `GET /api/v1/announcements`

All API routes except login require a Sanctum student token. Offline clients should
generate and retain a UUID in `sync_uuid` for each submission across retries.
The server validates the activity against the authenticated student's class
access and persists sync attempts in `sync_queue`; replaying the same UUID does
not create a second quiz attempt or assignment submission.

## Testing

```bash
php artisan test
```

## PWA

Students can install EduSync on their home screen. The service worker caches assets and IndexedDB stores offline quiz data and sync queue entries.

## Flutter Student Android app

The standalone Student client lives in `student_app/`; the existing Laravel
Admin, Teacher, and web Student modules continue to use the same backend and
database. Android debug builds use `API_BASE_URL` in `student_app/.env` or the
`--dart-define=API_BASE_URL=...` build-time option. Use
`http://10.0.2.2:8000/api/v1` for the Android emulator, or
`http://<PC-LAN-IP>:8000/api/v1` for a physical Android device on the same
Wi-Fi; run Laravel with `php artisan serve --host=0.0.0.0 --port=8000` and allow
port 8000 through the private-network firewall. Android release builds require
an explicitly supplied deployed HTTPS URL and do not use `.env` as a fallback.
No production host is assumed. Chrome running on the development PC uses
`API_BASE_URL_WEB`. Email verification links require the Laravel mail transport
and `APP_URL` to be configured for the deployed backend.

```powershell
Set-Location student_app
Copy-Item .env.example .env
flutter pub get
flutter run -d chrome
flutter run -d <android-device-id> --dart-define=API_BASE_URL=http://<PC-LAN-IP>:8000/api/v1
flutter clean
flutter pub get
flutter build apk --release --dart-define=API_BASE_URL=https://<your-deployed-host>/api/v1
```

Run one of the `flutter run` commands for the target you are testing. Start the
Laravel server separately and confirm `http://127.0.0.1:8000/up` responds before
signing in from Chrome.

The release APK is written to `student_app/build/app/outputs/flutter-apk/app-release.apk`.
The generated Android release configuration uses a development signing key;
configure a private release keystore before distributing the app through a store.
The Flutter app caches API data and downloaded learning resources in SQLite/app
storage, saves quiz and assignment drafts locally, and retries UUID-idempotent
submission queue entries when connectivity returns.

## License

MIT
