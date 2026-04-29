import { Request, Response } from 'express';
import { env } from '../config/env';

function readAdminSecret(req: Request): string {
    const headerSecret = req.headers['x-admin-secret'];
    const raw = Array.isArray(headerSecret) ? headerSecret[0] : headerSecret;
    return String(raw ?? '').trim();
}

export function hasValidAdminSecret(req: Request): boolean {
    const expected = env.ADMIN_API_SECRET.trim();
    if (!expected) {
        return false;
    }

    return readAdminSecret(req) === expected;
}

export function requireAdminSecret(req: Request, res: Response): boolean {
    const expected = env.ADMIN_API_SECRET.trim();
    if (!expected) {
        res.status(503).json({
            success: false,
            error: 'Admin API is disabled',
            detail: 'Set ADMIN_API_SECRET in backend/.env'
        });
        return false;
    }

    if (hasValidAdminSecret(req)) {
        return true;
    }

    res.status(401).json({
        success: false,
        error: 'Unauthorized admin request'
    });
    return false;
}

