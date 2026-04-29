import cors from 'cors';
import express from 'express';
import { env } from './config/env';
import { connectMongo } from './db/mongo';
import { AuthTokenService } from './services/authTokenService';
import { LmsService } from './services/lmsService';
import { DeviceService } from './services/deviceService';
import { NotifierService } from './services/notifierService';
import { PayrollService } from './services/payrollService';
import { createClassRouter } from './routes/classRoutes';
import { createDeviceRouter } from './routes/deviceRoutes';
import { createNotifierRouter } from './routes/notifierRoutes';
import { createPayrollRouter } from './routes/payrollRoutes';
import { createInMemoryRateLimiter } from './middleware/rateLimit';

export type AppContext = {
    app: express.Express;
    authTokenService: AuthTokenService;
    notifierService: NotifierService;
};

let appContextPromise: Promise<AppContext> | null = null;

async function buildAppContext(): Promise<AppContext> {
    const app = express();

    const allowedOrigins = new Set(env.CORS_ORIGINS.map((origin) => origin.trim()).filter(Boolean));

    app.set('trust proxy', env.TRUST_PROXY ? 1 : 0);
    app.use(cors({
        origin(origin, callback) {
            if (!origin) {
                callback(null, true);
                return;
            }

            if (allowedOrigins.size === 0) {
                callback(null, false);
                return;
            }

            callback(null, allowedOrigins.has(origin));
        },
        methods: ['GET', 'POST', 'OPTIONS'],
        allowedHeaders: ['Content-Type', 'Authorization', 'x-cron-secret', 'x-admin-secret']
    }));
    app.use(express.json({ limit: '1mb' }));
    app.use('/api', createInMemoryRateLimiter({
        windowMs: env.RATE_LIMIT_WINDOW_SECONDS * 1000,
        maxRequests: env.RATE_LIMIT_MAX_REQUESTS
    }));

    await connectMongo();

    const authTokenService = new AuthTokenService();
    const lmsService = new LmsService(authTokenService);
    const deviceService = new DeviceService();
    const notifierService = new NotifierService(lmsService);
    const payrollService = new PayrollService(lmsService);

    app.use('/api', createClassRouter(lmsService));
    app.use('/api', createDeviceRouter(deviceService, lmsService));
    app.use('/api', createNotifierRouter(notifierService));
    app.use('/api', createPayrollRouter(payrollService));
    app.get('/api/public-config', (_req, res) => {
        res.json({
            success: true,
            data: {
                firebaseApiKey: env.FIREBASE_API_KEY
            }
        });
    });

    app.get('/', (_req, res) => {
        res.status(200).json({
            success: true,
            service: 'lms-smooth-bridge-backend',
            health: '/health'
        });
    });

    app.get(['/favicon.ico', '/favicon.png'], (_req, res) => {
        res.status(204).end();
    });

    app.get('/health', (_req, res) => {
        res.json({
            success: true,
            status: 'ok'
        });
    });

    return {
        app,
        authTokenService,
        notifierService
    };
}

export async function createApp(): Promise<AppContext> {
    if (!appContextPromise) {
        appContextPromise = buildAppContext().catch((error) => {
            appContextPromise = null;
            throw error;
        });
    }

    return appContextPromise;
}
