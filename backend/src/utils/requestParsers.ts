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
