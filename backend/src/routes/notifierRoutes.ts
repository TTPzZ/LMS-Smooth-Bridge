import { Router, Request, Response } from 'express';
import { NotifierService } from '../services/notifierService';

export function createNotifierRouter(notifierService: NotifierService): Router {
    const router = Router();

    router.get('/notifier/status', async (_req: Request, res: Response) => {
        const status = await notifierService.getStatus();
        res.json({
            success: true,
            data: status
        });
    });

    router.post('/notifier/tick', async (_req: Request, res: Response) => {
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
