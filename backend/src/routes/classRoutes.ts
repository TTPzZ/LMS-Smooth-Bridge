import { Router, Request, Response } from 'express';
import { env } from '../config/env';
import { LmsService } from '../services/lmsService';
import {
    getClassAttendanceWindows,
    isRunningClass,
    normalizeClassStatus,
    parseDateToMs,
    shouldIncludeSlotForPrincipal,
    toPublicAttendanceWindow
} from '../services/attendanceWindowService';
import { parseBearerToken, parseBooleanQuery, parseIntegerQuery, sanitizePositiveInt } from '../utils/requestParsers';
import {
    LmsClassRecord,
    LmsSlotAttendanceCommand,
    LmsSlotAttendanceStatus,
    LmsStudentAttendancePayload,
    LmsTeacherAssignment,
    LmsTeacherAttendancePayload,
    LmsTeacherAttendanceRecord
} from '../types/lms';
import { decodeJwtPayload } from '../utils/jwt';

function collectStudentsForPrincipal(
    cls: LmsClassRecord,
    principal?: ReminderPrincipal | null
): string[] {
    const studentMap = new Map<string, string>();

    (cls.slots || []).forEach((slot) => {
        if (!shouldIncludeSlotForPrincipal(cls, slot, principal)) {
            return;
        }
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
    const scopedSlots = (cls.slots || []).filter((slot) =>
        shouldIncludeSlotForPrincipal(cls, slot, principal)
    );
    const hasScopedSlots = scopedSlots.length > 0;
    const hasPrincipal =
        Boolean(normalizeIdentity(principal?.teacherId))
        || Boolean(
            (principal?.usernames || [])
                .map((item) => normalizeIdentity(item))
                .filter(Boolean).length > 0
        )
        || Boolean(normalizeComparable(principal?.fullName))
        || Boolean(normalizeIdentity(principal?.username));
    const hasSlotLevelTeacherData = (cls.slots || []).some((slot) =>
        (slot.teachers || []).length > 0 || (slot.teacherAttendance || []).length > 0
    );
    const allowClassWideFallback = !hasPrincipal || !hasSlotLevelTeacherData;

    const assignments: LmsTeacherAssignment[] = hasScopedSlots
        ? [
            ...(scopedSlots.flatMap((slot) => slot.teachers || []))
        ]
        : allowClassWideFallback
            ? [
            ...(cls.teachers || []),
            ...((cls.slots || []).flatMap((slot) => slot.teachers || []))
        ]
            : [];

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

    const attendanceSlots = hasScopedSlots
        ? scopedSlots
        : allowClassWideFallback
            ? (cls.slots || [])
            : [];
    attendanceSlots.forEach((slot) => {
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

const SLOT_ATTENDANCE_STATUSES: LmsSlotAttendanceStatus[] = [
    'ATTENDED',
    'LATE_ARRIVED',
    'ABSENT_WITH_NOTICE',
    'ABSENT'
];
const SLOT_ATTENDANCE_STATUS_SET = new Set<string>(SLOT_ATTENDANCE_STATUSES);

type AttendanceSaveParticipantInput = {
    key: string;
    name: string;
    isCoTeacher: boolean;
    status: LmsSlotAttendanceStatus;
};

type AttendanceSaveRequestPayload = {
    classId: string;
    slotId: string;
    participants: AttendanceSaveParticipantInput[];
};

type AttendanceSaveUnresolvedParticipant = {
    key: string;
    name: string;
    isCoTeacher: boolean;
    reason: 'not_found' | 'ambiguous';
};

function buildParticipantKey(name: string, isCoTeacher: boolean): string {
    const kind = isCoTeacher ? 'co_teacher' : 'student';
    return `${kind}::${name.trim()}`;
}

function parseSlotAttendanceStatus(value: unknown): LmsSlotAttendanceStatus | null {
    const normalized = String(value ?? '').trim().toUpperCase();
    if (!normalized || !SLOT_ATTENDANCE_STATUS_SET.has(normalized)) {
        return null;
    }

    return normalized as LmsSlotAttendanceStatus;
}

function parseAttendanceSaveRequestBody(body: unknown): AttendanceSaveRequestPayload | null {
    if (!body || typeof body !== 'object') {
        return null;
    }

    const payload = body as {
        classId?: unknown;
        slotId?: unknown;
        participants?: unknown;
    };
    const classId = String(payload.classId ?? '').trim();
    const slotId = String(payload.slotId ?? '').trim();
    if (!classId || !slotId) {
        return null;
    }

    if (!Array.isArray(payload.participants)) {
        return {
            classId,
            slotId,
            participants: []
        };
    }

    const deduped = new Map<string, AttendanceSaveParticipantInput>();
    payload.participants.forEach((rawItem) => {
        if (!rawItem || typeof rawItem !== 'object') {
            return;
        }

        const item = rawItem as {
            key?: unknown;
            name?: unknown;
            isCoTeacher?: unknown;
            status?: unknown;
        };
        const name = String(item.name ?? '').trim();
        if (!name) {
            return;
        }

        const status = parseSlotAttendanceStatus(item.status);
        if (!status) {
            return;
        }

        const isCoTeacher = item.isCoTeacher === true;
        const keyFromBody = String(item.key ?? '').trim();
        const key = keyFromBody || buildParticipantKey(name, isCoTeacher);

        deduped.set(key, {
            key,
            name,
            isCoTeacher,
            status
        });
    });

    return {
        classId,
        slotId,
        participants: Array.from(deduped.values())
    };
}

function parseTeacherDisplayName(
    value: string
): { displayName: string; fullNamePart: string; usernameHint: string } {
    const displayName = String(value ?? '').trim();
    if (!displayName) {
        return {
            displayName: '',
            fullNamePart: '',
            usernameHint: ''
        };
    }

    const match = /^(.*?)\s*\(([^()]+)\)\s*$/.exec(displayName);
    if (!match) {
        return {
            displayName,
            fullNamePart: displayName,
            usernameHint: ''
        };
    }

    return {
        displayName,
        fullNamePart: String(match[1] ?? '').trim(),
        usernameHint: String(match[2] ?? '').trim()
    };
}

function collectTeacherMatchKeys(inputName: string): string[] {
    const parsed = parseTeacherDisplayName(inputName);
    const keys = new Set<string>();

    const pushRaw = (value: string) => {
        const normalizedIdentity = normalizeIdentity(value);
        if (normalizedIdentity) {
            keys.add(`id:${normalizedIdentity}`);
        }

        const normalizedComparable = normalizeComparable(value);
        if (normalizedComparable) {
            keys.add(`cmp:${normalizedComparable}`);
        }
    };

    pushRaw(parsed.displayName);
    pushRaw(parsed.fullNamePart);
    pushRaw(parsed.usernameHint);

    return Array.from(keys);
}

function collectTeacherRecordKeys(teacher?: { fullName?: string; username?: string; id?: string }): string[] {
    const keys = new Set<string>();
    const pushRaw = (value: string | null | undefined) => {
        const normalizedIdentity = normalizeIdentity(value);
        if (normalizedIdentity) {
            keys.add(`id:${normalizedIdentity}`);
        }

        const normalizedComparable = normalizeComparable(value);
        if (normalizedComparable) {
            keys.add(`cmp:${normalizedComparable}`);
        }
    };

    pushRaw(teacher?.fullName);
    pushRaw(teacher?.username);
    pushRaw(teacher?.id);

    return Array.from(keys);
}

function collectStudentMatchKeys(inputName: string): string[] {
    const keys = new Set<string>();
    const normalizedIdentity = normalizeIdentity(inputName);
    if (normalizedIdentity) {
        keys.add(`id:${normalizedIdentity}`);
    }
    const normalizedComparable = normalizeComparable(inputName);
    if (normalizedComparable) {
        keys.add(`cmp:${normalizedComparable}`);
    }
    return Array.from(keys);
}

function collectStudentRecordKeys(student?: { fullName?: string; id?: string }): string[] {
    const keys = new Set<string>();
    const fullNameIdentity = normalizeIdentity(student?.fullName);
    if (fullNameIdentity) {
        keys.add(`id:${fullNameIdentity}`);
    }
    const fullNameComparable = normalizeComparable(student?.fullName);
    if (fullNameComparable) {
        keys.add(`cmp:${fullNameComparable}`);
    }
    const studentIdIdentity = normalizeIdentity(student?.id);
    if (studentIdIdentity) {
        keys.add(`id:${studentIdIdentity}`);
    }
    return Array.from(keys);
}

function addToLookupIndex<T>(index: Map<string, T[]>, key: string, value: T): void {
    if (!key) {
        return;
    }

    const current = index.get(key);
    if (!current) {
        index.set(key, [value]);
        return;
    }

    current.push(value);
}

function createLookupIndex<T>(
    records: T[],
    keyBuilder: (record: T) => string[]
): Map<string, T[]> {
    const index = new Map<string, T[]>();
    records.forEach((record) => {
        keyBuilder(record).forEach((key) => {
            addToLookupIndex(index, key, record);
        });
    });
    return index;
}

function findSingleMatchByKeys<T>(
    index: Map<string, T[]>,
    keys: string[],
    stableIdBuilder: (record: T) => string
): { item: T | null; reason?: 'not_found' | 'ambiguous' } {
    const matched = new Map<string, T>();
    let fallbackCounter = 0;

    keys.forEach((key) => {
        const bucket = index.get(key);
        if (!bucket || bucket.length === 0) {
            return;
        }

        bucket.forEach((record) => {
            const stable = normalizeIdentity(stableIdBuilder(record));
            const finalStable = stable || `fallback_${fallbackCounter += 1}`;
            if (!matched.has(finalStable)) {
                matched.set(finalStable, record);
            }
        });
    });

    if (matched.size === 1) {
        return {
            item: Array.from(matched.values())[0]
        };
    }

    if (matched.size > 1) {
        return {
            item: null,
            reason: 'ambiguous'
        };
    }

    return {
        item: null,
        reason: 'not_found'
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
                    const students = collectStudentsForPrincipal(cls, principal);
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

    router.post('/attendance/slot', async (req: Request, res: Response) => {
        try {
            const idTokenFromHeader = parseBearerToken(req.headers.authorization);
            if (!idTokenFromHeader) {
                res.status(401).json({
                    success: false,
                    error: 'Authorization header khong hop le',
                    detail: 'Expected format: Bearer <id_token>'
                });
                return;
            }

            const parsedBody = parseAttendanceSaveRequestBody(req.body);
            if (!parsedBody) {
                res.status(400).json({
                    success: false,
                    error: 'Payload khong hop le',
                    detail: 'Can classId, slotId va participants[]'
                });
                return;
            }

            const { classId, slotId, participants } = parsedBody;
            if (participants.length === 0) {
                res.status(400).json({
                    success: false,
                    error: 'Khong co du lieu diem danh',
                    detail: 'participants[] dang rong hoac khong co trang thai hop le'
                });
                return;
            }

            const cls = await lmsService.getClassByIdForAttendance(classId, idTokenFromHeader);
            if (!cls) {
                res.status(404).json({
                    success: false,
                    error: 'Khong tim thay lop hoc',
                    detail: `classId=${classId}`
                });
                return;
            }

            const slot = (cls.slots || []).find((item) => normalizeIdentity(item._id) === normalizeIdentity(slotId));
            if (!slot?._id) {
                res.status(404).json({
                    success: false,
                    error: 'Khong tim thay buoi hoc',
                    detail: `classId=${classId}, slotId=${slotId}`
                });
                return;
            }

            const activeClassStudents = (cls.students || []).filter((item) => item.activeInClass !== false);
            const slotStudentAttendance = slot.studentAttendance || [];
            const slotTeacherAttendance = slot.teacherAttendance || [];

            const teacherAssignmentMap = new Map<string, LmsTeacherAssignment>();
            [...(cls.teachers || []), ...(slot.teachers || [])].forEach((assignment) => {
                if (assignment.isActive === false) {
                    return;
                }
                const teacherId = normalizeIdentity(assignment.teacher?.id);
                const teacherUsername = normalizeIdentity(assignment.teacher?.username);
                const classSiteId = normalizeIdentity(assignment.classSiteId);
                const stableKey = [teacherId, teacherUsername, classSiteId].filter(Boolean).join('::');
                if (!stableKey) {
                    return;
                }

                if (!teacherAssignmentMap.has(stableKey)) {
                    teacherAssignmentMap.set(stableKey, assignment);
                }
            });
            const teacherAssignments = Array.from(teacherAssignmentMap.values());

            const studentAttendanceIndex = createLookupIndex(
                slotStudentAttendance,
                (record) => collectStudentRecordKeys(record.student)
            );
            const classStudentIndex = createLookupIndex(
                activeClassStudents,
                (record) => collectStudentRecordKeys(record.student)
            );
            const teacherAttendanceIndex = createLookupIndex(
                slotTeacherAttendance,
                (record) => collectTeacherRecordKeys(record.teacher)
            );
            const teacherAssignmentIndex = createLookupIndex(
                teacherAssignments,
                (record) => collectTeacherRecordKeys(record.teacher)
            );

            const studentPayloadMap = new Map<string, LmsStudentAttendancePayload>();
            const teacherPayloadMap = new Map<string, LmsTeacherAttendancePayload>();
            const unresolvedParticipants: AttendanceSaveUnresolvedParticipant[] = [];
            const appliedParticipantKeys = new Set<string>();

            participants.forEach((participant) => {
                if (participant.isCoTeacher) {
                    const lookupKeys = collectTeacherMatchKeys(participant.name);
                    const attendanceMatch = findSingleMatchByKeys(
                        teacherAttendanceIndex,
                        lookupKeys,
                        (record) =>
                            record.teacher?.id
                            || record._id
                            || record.teacher?.username
                            || record.teacher?.fullName
                            || ''
                    );

                    if (attendanceMatch.item) {
                        const attendance = attendanceMatch.item;
                        const payload: LmsTeacherAttendancePayload = {
                            _id: attendance._id,
                            teacher: attendance.teacher?.id,
                            status: participant.status,
                            note: attendance.note ?? undefined,
                            classSiteId: attendance.classSiteId ?? undefined
                        };
                        const dedupeKey = normalizeIdentity(attendance._id)
                            || [
                                'teacher',
                                normalizeIdentity(attendance.teacher?.id),
                                normalizeIdentity(attendance.classSiteId)
                            ].join(':');
                        if (payload._id || payload.teacher) {
                            teacherPayloadMap.set(dedupeKey, payload);
                            appliedParticipantKeys.add(participant.key);
                            return;
                        }
                    }

                    const assignmentMatch = findSingleMatchByKeys(
                        teacherAssignmentIndex,
                        lookupKeys,
                        (record) =>
                            record.teacher?.id
                            || record._id
                            || record.teacher?.username
                            || record.teacher?.fullName
                            || ''
                    );
                    const assignmentTeacherId = assignmentMatch.item?.teacher?.id;
                    if (assignmentTeacherId) {
                        const assignment = assignmentMatch.item;
                        const payload: LmsTeacherAttendancePayload = {
                            teacher: assignmentTeacherId,
                            status: participant.status,
                            classSiteId: assignment?.classSiteId ?? undefined
                        };
                        const dedupeKey = [
                            'teacher',
                            normalizeIdentity(payload.teacher),
                            normalizeIdentity(payload.classSiteId)
                        ].join(':');
                        teacherPayloadMap.set(dedupeKey, payload);
                        appliedParticipantKeys.add(participant.key);
                        return;
                    }

                    unresolvedParticipants.push({
                        key: participant.key,
                        name: participant.name,
                        isCoTeacher: true,
                        reason: attendanceMatch.reason === 'ambiguous' || assignmentMatch.reason === 'ambiguous'
                            ? 'ambiguous'
                            : 'not_found'
                    });
                    return;
                }

                const lookupKeys = collectStudentMatchKeys(participant.name);
                const attendanceMatch = findSingleMatchByKeys(
                    studentAttendanceIndex,
                    lookupKeys,
                    (record) =>
                        record.student?.id
                        || record._id
                        || record.student?.fullName
                        || ''
                );
                if (attendanceMatch.item) {
                    const attendance = attendanceMatch.item;
                    const payload: LmsStudentAttendancePayload = {
                        _id: attendance._id,
                        student: attendance.student?.id,
                        status: participant.status,
                        note: attendance.note ?? attendance.comment ?? undefined
                    };
                    const dedupeKey = normalizeIdentity(attendance._id)
                        || ['student', normalizeIdentity(attendance.student?.id)].join(':');
                    if (payload._id || payload.student) {
                        studentPayloadMap.set(dedupeKey, payload);
                        appliedParticipantKeys.add(participant.key);
                        return;
                    }
                }

                const classStudentMatch = findSingleMatchByKeys(
                    classStudentIndex,
                    lookupKeys,
                    (record) =>
                        record.student?.id
                        || record._id
                        || record.student?.fullName
                        || ''
                );
                if (classStudentMatch.item?.student?.id) {
                    const payload: LmsStudentAttendancePayload = {
                        student: classStudentMatch.item.student.id,
                        status: participant.status
                    };
                    const dedupeKey = ['student', normalizeIdentity(payload.student)].join(':');
                    studentPayloadMap.set(dedupeKey, payload);
                    appliedParticipantKeys.add(participant.key);
                    return;
                }

                unresolvedParticipants.push({
                    key: participant.key,
                    name: participant.name,
                    isCoTeacher: false,
                    reason: attendanceMatch.reason === 'ambiguous' || classStudentMatch.reason === 'ambiguous'
                        ? 'ambiguous'
                        : 'not_found'
                });
            });

            const command: LmsSlotAttendanceCommand = {
                classId,
                slotId,
                studentAttendance: Array.from(studentPayloadMap.values()),
                teacherAttendance: Array.from(teacherPayloadMap.values())
            };

            const totalApplied = (command.studentAttendance || []).length + (command.teacherAttendance || []).length;
            if (totalApplied === 0) {
                res.status(400).json({
                    success: false,
                    error: 'Khong map duoc nguoi diem danh',
                    detail: {
                        requestedParticipants: participants.length,
                        unresolvedParticipants
                    }
                });
                return;
            }

            await lmsService.updateSlotAttendance(command, idTokenFromHeader);

            res.json({
                success: true,
                data: {
                    classId,
                    slotId,
                    requestedParticipants: participants.length,
                    appliedParticipants: totalApplied,
                    updatedStudents: (command.studentAttendance || []).length,
                    updatedTeachers: (command.teacherAttendance || []).length,
                    appliedParticipantKeys: Array.from(appliedParticipantKeys.values()),
                    unresolvedParticipants
                }
            });
        } catch (error: any) {
            const statusCode = error?.statusCode || error?.response?.status || 500;
            const detail = error?.response?.data || error?.message;
            console.error('Loi:', detail);
            res.status(statusCode).json({
                success: false,
                error: 'Loi luu diem danh',
                detail
            });
        }
    });

    return router;
}
