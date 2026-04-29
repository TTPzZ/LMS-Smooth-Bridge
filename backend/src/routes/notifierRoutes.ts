import { Router, Request, Response } from 'express';
import { env } from '../config/env';
import { NotifierService } from '../services/notifierService';
import { hasValidAdminSecret, requireAdminSecret } from '../middleware/adminAuth';

export function createNotifierRouter(notifierService: NotifierService): Router {
    const router = Router();

    function isTickAuthorized(req: Request): boolean {
        const expectedSecret = env.CRON_SECRET.trim();
        if (!expectedSecret) {
            return hasValidAdminSecret(req);
        }

        const headerSecret = String(req.headers['x-cron-secret'] ?? '').trim();
        return headerSecret === expectedSecret || hasValidAdminSecret(req);
    }

    router.get('/notifier/status', async (req: Request, res: Response) => {
        if (!requireAdminSecret(req, res)) {
            return;
        }

        const status = await notifierService.getStatus();
        res.json({
            success: true,
            data: status
        });
    });

    router.post('/notifier/tick', async (_req: Request, res: Response) => {
        if (!env.CRON_SECRET.trim() && !env.ADMIN_API_SECRET.trim()) {
            res.status(503).json({
                success: false,
                error: 'Notifier tick is disabled',
                detail: 'Set CRON_SECRET or ADMIN_API_SECRET in backend/.env'
            });
            return;
        }

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
        if (!requireAdminSecret(req, res)) {
            return;
        }

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
