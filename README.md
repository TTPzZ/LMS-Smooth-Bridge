<div align="center">

<img width="100%" src="https://capsule-render.vercel.app/api?type=waving&height=220&color=gradient&customColorList=1&text=LMS%20Smooth%20Bridge&fontSize=50&fontAlignY=40&desc=Proxy%20and%20Automation%20Middleware%20System&descAlignY=62" />

<img src="https://readme-typing-svg.demolab.com?font=Fira+Code&weight=600&size=20&pause=1000&center=true&vCenter=true&width=900&lines=Optimizing+LMS+Payloads+(4MB+%E2%86%92+50KB);Multi-Tenant+Session+and+Auth+Management;Automated+Payroll+%2B+AI-Assisted+Evaluations;Node.js+%2B+MongoDB+%2B+Vercel+%2B+Flutter" />

<br/>

<img src="https://img.shields.io/badge/Backend-Node.js%20%7C%20TS-339933?style=for-the-badge&logo=nodedotjs&logoColor=white" />
<img src="https://img.shields.io/badge/Database-MongoDB_Atlas-47A248?style=for-the-badge&logo=mongodb&logoColor=white" />
<img src="https://img.shields.io/badge/Hosting-Vercel-black?style=for-the-badge&logo=vercel" />
<img src="https://img.shields.io/badge/Auth-Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=white" />
<img src="https://img.shields.io/badge/Mobile-Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" />
<img src="https://img.shields.io/badge/API-GraphQL-E10098?style=for-the-badge&logo=graphql&logoColor=white" />

</div>

---

## About The Project

**LMS Smooth Bridge** is a dedicated backend middleware system designed to optimize, automate, and extend the capabilities of a legacy LMS for a custom mobile application. 

Initially conceived to solve severe performance bottlenecks caused by heavy API payloads, this architecture is built to scale into a multi-tenant platform supporting up to 30 instructors. It seamlessly manages session states, drastically filters redundant data, and introduces powerful automation features like background payroll tracking and AI-assisted student evaluations.

---

## System Architecture & Data Flow

```
                                  ┌────────────────────┐
                                  │   Flutter Mobile   │
                                  │   (iOS & Android)  │
                                  └─────────┬──────────┘
                                            │ Optimized JSON Payload (< 50KB)
                                            ▼
                                  ┌───────────────────────┐
                   ┌──────────────┤   LMS Smooth Bridge   ├──────────────┐
                   │              │  (Node.js + Vercel)   │              │
                   │              └─────────┬─────────────┘              │
             Firebase Auth                  │ GraphQL                    │ MongoDB Atlas
          (Auth & Token Swap)               │ (Heavy Payload: ~4MB)      │ (Sessions & Caching)
                   ▼                        ▼                            ▼
           ┌──────────────┐          ┌──────────────┐             ┌──────────────┐
           │   Firebase   │          │ Upstream LMS │             │   MongoDB    │
           └──────────────┘          └──────────────┘             └──────────────┘
```
### Core Data Flows
Authentication Flow: Flutter app sends credentials ➔ Backend authenticates via Firebase ➔ Retrieves tokens & stores refreshToken in MongoDB ➔ Returns session ID to app.

Proxy Flow: Mobile app requests data ➔ Backend retrieves active idToken ➔ Forwards request to LMS GraphQL ➔ Transforms & strips PII (4MB down to 50KB) ➔ Returns sanitized JSON.

Action Flow: Instructor submits attendance ➔ Backend compiles GraphQL mutation ➔ Executes on Upstream LMS.

### Key Features
#### Payload Optimization (Data Transformation): 
Intercepts massive GraphQL responses (up to 4MB), strips unnecessary metadata and PII, and delivers lightweight JSON (< 50KB) for a fluid mobile experience.

#### Multi-Tenant Session Management: 
Secure auth for multiple instructors. Stores encrypted refreshTokens (MongoDB) and auto-negotiates with Firebase Auth to issue fresh idTokens, eliminating manual re-logins.

#### Automated Payroll & Timesheets: 
Background cronjobs scan and aggregate completed teaching slots. Data is locally cached for instant payroll/timesheet reporting without hammering the LMS server.

#### Smart Evaluation System: 
Pre-defined evaluation templates for subjects (Game Maker, Robot 1, Python). Structured for AI integration to generate draft comments based on attendance and performance.

#### Push Notification Engine: 
FCM-based auto-reminders for upcoming and active attendance windows.

### Tech Stack
```
Layer	Technology
Backend / API	Node.js, TypeScript (Express/Fastify)
Database	MongoDB Atlas
Mobile Client	Flutter (iOS & Android)
Authentication	Firebase Auth (REST signInWithPassword)
Deployment	Vercel (Serverless Functions)
Target Endpoints	Firebase API, Upstream LMS GraphQL
```
### Code Structure
```
lms-smooth-bridge/
├── src/
│   ├── index.ts           # Server bootstrap
│   ├── config/env.ts      # Env parsing and default configurations
│   ├── db/                # MongoDB connection and schemas/models
│   ├── services/          # Business logic: LMS Auth, LMS API, Windows, Notifiers
│   └── routes/            # API endpoints grouped by feature
├── .env.example           # Environment template
└── package.json
```
### Getting Started
1. Database Setup (MongoDB Atlas)
   
         Sign in to MongoDB Atlas and create a project (LMS-Smooth-Bridge).
         Create a Free Tier Cluster.
         In Database Access, create a user (e.g., lms_admin / <strong_password>) with the Atlas admin role.
         In Network Access, whitelist your IP (use 0.0.0.0/0 temporarily for local dev).
         Copy the connection string from Connect ➔ Drivers.

2. Backend Authentication Setup (No More F12)
Clone the repo and navigate to the backend folder:
```
npm install
cp .env.example .env
```
Configure ONE of these Auth strategies in .env:

Recommended: 
```
FIREBASE_API_KEY + LMS_REFRESH_TOKEN (Server auto-refreshes idToken).
```   
Alternative:
```
FIREBASE_API_KEY + LMS_EMAIL + LMS_PASSWORD (Server logs in ➔ auto-refreshes).
```
Set your MongoDB variables:
```
MONGO_URI="your_connection_string_here"
MONGO_DB_NAME="lms_smooth_bridge"
```
3. Running Locally
```
npm run dev
```
The server will log the active auth mode (refresh-token or email-password) and confirm MongoDB: connected.

### API Ecosystem
Firebase Auth: 
```
https://www.googleapis.com/identitytoolkit/v3/relyingparty/verifyPassword?key=[KEY]
```
LMS GraphQL: 
```
https://lms-api.mindx.edu.vn/graphql
```
query GetClasses: Fetches assigned classes and student lists.
mutation StudentAttendance: Submits attendance and teacher comments.

```
GET /api/classes
```
Extends standard response with: classEndDate, isClassEnded, nextAttendanceWindow (slot details, open/close times, countdown).

```
GET /api/attendance-reminders
```
Returns upcoming attendance windows.

Params: lookAheadMinutes (def: 1440), maxSlots (def: 20), activeOnly (def: true).

Rule: Opens 5 mins before slot start, closes 30 mins after slot end.

```
GET /api/payroll/monthly
```
Query Params: month (1-12), year (YYYY), timezone, teacherId / username, countedStatuses (def: ATTENDED,LATE_ARRIVED).

Returns: Total taught slots, roles (LEC, TA, Judge), and slot-level details for manual verification.

#### Requires .env config: ENABLE_PUSH_NOTIFIER=true + FCM Credentials.

Registration: - POST /api/devices/register - { token, platform, userId?, timezone?, appVersion? }

```
POST /api/devices/unregister - { token }
```
#### Operations:
```
GET /api/notifier/status - Runtime health check.

POST /api/notifications/test - Trigger test push.
```
Automation: Sends UPCOMING (15 mins prior) and OPEN reminders. Deduplication active to prevent spam.

Development Roadmap
```
[x] Phase 1: Prototype (MVP) - The Data Filter: Node.js backend setup, hardcoded token connection, core parser built to crush 4MB payloads to 50KB.

[x] Phase 2: Multi-Tenant Auth: MongoDB integration, Users schema, automated login, and token refresh logic.

[x] Phase 3: Flutter Mobile App: Dashboard, Class List, and Attendance Form UI connected to optimized endpoints.

[x] Phase 4: Payroll Automation: Cronjobs for slot aggregation, working hour compilation, and automated salary calculation.

[ ] Phase 5: Evaluation Engine: AI-generated grading drafts and subject-specific comment templates.
```
