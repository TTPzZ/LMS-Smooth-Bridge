import { env } from '../config/env';
import { LmsClassRecord, LmsSlotRecord, LmsTeacherAssignment } from '../types/lms';

type ReminderPrincipal = {
    teacherId?: string | null;
    username?: string | null;
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

function resolveRoleForPrincipal(
    cls: LmsClassRecord,
    slot: LmsSlotRecord,
    principal?: ReminderPrincipal | null
): { roleName: string | null; roleShortName: string | null } {
    const assignments = (slot.teachers || []).length > 0 ? slot.teachers || [] : cls.teachers || [];
    if (assignments.length === 0) {
        return {
            roleName: null,
            roleShortName: null
        };
    }

    const principalTeacherId = normalizeIdentity(principal?.teacherId);
    const principalUsername = normalizeIdentity(principal?.username);
    const principalDerivedUsername = deriveUsernameFromEmail(principal?.username);

    const isMatch = (assignment: LmsTeacherAssignment): boolean => {
        const teacherId = normalizeIdentity(assignment.teacher?.id);
        const teacherUsername = normalizeIdentity(assignment.teacher?.username);
        if (principalTeacherId && teacherId && principalTeacherId === teacherId) {
            return true;
        }
        if (principalUsername && teacherUsername && principalUsername === teacherUsername) {
            return true;
        }
        if (principalDerivedUsername && teacherUsername && principalDerivedUsername === teacherUsername) {
            return true;
        }
        return false;
    };

    const matched = assignments.find(isMatch);
    const fallback = assignments.find((item) => item.isActive) || assignments[0];
    const picked = matched || fallback;

    return {
        roleName: picked.role?.name || null,
        roleShortName: picked.role?.shortName || null
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
