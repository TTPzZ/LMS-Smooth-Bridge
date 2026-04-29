# LMS Smooth Bridge

Backend + mobile app for consuming LMS GraphQL data with a smoother UX:
- backend proxy/transformation layer (`Node.js + TypeScript + Express + MongoDB`)
- mobile client (`Flutter`)

This project is for internal LMS accounts (users must have valid LMS/Firebase credentials).

## Repository Layout

```text
LMS-Smooth-Bridge/
|- backend/
|  |- src/
|  |- .env.example
|  |- package.json
|- mobile/
|  |- lib/
|  |- pubspec.yaml
|- README.md
```

## Current Behavior

1. User logs in from mobile (Firebase REST `verifyPassword`).
2. Mobile stores session locally and sends `Authorization: Bearer <id_token>` to backend.
3. Backend calls LMS GraphQL with that token, filters/reshapes payload, and returns smaller JSON.
4. Optional background notifier can run on backend for reminder pushes.

## Backend Setup

### Requirements

- Node.js `20.x`
- MongoDB (Atlas or self-hosted)

### Install

```bash
cd backend
npm install
```

### Environment

Create `backend/.env` from `backend/.env.example`.

Minimal required for normal API usage:
- `MONGO_URI`
- `MONGO_DB_NAME`

For server-managed auth flows (refresh/login on backend):
- `FIREBASE_API_KEY`
- `LMS_REFRESH_TOKEN` (recommended) or `LMS_EMAIL` + `LMS_PASSWORD`

Security and limits:
- `ADMIN_API_SECRET`
- `CORS_ORIGINS`
- `RATE_LIMIT_WINDOW_SECONDS`
- `RATE_LIMIT_MAX_REQUESTS`
- `MAX_ITEMS_PER_PAGE`
- `MAX_MAX_PAGES`
- `MAX_LOOKAHEAD_MINUTES`
- `MAX_REMINDER_SLOTS`

Push notifier (optional):
- `ENABLE_PUSH_NOTIFIER=true`
- `FCM_SERVER_KEY`
- `CRON_SECRET` (or use `x-admin-secret` with `ADMIN_API_SECRET`)

### Run

```bash
npm run dev
```

Startup logs include auth mode, CORS mode, admin protection status, and push notifier status.

## Mobile Setup

### Requirements

- Flutter SDK `>=3.3.0 <4.0.0`

### Install and run

```bash
cd mobile
flutter pub get
flutter run
```

Firebase API key for mobile login:
- Preferred: provide at build/run time:
  - `--dart-define=FIREBASE_API_KEY=...`
- Fallback implemented: app can fetch key from backend `GET /api/public-config` (reads `FIREBASE_API_KEY` from backend env).

If both are missing, login will fail with "missing Firebase API key".

## API Overview

Base URL: `https://<your-domain>/api`

### Public

- `GET /public-config`
  - returns `firebaseApiKey` for mobile fallback config

### Requires Bearer Token

- `GET /classes`
- `GET /attendance-reminders`
- `GET /attendance/slot/comments`
- `POST /attendance/slot/comments`
- `POST /attendance/slot`
- `GET /payroll/monthly`
- `POST /devices/register`
- `POST /devices/unregister`

### Requires Admin Secret (`x-admin-secret`)

- `GET /devices`
- `GET /notifier/status`
- `POST /notifications/test`

### Scheduled Tick Endpoint

- `POST /notifier/tick`
  - auth: `x-cron-secret` (if `CRON_SECRET` is set) or valid `x-admin-secret`
  - if both `CRON_SECRET` and `ADMIN_API_SECRET` are missing, endpoint is disabled (`503`)

## Security Notes

- Global in-memory rate limit is applied to `/api/*`.
- Browser CORS is allowlist-based (`CORS_ORIGINS`).
- Query pagination/lookahead inputs are clamped by env max values.
- Admin endpoints are disabled until `ADMIN_API_SECRET` is configured.
- Device tokens and user sessions are stored in MongoDB; remember-password on mobile is stored in secure storage.

## Deploy Notes (Vercel)

1. Set backend env vars in Vercel project settings.
2. Deploy backend first (so `/api/public-config` is available).
3. Deploy mobile build with either:
   - `--dart-define=FIREBASE_API_KEY=...`, or
   - rely on backend fallback key endpoint.

## Quick Troubleshooting

- "Missing Firebase API key":
  - set `FIREBASE_API_KEY` in `backend/.env` (and redeploy backend), or
  - pass `--dart-define=FIREBASE_API_KEY=...` when running/building mobile.

- `401 Authorization header khong hop le`:
  - send `Authorization: Bearer <id_token>`.

- Admin API returns `503 Admin API is disabled`:
  - set `ADMIN_API_SECRET`.
