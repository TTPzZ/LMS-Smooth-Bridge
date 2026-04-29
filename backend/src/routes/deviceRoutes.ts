import { Router, Request, Response } from 'express';
import { decodeJwtPayload } from '../utils/jwt';
import { parseBearerToken } from '../utils/requestParsers';
import { DeviceService, toPublicDevice } from '../services/deviceService';
import { requireAdminSecret } from '../middleware/adminAuth';

function readUserIdFromToken(token: string): string | null {
    const payload = decodeJwtPayload(token);
    const userId = typeof payload?.user_id === 'string'
        ? payload.user_id.trim()
        : typeof payload?.sub === 'string'
            ? payload.sub.trim()
            : '';
    return userId || null;
}

export function createDeviceRouter(deviceService: DeviceService): Router {
    const router = Router();

    router.get('/devices', async (req: Request, res: Response) => {
        if (!requireAdminSecret(req, res)) {
            return;
        }

        const devices = await deviceService.listDevices();
        const publicDevices = devices.map((device) => toPublicDevice({
            token: device.token,
            platform: device.platform,
            userId: device.userId,
            timezone: device.timezone,
            appVersion: device.appVersion,
            createdAt: device.createdAt,
            lastSeenAt: device.lastSeenAt
        }));

        res.json({
            success: true,
            data: publicDevices,
            meta: {
                totalDevices: publicDevices.length
            }
        });
    });

    router.post('/devices/register', async (req: Request, res: Response) => {
        try {
            const idTokenFromHeader = parseBearerToken(req.headers.authorization);
            if (!idTokenFromHeader) {
                res.status(401).json({
                    success: false,
                    error: 'Authorization header khong hop le',
                    detail: 'Expected format: Bearer <id_token>'
                });
                return;
            }

            const token = String(req.body?.token ?? '').trim();
            const platform = String(req.body?.platform ?? 'unknown').trim() || 'unknown';
            const userIdFromToken = readUserIdFromToken(idTokenFromHeader);
            const userId = userIdFromToken || (req.body?.userId ? String(req.body.userId).trim() : null);
            const timezone = req.body?.timezone ? String(req.body.timezone).trim() : null;
            const appVersion = req.body?.appVersion ? String(req.body.appVersion).trim() : null;

            const device = await deviceService.registerDevice({
                token,
                platform,
                userId,
                timezone,
                appVersion
            });

            res.json({
                success: true,
                data: toPublicDevice({
                    token: device.token,
                    platform: device.platform,
                    userId: device.userId,
                    timezone: device.timezone,
                    appVersion: device.appVersion,
                    createdAt: device.createdAt,
                    lastSeenAt: device.lastSeenAt
                }),
                meta: {
                    totalDevices: await deviceService.countDevices()
                }
            });
        } catch (error: any) {
            res.status(400).json({
                success: false,
                error: error?.message || 'Dang ky device that bai'
            });
        }
    });

    router.post('/devices/unregister', async (req: Request, res: Response) => {
        try {
            const idTokenFromHeader = parseBearerToken(req.headers.authorization);
            if (!idTokenFromHeader) {
                res.status(401).json({
                    success: false,
                    error: 'Authorization header khong hop le',
                    detail: 'Expected format: Bearer <id_token>'
                });
                return;
            }

            const token = String(req.body?.token ?? '').trim();
            const removed = await deviceService.unregisterDevice(token);

            res.json({
                success: true,
                data: {
                    removed
                },
                meta: {
                    totalDevices: await deviceService.countDevices()
                }
            });
        } catch (error: any) {
            res.status(400).json({
                success: false,
                error: error?.message || 'Go device that bai'
            });
        }
    });

    return router;
}
