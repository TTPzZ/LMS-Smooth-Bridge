export type JwtPayload = {
    username?: string;
    user_id?: string;
    sub?: string;
    email?: string;
    [key: string]: unknown;
};

function normalizeJwtSegment(segment: string): string {
    const base64 = segment.replace(/-/g, '+').replace(/_/g, '/');
    const paddingLength = (4 - (base64.length % 4)) % 4;
    return `${base64}${'='.repeat(paddingLength)}`;
}

export function decodeJwtPayload(token: string): JwtPayload | null {
    const sections = token.split('.');
    if (sections.length < 2) {
        return null;
    }

    try {
        const payloadBuffer = Buffer.from(normalizeJwtSegment(sections[1]), 'base64');
        const payload = JSON.parse(payloadBuffer.toString('utf8')) as JwtPayload;
        return payload;
    } catch {
        return null;
    }
}
