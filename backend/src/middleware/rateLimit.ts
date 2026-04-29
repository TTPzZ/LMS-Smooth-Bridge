import { NextFunction, Request, Response } from 'express';

type RateLimitOptions = {
    windowMs: number;
    maxRequests: number;
    keyGenerator?: (req: Request) => string;
    skip?: (req: Request) => boolean;
};

type RateLimitEntry = {
    count: number;
    resetAt: number;
};

export function createInMemoryRateLimiter(options: RateLimitOptions) {
    const entries = new Map<string, RateLimitEntry>();
    const windowMs = Math.max(1_000, options.windowMs);
    const maxRequests = Math.max(1, options.maxRequests);
    const keyGenerator = options.keyGenerator
        || ((req: Request) => req.ip || 'unknown-ip');

    return (req: Request, res: Response, next: NextFunction) => {
        if (options.skip?.(req)) {
            next();
            return;
        }

        const now = Date.now();
        const key = keyGenerator(req);
        const existing = entries.get(key);

        if (!existing || existing.resetAt <= now) {
            entries.set(key, {
                count: 1,
                resetAt: now + windowMs
            });
            next();
            return;
        }

        existing.count += 1;
        if (existing.count <= maxRequests) {
            next();
            return;
        }

        const retryAfterSeconds = Math.max(1, Math.ceil((existing.resetAt - now) / 1000));
        res.setHeader('Retry-After', String(retryAfterSeconds));
        res.status(429).json({
            success: false,
            error: 'Too many requests',
            detail: `Retry after ${retryAfterSeconds} seconds`
        });

        if (entries.size > 20_000) {
            entries.forEach((value, mapKey) => {
                if (value.resetAt <= now) {
                    entries.delete(mapKey);
                }
            });
        }
    };
}

