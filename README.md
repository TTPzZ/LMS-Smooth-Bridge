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

Development Roadmap
Phase 1: Prototype (MVP) - The Data Filter: Set up the Node.js backend. Hardcode a single active token to establish the connection. Build the core parser to transform the 4MB LMS payload into a lightweight structure.

Phase 2: Multi-Tenant Auth: Integrate MongoDB. Create the Users schema. Implement the automated login and token refresh logic for multiple accounts.

Phase 3: Flutter Mobile App: Develop the UI components (Dashboard, Class List, Attendance Form) and connect them to the optimized Node.js endpoints.

Phase 4: Payroll Automation: Implement cronjobs to fetch completed slots, aggregate working hours, and calculate payroll based on hourly rates.

Phase 5: Evaluation Engine: Integrate subject-specific comment templates and AI generation endpoints for quick grading.