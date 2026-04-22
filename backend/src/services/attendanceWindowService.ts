import { env } from '../config/env';
import { LmsClassRecord, LmsSlotRecord } from '../types/lms';

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
    nowMs: number
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
        attendanceOpenAtMs,
        attendanceCloseAtMs
    };
}

export function getClassAttendanceWindows(cls: LmsClassRecord, nowMs: number): SlotAttendanceWindow[] {
    const windows = (cls.slots || [])
        .map((slot) => buildSlotAttendanceWindow(cls, slot, nowMs))
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
        totalStudentsInSlot: window.totalStudentsInSlot
    };
}
