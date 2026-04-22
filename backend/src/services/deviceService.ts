import { Device } from '../db/models/device.model';

export type RegisterDevicePayload = {
    token: string;
    platform?: string;
    userId?: string | null;
    timezone?: string | null;
    appVersion?: string | null;
};

export function maskToken(token: string): string {
    if (token.length <= 18) {
        return token;
    }

    return `${token.slice(0, 8)}...${token.slice(-8)}`;
}

export function toPublicDevice(device: {
    token: string;
    platform: string;
    userId?: string | null;
    timezone?: string | null;
    appVersion?: string | null;
    createdAt?: Date;
    lastSeenAt: Date;
}) {
    return {
        tokenPreview: maskToken(device.token),
        platform: device.platform,
        userId: device.userId ?? null,
        timezone: device.timezone ?? null,
        appVersion: device.appVersion ?? null,
        createdAt: device.createdAt?.toISOString() ?? null,
        lastSeenAt: device.lastSeenAt.toISOString()
    };
}

export class DeviceService {
    async registerDevice(payload: RegisterDevicePayload) {
        const token = payload.token.trim();
        if (!token) {
            throw new Error('token la bat buoc');
        }

        const now = new Date();
        const platform = (payload.platform ?? 'unknown').trim() || 'unknown';

        const doc = await Device.findOneAndUpdate(
            { token },
            {
                $set: {
                    platform,
                    userId: payload.userId ? String(payload.userId).trim() : null,
                    timezone: payload.timezone ? String(payload.timezone).trim() : null,
                    appVersion: payload.appVersion ? String(payload.appVersion).trim() : null,
                    lastSeenAt: now
                },
                $setOnInsert: {
                    token
                }
            },
            {
                new: true,
                upsert: true
            }
        ).lean();

        return doc;
    }

    async unregisterDevice(tokenRaw: string): Promise<boolean> {
        const token = tokenRaw.trim();
        if (!token) {
            throw new Error('token la bat buoc');
        }

        const result = await Device.deleteOne({ token });
        return result.deletedCount > 0;
    }

    async listDevices() {
        return Device.find({})
            .sort({ lastSeenAt: -1 })
            .lean();
    }

    async countDevices(): Promise<number> {
        return Device.countDocuments({});
    }

    async removeDeviceByToken(token: string): Promise<void> {
        await Device.deleteOne({ token });
    }
}
