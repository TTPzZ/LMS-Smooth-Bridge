import admin from 'firebase-admin';
import { env } from '../config/env';
import { Device } from '../db/models/device.model';
import { NotificationEvent } from '../db/models/notification-event.model';
import { LmsClassRecord, LmsSlotRecord, LmsStudentAttendanceRecord } from '../types/lms';
import {
    SlotAttendanceWindow,
    getClassAttendanceWindows,
    isRunningClass,
    parseDateToMs
} from './attendanceWindowService';
import { LmsService } from './lmsService';
import { maskToken } from './deviceService';

type NotificationStage = 'UPCOMING' | 'OPEN' | 'COMMENT_PENDING_NOON';

type NotificationCandidate = {
    stage: NotificationStage;
    classId: string;
    className: string;
    slotId: string;
    eventTimeIso: string;
    dedupeSuffix: string;
    title: string;
    body: string;
    data: Record<string, string>;
};

type PendingCommentClass = {
    classId: string;
    className: string;
    slotId: string;
    slotStartTime: string;
    slotEndTime: string;
    missingCommentStudentCount: number;
    missingCommentStudents: string[];
};

const COMMENT_REMINDER_TIMEZONE = 'Asia/Ho_Chi_Minh';
const COMMENT_REMINDER_HOUR = 12;
const COMMENT_REMINDER_WINDOW_MINUTES = 20;

function shouldRemoveInvalidToken(error: unknown): boolean {
    const errorCode = (error as { code?: string })?.code || '';
    return errorCode === 'messaging/registration-token-not-registered'
        || errorCode === 'messaging/invalid-registration-token';
}

function normalizeIdentity(value: string | null | undefined): string {
    return String(value ?? '').trim().toLowerCase();
}

function normalizeComparable(value: string | null | undefined): string {
    return normalizeIdentity(value)
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .replace(/[^a-z0-9]/g, '');
}

function normalizeCommentText(value: unknown): string {
    return String(value ?? '').replace(/\s+/g, ' ').trim();
}

function extractNarrativeCommentFromHtml(content: string): string {
    const plain = String(content ?? '')
        .replace(/<[^>]*>/g, ' ')
        .replace(/&nbsp;/gi, ' ')
        .replace(/\s+/g, ' ')
        .trim();
    if (!plain) {
        return '';
    }

    const labelMatch = /nhan\s*xet\s*:?\s*(.+)$/i.exec(plain);
    if (labelMatch?.[1]) {
        return normalizeCommentText(labelMatch[1]);
    }

    return normalizeCommentText(plain);
}

function readAttendanceCommentText(attendance?: LmsStudentAttendanceRecord | null): string {
    if (!attendance) {
        return '';
    }

    const richContent = String(
        (attendance.commentByAreas || []).find((item) => String(item?.content ?? '').trim())?.content ?? ''
    ).trim();
    const rawSource = richContent
        || String(attendance.comment ?? '').trim()
        || String(attendance.note ?? '').trim();
    if (!rawSource) {
        return '';
    }

    return extractNarrativeCommentFromHtml(rawSource);
}

function getStartOfWeekMs(date: Date): number {
    const local = new Date(date.getTime());
    const day = local.getDay();
    const daysFromMonday = (day + 6) % 7;
    local.setHours(0, 0, 0, 0);
    local.setDate(local.getDate() - daysFromMonday);
    return local.getTime();
}

function findPreviousWeekCommentSlot(
    cls: LmsClassRecord,
    currentWeekStartMs: number
): LmsSlotRecord | null {
    const previousWeekStartMs = currentWeekStartMs - (7 * 24 * 60 * 60 * 1000);
    const slotsWithStart = (cls.slots || [])
        .flatMap((slot) => {
            const startMs = parseDateToMs(slot.startTime ?? slot.date);
            if (startMs === null) {
                return [];
            }
            return [{
                slot,
                startMs
            }];
        })
        .sort((a, b) => a.startMs - b.startMs);

    const previousWeekSlots = slotsWithStart.filter((item) =>
        item.startMs >= previousWeekStartMs
        && item.startMs < currentWeekStartMs
    );

    if (previousWeekSlots.length === 0) {
        return null;
    }

    return previousWeekSlots[previousWeekSlots.length - 1].slot;
}

function collectMissingCommentStudents(
    cls: LmsClassRecord,
    slot: LmsSlotRecord
): string[] {
    const activeClassStudents = (cls.students || []).filter((item) => item.activeInClass !== false);
    if (activeClassStudents.length === 0) {
        return [];
    }

    const attendanceByStudentId = new Map<string, LmsStudentAttendanceRecord>();
    const attendanceByStudentName = new Map<string, LmsStudentAttendanceRecord>();
    (slot.studentAttendance || []).forEach((attendance) => {
        const studentId = normalizeIdentity(attendance.student?.id);
        if (studentId && !attendanceByStudentId.has(studentId)) {
            attendanceByStudentId.set(studentId, attendance);
        }

        const studentName = normalizeComparable(attendance.student?.fullName);
        if (studentName && !attendanceByStudentName.has(studentName)) {
            attendanceByStudentName.set(studentName, attendance);
        }
    });

    const missingStudents: string[] = [];
    activeClassStudents.forEach((classStudent) => {
        const name = String(classStudent.student?.fullName ?? '').trim();
        if (!name) {
            return;
        }

        const studentId = normalizeIdentity(classStudent.student?.id);
        const attendance = (studentId ? attendanceByStudentId.get(studentId) : null)
            || attendanceByStudentName.get(normalizeComparable(name))
            || null;
        const hasComment = normalizeCommentText(readAttendanceCommentText(attendance)).length > 0;
        if (!hasComment) {
            missingStudents.push(name);
        }
    });

    return Array.from(new Set(missingStudents));
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

    private buildAttendanceNotificationCandidates(
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
                    classId: window.classId,
                    className: window.className,
                    slotId: window.slotId,
                    eventTimeIso: window.attendanceOpenAt,
                    dedupeSuffix: window.attendanceOpenAt,
                    title: 'Den gio diem danh',
                    body: `${window.className} dang trong khung diem danh`,
                    data: {
                        type: 'attendance_reminder',
                        stage: 'OPEN',
                        classId: window.classId,
                        className: window.className,
                        classEndDate: window.classEndDate ?? '',
                        slotId: window.slotId,
                        slotStartTime: window.slotStartTime,
                        slotEndTime: window.slotEndTime,
                        attendanceOpenAt: window.attendanceOpenAt,
                        attendanceCloseAt: window.attendanceCloseAt
                    }
                });
                return;
            }

            if (window.minutesUntilWindowOpen > 0 && window.minutesUntilWindowOpen <= env.PUSH_LOOKAHEAD_MINUTES) {
                candidates.push({
                    stage: 'UPCOMING',
                    classId: window.classId,
                    className: window.className,
                    slotId: window.slotId,
                    eventTimeIso: window.attendanceOpenAt,
                    dedupeSuffix: window.attendanceOpenAt,
                    title: 'Sap den gio diem danh',
                    body: `${window.className} mo diem danh sau ${window.minutesUntilWindowOpen} phut`,
                    data: {
                        type: 'attendance_reminder',
                        stage: 'UPCOMING',
                        classId: window.classId,
                        className: window.className,
                        classEndDate: window.classEndDate ?? '',
                        slotId: window.slotId,
                        slotStartTime: window.slotStartTime,
                        slotEndTime: window.slotEndTime,
                        attendanceOpenAt: window.attendanceOpenAt,
                        attendanceCloseAt: window.attendanceCloseAt
                    }
                });
            }
        });

        return candidates;
    }

    private getTimeZoneParts(
        nowMs: number,
        timeZone: string
    ): { year: string; month: string; day: string; hour: number; minute: number } {
        const formatter = new Intl.DateTimeFormat('en-US', {
            timeZone,
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            hour12: false
        });
        const parts = formatter.formatToParts(new Date(nowMs));
        const get = (type: Intl.DateTimeFormatPartTypes): string =>
            parts.find((part) => part.type === type)?.value ?? '';

        return {
            year: get('year'),
            month: get('month'),
            day: get('day'),
            hour: Number.parseInt(get('hour'), 10),
            minute: Number.parseInt(get('minute'), 10)
        };
    }

    private getNoonReminderContext(
        nowMs: number
    ): { enabled: boolean; dateKey: string; eventTimeIso: string } {
        const parts = this.getTimeZoneParts(nowMs, COMMENT_REMINDER_TIMEZONE);
        const isValidHour = Number.isFinite(parts.hour) && parts.hour === COMMENT_REMINDER_HOUR;
        const isValidMinute = Number.isFinite(parts.minute) && parts.minute >= 0 && parts.minute < COMMENT_REMINDER_WINDOW_MINUTES;
        if (!isValidHour || !isValidMinute) {
            return {
                enabled: false,
                dateKey: '',
                eventTimeIso: new Date(nowMs).toISOString()
            };
        }

        const dateKey = `${parts.year}-${parts.month}-${parts.day}`;
        return {
            enabled: true,
            dateKey,
            eventTimeIso: new Date(nowMs).toISOString()
        };
    }

    private collectPendingCommentClasses(
        classes: LmsClassRecord[],
        nowMs: number
    ): PendingCommentClass[] {
        const now = new Date(nowMs);
        const currentWeekStartMs = getStartOfWeekMs(now);
        const pending: PendingCommentClass[] = [];

        classes.forEach((cls) => {
            const slot = findPreviousWeekCommentSlot(cls, currentWeekStartMs);
            if (!slot?._id) {
                return;
            }

            const missingCommentStudents = collectMissingCommentStudents(cls, slot);
            if (missingCommentStudents.length === 0) {
                return;
            }

            pending.push({
                classId: cls.id,
                className: cls.name,
                slotId: slot._id,
                slotStartTime: slot.startTime ?? slot.date ?? '',
                slotEndTime: slot.endTime ?? '',
                missingCommentStudentCount: missingCommentStudents.length,
                missingCommentStudents
            });
        });

        return pending;
    }

    private buildNoonCommentReminderCandidates(
        classes: LmsClassRecord[],
        nowMs: number
    ): NotificationCandidate[] {
        const reminderContext = this.getNoonReminderContext(nowMs);
        if (!reminderContext.enabled) {
            return [];
        }

        const pendingClasses = this.collectPendingCommentClasses(classes, nowMs);
        if (pendingClasses.length === 0) {
            return [];
        }

        return pendingClasses.map((item) => ({
            stage: 'COMMENT_PENDING_NOON',
            classId: item.classId,
            className: item.className,
            slotId: item.slotId,
            eventTimeIso: reminderContext.eventTimeIso,
            dedupeSuffix: reminderContext.dateKey,
            title: 'Nhac nho nhan xet hoc vien',
            body: `${item.className}: con ${item.missingCommentStudentCount} hoc vien chua nhan xet`,
            data: {
                type: 'comment_reminder',
                stage: 'COMMENT_PENDING_NOON',
                classId: item.classId,
                className: item.className,
                slotId: item.slotId,
                slotStartTime: item.slotStartTime,
                slotEndTime: item.slotEndTime,
                missingCommentStudentCount: String(item.missingCommentStudentCount),
                missingCommentStudents: item.missingCommentStudents.join(' | '),
                reminderDate: reminderContext.dateKey
            }
        }));
    }

    private buildDedupeKey(deviceToken: string, candidate: NotificationCandidate): string {
        return [
            deviceToken,
            candidate.stage,
            candidate.classId,
            candidate.slotId,
            candidate.dedupeSuffix
        ].join('|');
    }

    private async reserveNotificationEvent(
        deviceToken: string,
        candidate: NotificationCandidate,
        nowMs: number
    ): Promise<boolean> {
        const dedupeKey = this.buildDedupeKey(deviceToken, candidate);
        const eventAt = new Date(candidate.eventTimeIso);

        try {
            await NotificationEvent.create({
                dedupeKey,
                token: deviceToken,
                stage: candidate.stage,
                classId: candidate.classId,
                slotId: candidate.slotId,
                attendanceOpenAt: Number.isNaN(eventAt.getTime()) ? new Date(nowMs) : eventAt,
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

    private async rollbackPendingNotification(
        deviceToken: string,
        candidate: NotificationCandidate,
        error: unknown
    ): Promise<void> {
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

            const attendanceCandidates = this.buildAttendanceNotificationCandidates(candidateWindows, nowMs);
            const commentCandidates = this.buildNoonCommentReminderCandidates(activeClasses, nowMs);
            const candidates = [...attendanceCandidates, ...commentCandidates];
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
                            data: candidate.data,
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
            commentReminderHour: COMMENT_REMINDER_HOUR,
            commentReminderWindowMinutes: COMMENT_REMINDER_WINDOW_MINUTES,
            commentReminderTimeZone: COMMENT_REMINDER_TIMEZONE,
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
