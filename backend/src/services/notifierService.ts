import admin from 'firebase-admin';
import { env } from '../config/env';
import { Device } from '../db/models/device.model';
import { NotificationEvent } from '../db/models/notification-event.model';
import {
    SlotAttendanceWindow,
    getClassAttendanceWindows,
    isRunningClass
} from './attendanceWindowService';
import { LmsService } from './lmsService';
import { maskToken } from './deviceService';

type NotificationStage = 'UPCOMING' | 'OPEN';

type NotificationCandidate = {
    stage: NotificationStage;
    window: SlotAttendanceWindow;
    title: string;
    body: string;
};

function shouldRemoveInvalidToken(error: unknown): boolean {
    const errorCode = (error as { code?: string })?.code || '';
    return errorCode === 'messaging/registration-token-not-registered'
        || errorCode === 'messaging/invalid-registration-token';
}

export class NotifierService {
    private timer: NodeJS.Timeout | null = null;
    private tickInProgress = false;

    constructor(private readonly lmsService: LmsService) {}

    private get historyTtlMs(): number {
        return env.PUSH_HISTORY_TTL_HOURS * 60 * 60 * 1000;
    }

    private async getMessaging(): Promise<admin.messaging.Messaging | null> {
        if (!env.ENABLE_PUSH_NOTIFIER) {
            return null;
        }

        if (!admin.apps.length) {
            try {
                const hasInlineServiceAccount = Boolean(
                    env.FCM_PROJECT_ID && env.FCM_CLIENT_EMAIL && env.FCM_PRIVATE_KEY
                );

                if (hasInlineServiceAccount) {
                    admin.initializeApp({
                        credential: admin.credential.cert({
                            projectId: env.FCM_PROJECT_ID,
                            clientEmail: env.FCM_CLIENT_EMAIL,
                            privateKey: env.FCM_PRIVATE_KEY
                        })
                    });
                } else {
                    admin.initializeApp();
                }
            } catch (error: any) {
                console.error('Khoi tao FCM that bai:', error?.message || error);
                return null;
            }
        }

        try {
            return admin.messaging();
        } catch (error: any) {
            console.error('Khoi tao Firebase Messaging that bai:', error?.message || error);
            return null;
        }
    }

    private buildNotificationCandidates(
        windows: SlotAttendanceWindow[],
        nowMs: number
    ): NotificationCandidate[] {
        const candidates: NotificationCandidate[] = [];

        windows.forEach((window) => {
            if (window.attendanceCloseAtMs < nowMs) {
                return;
            }

            if (window.isWindowOpen) {
                candidates.push({
                    stage: 'OPEN',
                    window,
                    title: 'Den gio diem danh',
                    body: `${window.className} dang trong khung diem danh`
                });
                return;
            }

            if (window.minutesUntilWindowOpen > 0 && window.minutesUntilWindowOpen <= env.PUSH_LOOKAHEAD_MINUTES) {
                candidates.push({
                    stage: 'UPCOMING',
                    window,
                    title: 'Sap den gio diem danh',
                    body: `${window.className} mo diem danh sau ${window.minutesUntilWindowOpen} phut`
                });
            }
        });

        return candidates;
    }

    private buildDedupeKey(deviceToken: string, candidate: NotificationCandidate): string {
        return [
            deviceToken,
            candidate.stage,
            candidate.window.classId,
            candidate.window.slotId,
            candidate.window.attendanceOpenAt
        ].join('|');
    }

    private async reserveNotificationEvent(
        deviceToken: string,
        candidate: NotificationCandidate,
        nowMs: number
    ): Promise<boolean> {
        const dedupeKey = this.buildDedupeKey(deviceToken, candidate);

        try {
            await NotificationEvent.create({
                dedupeKey,
                token: deviceToken,
                stage: candidate.stage,
                classId: candidate.window.classId,
                slotId: candidate.window.slotId,
                attendanceOpenAt: new Date(candidate.window.attendanceOpenAt),
                status: 'PENDING',
                expiresAt: new Date(nowMs + this.historyTtlMs)
            });
            return true;
        } catch (error: any) {
            if (error?.code === 11000) {
                return false;
            }

            throw error;
        }
    }

    private async markNotificationAsSent(deviceToken: string, candidate: NotificationCandidate): Promise<void> {
        const dedupeKey = this.buildDedupeKey(deviceToken, candidate);
        await NotificationEvent.updateOne(
            { dedupeKey },
            {
                $set: {
                    status: 'SENT',
                    error: null
                }
            }
        );
    }

    private async rollbackPendingNotification(deviceToken: string, candidate: NotificationCandidate, error: unknown): Promise<void> {
        const dedupeKey = this.buildDedupeKey(deviceToken, candidate);
        await NotificationEvent.deleteOne({ dedupeKey, status: 'PENDING' });
        const errorMessage = String((error as { message?: string })?.message || 'unknown error');
        console.error(`Rollback pending notification ${dedupeKey}: ${errorMessage}`);
    }

    async runTick(): Promise<void> {
        if (this.tickInProgress || !env.ENABLE_PUSH_NOTIFIER) {
            return;
        }

        const messaging = await this.getMessaging();
        if (!messaging) {
            return;
        }

        this.tickInProgress = true;
        const nowMs = Date.now();

        try {
            const { classes } = await this.lmsService.fetchUniqueClasses();
            const activeClasses = classes.filter((cls) => isRunningClass(cls, new Date(nowMs)));
            const lookAheadUntilMs = nowMs + env.PUSH_LOOKAHEAD_MINUTES * 60_000;

            const candidateWindows: SlotAttendanceWindow[] = [];
            activeClasses.forEach((cls) => {
                const windows = getClassAttendanceWindows(cls, nowMs);
                windows.forEach((window) => {
                    if (window.attendanceCloseAtMs < nowMs) {
                        return;
                    }
                    if (!window.isWindowOpen && window.attendanceOpenAtMs > lookAheadUntilMs) {
                        return;
                    }
                    candidateWindows.push(window);
                });
            });

            const candidates = this.buildNotificationCandidates(candidateWindows, nowMs);
            if (candidates.length === 0) {
                return;
            }

            const devices = await Device.find({}, { token: 1 }).lean();
            if (devices.length === 0) {
                return;
            }

            let sentCount = 0;
            let duplicateSkipped = 0;
            let invalidTokenRemoved = 0;

            for (const candidate of candidates) {
                for (const device of devices) {
                    const token = device.token;
                    const reserved = await this.reserveNotificationEvent(token, candidate, nowMs);
                    if (!reserved) {
                        duplicateSkipped += 1;
                        continue;
                    }

                    try {
                        await messaging.send({
                            token,
                            notification: {
                                title: candidate.title,
                                body: candidate.body
                            },
                            data: {
                                type: 'attendance_reminder',
                                stage: candidate.stage,
                                classId: candidate.window.classId,
                                className: candidate.window.className,
                                classEndDate: candidate.window.classEndDate ?? '',
                                slotId: candidate.window.slotId,
                                slotStartTime: candidate.window.slotStartTime,
                                slotEndTime: candidate.window.slotEndTime,
                                attendanceOpenAt: candidate.window.attendanceOpenAt,
                                attendanceCloseAt: candidate.window.attendanceCloseAt
                            },
                            android: {
                                priority: 'high'
                            },
                            apns: {
                                headers: {
                                    'apns-priority': '10'
                                }
                            }
                        });

                        await this.markNotificationAsSent(token, candidate);
                        sentCount += 1;
                    } catch (error: any) {
                        await this.rollbackPendingNotification(token, candidate, error);

                        if (shouldRemoveInvalidToken(error)) {
                            await Device.deleteOne({ token });
                            invalidTokenRemoved += 1;
                        } else {
                            console.error(
                                `Gui thong bao that bai cho token ${maskToken(token)}:`,
                                error?.message || error
                            );
                        }
                    }
                }
            }

            if (sentCount > 0 || duplicateSkipped > 0 || invalidTokenRemoved > 0) {
                console.log(
                    `Notifier tick: sent=${sentCount}, duplicateSkipped=${duplicateSkipped}, invalidTokenRemoved=${invalidTokenRemoved}`
                );
            }
        } catch (error: any) {
            console.error('Notifier tick loi:', error?.message || error);
        } finally {
            this.tickInProgress = false;
        }
    }

    start(): void {
        if (!env.ENABLE_PUSH_NOTIFIER) {
            return;
        }

        if (this.timer) {
            clearInterval(this.timer);
        }

        this.timer = setInterval(() => {
            this.runTick().catch((error) => {
                console.error('Notifier interval loi:', error);
            });
        }, env.PUSH_NOTIFIER_INTERVAL_SECONDS * 1000);

        this.runTick().catch((error) => {
            console.error('Notifier first tick loi:', error);
        });
    }

    stop(): void {
        if (this.timer) {
            clearInterval(this.timer);
            this.timer = null;
        }
    }

    async getStatus() {
        const registeredDevices = await Device.countDocuments({});
        return {
            enabled: env.ENABLE_PUSH_NOTIFIER,
            intervalSeconds: env.PUSH_NOTIFIER_INTERVAL_SECONDS,
            lookAheadMinutes: env.PUSH_LOOKAHEAD_MINUTES,
            historyTtlHours: env.PUSH_HISTORY_TTL_HOURS,
            registeredDevices,
            notifierRunning: this.tickInProgress,
            firebaseInitialized: admin.apps.length > 0
        };
    }

    async sendTestNotification(title: string, body: string, token?: string) {
        if (!env.ENABLE_PUSH_NOTIFIER) {
            throw new Error('Push notifier dang tat. Set ENABLE_PUSH_NOTIFIER=true trong backend/.env');
        }

        const messaging = await this.getMessaging();
        if (!messaging) {
            throw new Error('Khong khoi tao duoc Firebase Messaging');
        }

        const targetTokens = token
            ? [token]
            : (await Device.find({}, { token: 1 }).lean()).map((item) => item.token);

        if (targetTokens.length === 0) {
            throw new Error('Khong co token de gui. Dang ky device truoc');
        }

        let sent = 0;
        let failed = 0;
        const failures: Array<{ tokenPreview: string; error: string }> = [];

        for (const targetToken of targetTokens) {
            try {
                await messaging.send({
                    token: targetToken,
                    notification: {
                        title,
                        body
                    },
                    data: {
                        type: 'attendance_reminder_test',
                        sentAt: new Date().toISOString()
                    },
                    android: {
                        priority: 'high'
                    }
                });
                sent += 1;
            } catch (error: any) {
                failed += 1;
                failures.push({
                    tokenPreview: maskToken(targetToken),
                    error: error?.message || 'unknown error'
                });

                if (shouldRemoveInvalidToken(error)) {
                    await Device.deleteOne({ token: targetToken });
                }
            }
        }

        return {
            sent,
            failed,
            failures
        };
    }
}
