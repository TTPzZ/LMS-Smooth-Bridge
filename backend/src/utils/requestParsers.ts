export function parseIntegerQuery(value: unknown, fallback: number): number {
    const parsedValue = Number.parseInt(String(value ?? ''), 10);
    if (Number.isNaN(parsedValue) || parsedValue <= 0) {
        return fallback;
    }

    return parsedValue;
}

export function parseBooleanQuery(value: unknown, fallback: boolean): boolean {
    if (value === undefined || value === null) {
        return fallback;
    }

    const normalized = String(value).toLowerCase();
    if (normalized === '1' || normalized === 'true' || normalized === 'yes') {
        return true;
    }

    if (normalized === '0' || normalized === 'false' || normalized === 'no') {
        return false;
    }

    return fallback;
}

export function sanitizePositiveInt(value: unknown, fallback: number): number {
    const parsed = parseIntegerQuery(value, fallback);
    return parsed > 0 ? parsed : fallback;
}

export function parseBearerToken(value: unknown): string | null {
    const rawHeader = Array.isArray(value) ? value[0] : value;
    const authHeader = String(rawHeader ?? '').trim();
    if (!authHeader) {
        return null;
    }

    const matcher = /^Bearer\s+(.+)$/i.exec(authHeader);
    if (!matcher) {
        return null;
    }

    const token = matcher[1]?.trim();
    return token ? token : null;
}
