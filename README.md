# Moona

A bilingual (Arabic-RTL / English-LTR) shared shopping-list app. Flutter
front-end (Riverpod, go_router, Appwrite SDK); the backend is a single Appwrite
Dart Function (`moonaApi`) plus Appwrite TablesDB/Storage — see `backend/`.

- **Auth:** phone + password (OTP deferred). Unknown numbers auto-create an account.
- **Live backend (default):** endpoint `https://nyc.cloud.appwrite.io/v1`,
  project `6a20305f000a1a0251d2`. No configuration needed to run against it.

## Prerequisites

- Flutter **3.41+** / Dart **3.11+** (`flutter --version`).
- A Chromium/Chrome browser for the web target.

```bash
flutter pub get
```

## Running the app

> **Origin allow-list:** Appwrite only accepts web requests from registered
> origins — `localhost`, `127.0.0.1`, `dev.almou.sa`. The browser must see the
> app as one of these, or live auth/data calls are rejected. (Mobile uses the
> registered bundle id `sa.almou.moona`.)

### Option A — run on a remote/headless server, view over an SSH tunnel (recommended on this box)

On the server:

```bash
cd /mnt/unraid/moona
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080
```

From your laptop:

```bash
ssh -L 8080:127.0.0.1:8080 <you>@<server>
```

Open <http://localhost:8080>. The origin stays `localhost`, so live auth works.
Press `r` / `R` in the terminal for reload / restart.

### Option B — run on your own machine

```bash
flutter run -d chrome
```

`localhost` works directly. (If the server has a desktop session, this works
there too.)

### Option C — direct access by server IP/hostname

Using `--web-hostname 0.0.0.0` and opening `http://<server-ip>:8080` needs that
host added as a **Web platform** in the Appwrite console first, otherwise
requests are rejected.

### Backend modes

| Mode | Command |
| --- | --- |
| Live (default) | `flutter run -d chrome` |
| Offline demo (in-memory fake repo, mockup seed data) | `flutter run -d chrome --dart-define=APPWRITE_ENDPOINT= --dart-define=APPWRITE_PROJECT_ID=` |
| Custom backend | `flutter run --dart-define=APPWRITE_ENDPOINT=… --dart-define=APPWRITE_PROJECT_ID=…` |

## Creating a test user / signing in

There is no separate signup — **the first sign-in with a new phone number creates
the account** (then the app provisions the profile via `ensureProfile`).

1. On the login screen, enter a phone number and a password.
2. Tap **Sign in**.

Rules:

- **Phone** — any form that normalizes to 8–15 digits. Saudi local `0501112233`
  → `+966501112233`; or enter full international `+9665…`.
- **Password** — must be **≥ 8 characters** (Appwrite minimum); a shorter one
  fails account creation with a generic error.
- **Example:** phone `0501112233`, password `moona1234`.
- The first sign-in can take a few seconds (cold function start). Re-entering the
  same phone + password logs back in; a wrong password on an existing number
  shows "wrong password".

## Test checklist

- Log in → land on the shopping list.
- Add an item (＋); pick category/unit, mark important.
- **Scratch-to-delete:** tap an item → 10s countdown → moves to Trash; tap again
  within 10s to cancel.
- **Trash:** restore or clear items.
- **Settings:** toggle language (AR/EN — layout flips RTL/LTR) and theme; these
  persist across logout/login.
- **Confirm it's hitting the live backend:** DevTools → Network shows
  `createExecution` POSTs to `nyc.cloud.appwrite.io`.

### Testing sharing (needs two users)

Sign in as a second phone number in an **incognito window** (e.g. `0507654321` /
`moona1234`). From user A's **Settings → Sharing**, request to share with user
B's number; user B receives an accept/decline prompt, then sees A's list.

## Tests & checks

```bash
flutter analyze
flutter test
```

## Web release build

For a deployable web bundle, build the default JavaScript target:

```bash
flutter build web --release
python3 server.py 8080
```

Open <http://localhost:8080>. The helper serves `build/web` by default and adds
the headers Flutter's web engine expects. Do not serve the repository root as a
static site; that produces missing `flutter_bootstrap.js` / `main.dart.js`
requests and looks like a permanently loading app.

## Project layout

- `lib/` — Flutter app (`app/` state + controller, `data/` models + repositories,
  `features/` screens, `core/` config/theme/l10n).
- `backend/` — Appwrite Dart Function + provisioning (`backend/README.md`,
  `backend/DEPLOY_LOG.md`).
- `front_to_backend.md` / `back_to_frontend.md` — the frontend⇄backend API
  contract and coordination notes.
