import { Router, Request, Response } from 'express';
import { env } from '../config/env';
import { NotifierService } from '../services/notifierService';

export function createNotifierRouter(notifierService: NotifierService): Router {
    const router = Router();

    function isTickAuthorized(req: Request): boolean {
        const expectedSecret = env.CRON_SECRET.trim();
        if (!expectedSecret) {
            return true;
        }

        const headerSecret = String(req.headers['x-cron-secret'] ?? '').trim();
        const querySecret = String(req.query.cronSecret ?? '').trim();
        const providedSecret = headerSecret || querySecret;
        return providedSecret === expectedSecret;
    }

    router.get('/notifier/status', async (_req: Request, res: Response) => {
        const status = await notifierService.getStatus();
        res.json({
            success: true,
            data: status
        });
    });

    router.post('/notifier/tick', async (_req: Request, res: Response) => {
        if (!isTickAuthorized(_req)) {
            res.status(401).json({
                success: false,
                error: 'Unauthorized notifier tick'
            });
            return;
        }

        await notifierService.runTick();
        res.json({
            success: true,
            data: {
                triggered: true
            }
        });
    });

    router.post('/notifications/test', async (req: Request, res: Response) => {
        try {
            const token = String(req.body?.token ?? '').trim() || undefined;
            const title = String(req.body?.title ?? 'Test thong bao diem danh');
            const body = String(req.body?.body ?? 'Backend dang gui test push notification');

            const result = await notifierService.sendTestNotification(title, body, token);
            res.json({
                success: result.failed === 0,
                data: result
            });
        } catch (error: any) {
            res.status(400).json({
                success: false,
                error: error?.message || 'Gui test notification that bai'
            });
        }
    });

    return router;
}
