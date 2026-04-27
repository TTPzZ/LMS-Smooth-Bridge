import { Router, Request, Response } from 'express';
import { env } from '../config/env';
import { LmsService } from '../services/lmsService';
import {
    getClassAttendanceWindows,
    isRunningClass,
    normalizeClassStatus,
    parseDateToMs,
    toPublicAttendanceWindow
} from '../services/attendanceWindowService';
import { parseBearerToken, parseBooleanQuery, parseIntegerQuery, sanitizePositiveInt } from '../utils/requestParsers';
import { LmsClassRecord, LmsTeacherAssignment, LmsTeacherAttendanceRecord } from '../types/lms';
import { decodeJwtPayload } from '../utils/jwt';

function collectStudents(cls: LmsClassRecord): string[] {
    const studentMap = new Map<string, string>();

    (cls.slots || []).forEach((slot) => {
        (slot.studentAttendance || []).forEach((attendance) => {
            const student = attendance.student;
            if (student?.id && student.fullName) {
                studentMap.set(student.id, student.fullName);
            }
        });
    });

    return Array.from(studentMap.values());
}

type ReminderPrincipal = {
    teacherId?: string | null;
    username?: string | null;
    usernames?: string[];
    fullName?: string | null;
};

function normalizeIdentity(value: string | null | undefined): string {
    return String(value ?? '').trim().toLowerCase();
}

function normalizeComparable(value: string | null | undefined): string {
    return normalizeIdentity(value)
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .replace(/[^a-z0-9]/g, '');
}

function deriveUsernameFromEmail(value: string | null | undefined): string {
    const raw = normalizeIdentity(value);
    if (!raw) {
        return '';
    }

    const at = raw.indexOf('@');
    if (at <= 0) {
        return raw;
    }

    return raw.substring(0, at);
}

function isPrincipalTeacher(
    assignment: LmsTeacherAssignment,
    principal?: ReminderPrincipal | null
): boolean {
    const principalTeacherId = normalizeIdentity(principal?.teacherId);
    const principalUsernames = new Set(
        (principal?.usernames || [principal?.username || ''])
            .map((item) => normalizeIdentity(item))
            .filter(Boolean)
    );
    const principalDerivedUsernames = new Set(
        Array.from(principalUsernames)
            .map((item) => deriveUsernameFromEmail(item))
            .filter(Boolean)
    );
    const principalComparableFullName = normalizeComparable(principal?.fullName);
    const teacherId = normalizeIdentity(assignment.teacher?.id);
    const teacherUsername = normalizeIdentity(assignment.teacher?.username);
    const teacherComparableFullName = normalizeComparable(assignment.teacher?.fullName);

    if (principalTeacherId && teacherId && principalTeacherId === teacherId) {
        return true;
    }

    if (teacherUsername && principalUsernames.has(teacherUsername)) {
        return true;
    }

    if (teacherUsername && principalDerivedUsernames.has(teacherUsername)) {
        return true;
    }

    if (
        principalComparableFullName
        && teacherComparableFullName
        && principalComparableFullName === teacherComparableFullName
    ) {
        return true;
    }

    return false;
}

function collectCoTeachers(
    cls: LmsClassRecord,
    principal?: ReminderPrincipal | null
): string[] {
    const coTeacherMap = new Map<string, string>();
    const assignments: LmsTeacherAssignment[] = [
        ...(cls.teachers || []),
        ...((cls.slots || []).flatMap((slot) => slot.teachers || []))
    ];

    const pushCoTeacher = (assignment: LmsTeacherAssignment) => {
        if (assignment.isActive === false) {
            return;
        }

        if (isPrincipalTeacher(assignment, principal)) {
            return;
        }

        const teacher = assignment.teacher;
        const fullName = String(teacher?.fullName || '').trim();
        const username = String(teacher?.username || '').trim();
        const displayName = String(
            fullName && username && normalizeIdentity(fullName) !== normalizeIdentity(username)
                ? `${fullName} (${username})`
                : fullName || username || teacher?.id || ''
        ).trim();
        if (!displayName) {
            return;
        }

        const dedupeKey = normalizeIdentity(teacher?.id)
            || normalizeIdentity(teacher?.username)
            || normalizeIdentity(displayName);
        if (!dedupeKey) {
            return;
        }

        coTeacherMap.set(dedupeKey, displayName);
    };

    assignments.forEach(pushCoTeacher);

    (cls.slots || []).forEach((slot) => {
        (slot.teacherAttendance || []).forEach((attendance: LmsTeacherAttendanceRecord) => {
            pushCoTeacher({
                isActive: true,
                teacher: attendance.teacher
            });
        });
    });

    return Array.from(coTeacherMap.values());
}

function readPrincipal(req: Request, idTokenFromHeader: string | null | undefined): ReminderPrincipal {
    const tokenPayload = idTokenFromHeader ? decodeJwtPayload(idTokenFromHeader) : null;
    const usernameFromQuery = typeof req.query.username === 'string'
        ? req.query.username.trim()
        : '';
    const usernameFromToken = typeof tokenPayload?.username === 'string'
        ? tokenPayload.username.trim()
        : '';
    const emailFromToken = typeof tokenPayload?.email === 'string'
        ? tokenPayload.email.trim()
        : '';
    const derivedFromEmail = deriveUsernameFromEmail(emailFromToken);

    const usernames = Array.from(new Set([
        usernameFromQuery,
        usernameFromToken,
        emailFromToken,
        derivedFromEmail
    ].map((item) => item.trim()).filter(Boolean)));

    return {
        teacherId: typeof tokenPayload?.user_id === 'string'
            ? tokenPayload.user_id.trim()
            : typeof tokenPayload?.sub === 'string'
                ? tokenPayload.sub.trim()
                : null,
        username: usernames[0] || null,
        usernames,
        fullName: typeof tokenPayload?.name === 'string'
            ? tokenPayload.name.trim()
            : null
    };
}

export function createClassRouter(lmsService: LmsService): Router {
    const router = Router();

    router.get('/classes', async (req: Request, res: Response) => {
        try {
            const idTokenFromHeader = parseBearerToken(req.headers.authorization);
            if (req.headers.authorization && !idTokenFromHeader) {
                res.status(401).json({
                    success: false,
                    error: 'Authorization header khong hop le',
                    detail: 'Expected format: Bearer <id_token>'
                });
                return;
            }

            const itemsPerPage = parseIntegerQuery(req.query.itemsPerPage, env.DEFAULT_ITEMS_PER_PAGE);
            const maxPages = parseIntegerQuery(req.query.maxPages, env.DEFAULT_MAX_PAGES);
            const activeOnly = parseBooleanQuery(req.query.activeOnly, true);
            const now = new Date();
            const nowMs = now.getTime();
            const principal = readPrincipal(req, idTokenFromHeader);

            const {
                classes,
                fetchedPages,
                totalRawClasses,
                totalUniqueClasses
            } = await lmsService.fetchUniqueClasses(itemsPerPage, maxPages, idTokenFromHeader ?? undefined);

            const cleanClasses = classes
                .filter((cls) => (activeOnly ? isRunningClass(cls, now) : true))
                .map((cls) => {
                    const students = collectStudents(cls);
                    const coTeachers = collectCoTeachers(cls, principal);
                    const upcomingWindows = getClassAttendanceWindows(cls, nowMs, principal)
                        .filter((window) => window.attendanceCloseAtMs >= nowMs);
                    const nextAttendanceWindow = upcomingWindows.length > 0
                        ? toPublicAttendanceWindow(upcomingWindows[0])
                        : null;
                    const classEndDateMs = parseDateToMs(cls.endDate);
                    const isClassEnded = classEndDateMs !== null ? classEndDateMs < nowMs : false;

                    return {
                        classId: cls.id,
                        className: cls.name,
                        status: normalizeClassStatus(cls.status) ?? null,
                        endDate: cls.endDate,
                        classEndDate: cls.endDate ?? null,
                        isClassEnded,
                        totalStudents: students.length,
                        students,
                        totalCoTeachers: coTeachers.length,
                        coTeachers,
                        totalSlots: (cls.slots || []).length,
                        nextAttendanceWindow
                    };
                });

            res.json({
                success: true,
                data: cleanClasses,
                meta: {
                    fetchedPages,
                    itemsPerPage,
                    maxPages,
                    activeOnly,
                    totalRawClasses,
                    totalUniqueClasses,
                    returnedClasses: cleanClasses.length
                }
            });
        } catch (error: any) {
            const statusCode = error?.statusCode || error?.response?.status || 500;
            const detail = error?.response?.data || error?.message;
            console.error('Loi:', detail);
            res.status(statusCode).json({
                success: false,
                error: 'Loi ket noi API',
                detail
            });
        }
    });

    router.get('/attendance-reminders', async (req: Request, res: Response) => {
        try {
            const idTokenFromHeader = parseBearerToken(req.headers.authorization);
            if (req.headers.authorization && !idTokenFromHeader) {
                res.status(401).json({
                    success: false,
                    error: 'Authorization header khong hop le',
                    detail: 'Expected format: Bearer <id_token>'
                });
                return;
            }

            const itemsPerPage = parseIntegerQuery(req.query.itemsPerPage, env.DEFAULT_ITEMS_PER_PAGE);
            const maxPages = parseIntegerQuery(req.query.maxPages, env.DEFAULT_MAX_PAGES);
            const activeOnly = parseBooleanQuery(req.query.activeOnly, true);
            const lookAheadMinutes = sanitizePositiveInt(req.query.lookAheadMinutes, env.DEFAULT_LOOKAHEAD_MINUTES);
            const maxSlots = sanitizePositiveInt(req.query.maxSlots, env.DEFAULT_MAX_REMINDER_SLOTS);
            const now = new Date();
            const nowMs = now.getTime();
            const lookAheadUntilMs = nowMs + lookAheadMinutes * 60_000;
            const principal = readPrincipal(req, idTokenFromHeader);

            const {
                classes,
                fetchedPages,
                totalRawClasses,
                totalUniqueClasses
            } = await lmsService.fetchUniqueClasses(itemsPerPage, maxPages, idTokenFromHeader ?? undefined);

            const filteredClasses = classes.filter((cls) => (activeOnly ? isRunningClass(cls, now) : true));
            const windows = filteredClasses.flatMap((cls) => getClassAttendanceWindows(cls, nowMs, principal))
                .filter((window) => window.attendanceCloseAtMs >= nowMs)
                .filter((window) => window.attendanceOpenAtMs <= lookAheadUntilMs)
                .sort((a, b) => {
                    if (a.attendanceOpenAtMs !== b.attendanceOpenAtMs) {
                        return a.attendanceOpenAtMs - b.attendanceOpenAtMs;
                    }
                    return a.className.localeCompare(b.className);
                });

            const reminders = windows.slice(0, maxSlots).map((window) => toPublicAttendanceWindow(window));

            res.json({
                success: true,
                data: reminders,
                meta: {
                    now: now.toISOString(),
                    lookAheadMinutes,
                    lookAheadUntil: new Date(lookAheadUntilMs).toISOString(),
                    maxSlots,
                    fetchedPages,
                    itemsPerPage,
                    maxPages,
                    activeOnly,
                    totalRawClasses,
                    totalUniqueClasses,
                    scannedClasses: filteredClasses.length,
                    matchedSlots: windows.length,
                    returnedSlots: reminders.length
                }
            });
        } catch (error: any) {
            const statusCode = error?.statusCode || error?.response?.status || 500;
            const detail = error?.response?.data || error?.message;
            console.error('Loi:', detail);
            res.status(statusCode).json({
                success: false,
                error: 'Loi ket noi API',
                detail
            });
        }
    });

    return router;
}
