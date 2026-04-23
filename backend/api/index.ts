import { createApp } from '../src/app';

let appPromise: ReturnType<typeof createApp> | null = null;

async function getApp() {
    if (!appPromise) {
        appPromise = createApp().catch((error) => {
            appPromise = null;
            throw error;
        });
    }

    const context = await appPromise;
    return context.app;
}

export default async function handler(req: any, res: any) {
    try {
        const app = await getApp();
        return app(req, res);
    } catch (error: any) {
        const message = error?.message || 'Server bootstrap failed';
        console.error('Vercel handler error:', message);
        res.status(500).json({
            success: false,
            error: 'Backend khoi tao that bai',
            detail: message
        });
    }
}
