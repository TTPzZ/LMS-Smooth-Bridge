import cors from 'cors';
import express from 'express';
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

export type AppContext = {
    app: express.Express;
    authTokenService: AuthTokenService;
    notifierService: NotifierService;
};

let appContextPromise: Promise<AppContext> | null = null;

async function buildAppContext(): Promise<AppContext> {
    const app = express();

    app.use(cors());
    app.use(express.json());

    await connectMongo();

    const authTokenService = new AuthTokenService();
    const lmsService = new LmsService(authTokenService);
    const deviceService = new DeviceService();
    const notifierService = new NotifierService(lmsService);
    const payrollService = new PayrollService(lmsService);

    app.use('/api', createClassRouter(lmsService));
    app.use('/api', createDeviceRouter(deviceService));
    app.use('/api', createNotifierRouter(notifierService));
    app.use('/api', createPayrollRouter(payrollService));

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
