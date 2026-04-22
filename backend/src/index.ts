import express from 'express';
import cors from 'cors';
import { env } from './config/env';
import { connectMongo, disconnectMongo } from './db/mongo';
import { AuthTokenService } from './services/authTokenService';
import { LmsService } from './services/lmsService';
import { DeviceService } from './services/deviceService';
import { NotifierService } from './services/notifierService';
import { PayrollService } from './services/payrollService';
import { createClassRouter } from './routes/classRoutes';
import { createDeviceRouter } from './routes/deviceRoutes';
import { createNotifierRouter } from './routes/notifierRoutes';
import { createPayrollRouter } from './routes/payrollRoutes';

async function bootstrap(): Promise<void> {
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

    const server = app.listen(env.PORT, () => {
        console.log(`Server dang chay tai http://localhost:${env.PORT}`);
        console.log(`Auth mode: ${authTokenService.getAuthMode()}`);
        console.log(`Push notifier: ${env.ENABLE_PUSH_NOTIFIER ? 'enabled' : 'disabled'}`);
        console.log('MongoDB: connected');

        if (env.ENABLE_PUSH_NOTIFIER) {
            notifierService.start();
            console.log(
                `Push notifier interval: ${env.PUSH_NOTIFIER_INTERVAL_SECONDS}s, lookAhead: ${env.PUSH_LOOKAHEAD_MINUTES}m`
            );
        }
    });

    async function shutdown(signal: string): Promise<void> {
        console.log(`Nhan ${signal}, dang tat server...`);
        notifierService.stop();
        server.close(async () => {
            await disconnectMongo();
            process.exit(0);
        });
    }

    process.on('SIGINT', () => {
        shutdown('SIGINT').catch((error) => {
            console.error('Shutdown loi:', error);
            process.exit(1);
        });
    });

    process.on('SIGTERM', () => {
        shutdown('SIGTERM').catch((error) => {
            console.error('Shutdown loi:', error);
            process.exit(1);
        });
    });
}

bootstrap().catch((error) => {
    console.error('Khoi dong server that bai:', error?.message || error);
    process.exit(1);
});
