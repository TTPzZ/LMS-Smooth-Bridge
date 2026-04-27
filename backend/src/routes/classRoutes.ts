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
    LmsClassStudent,
    LmsCommentArea,
    LmsCourseProcess,
    LmsSlotRecord,
    LmsSlotAttendanceCommand,
    LmsSlotAttendanceStatus,
    LmsStudentAttendanceRecord,
    LmsStudentAttendancePayload,
    LmsTeacherAssignment,
    LmsTeacherAttendancePayload,
    LmsTeacherAttendanceRecord,
    LmsUpdateSlotCommentCommand
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

type AttendanceCommentInput = {
    key: string;
    name: string;
    studentId?: string;
    studentAttendanceId?: string;
    classSiteId?: string;
    courseProcessId?: string;
    sessionNumber?: number;
    commentAreaId?: string;
    kienThucScore?: number;
    kyNangScore?: number;
    thaiDoScore?: number;
    comment?: string;
};

type AttendanceCommentRequestPayload = {
    classId: string;
    slotId: string;
    comments: AttendanceCommentInput[];
};

type AttendanceCommentUnresolvedParticipant = {
    key: string;
    name: string;
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

function normalizeCommentText(value: unknown): string {
    const normalized = String(value ?? '')
        .replace(/\r\n/g, '\n')
        .trim();

    if (!normalized) {
        return '';
    }

    return normalized.length > 5000
        ? normalized.slice(0, 5000)
        : normalized;
}

function parseOptionalScore(value: unknown): number | undefined {
    if (value === null || value === undefined || value === '') {
        return undefined;
    }

    const raw = typeof value === 'number'
        ? value
        : Number.parseFloat(String(value).replace(',', '.'));
    if (Number.isNaN(raw)) {
        return undefined;
    }

    const bounded = Math.max(0, Math.min(5, raw));
    return Math.round(bounded * 10) / 10;
}

function parseOptionalInt(value: unknown): number | undefined {
    if (value === null || value === undefined || value === '') {
        return undefined;
    }

    const raw = typeof value === 'number'
        ? Math.round(value)
        : Number.parseInt(String(value), 10);
    if (Number.isNaN(raw)) {
        return undefined;
    }

    return raw;
}

function normalizeComparableLoose(value: string): string {
    return String(value ?? '')
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .replace(/[^a-zA-Z0-9\s]/g, ' ')
        .replace(/\s+/g, ' ')
        .trim()
        .toUpperCase();
}

function escapeHtmlText(value: string): string {
    return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function buildCommentHtmlFromScores(scores: {
    kienThucScore?: number;
    kyNangScore?: number;
    thaiDoScore?: number;
}, fallbackComment?: string): string {
    const lines: string[] = [];

    if (scores.kienThucScore !== undefined) {
        lines.push(`<p><b>KIEN THUC:</b> ${scores.kienThucScore}/5</p>`);
    }
    if (scores.kyNangScore !== undefined) {
        lines.push(`<p><b>KY NANG:</b> ${scores.kyNangScore}/5</p>`);
    }
    if (scores.thaiDoScore !== undefined) {
        lines.push(`<p><b>THAI DO:</b> ${scores.thaiDoScore}/5</p>`);
    }

    const normalizedComment = normalizeCommentText(fallbackComment);
    if (normalizedComment) {
        lines.push(`<p>${escapeHtmlText(normalizedComment)}</p>`);
    }

    if (lines.length === 0) {
        return '<p>Nhan xet chua cap nhat.</p>';
    }

    return lines.join('');
}

function extractScoresFromCommentHtml(content: string): {
    kienThucScore?: number;
    kyNangScore?: number;
    thaiDoScore?: number;
} {
    const normalized = normalizeComparableLoose(content);
    const extract = (label: string): number | undefined => {
        const escaped = label.replace(/\s+/g, '\\s+');
        const regex = new RegExp(`${escaped}\\s*:?\\s*(\\d+(?:[\\.,]\\d+)?)`, 'i');
        const match = regex.exec(normalized);
        if (!match || !match[1]) {
            return undefined;
        }
        const value = Number.parseFloat(match[1].replace(',', '.'));
        if (Number.isNaN(value)) {
            return undefined;
        }
        return Math.round(Math.max(0, Math.min(5, value)) * 10) / 10;
    };

    return {
        kienThucScore: extract('KIEN THUC'),
        kyNangScore: extract('KY NANG'),
        thaiDoScore: extract('THAI DO')
    };
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

function pickCommentAreaIdFromCourseProcess(
    courseProcess: LmsCourseProcess | undefined,
    sessionNumber?: number
): string | undefined {
    if (!courseProcess) {
        return undefined;
    }

    const sessionCommentAreas = (courseProcess.specificSessions || [])
        .find((session) => sessionNumber !== undefined && session.session === sessionNumber)
        ?.commentAreas || [];
    const defaultCommentAreas = courseProcess.defaultCommentAreas || [];
    const all = [
        ...sessionCommentAreas,
        ...defaultCommentAreas
    ].filter((item): item is LmsCommentArea => Boolean(item?.id));
    if (all.length === 0) {
        return undefined;
    }

    const scoringLike = all.find((item) => {
        const fieldName = normalizeComparableLoose(item.fieldName || '');
        const name = normalizeComparableLoose(item.name || '');
        return fieldName.includes('NHAN XET')
            || name.includes('NHAN XET')
            || fieldName.includes('COMMENT')
            || name.includes('COMMENT')
            || fieldName.includes('DANH GIA')
            || name.includes('DANH GIA');
    });

    return String(scoringLike?.id || all[0].id || '').trim() || undefined;
}

function parseAttendanceCommentRequestBody(body: unknown): AttendanceCommentRequestPayload | null {
    if (!body || typeof body !== 'object') {
        return null;
    }

    const payload = body as {
        classId?: unknown;
        slotId?: unknown;
        comments?: unknown;
    };
    const classId = String(payload.classId ?? '').trim();
    const slotId = String(payload.slotId ?? '').trim();
    if (!classId || !slotId) {
        return null;
    }

    if (!Array.isArray(payload.comments)) {
        return {
            classId,
            slotId,
            comments: []
        };
    }

    const deduped = new Map<string, AttendanceCommentInput>();
    payload.comments.forEach((rawItem) => {
        if (!rawItem || typeof rawItem !== 'object') {
            return;
        }

        const item = rawItem as {
            key?: unknown;
            name?: unknown;
            studentId?: unknown;
            studentAttendanceId?: unknown;
            classSiteId?: unknown;
            courseProcessId?: unknown;
            sessionNumber?: unknown;
            commentAreaId?: unknown;
            kienThucScore?: unknown;
            kyNangScore?: unknown;
            thaiDoScore?: unknown;
            comment?: unknown;
        };
        const name = String(item.name ?? '').trim();
        if (!name) {
            return;
        }

        const studentId = String(item.studentId ?? '').trim();
        const studentAttendanceId = String(item.studentAttendanceId ?? '').trim();
        const classSiteId = String(item.classSiteId ?? '').trim();
        const courseProcessId = String(item.courseProcessId ?? '').trim();
        const commentAreaId = String(item.commentAreaId ?? '').trim();
        const keyFromBody = String(item.key ?? '').trim();
        const key = keyFromBody || (studentId ? `student_id::${studentId}` : buildParticipantKey(name, false));

        deduped.set(key, {
            key,
            name,
            studentId: studentId || undefined,
            studentAttendanceId: studentAttendanceId || undefined,
            classSiteId: classSiteId || undefined,
            courseProcessId: courseProcessId || undefined,
            sessionNumber: parseOptionalInt(item.sessionNumber),
            commentAreaId: commentAreaId || undefined,
            kienThucScore: parseOptionalScore(item.kienThucScore),
            kyNangScore: parseOptionalScore(item.kyNangScore),
            thaiDoScore: parseOptionalScore(item.thaiDoScore),
            comment: normalizeCommentText(item.comment)
        });
    });

    return {
        classId,
        slotId,
        comments: Array.from(deduped.values())
    };
}

function parseClassSlotQuery(req: Request): { classId: string; slotId: string } | null {
    const classId = typeof req.query.classId === 'string'
        ? req.query.classId.trim()
        : '';
    const slotId = typeof req.query.slotId === 'string'
        ? req.query.slotId.trim()
        : '';

    if (!classId || !slotId) {
        return null;
    }

    return {
        classId,
        slotId
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

function buildStudentCommentKey(
    student?: { id?: string; fullName?: string },
    fallbackName?: string
): string {
    const studentId = String(student?.id ?? '').trim();
    if (studentId) {
        return `student_id::${studentId}`;
    }

    const name = String(student?.fullName ?? fallbackName ?? '').trim();
    return buildParticipantKey(name, false);
}

function studentDisplayName(student?: { fullName?: string }, fallbackName?: string): string {
    return String(student?.fullName ?? fallbackName ?? '').trim();
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

function getStartOfWeekMs(date: Date): number {
    const local = new Date(date.getTime());
    const day = local.getDay();
    const daysFromMonday = (day + 6) % 7;
    local.setHours(0, 0, 0, 0);
    local.setDate(local.getDate() - daysFromMonday);
    return local.getTime();
}

function buildPublicCommentContext(
    cls: LmsClassRecord,
    slot: LmsSlotRecord | null | undefined
): {
    classSiteId: string | null;
    courseProcessId: string | null;
    sessionNumber: number | null;
    commentAreaId: string | null;
    slotId: string | null;
    slotStartTime: string | null;
    slotEndTime: string | null;
    missingCommentStudentCount: number;
    missingCommentStudents: string[];
    students: Array<{
        key: string;
        name: string;
        studentId: string | null;
        studentAttendanceId: string | null;
        classSiteId: string | null;
        courseProcessId: string | null;
        sessionNumber: number | null;
        commentAreaId: string | null;
        hasComment: boolean;
    }>;
} | null {
    if (!slot?._id) {
        return null;
    }

    const activeClassStudents = (cls.students || []).filter((item) => item.activeInClass !== false);
    const classSiteId = String(
        (cls.classSites || []).find((site) => String(site?._id ?? '').trim())?._id ?? ''
    ).trim() || null;
    const courseProcessId = String(cls.courseProcessId ?? cls.courseProcess?.id ?? '').trim() || null;
    const sessionNumber = typeof slot.index === 'number' ? slot.index : null;
    const commentAreaId = pickCommentAreaIdFromCourseProcess(
        cls.courseProcess,
        sessionNumber ?? undefined
    ) ?? null;
    const slotStudentAttendance = slot.studentAttendance || [];
    const studentAttendanceIndex = createLookupIndex(
        slotStudentAttendance,
        (record) => collectStudentRecordKeys(record.student)
    );

    const students = activeClassStudents.flatMap((classStudent) => {
        const student = classStudent.student;
        const name = studentDisplayName(student);
        if (!name) {
            return [];
        }

        const attendanceMatch = findSingleMatchByKeys(
            studentAttendanceIndex,
            collectStudentRecordKeys(student),
            (record) =>
                record.student?.id
                || record._id
                || record.student?.fullName
                || ''
        );
        const attendance = attendanceMatch.item;
        const attendanceCommentAreaId = String(
            (attendance?.commentByAreas || []).find((item) =>
                String(item?.commentAreaId ?? '').trim()
            )?.commentAreaId ?? ''
        ).trim() || null;
        const commentText = readAttendanceCommentText(attendance);
        const hasComment = normalizeCommentText(commentText).length > 0;

        return [{
            key: buildStudentCommentKey(student, name),
            name,
            studentId: student?.id ?? null,
            studentAttendanceId: attendance?._id ?? null,
            classSiteId: classStudent.classSite?._id ?? classSiteId ?? null,
            courseProcessId,
            sessionNumber,
            commentAreaId: attendanceCommentAreaId ?? commentAreaId,
            hasComment
        }];
    });
    const missingCommentStudents = students
        .filter((item) => !item.hasComment)
        .map((item) => item.name);

    return {
        classSiteId,
        courseProcessId,
        sessionNumber,
        commentAreaId,
        slotId: slot._id ?? null,
        slotStartTime: slot.startTime ?? slot.date ?? null,
        slotEndTime: slot.endTime ?? null,
        missingCommentStudentCount: missingCommentStudents.length,
        missingCommentStudents,
        students
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
                    const slotStartTimes = (cls.slots || [])
                        .map((slot) => parseDateToMs(slot.startTime ?? slot.date))
                        .filter((value): value is number => value !== null)
                        .sort((a, b) => a - b);
                    const classStartDate = slotStartTimes.length > 0
                        ? new Date(slotStartTimes[0]).toISOString()
                        : null;
                    const upcomingWindows = getClassAttendanceWindows(cls, nowMs, principal)
                        .filter((window) => window.attendanceCloseAtMs >= nowMs);
                    const nextAttendanceWindow = upcomingWindows.length > 0
                        ? toPublicAttendanceWindow(upcomingWindows[0])
                        : null;
                    const classEndDateMs = parseDateToMs(cls.endDate);
                    const isClassEnded = classEndDateMs !== null ? classEndDateMs < nowMs : false;
                    const nextCommentSlot = nextAttendanceWindow
                        ? (cls.slots || []).find((slot) =>
                            normalizeIdentity(slot._id) === normalizeIdentity(nextAttendanceWindow.slotId)
                        )
                        : null;
                    const currentWeekStartMs = getStartOfWeekMs(now);
                    const previousWeekStartMs = currentWeekStartMs - (7 * 24 * 60 * 60 * 1000);
                    const previousWeekSlots = slotsWithStart.filter((item) =>
                        item.startMs >= previousWeekStartMs
                        && item.startMs < currentWeekStartMs
                    );
                    const previousCommentSlot = previousWeekSlots.length > 0
                        ? previousWeekSlots[previousWeekSlots.length - 1].slot
                        : null;
                    const nextCommentContext = buildPublicCommentContext(cls, nextCommentSlot);
                    const previousCommentContext = buildPublicCommentContext(cls, previousCommentSlot);

                    return {
                        classId: cls.id,
                        className: cls.name,
                        status: normalizeClassStatus(cls.status) ?? null,
                        endDate: cls.endDate,
                        classStartDate,
                        classEndDate: cls.endDate ?? null,
                        isClassEnded,
                        totalStudents: students.length,
                        students,
                        totalCoTeachers: coTeachers.length,
                        coTeachers,
                        totalSlots: (cls.slots || []).length,
                        nextAttendanceWindow,
                        nextCommentContext,
                        previousCommentContext
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

    router.get('/attendance/slot/comments', async (req: Request, res: Response) => {
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

            const query = parseClassSlotQuery(req);
            if (!query) {
                res.status(400).json({
                    success: false,
                    error: 'Query khong hop le',
                    detail: 'Can classId va slotId'
                });
                return;
            }

            const { classId, slotId } = query;
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
            if (!slot) {
                res.status(404).json({
                    success: false,
                    error: 'Khong tim thay buoi hoc',
                    detail: `classId=${classId}, slotId=${slotId}`
                });
                return;
            }

            const activeClassStudents = (cls.students || []).filter((item) => item.activeInClass !== false);
            const slotStudentAttendance = slot.studentAttendance || [];
            const studentAttendanceIndex = createLookupIndex(
                slotStudentAttendance,
                (record) => collectStudentRecordKeys(record.student)
            );
            const classSiteFallback = String(
                (cls.classSites || []).find((site) => String(site?._id ?? '').trim())?._id ?? ''
            ).trim() || null;
            const courseProcessId = String(cls.courseProcessId ?? cls.courseProcess?.id ?? '').trim() || null;
            const sessionNumber = typeof slot.index === 'number' ? slot.index : null;
            const defaultCommentAreaId = pickCommentAreaIdFromCourseProcess(
                cls.courseProcess,
                sessionNumber ?? undefined
            ) ?? null;
            const commentsByKey = new Map<string, {
                key: string;
                name: string;
                studentId: string | null;
                studentAttendanceId: string | null;
                classSiteId: string | null;
                courseProcessId: string | null;
                sessionNumber: number | null;
                commentAreaId: string | null;
                kienThucScore?: number;
                kyNangScore?: number;
                thaiDoScore?: number;
                comment: string;
            }>();

            const upsertComment = (params: {
                key: string;
                name: string;
                studentId?: string | null;
                studentAttendanceId?: string | null;
                classSiteId?: string | null;
                courseProcessId?: string | null;
                sessionNumber?: number | null;
                commentAreaId?: string | null;
                kienThucScore?: number;
                kyNangScore?: number;
                thaiDoScore?: number;
                comment?: string | null;
            }) => {
                const key = String(params.key || '').trim();
                const name = String(params.name || '').trim();
                if (!key || !name) {
                    return;
                }

                const existing = commentsByKey.get(key);
                const normalizedComment = normalizeCommentText(params.comment);
                commentsByKey.set(key, {
                    key,
                    name: existing?.name || name,
                    studentId: params.studentId?.trim() || existing?.studentId || null,
                    studentAttendanceId: params.studentAttendanceId?.trim() || existing?.studentAttendanceId || null,
                    classSiteId: params.classSiteId?.trim() || existing?.classSiteId || null,
                    courseProcessId: params.courseProcessId?.trim() || existing?.courseProcessId || null,
                    sessionNumber: params.sessionNumber ?? existing?.sessionNumber ?? null,
                    commentAreaId: params.commentAreaId?.trim() || existing?.commentAreaId || null,
                    kienThucScore: params.kienThucScore ?? existing?.kienThucScore,
                    kyNangScore: params.kyNangScore ?? existing?.kyNangScore,
                    thaiDoScore: params.thaiDoScore ?? existing?.thaiDoScore,
                    comment: normalizedComment || existing?.comment || ''
                });
            };

            activeClassStudents.forEach((classStudent: LmsClassStudent) => {
                const student = classStudent.student;
                const name = studentDisplayName(student);
                if (!name) {
                    return;
                }

                const lookupKeys = collectStudentRecordKeys(student);
                const attendanceMatch = findSingleMatchByKeys(
                    studentAttendanceIndex,
                    lookupKeys,
                    (record) =>
                        record.student?.id
                        || record._id
                        || record.student?.fullName
                        || ''
                );
                const attendance = attendanceMatch.item;
                const commentByArea = (attendance?.commentByAreas || []).find((item) =>
                    Boolean(String(item?.content ?? '').trim() || String(item?.commentAreaId ?? '').trim())
                );
                const richContent = String(commentByArea?.content ?? '').trim();
                const scoreSource = richContent || String(attendance?.comment ?? attendance?.note ?? '').trim();
                const scoreData = scoreSource ? extractScoresFromCommentHtml(scoreSource) : {};
                const narrativeComment = readAttendanceCommentText(attendance);

                upsertComment({
                    key: buildStudentCommentKey(student),
                    name,
                    studentId: student?.id ?? attendance?.student?.id ?? null,
                    studentAttendanceId: attendance?._id ?? null,
                    classSiteId: classStudent.classSite?._id ?? classSiteFallback,
                    courseProcessId,
                    sessionNumber,
                    commentAreaId: String(commentByArea?.commentAreaId ?? defaultCommentAreaId ?? '').trim() || null,
                    kienThucScore: scoreData.kienThucScore,
                    kyNangScore: scoreData.kyNangScore,
                    thaiDoScore: scoreData.thaiDoScore,
                    comment: narrativeComment
                });
            });

            slotStudentAttendance.forEach((attendance: LmsStudentAttendanceRecord) => {
                const student = attendance.student;
                const name = studentDisplayName(student);
                if (!name) {
                    return;
                }

                const commentByArea = (attendance.commentByAreas || []).find((item) =>
                    Boolean(String(item?.content ?? '').trim() || String(item?.commentAreaId ?? '').trim())
                );
                const richContent = String(commentByArea?.content ?? '').trim();
                const scoreSource = richContent || String(attendance.comment ?? attendance.note ?? '').trim();
                const scoreData = scoreSource ? extractScoresFromCommentHtml(scoreSource) : {};
                const narrativeComment = readAttendanceCommentText(attendance);

                upsertComment({
                    key: buildStudentCommentKey(student, name),
                    name,
                    studentId: student?.id ?? null,
                    studentAttendanceId: attendance._id ?? null,
                    classSiteId: classSiteFallback,
                    courseProcessId,
                    sessionNumber,
                    commentAreaId: String(commentByArea?.commentAreaId ?? defaultCommentAreaId ?? '').trim() || null,
                    kienThucScore: scoreData.kienThucScore,
                    kyNangScore: scoreData.kyNangScore,
                    thaiDoScore: scoreData.thaiDoScore,
                    comment: narrativeComment
                });
            });

            const comments = Array.from(commentsByKey.values())
                .sort((a, b) => a.name.localeCompare(b.name));

            res.json({
                success: true,
                data: {
                    classId,
                    slotId,
                    comments
                }
            });
        } catch (error: any) {
            const statusCode = error?.statusCode || error?.response?.status || 500;
            const detail = error?.response?.data || error?.message;
            console.error('Loi:', detail);
            res.status(statusCode).json({
                success: false,
                error: 'Loi lay nhan xet',
                detail
            });
        }
    });

    router.post('/attendance/slot/comments', async (req: Request, res: Response) => {
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

            const parsedBody = parseAttendanceCommentRequestBody(req.body);
            if (!parsedBody) {
                res.status(400).json({
                    success: false,
                    error: 'Payload khong hop le',
                    detail: 'Can classId, slotId va comments[]'
                });
                return;
            }

            const { classId, slotId, comments } = parsedBody;
            if (comments.length === 0) {
                res.status(400).json({
                    success: false,
                    error: 'Khong co du lieu nhan xet',
                    detail: 'comments[] dang rong'
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
            const studentAttendanceById = new Map<string, LmsStudentAttendanceRecord>();
            slotStudentAttendance.forEach((attendance) => {
                const attendanceId = normalizeIdentity(attendance._id);
                if (attendanceId) {
                    studentAttendanceById.set(attendanceId, attendance);
                }
            });
            const studentAttendanceIndex = createLookupIndex(
                slotStudentAttendance,
                (record) => collectStudentRecordKeys(record.student)
            );
            const classStudentIndex = createLookupIndex(
                activeClassStudents,
                (record) => collectStudentRecordKeys(record.student)
            );
            const classStudentById = new Map<string, LmsClassStudent>();
            activeClassStudents.forEach((record) => {
                const studentId = normalizeIdentity(record.student?.id);
                if (studentId) {
                    classStudentById.set(studentId, record);
                }
            });

            const fallbackClassSiteId = String(
                (cls.classSites || []).find((site) => String(site?._id ?? '').trim())?._id ?? ''
            ).trim() || undefined;
            const defaultCourseProcessId = String(cls.courseProcessId ?? cls.courseProcess?.id ?? '').trim() || undefined;
            const defaultSessionNumber = typeof slot.index === 'number' ? slot.index : undefined;

            const unresolvedParticipants: AttendanceCommentUnresolvedParticipant[] = [];
            const appliedParticipantKeys = new Set<string>();
            const failedParticipants: Array<{ key: string; name: string; detail: string }> = [];
            const commandsToApply: Array<{
                key: string;
                name: string;
                command: LmsUpdateSlotCommentCommand;
            }> = [];

            comments.forEach((commentInput) => {
                const lookupKeysSet = new Set<string>();
                const studentIdIdentity = normalizeIdentity(commentInput.studentId);
                if (studentIdIdentity) {
                    lookupKeysSet.add(`id:${studentIdIdentity}`);
                }
                collectStudentMatchKeys(commentInput.name).forEach((key) => lookupKeysSet.add(key));
                const lookupKeys = Array.from(lookupKeysSet);

                const attendanceIdIdentity = normalizeIdentity(commentInput.studentAttendanceId);
                let attendanceByStudentIdAmbiguous = false;
                let attendanceFromId = attendanceIdIdentity
                    ? studentAttendanceById.get(attendanceIdIdentity) || null
                    : null;
                if (!attendanceFromId && studentIdIdentity) {
                    const matches = slotStudentAttendance.filter((record) =>
                        normalizeIdentity(record.student?.id) === studentIdIdentity
                    );
                    if (matches.length === 1) {
                        attendanceFromId = matches[0];
                    } else if (matches.length > 1) {
                        attendanceByStudentIdAmbiguous = true;
                    }
                }

                const attendanceMatch = attendanceFromId
                    ? { item: attendanceFromId, reason: undefined as ('not_found' | 'ambiguous' | undefined) }
                    : findSingleMatchByKeys(
                        studentAttendanceIndex,
                        lookupKeys,
                        (record) =>
                            record.student?.id
                            || record._id
                            || record.student?.fullName
                            || ''
                    );

                let classStudentFromId = studentIdIdentity
                    ? classStudentById.get(studentIdIdentity) || null
                    : null;
                if (!classStudentFromId && attendanceMatch.item?.student?.id) {
                    classStudentFromId = classStudentById.get(
                        normalizeIdentity(attendanceMatch.item.student.id)
                    ) || null;
                }
                const classStudentMatch = classStudentFromId
                    ? { item: classStudentFromId, reason: undefined as ('not_found' | 'ambiguous' | undefined) }
                    : findSingleMatchByKeys(
                        classStudentIndex,
                        lookupKeys,
                        (record) =>
                            record.student?.id
                            || record._id
                            || record.student?.fullName
                            || ''
                    );

                const attendance = attendanceMatch.item;
                const classStudent = classStudentMatch.item;
                const ambiguous = attendanceByStudentIdAmbiguous
                    || attendanceMatch.reason === 'ambiguous'
                    || classStudentMatch.reason === 'ambiguous';
                const studentId = String(
                    commentInput.studentId
                    ?? attendance?.student?.id
                    ?? classStudent?.student?.id
                    ?? ''
                ).trim();
                const studentAttendanceId = String(
                    commentInput.studentAttendanceId
                    ?? attendance?._id
                    ?? ''
                ).trim();

                if (!studentId || !studentAttendanceId) {
                    unresolvedParticipants.push({
                        key: commentInput.key,
                        name: commentInput.name,
                        reason: ambiguous ? 'ambiguous' : 'not_found'
                    });
                    return;
                }

                const sessionNumber = commentInput.sessionNumber ?? defaultSessionNumber;
                const courseProcessId = commentInput.courseProcessId || defaultCourseProcessId;
                const knownCommentAreaId = String(
                    (attendance?.commentByAreas || []).find((item) => String(item?.commentAreaId ?? '').trim())
                        ?.commentAreaId ?? ''
                ).trim();
                const commentAreaId = String(
                    commentInput.commentAreaId
                    ?? knownCommentAreaId
                    ?? pickCommentAreaIdFromCourseProcess(cls.courseProcess, sessionNumber)
                    ?? ''
                ).trim();
                const classSiteId = String(
                    commentInput.classSiteId
                    ?? classStudent?.classSite?._id
                    ?? fallbackClassSiteId
                    ?? ''
                ).trim();
                const commentHtml = buildCommentHtmlFromScores({
                    kienThucScore: commentInput.kienThucScore,
                    kyNangScore: commentInput.kyNangScore,
                    thaiDoScore: commentInput.thaiDoScore
                }, commentInput.comment);

                const command: LmsUpdateSlotCommentCommand = {
                    classId,
                    slotId: String(slot._id || slotId),
                    classSiteId: classSiteId || undefined,
                    sessionNumber,
                    courseProcessId,
                    studentComment: {
                        studentAttendanceId,
                        studentId,
                        content: commentHtml,
                        byAreas: commentAreaId
                            ? [{
                                commentAreaId,
                                content: commentHtml,
                                type: 'CONTENT'
                            }]
                            : []
                    }
                };

                commandsToApply.push({
                    key: commentInput.key,
                    name: commentInput.name,
                    command
                });
            });

            if (commandsToApply.length === 0) {
                res.status(400).json({
                    success: false,
                    error: 'Khong map duoc hoc vien de luu nhan xet',
                    detail: {
                        requestedComments: comments.length,
                        unresolvedParticipants
                    }
                });
                return;
            }

            for (const item of commandsToApply) {
                try {
                    await lmsService.updateSlotComment(item.command, idTokenFromHeader);
                    appliedParticipantKeys.add(item.key);
                } catch (error: any) {
                    const rawDetail = error?.response?.data || error?.message || error;
                    const detail = typeof rawDetail === 'string'
                        ? rawDetail
                        : JSON.stringify(rawDetail);
                    failedParticipants.push({
                        key: item.key,
                        name: item.name,
                        detail
                    });
                }
            }

            const totalApplied = appliedParticipantKeys.size;
            if (totalApplied === 0 && failedParticipants.length > 0) {
                res.status(500).json({
                    success: false,
                    error: 'Khong luu duoc nhan xet nao len LMS',
                    detail: {
                        requestedComments: comments.length,
                        unresolvedParticipants,
                        failedParticipants
                    }
                });
                return;
            }

            res.json({
                success: true,
                data: {
                    classId,
                    slotId: String(slot._id || slotId),
                    requestedComments: comments.length,
                    appliedComments: totalApplied,
                    updatedStudents: totalApplied,
                    appliedParticipantKeys: Array.from(appliedParticipantKeys.values()),
                    unresolvedParticipants,
                    failedParticipants
                }
            });
        } catch (error: any) {
            const statusCode = error?.statusCode || error?.response?.status || 500;
            const detail = error?.response?.data || error?.message;
            console.error('Loi:', detail);
            res.status(statusCode).json({
                success: false,
                error: 'Loi luu nhan xet',
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
