import axios from 'axios';
import { env, firebaseRefreshUrl, firebaseVerifyPasswordUrl } from '../config/env';
import { FirebaseLoginResponse, FirebaseRefreshResponse } from '../types/lms';

export class AuthTokenService {
    private activeIdToken = env.LMS_ID_TOKEN;
    private activeRefreshToken = env.LMS_REFRESH_TOKEN;
    private activeTokenExpiresAtMs = 0;
    private tokenPromise: Promise<string> | null = null;

    private normalizeJwtSegment(segment: string): string {
        const base64 = segment.replace(/-/g, '+').replace(/_/g, '/');
        const paddingLength = (4 - (base64.length % 4)) % 4;
        return `${base64}${'='.repeat(paddingLength)}`;
    }

    private decodeJwtExp(token: string): number | null {
        const sections = token.split('.');
        if (sections.length < 2) {
            return null;
        }

        try {
            const payloadBuffer = Buffer.from(this.normalizeJwtSegment(sections[1]), 'base64');
            const payload = JSON.parse(payloadBuffer.toString('utf8')) as { exp?: number };
            if (!payload.exp || typeof payload.exp !== 'number') {
                return null;
            }

            return payload.exp * 1000;
        } catch {
            return null;
        }
    }

    private isTokenFresh(expiresAtMs: number): boolean {
        return expiresAtMs - Date.now() > 60_000;
    }

    private hasPasswordCredentials(): boolean {
        return env.FIREBASE_API_KEY.length > 0
            && env.LMS_EMAIL.length > 0
            && env.LMS_PASSWORD.length > 0;
    }

    private hasRefreshCredential(): boolean {
        return env.FIREBASE_API_KEY.length > 0 && this.activeRefreshToken.length > 0;
    }

    private computeExpiryMs(expiresIn: string | undefined, fallbackToken: string): number {
        const expiresInSeconds = Number.parseInt(String(expiresIn ?? ''), 10);
        if (!Number.isNaN(expiresInSeconds) && expiresInSeconds > 0) {
            return Date.now() + expiresInSeconds * 1000;
        }

        return this.decodeJwtExp(fallbackToken) ?? 0;
    }

    private assertAuthConfigured(): void {
        if (this.activeIdToken || this.hasRefreshCredential() || this.hasPasswordCredentials()) {
            return;
        }

        throw new Error(
            'Missing auth configuration. Set LMS_REFRESH_TOKEN + FIREBASE_API_KEY or LMS_EMAIL + LMS_PASSWORD + FIREBASE_API_KEY in backend/.env'
        );
    }

    private async loginWithPassword(): Promise<void> {
        if (!this.hasPasswordCredentials() || !firebaseVerifyPasswordUrl) {
            throw new Error('Password login is not configured');
        }

        const response = await axios.post<FirebaseLoginResponse>(
            firebaseVerifyPasswordUrl,
            {
                email: env.LMS_EMAIL,
                password: env.LMS_PASSWORD,
                returnSecureToken: true
            },
            {
                headers: {
                    'Content-Type': 'application/json'
                }
            }
        );

        const idToken = response.data?.idToken;
        if (!idToken) {
            throw new Error('Firebase did not return idToken');
        }

        this.activeIdToken = idToken;
        if (response.data?.refreshToken) {
            this.activeRefreshToken = response.data.refreshToken;
        }
        this.activeTokenExpiresAtMs = this.computeExpiryMs(response.data?.expiresIn, idToken);
    }

    private async refreshWithStoredToken(): Promise<void> {
        if (!this.hasRefreshCredential() || !firebaseRefreshUrl) {
            throw new Error('Refresh token flow is not configured');
        }

        const body = new URLSearchParams({
            grant_type: 'refresh_token',
            refresh_token: this.activeRefreshToken
        });

        const response = await axios.post<FirebaseRefreshResponse>(
            firebaseRefreshUrl,
            body.toString(),
            {
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded'
                }
            }
        );

        const idToken = response.data?.id_token;
        if (!idToken) {
            throw new Error('Firebase refresh API did not return id_token');
        }

        this.activeIdToken = idToken;
        if (response.data?.refresh_token) {
            this.activeRefreshToken = response.data.refresh_token;
        }
        this.activeTokenExpiresAtMs = this.computeExpiryMs(response.data?.expires_in, idToken);
    }

    async getValidIdToken(forceRefresh: boolean = false): Promise<string> {
        this.assertAuthConfigured();

        if (this.activeIdToken && this.activeTokenExpiresAtMs === 0) {
            this.activeTokenExpiresAtMs = this.decodeJwtExp(this.activeIdToken) ?? 0;
        }

        if (!forceRefresh && this.activeIdToken && this.isTokenFresh(this.activeTokenExpiresAtMs)) {
            return this.activeIdToken;
        }

        if (this.tokenPromise) {
            return this.tokenPromise;
        }

        this.tokenPromise = (async () => {
            if (!forceRefresh && this.activeIdToken && this.isTokenFresh(this.activeTokenExpiresAtMs)) {
                return this.activeIdToken;
            }

            if (this.hasRefreshCredential()) {
                try {
                    await this.refreshWithStoredToken();
                    return this.activeIdToken;
                } catch (error) {
                    if (!this.hasPasswordCredentials()) {
                        throw error;
                    }
                }
            }

            if (this.hasPasswordCredentials()) {
                await this.loginWithPassword();
                return this.activeIdToken;
            }

            if (!forceRefresh && this.activeIdToken) {
                return this.activeIdToken;
            }

            throw new Error('Unable to obtain a valid idToken');
        })();

        try {
            return await this.tokenPromise;
        } finally {
            this.tokenPromise = null;
        }
    }

    getAuthMode(): string {
        if (this.hasRefreshCredential()) {
            return 'refresh-token';
        }
        if (this.hasPasswordCredentials()) {
            return 'email-password';
        }
        if (this.activeIdToken) {
            return 'static-id-token';
        }

        return 'missing-auth';
    }
}
