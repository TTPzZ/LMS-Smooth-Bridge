LMS Smooth Bridge
A middleman proxy server designed to optimize the user experience between the MindX LMS and a custom mobile application. This project resolves performance bottlenecks caused by excessive data exposure, automates authentication flows, and minimizes API payloads for mobile consumption.

Problem & Solution
Problem: The original LMS GraphQL API returns oversized payloads (up to 4MB per request) containing redundant metadata and unnecessary PII. This causes severe lag and high memory consumption on mobile devices.

Solution: A Node.js proxy server that intercepts the LMS response, filters out all unnecessary data, and delivers a highly optimized, lightweight JSON payload (reducing size by ~90%) to the mobile client.

Technologies Used
Backend: Node.js, TypeScript (Express or NestJS)

Database: MongoDB (Used for storing refreshToken, basic configurations, and temporary data caching)

Mobile Client: Flutter

Authentication: Firebase Auth (REST API signInWithPassword flow)

System Architecture
Auth Module: Automatically authenticates with Firebase to retrieve the idToken. Manages session state and automatically requests a new token using the refreshToken when the current one expires.

Proxy Module: Receives lightweight requests from the Flutter app, attaches the valid Bearer Token, and forwards the request to the upstream LMS GraphQL server.

Data Transformer: The core component. It receives the massive JSON response from the LMS, parses the nested objects, extracts only the essential fields (e.g., class ID, student name, attendance status), and returns the clean data to the mobile app.

Target APIs (Reverse Engineered)
Authentication: https://www.googleapis.com/identitytoolkit/v3/relyingparty/verifyPassword?key=[FIREBASE_API_KEY]

LMS GraphQL Endpoint: https://lms-api.mindx.edu.vn/graphql

query GetClasses: Fetches the assigned classes and student lists.

mutation StudentAttendance (Expected): Submits attendance records and teacher comments.

Development Roadmap
[ ] Phase 1: Initialize the Node.js project and configure the MongoDB connection.

[ ] Phase 2: Implement the Firebase automated login and token refresh logic.

[ ] Phase 3: Build the Data Transformer utility to parse and map the GetClasses GraphQL response.

[ ] Phase 4: Develop the Flutter mobile UI (Dashboard, Class List, Attendance form) to consume the optimized API.

[ ] Phase 5: Deploy the Node.js backend to a cloud provider (e.g., Vercel).
