import dotenv from 'dotenv';

dotenv.config();

function parseBooleanEnv(value: string | undefined, fallback: boolean): boolean {
    if (value === undefined) {
        return fallback;
    }

    const normalized = value.trim().toLowerCase();
    if (normalized === '1' || normalized === 'true' || normalized === 'yes' || normalized === 'on') {
        return true;
    }
    if (normalized === '0' || normalized === 'false' || normalized === 'no' || normalized === 'off') {
        return false;
    }

    return fallback;
}

function parseIntegerEnv(value: string | undefined, fallback: number): number {
    const parsed = Number.parseInt(value ?? '', 10);
    if (Number.isNaN(parsed) || parsed <= 0) {
        return fallback;
    }

    return parsed;
}

const parsedPort = Number.parseInt(process.env.PORT ?? '3000', 10);

export const env = {
    PORT: Number.isNaN(parsedPort) ? 3000 : parsedPort,
    LMS_GRAPHQL_URL: process.env.LMS_GRAPHQL_URL?.trim() || 'https://lms-api.mindx.edu.vn/graphql',
    DEFAULT_ITEMS_PER_PAGE: parseIntegerEnv(process.env.DEFAULT_ITEMS_PER_PAGE, 50),
    DEFAULT_MAX_PAGES: parseIntegerEnv(process.env.DEFAULT_MAX_PAGES, 10),
    ATTENDANCE_OPEN_MINUTES_BEFORE: parseIntegerEnv(process.env.ATTENDANCE_OPEN_MINUTES_BEFORE, 5),
    ATTENDANCE_CLOSE_MINUTES_AFTER: parseIntegerEnv(process.env.ATTENDANCE_CLOSE_MINUTES_AFTER, 30),
    DEFAULT_LOOKAHEAD_MINUTES: parseIntegerEnv(process.env.DEFAULT_LOOKAHEAD_MINUTES, 24 * 60),
    DEFAULT_MAX_REMINDER_SLOTS: parseIntegerEnv(process.env.DEFAULT_MAX_REMINDER_SLOTS, 20),

    FIREBASE_API_KEY: process.env.FIREBASE_API_KEY?.trim() ?? '',
    LMS_EMAIL: process.env.LMS_EMAIL?.trim() ?? '',
    LMS_PASSWORD: process.env.LMS_PASSWORD?.trim() ?? '',
    LMS_ID_TOKEN: process.env.LMS_ID_TOKEN?.trim() ?? '',
    LMS_REFRESH_TOKEN: process.env.LMS_REFRESH_TOKEN?.trim() ?? '',

    MONGO_URI: process.env.MONGO_URI?.trim() ?? '',
    MONGO_DB_NAME: process.env.MONGO_DB_NAME?.trim() ?? '',

    ENABLE_PUSH_NOTIFIER: parseBooleanEnv(process.env.ENABLE_PUSH_NOTIFIER, false),
    PUSH_NOTIFIER_INTERVAL_SECONDS: parseIntegerEnv(process.env.PUSH_NOTIFIER_INTERVAL_SECONDS, 60),
    PUSH_LOOKAHEAD_MINUTES: parseIntegerEnv(process.env.PUSH_LOOKAHEAD_MINUTES, 15),
    PUSH_HISTORY_TTL_HOURS: parseIntegerEnv(process.env.PUSH_HISTORY_TTL_HOURS, 72),

    FCM_PROJECT_ID: process.env.FCM_PROJECT_ID?.trim() ?? '',
    FCM_CLIENT_EMAIL: process.env.FCM_CLIENT_EMAIL?.trim() ?? '',
    FCM_PRIVATE_KEY: (process.env.FCM_PRIVATE_KEY ?? '').replace(/\\n/g, '\n')
};

export const firebaseVerifyPasswordUrl = env.FIREBASE_API_KEY
    ? `https://www.googleapis.com/identitytoolkit/v3/relyingparty/verifyPassword?key=${env.FIREBASE_API_KEY}`
    : '';

export const firebaseRefreshUrl = env.FIREBASE_API_KEY
    ? `https://securetoken.googleapis.com/v1/token?key=${env.FIREBASE_API_KEY}`
    : '';
