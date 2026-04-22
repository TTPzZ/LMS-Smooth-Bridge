LMS Smooth Bridge (Proxy & Automation System)
Overview
LMS Smooth Bridge is a dedicated backend middleware system designed to optimize, automate, and extend the capabilities of the original LMS for a custom mobile application. Initially conceived to solve performance bottlenecks caused by heavy API payloads, the architecture is designed to scale into a multi-tenant platform supporting up to 30 instructors. It manages session states, filters redundant data, and introduces automation features like payroll tracking and AI-assisted student evaluations.

Core Features
Data Transformation (Payload Optimization): Intercepts massive GraphQL responses (up to 4MB) from the upstream LMS, strips out unnecessary metadata and PII, and delivers highly optimized JSON payloads (under 50KB) to ensure a fluid mobile experience.

Multi-Tenant Session Management: Securely handles authentication for multiple instructors. It stores encrypted refreshTokens in MongoDB and automatically negotiates with Firebase Auth to issue fresh idTokens upon expiration, eliminating the need for manual re-login.

Automated Payroll & Timesheets: Utilizes background cronjobs to periodically scan and aggregate completed teaching slots from the LMS. Data is cached locally to generate instant payroll reports and timesheets without repeatedly querying the original server.

Smart Evaluation System: Stores pre-defined evaluation templates for specific subjects (e.g., Game Maker, Robot 1, Python). It is structured to integrate AI models that can generate draft comments based on attendance and performance parameters, allowing instructors to review and submit with a single tap.

Technology Stack
Backend Environment: Node.js with TypeScript (Framework: Express or Fastify). TypeScript is strictly used to define interfaces for complex GraphQL responses.

Database: MongoDB (MongoDB Atlas). Used for storing the Users collection, encrypted tokens, evaluation templates, and cached timesheet data.

Mobile Client: Flutter (Targeting iOS and Android).

Authentication: Firebase Authentication (via REST API signInWithPassword flow).

Deployment & Hosting: Vercel (Optimized for serverless Node.js functions).

System Architecture & Data Flow
Authentication Flow: The Flutter app sends credentials to the Node.js Backend. The Backend authenticates with Firebase, retrieves the tokens, stores the refreshToken in MongoDB, and returns a session identifier to the app.

Proxy Flow: The mobile app requests data (e.g., class list). The Backend retrieves the active idToken from the database, forwards the request to the LMS GraphQL endpoint, receives the raw data, applies the Data Transformer logic, and returns the sanitized data to the app.

Action Flow: When an instructor submits an attendance record, the Backend compiles the required GraphQL mutation and executes it on the upstream LMS on behalf of the user.

Target APIs (Reverse Engineered)
Authentication: https://www.googleapis.com/identitytoolkit/v3/relyingparty/verifyPassword?key=[FIREBASE_API_KEY]

LMS GraphQL Endpoint: https://lms-api.mindx.edu.vn/graphql

query GetClasses: Fetches assigned classes and student lists.

mutation StudentAttendance: Submits attendance records and teacher comments.

Backend Auth Setup (No More F12)
1. Create `backend/.env` from `backend/.env.example`.
2. Configure one of these strategies:
   - Recommended: `FIREBASE_API_KEY` + `LMS_REFRESH_TOKEN` (server will auto refresh idToken).
   - Alternative: `FIREBASE_API_KEY` + `LMS_EMAIL` + `LMS_PASSWORD` (server logs in, then auto refreshes).
3. Start backend with `npm run dev` inside `backend`.
4. Server logs current auth mode at startup (`refresh-token`, `email-password`, or fallback mode).

Database Setup (MongoDB Atlas - Step by Step)
1. Sign in to MongoDB Atlas: https://www.mongodb.com/atlas/database
2. Create a new Project (e.g., `LMS-Smooth-Bridge`).
3. Create a Cluster (shared free tier is enough for MVP).
4. Open `Database Access` and create a database user:
   - Username: your choice (e.g., `lms_admin`)
   - Password: generate a strong password and store securely
   - Role: `Atlas admin` for quick setup (tighten later if needed)
5. Open `Network Access` and allow your backend IP:
   - For local test: add `0.0.0.0/0` temporarily
   - For production: whitelist only server IPs
6. In Cluster view, click `Connect` -> `Drivers` -> copy the connection string.
7. In `backend/.env`, set:
   - `MONGO_URI=<your connection string>`
   - `MONGO_DB_NAME=lms_smooth_bridge`
8. Start backend with `npm run dev` and verify log `MongoDB: connected`.
9. Check collections are auto-created after API calls:
   - `devices`
   - `notificationevents`

Attendance Reminder APIs
1. `GET /api/classes`: now also returns:
   - `classEndDate` and `isClassEnded`
   - `nextAttendanceWindow` (slotId, slot start/end, attendance open/close window, countdown minutes)
2. `GET /api/attendance-reminders`: returns upcoming attendance windows across classes.
   - Useful query params: `lookAheadMinutes` (default 1440), `maxSlots` (default 20), `activeOnly` (default true)
   - Attendance window rule follows LMS: open 5 minutes before slot start, close 30 minutes after slot end.

Payroll API (Monthly Teaching Summary)
1. `GET /api/payroll/monthly`
2. Query params:
   - `month` (1-12), `year` (YYYY), `timezone` (default `Asia/Ho_Chi_Minh`)
   - Optional teacher selector: `teacherId` or `username`
   - Optional status counted as taught: `countedStatuses` (comma separated, default `ATTENDED,LATE_ARRIVED`)
3. Response includes:
   - Total taught slots in month
   - Classes taught
   - Role breakdown (`LEC`, `TA`, `Judge`, ...)
   - Slot-level details for manual salary calculation

Backend Push Notifier (FCM)
1. Enable in `backend/.env`:
   - `ENABLE_PUSH_NOTIFIER=true`
   - Configure FCM credentials using either:
     - `FCM_PROJECT_ID` + `FCM_CLIENT_EMAIL` + `FCM_PRIVATE_KEY`
     - or `GOOGLE_APPLICATION_CREDENTIALS`
2. Device registration endpoints:
   - `POST /api/devices/register` with body `{ token, platform, userId?, timezone?, appVersion? }`
   - `POST /api/devices/unregister` with body `{ token }`
   - `GET /api/devices` to inspect registered devices (masked token preview)
3. Notifier operations:
   - `GET /api/notifier/status` to check runtime status
   - `POST /api/notifications/test` to send test push to one token or all registered tokens
4. Auto-reminder behavior:
   - Sends `UPCOMING` reminder before attendance window opens (default look-ahead: 15 minutes)
   - Sends `OPEN` reminder when attendance window is open
   - Dedupe is enabled to prevent repeated spam for the same slot stage

Code Structure (Refactored)
- `src/index.ts`: server bootstrap only
- `src/config/env.ts`: env parsing and defaults
- `src/db/`: MongoDB connection and models
- `src/services/`: LMS auth, LMS API, attendance window logic, notifier logic
- `src/routes/`: API endpoints grouped by feature

Development Roadmap
Phase 1: Prototype (MVP) - The Data Filter: Set up the Node.js backend. Hardcode a single active token to establish the connection. Build the core parser to transform the 4MB LMS payload into a lightweight structure.

Phase 2: Multi-Tenant Auth: Integrate MongoDB. Create the Users schema. Implement the automated login and token refresh logic for multiple accounts.

Phase 3: Flutter Mobile App: Develop the UI components (Dashboard, Class List, Attendance Form) and connect them to the optimized Node.js endpoints.

Phase 4: Payroll Automation: Implement cronjobs to fetch completed slots, aggregate working hours, and calculate payroll based on hourly rates.

Phase 5: Evaluation Engine: Integrate subject-specific comment templates and AI generation endpoints for quick grading.
