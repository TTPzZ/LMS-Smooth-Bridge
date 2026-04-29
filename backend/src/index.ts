import { env } from './config/env';
import { disconnectMongo } from './db/mongo';
import { createApp } from './app';

async function bootstrap(): Promise<void> {
    const { app, authTokenService, notifierService } = await createApp();

    const server = app.listen(env.PORT, () => {
        console.log(`Server dang chay tai http://localhost:${env.PORT}`);
        console.log(`Auth mode: ${authTokenService.getAuthMode()}`);
        console.log(`Push notifier: ${env.ENABLE_PUSH_NOTIFIER ? 'enabled' : 'disabled'}`);
        console.log('MongoDB: connected');
        console.log(
            `Admin APIs: ${env.ADMIN_API_SECRET.trim() ? 'protected' : 'disabled (missing ADMIN_API_SECRET)'}`
        );
        if (env.CORS_ORIGINS.length === 0) {
            console.log('CORS: no allowed origins configured (browser CORS requests are blocked by default)');
        } else {
            console.log(`CORS: allowlist(${env.CORS_ORIGINS.length}) configured`);
        }

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
