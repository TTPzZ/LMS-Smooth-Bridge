import { env } from '../config/env';
import { LmsClassRecord, LmsSlotRecord, LmsTeacherAssignment, LmsTeacherUser } from '../types/lms';

type ReminderPrincipal = {
    teacherId?: string | null;
    username?: string | null;
    usernames?: string[];
    fullName?: string | null;
};

export type SlotAttendanceWindow = {
    classId: string;
    className: string;
    classStatus: string | null;
    classEndDate: string | null;
    slotId: string;
    slotIndex: number | null;
    slotDate: string | null;
    slotStartTime: string;
    slotEndTime: string;
    attendanceOpenAt: string;
    attendanceCloseAt: string;
    isWindowOpen: boolean;
    minutesUntilWindowOpen: number;
    minutesUntilWindowClose: number;
    totalStudentsInSlot: number;
    roleName: string | null;
    roleShortName: string | null;
    attendanceOpenAtMs: number;
    attendanceCloseAtMs: number;
};

export function parseDateToMs(value: string | undefined): number | null {
    if (!value) {
        return null;
    }

    const dateValue = new Date(value);
    const ms = dateValue.getTime();
    if (Number.isNaN(ms)) {
        return null;
    }

    return ms;
}

export function normalizeClassStatus(status: string | undefined): string | undefined {
    if (!status) {
        return undefined;
    }

    return status.trim().toUpperCase();
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

function hasPrincipalIdentity(principal?: ReminderPrincipal | null): boolean {
    const hasTeacherId = Boolean(normalizeIdentity(principal?.teacherId));
    const hasUsernames = (principal?.usernames || [])
        .map((item) => normalizeIdentity(item))
        .filter(Boolean).length > 0;
    const hasUsername = Boolean(normalizeIdentity(principal?.username));
    const hasFullName = Boolean(normalizeComparable(principal?.fullName));
    return hasTeacherId || hasUsernames || hasUsername || hasFullName;
}

function matchesPrincipalUser(
    teacher: LmsTeacherUser | null | undefined,
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

    const teacherId = normalizeIdentity(teacher?.id);
    const teacherUsername = normalizeIdentity(teacher?.username);
    const teacherComparableFullName = normalizeComparable(teacher?.fullName);

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

function findMatchedAssignment(
    assignments: LmsTeacherAssignment[] | undefined,
    principal?: ReminderPrincipal | null
): LmsTeacherAssignment | undefined {
    return (assignments || []).find((assignment) =>
        matchesPrincipalUser(assignment.teacher, principal)
    );
}

export function shouldIncludeSlotForPrincipal(
    cls: LmsClassRecord,
    slot: LmsSlotRecord,
    principal?: ReminderPrincipal | null
): boolean {
    if (!hasPrincipalIdentity(principal)) {
        return true;
    }

    const slotAssignments = slot.teachers || [];
    const slotAttendance = slot.teacherAttendance || [];
    const hasSlotTeacherSignals = slotAssignments.length > 0 || slotAttendance.length > 0;

    const matchedSlotAssignment = findMatchedAssignment(slotAssignments, principal);
    const matchedAttendance = slotAttendance.some((record) =>
        matchesPrincipalUser(record.teacher, principal)
    );

    if (hasSlotTeacherSignals) {
        return Boolean(matchedSlotAssignment || matchedAttendance);
    }

    const matchedClassAssignment = findMatchedAssignment(cls.teachers, principal);
    return Boolean(matchedClassAssignment);
}

function resolveRoleForPrincipal(
    cls: LmsClassRecord,
    slot: LmsSlotRecord,
    principal?: ReminderPrincipal | null
): { roleName: string | null; roleShortName: string | null } {
    const slotAssignments = slot.teachers || [];
    const classAssignments = cls.teachers || [];
    const assignments = slotAssignments.length > 0 ? slotAssignments : classAssignments;
    if (assignments.length === 0 && classAssignments.length === 0) {
        return {
            roleName: null,
            roleShortName: null
        };
    }

    const matched = findMatchedAssignment(slotAssignments, principal)
        || findMatchedAssignment(classAssignments, principal);
    if (matched) {
        return {
            roleName: matched.role?.name || null,
            roleShortName: matched.role?.shortName || null
        };
    }

    if (hasPrincipalIdentity(principal)) {
        return {
            roleName: null,
            roleShortName: null
        };
    }

    const fallback = assignments.find((item) => item.isActive) || assignments[0];

    return {
        roleName: fallback.role?.name || null,
        roleShortName: fallback.role?.shortName || null
    };
}

function hasNotEnded(endDate: string | undefined, now: Date): boolean {
    if (!endDate) {
        return true;
    }

    const endDateValue = new Date(endDate);
    if (Number.isNaN(endDateValue.getTime())) {
        return true;
    }

    return endDateValue >= now;
}

export function isRunningClass(cls: LmsClassRecord, now: Date): boolean {
    const normalizedStatus = normalizeClassStatus(cls.status);
    if (normalizedStatus) {
        return normalizedStatus === 'RUNNING';
    }

    return hasNotEnded(cls.endDate, now);
}

function buildSlotAttendanceWindow(
    cls: LmsClassRecord,
    slot: LmsSlotRecord,
    nowMs: number,
    principal?: ReminderPrincipal | null
): SlotAttendanceWindow | null {
    if (!slot._id || !slot.startTime || !slot.endTime) {
        return null;
    }

    const startMs = parseDateToMs(slot.startTime);
    const endMs = parseDateToMs(slot.endTime);
    if (startMs === null || endMs === null) {
        return null;
    }

    if (!shouldIncludeSlotForPrincipal(cls, slot, principal)) {
        return null;
    }

    const attendanceOpenAtMs = startMs - env.ATTENDANCE_OPEN_MINUTES_BEFORE * 60_000;
    const attendanceCloseAtMs = endMs + env.ATTENDANCE_CLOSE_MINUTES_AFTER * 60_000;
    const classStatus = normalizeClassStatus(cls.status) ?? null;
    const isWindowOpen = nowMs >= attendanceOpenAtMs && nowMs <= attendanceCloseAtMs;
    const role = resolveRoleForPrincipal(cls, slot, principal);

    return {
        classId: cls.id,
        className: cls.name,
        classStatus,
        classEndDate: cls.endDate ?? null,
        slotId: slot._id,
        slotIndex: typeof slot.index === 'number' ? slot.index : null,
        slotDate: slot.date ?? null,
        slotStartTime: slot.startTime,
        slotEndTime: slot.endTime,
        attendanceOpenAt: new Date(attendanceOpenAtMs).toISOString(),
        attendanceCloseAt: new Date(attendanceCloseAtMs).toISOString(),
        isWindowOpen,
        minutesUntilWindowOpen: attendanceOpenAtMs > nowMs
            ? Math.ceil((attendanceOpenAtMs - nowMs) / 60_000)
            : 0,
        minutesUntilWindowClose: attendanceCloseAtMs > nowMs
            ? Math.ceil((attendanceCloseAtMs - nowMs) / 60_000)
            : 0,
        totalStudentsInSlot: (slot.studentAttendance || []).length,
        roleName: role.roleName,
        roleShortName: role.roleShortName,
        attendanceOpenAtMs,
        attendanceCloseAtMs
    };
}

export function getClassAttendanceWindows(
    cls: LmsClassRecord,
    nowMs: number,
    principal?: ReminderPrincipal | null
): SlotAttendanceWindow[] {
    const windows = (cls.slots || [])
        .map((slot) => buildSlotAttendanceWindow(cls, slot, nowMs, principal))
        .filter((item): item is SlotAttendanceWindow => item !== null)
        .sort((a, b) => a.attendanceOpenAtMs - b.attendanceOpenAtMs);

    return windows;
}

export function toPublicAttendanceWindow(window: SlotAttendanceWindow) {
    return {
        classId: window.classId,
        className: window.className,
        classStatus: window.classStatus,
        classEndDate: window.classEndDate,
        slotId: window.slotId,
        slotIndex: window.slotIndex,
        slotDate: window.slotDate,
        slotStartTime: window.slotStartTime,
        slotEndTime: window.slotEndTime,
        attendanceOpenAt: window.attendanceOpenAt,
        attendanceCloseAt: window.attendanceCloseAt,
        isWindowOpen: window.isWindowOpen,
        minutesUntilWindowOpen: window.minutesUntilWindowOpen,
        minutesUntilWindowClose: window.minutesUntilWindowClose,
        totalStudentsInSlot: window.totalStudentsInSlot,
        roleName: window.roleName,
        roleShortName: window.roleShortName
    };
}
