import { env } from '../config/env';
import {
    LmsClassRecord,
    LmsTeacherAssignment,
    LmsTeacherAttendanceRecord,
    LmsTimesheetItem
} from '../types/lms';
import { decodeJwtPayload } from '../utils/jwt';
import { parseIntegerInRange } from '../utils/requestParsers';
import { LmsService } from './lmsService';

type PayrollParams = {
    month?: unknown;
    year?: unknown;
    timezone?: unknown;
    teacherId?: unknown;
    username?: unknown;
    itemsPerPage?: unknown;
    maxPages?: unknown;
    countedStatuses?: unknown;
};

type TeacherPrincipal = {
    teacherId: string | null;
    username: string | null;
    internalUserId: string | null;
    teacherObjectId: string | null;
    source: 'query' | 'token';
};

type PayrollSlotItem = {
    classId: string;
    className: string;
    slotId: string;
    slotIndex: number | null;
    startTime: string;
    endTime: string | null;
    attendanceStatus: string;
    roleName: string | null;
    roleShortName: string | null;
    durationHours: number;
};

type PayrollOfficeHourItem = {
    timesheetId: string;
    officeHourId: string | null;
    startTime: string;
    endTime: string | null;
    status: string;
    officeHourType: string | null;
    studentCount: number;
    durationHours: number;
    note: string | null;
    managerNote: string | null;
    shortName: string | null;
};

type PayrollFetchMeta = {
    fetchedPages: number;
    itemsPerPage: number;
    maxPages: number;
    totalRawClasses: number;
    totalUniqueClasses: number;
};

function normalizeStatus(value: string | undefined): string {
    return (value ?? '').trim().toUpperCase();
}

function getDatePartsInTimeZone(date: Date, timeZone: string): { year: number; month: number } {
    const formatter = new Intl.DateTimeFormat('en-US', {
        timeZone,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit'
    });
    const parts = formatter.formatToParts(date);
    const year = Number.parseInt(parts.find((part) => part.type === 'year')?.value ?? '', 10);
    const month = Number.parseInt(parts.find((part) => part.type === 'month')?.value ?? '', 10);

    return { year, month };
}

function isValidTimeZone(timeZone: string): boolean {
    try {
        new Intl.DateTimeFormat('en-US', { timeZone }).format(new Date());
        return true;
    } catch {
        return false;
    }
}

function isObjectId(value: string | null | undefined): boolean {
    if (!value) {
        return false;
    }

    return /^[a-fA-F0-9]{24}$/.test(value.trim());
}

function parseLmsDateTime(value: string | null | undefined): Date | null {
    const raw = String(value ?? '').trim();
    if (!raw) {
        return null;
    }

    if (/^\d{13}$/.test(raw)) {
        const ms = Number.parseInt(raw, 10);
        if (!Number.isNaN(ms)) {
            const parsed = new Date(ms);
            if (!Number.isNaN(parsed.getTime())) {
                return parsed;
            }
        }
    }

    if (/^\d{10}$/.test(raw)) {
        const seconds = Number.parseInt(raw, 10);
        if (!Number.isNaN(seconds)) {
            const parsed = new Date(seconds * 1000);
            if (!Number.isNaN(parsed.getTime())) {
                return parsed;
            }
        }
    }

    const parsed = new Date(raw);
    if (Number.isNaN(parsed.getTime())) {
        return null;
    }

    return parsed;
}

function round2(value: number): number {
    return Math.round(value * 100) / 100;
}

function buildMonthQueryRange(month: number, year: number): { startIso: string; endIso: string } {
    const bufferMs = 48 * 60 * 60 * 1000;
    const startMs = Date.UTC(year, month - 1, 1, 0, 0, 0, 0) - bufferMs;
    const endMs = Date.UTC(year, month, 1, 0, 0, 0, 0) + bufferMs - 1;
    return {
        startIso: new Date(startMs).toISOString(),
        endIso: new Date(endMs).toISOString()
    };
}

function matchesTeacher(
    principal: TeacherPrincipal,
    candidate: { id?: string; username?: string } | undefined
): boolean {
    if (!candidate) {
        return false;
    }

    if (principal.teacherObjectId && candidate.id && principal.teacherObjectId === candidate.id) {
        return true;
    }

    if (principal.teacherId && candidate.id && principal.teacherId === candidate.id) {
        return true;
    }

    if (principal.username && candidate.username) {
        return principal.username.toLowerCase() === candidate.username.toLowerCase();
    }

    return false;
}

function getRoleFromAssignments(
    assignments: LmsTeacherAssignment[] | undefined,
    principal: TeacherPrincipal
): LmsTeacherAssignment['role'] | null {
    const matched = (assignments || []).find((assignment) => matchesTeacher(principal, assignment.teacher));
    return matched?.role ?? null;
}

function getAttendanceMatch(
    records: LmsTeacherAttendanceRecord[] | undefined,
    principal: TeacherPrincipal
): LmsTeacherAttendanceRecord | null {
    const matched = (records || []).find((record) => matchesTeacher(principal, record.teacher));
    return matched ?? null;
}

function getSlotDurationHours(startTime: string, endTime?: string): number {
    if (!endTime) {
        return 0;
    }

    const startDate = parseLmsDateTime(startTime);
    const endDate = parseLmsDateTime(endTime);
    if (!startDate || !endDate) {
        return 0;
    }

    const startMs = startDate.getTime();
    const endMs = endDate.getTime();
    if (endMs <= startMs) {
        return 0;
    }

    return round2((endMs - startMs) / 3_600_000);
}

function normalizeCountedStatuses(value: unknown): string[] {
    const raw = String(value ?? '').trim();
    if (!raw) {
        return ['ATTENDED', 'LATE_ARRIVED'];
    }

    const statuses = raw
        .split(',')
        .map((item) => item.trim().toUpperCase())
        .filter(Boolean);

    return statuses.length > 0 ? statuses : ['ATTENDED', 'LATE_ARRIVED'];
}

function isExcludedOfficeHourStatus(value: string): boolean {
    const normalized = normalizeStatus(value);
    if (!normalized) {
        return false;
    }

    return normalized.includes('CANCEL') || normalized === 'DELETED';
}

export class PayrollService {
    constructor(private readonly lmsService: LmsService) {}

    private async resolvePrincipal(
        teacherIdQuery: unknown,
        usernameQuery: unknown,
        idTokenOverride?: string
    ): Promise<TeacherPrincipal> {
        const queryTeacherId = String(teacherIdQuery ?? '').trim() || null;
        const queryUsername = String(usernameQuery ?? '').trim() || null;
        let payload = null;
        try {
            const token = await this.lmsService.getCurrentAuthToken(idTokenOverride);
            payload = decodeJwtPayload(token);
        } catch {
            payload = null;
        }

        const tokenUsername = typeof payload?.username === 'string'
            ? payload.username.trim()
            : typeof payload?.email === 'string'
                ? payload.email.split('@')[0]?.trim() || null
                : null;

        const tokenTeacherId = typeof payload?.user_id === 'string'
            ? payload.user_id.trim()
            : typeof payload?.sub === 'string'
                ? payload.sub.trim()
                : null;

        const tokenInternalUserId = typeof payload?.id === 'string'
            ? payload.id.trim()
            : null;

        const hasTokenIdentity = Boolean(tokenTeacherId || tokenUsername || tokenInternalUserId);
        const hasQueryIdentity = Boolean(queryTeacherId || queryUsername);
        const teacherId = hasTokenIdentity ? tokenTeacherId : queryTeacherId;
        const username = hasTokenIdentity ? tokenUsername : queryUsername;

        return {
            teacherId: teacherId || tokenTeacherId || null,
            username: username || null,
            internalUserId: tokenInternalUserId || (isObjectId(teacherId) ? teacherId : null),
            teacherObjectId: isObjectId(teacherId) ? teacherId : null,
            source: hasTokenIdentity || !hasQueryIdentity ? 'token' : 'query'
        };
    }

    private async resolveTeacherObjectId(
        principal: TeacherPrincipal,
        idTokenOverride?: string
    ): Promise<{ teacherObjectId: string | null; username: string | null }> {
        if (principal.teacherObjectId && isObjectId(principal.teacherObjectId)) {
            return {
                teacherObjectId: principal.teacherObjectId,
                username: principal.username
            };
        }

        if (principal.internalUserId && isObjectId(principal.internalUserId)) {
            const teacher = await this.lmsService.getTeacherByUserId(principal.internalUserId, idTokenOverride);
            if (teacher?.id) {
                return {
                    teacherObjectId: teacher.id,
                    username: teacher.username || principal.username
                };
            }
        }

        if (principal.teacherId && isObjectId(principal.teacherId)) {
            const teacher = await this.lmsService.getTeacherByUserId(principal.teacherId, idTokenOverride);
            if (teacher?.id) {
                return {
                    teacherObjectId: teacher.id,
                    username: teacher.username || principal.username
                };
            }

            return {
                teacherObjectId: principal.teacherId,
                username: principal.username
            };
        }

        if (principal.username) {
            const teacher = await this.lmsService.findTeacherByUsername(principal.username, idTokenOverride);
            if (teacher?.id) {
                return {
                    teacherObjectId: teacher.id,
                    username: teacher.username || principal.username
                };
            }
        }

        return {
            teacherObjectId: null,
            username: principal.username
        };
    }

    private collectSlotsFromTimesheet(
        items: LmsTimesheetItem[],
        month: number,
        year: number,
        timezone: string
    ): PayrollSlotItem[] {
        const slots: PayrollSlotItem[] = [];

        items.forEach((item) => {
            const type = normalizeStatus(item.type);
            if (type !== 'ATTENDANCE_CLASS') {
                return;
            }

            const attendance = item.classSessionAttendance;
            if (!attendance?.id || !attendance.class?.id || !attendance.startTime) {
                return;
            }

            const slotStartDate = parseLmsDateTime(attendance.startTime);
            if (!slotStartDate) {
                return;
            }

            const slotDateParts = getDatePartsInTimeZone(slotStartDate, timezone);
            if (slotDateParts.year !== year || slotDateParts.month !== month) {
                return;
            }

            const slotEndDate = parseLmsDateTime(attendance.endTime);
            const sessionHour = typeof attendance.sessionHour === 'number'
                ? attendance.sessionHour
                : Number.NaN;
            const durationHours = Number.isFinite(sessionHour) && sessionHour > 0
                ? round2(sessionHour)
                : getSlotDurationHours(attendance.startTime, attendance.endTime);

            slots.push({
                classId: attendance.class.id,
                className: attendance.class.name || 'UNKNOWN',
                slotId: attendance.id,
                slotIndex: null,
                startTime: slotStartDate.toISOString(),
                endTime: slotEndDate ? slotEndDate.toISOString() : null,
                attendanceStatus: normalizeStatus(attendance.status),
                roleName: null,
                roleShortName: null,
                durationHours
            });
        });

        return slots;
    }

    private collectOfficeHoursFromTimesheet(
        items: LmsTimesheetItem[],
        month: number,
        year: number,
        timezone: string
    ): PayrollOfficeHourItem[] {
        const officeHours: PayrollOfficeHourItem[] = [];

        items.forEach((item) => {
            const type = normalizeStatus(item.type);
            if (type !== 'OFFICE_HOUR') {
                return;
            }

            const officeHour = item.officeHour;
            if (!officeHour?.startTime) {
                return;
            }

            const officeHourStartDate = parseLmsDateTime(officeHour.startTime) || parseLmsDateTime(item.date);
            if (!officeHourStartDate) {
                return;
            }

            const dateParts = getDatePartsInTimeZone(officeHourStartDate, timezone);
            if (dateParts.year !== year || dateParts.month !== month) {
                return;
            }

            const normalizedStatus = normalizeStatus(officeHour.status || item.status);
            if (isExcludedOfficeHourStatus(normalizedStatus)) {
                return;
            }

            const officeHourEndDate = parseLmsDateTime(officeHour.endTime);
            const durationHours = getSlotDurationHours(officeHour.startTime, officeHour.endTime);
            const parsedStudentCount = Number.parseInt(String(officeHour.studentCount ?? ''), 10);
            const studentCount = Number.isFinite(parsedStudentCount) && parsedStudentCount > 0
                ? parsedStudentCount
                : 0;

            officeHours.push({
                timesheetId: item.id || '',
                officeHourId: officeHour.id || null,
                startTime: officeHourStartDate.toISOString(),
                endTime: officeHourEndDate ? officeHourEndDate.toISOString() : null,
                status: normalizedStatus,
                officeHourType: officeHour.type || null,
                studentCount,
                durationHours,
                note: officeHour.note || null,
                managerNote: officeHour.managerNote || null,
                shortName: officeHour.shortName || null
            });
        });

        officeHours.sort((a, b) => {
            const aTime = parseLmsDateTime(a.startTime)?.getTime() ?? 0;
            const bTime = parseLmsDateTime(b.startTime)?.getTime() ?? 0;
            return aTime - bTime;
        });

        return officeHours;
    }

    private collectSlotsForClass(
        cls: LmsClassRecord,
        principal: TeacherPrincipal,
        month: number,
        year: number,
        timezone: string
    ): PayrollSlotItem[] {
        const slots: PayrollSlotItem[] = [];

        (cls.slots || []).forEach((slot) => {
            if (!slot._id || !slot.startTime) {
                return;
            }

            const slotStartDate = parseLmsDateTime(slot.startTime);
            if (!slotStartDate) {
                return;
            }

            const slotDateParts = getDatePartsInTimeZone(slotStartDate, timezone);
            if (slotDateParts.year !== year || slotDateParts.month !== month) {
                return;
            }

            const slotRole = getRoleFromAssignments(slot.teachers, principal);
            const classRole = getRoleFromAssignments(cls.teachers, principal);
            const attendance = getAttendanceMatch(slot.teacherAttendance, principal);
            const hasAnyTeacherMatch = Boolean(slotRole || classRole || attendance);
            if (!hasAnyTeacherMatch) {
                return;
            }

            const attendanceStatus = normalizeStatus(attendance?.status);
            const role = slotRole || classRole || null;
            slots.push({
                classId: cls.id,
                className: cls.name,
                slotId: slot._id,
                slotIndex: typeof slot.index === 'number' ? slot.index : null,
                startTime: slot.startTime,
                endTime: slot.endTime ?? null,
                attendanceStatus,
                roleName: role?.name ?? null,
                roleShortName: role?.shortName ?? null,
                durationHours: getSlotDurationHours(slot.startTime, slot.endTime)
            });
        });

        return slots;
    }

    async getMonthlyPayroll(params: PayrollParams, idTokenOverride?: string) {
        const timezoneInput = String(params.timezone ?? 'Asia/Ho_Chi_Minh').trim() || 'Asia/Ho_Chi_Minh';
        const timezone = isValidTimeZone(timezoneInput) ? timezoneInput : 'Asia/Ho_Chi_Minh';

        const now = new Date();
        const nowParts = getDatePartsInTimeZone(now, timezone);
        const month = parseIntegerInRange(params.month, nowParts.month, 1, 12);
        const year = parseIntegerInRange(params.year, nowParts.year, 2000, 2100);
        const itemsPerPage = parseIntegerInRange(
            params.itemsPerPage,
            env.DEFAULT_ITEMS_PER_PAGE,
            1,
            env.MAX_ITEMS_PER_PAGE
        );
        const maxPages = parseIntegerInRange(
            params.maxPages,
            env.DEFAULT_MAX_PAGES,
            1,
            env.MAX_MAX_PAGES
        );
        const countedStatusesSet = new Set(normalizeCountedStatuses(params.countedStatuses));

        const principal = await this.resolvePrincipal(params.teacherId, params.username, idTokenOverride);
        if (!principal.teacherId && !principal.username && !principal.internalUserId) {
            throw new Error('Khong xac dinh duoc teacher. Hay truyen teacherId hoac username');
        }

        const resolvedTeacher = await this.resolveTeacherObjectId(principal, idTokenOverride);
        principal.teacherObjectId = resolvedTeacher.teacherObjectId;
        principal.username = resolvedTeacher.username || principal.username;

        let allAssignedSlotItems: PayrollSlotItem[] = [];
        let officeHourItems: PayrollOfficeHourItem[] = [];
        let meta: PayrollFetchMeta = {
            fetchedPages: 0,
            itemsPerPage,
            maxPages,
            totalRawClasses: 0,
            totalUniqueClasses: 0
        };

        const monthRange = buildMonthQueryRange(month, year);

        const runClassScanFallback = async () => {
            const {
                classes,
                fetchedPages,
                totalRawClasses,
                totalUniqueClasses
            } = await this.lmsService.fetchUniqueClassesForPayroll(
                itemsPerPage,
                maxPages,
                idTokenOverride
            );

            meta = {
                fetchedPages,
                itemsPerPage,
                maxPages,
                totalRawClasses,
                totalUniqueClasses
            };

            const scannedSlots: PayrollSlotItem[] = [];
            classes.forEach((cls) => {
                const slotItems = this.collectSlotsForClass(
                    cls,
                    principal,
                    month,
                    year,
                    timezone
                );
                scannedSlots.push(...slotItems);
            });

            allAssignedSlotItems = scannedSlots;
        };

        if (!principal.teacherObjectId) {
            await runClassScanFallback();
        } else {
            try {
                const timesheetItems = await this.lmsService.findTimesheetByTeacher(
                    principal.teacherObjectId,
                    monthRange.startIso,
                    monthRange.endIso,
                    idTokenOverride
                );

                allAssignedSlotItems = this.collectSlotsFromTimesheet(
                    timesheetItems,
                    month,
                    year,
                    timezone
                );

                const classIds = Array.from(
                    new Set(allAssignedSlotItems.map((item) => item.classId).filter(Boolean))
                );
                if (classIds.length > 0) {
                    const {
                        classes,
                        fetchedPages,
                        totalRawClasses,
                        totalUniqueClasses
                    } = await this.lmsService.fetchUniqueClassesForPayroll(
                        itemsPerPage,
                        maxPages,
                        idTokenOverride,
                        {
                            id_in: classIds,
                            teacher_equals: principal.teacherObjectId,
                            haveSlot_from: monthRange.startIso,
                            haveSlot_to: monthRange.endIso
                        }
                    );

                    meta = {
                        fetchedPages,
                        itemsPerPage,
                        maxPages,
                        totalRawClasses,
                        totalUniqueClasses
                    };

                    const roleBySlotId = new Map<string, {
                        roleName: string | null;
                        roleShortName: string | null;
                        slotIndex: number | null;
                    }>();

                    classes.forEach((cls) => {
                        const classSlots = this.collectSlotsForClass(
                            cls,
                            principal,
                            month,
                            year,
                            timezone
                        );
                        classSlots.forEach((slot) => {
                            roleBySlotId.set(slot.slotId, {
                                roleName: slot.roleName,
                                roleShortName: slot.roleShortName,
                                slotIndex: slot.slotIndex
                            });
                        });
                    });

                    allAssignedSlotItems = allAssignedSlotItems.map((slot) => {
                        const role = roleBySlotId.get(slot.slotId);
                        if (!role) {
                            return slot;
                        }

                        return {
                            ...slot,
                            roleName: role.roleName,
                            roleShortName: role.roleShortName,
                            slotIndex: role.slotIndex ?? slot.slotIndex
                        };
                    });
                }
            } catch {
                await runClassScanFallback();
            }

            try {
                const officeHourTimesheetItems = await this.lmsService.findOfficeHourTimesheetByTeacher(
                    principal.teacherObjectId,
                    monthRange.startIso,
                    monthRange.endIso,
                    idTokenOverride
                );
                officeHourItems = this.collectOfficeHoursFromTimesheet(
                    officeHourTimesheetItems,
                    month,
                    year,
                    timezone
                );
            } catch {
                officeHourItems = [];
            }
        }

        const allSlotItems = allAssignedSlotItems.filter((item) => countedStatusesSet.has(item.attendanceStatus));

        allSlotItems.sort((a, b) => {
            const aTime = parseLmsDateTime(a.startTime)?.getTime() ?? 0;
            const bTime = parseLmsDateTime(b.startTime)?.getTime() ?? 0;
            const timeDiff = aTime - bTime;
            if (timeDiff !== 0) {
                return timeDiff;
            }
            return a.className.localeCompare(b.className);
        });

        const classMap = new Map<string, {
            classId: string;
            className: string;
            taughtSlotCount: number;
            totalHours: number;
            roles: Set<string>;
            slots: PayrollSlotItem[];
        }>();
        const roleMap = new Map<string, {
            role: string;
            slotCount: number;
            totalHours: number;
            classIds: Set<string>;
        }>();
        const projectedRoleMap = new Map<string, {
            role: string;
            slotCount: number;
            totalHours: number;
            classIds: Set<string>;
        }>();

        allSlotItems.forEach((item) => {
            if (!classMap.has(item.classId)) {
                classMap.set(item.classId, {
                    classId: item.classId,
                    className: item.className,
                    taughtSlotCount: 0,
                    totalHours: 0,
                    roles: new Set<string>(),
                    slots: []
                });
            }

            const classEntry = classMap.get(item.classId)!;
            classEntry.taughtSlotCount += 1;
            classEntry.totalHours += item.durationHours;
            classEntry.slots.push(item);

            const roleKey = item.roleShortName || item.roleName || 'UNKNOWN';
            classEntry.roles.add(roleKey);

            if (!roleMap.has(roleKey)) {
                roleMap.set(roleKey, {
                    role: roleKey,
                    slotCount: 0,
                    totalHours: 0,
                    classIds: new Set<string>()
                });
            }

            const roleEntry = roleMap.get(roleKey)!;
            roleEntry.slotCount += 1;
            roleEntry.totalHours += item.durationHours;
            roleEntry.classIds.add(item.classId);
        });

        allAssignedSlotItems.forEach((item) => {
            const roleKey = item.roleShortName || item.roleName || 'UNKNOWN';
            if (!projectedRoleMap.has(roleKey)) {
                projectedRoleMap.set(roleKey, {
                    role: roleKey,
                    slotCount: 0,
                    totalHours: 0,
                    classIds: new Set<string>()
                });
            }

            const roleEntry = projectedRoleMap.get(roleKey)!;
            roleEntry.slotCount += 1;
            roleEntry.totalHours += item.durationHours;
            roleEntry.classIds.add(item.classId);
        });

        const classesData = Array.from(classMap.values())
            .map((entry) => ({
                classId: entry.classId,
                className: entry.className,
                taughtSlotCount: entry.taughtSlotCount,
                totalHours: round2(entry.totalHours),
                roles: Array.from(entry.roles.values()).sort(),
                slots: entry.slots
            }))
            .sort((a, b) => a.className.localeCompare(b.className));

        const byRole = Array.from(roleMap.values())
            .map((entry) => ({
                role: entry.role,
                slotCount: entry.slotCount,
                classCount: entry.classIds.size,
                totalHours: round2(entry.totalHours)
            }))
            .sort((a, b) => b.slotCount - a.slotCount);

        const totalHours = allSlotItems.reduce((sum, item) => sum + item.durationHours, 0);
        const projectedTotalHours = allAssignedSlotItems.reduce((sum, item) => sum + item.durationHours, 0);
        const projectedByRole = Array.from(projectedRoleMap.values())
            .map((entry) => ({
                role: entry.role,
                slotCount: entry.slotCount,
                classCount: entry.classIds.size,
                totalHours: round2(entry.totalHours)
            }))
            .sort((a, b) => b.slotCount - a.slotCount);

        return {
            month,
            year,
            timezone,
            principal: {
                teacherId: principal.teacherId,
                username: principal.username,
                source: principal.source
            },
            countedStatuses: Array.from(countedStatusesSet.values()),
            summary: {
                totalTaughtSlots: allSlotItems.length,
                totalClasses: classesData.length,
                totalHours: round2(totalHours),
                byRole
            },
            projection: {
                totalAssignedSlots: allAssignedSlotItems.length,
                totalAssignedHours: round2(projectedTotalHours),
                byRole: projectedByRole
            },
            officeHours: officeHourItems,
            classes: classesData,
            meta: {
                fetchedPages: meta.fetchedPages,
                itemsPerPage: meta.itemsPerPage,
                maxPages: meta.maxPages,
                totalRawClasses: meta.totalRawClasses,
                totalUniqueClasses: meta.totalUniqueClasses
            }
        };
    }
}
