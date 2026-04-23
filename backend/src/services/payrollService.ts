import { env } from '../config/env';
import { LmsClassRecord, LmsTeacherAssignment, LmsTeacherAttendanceRecord } from '../types/lms';
import { decodeJwtPayload } from '../utils/jwt';
import { parseIntegerQuery } from '../utils/requestParsers';
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

function matchesTeacher(
    principal: TeacherPrincipal,
    candidate: { id?: string; username?: string } | undefined
): boolean {
    if (!candidate) {
        return false;
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

    const startMs = new Date(startTime).getTime();
    const endMs = new Date(endTime).getTime();
    if (Number.isNaN(startMs) || Number.isNaN(endMs) || endMs <= startMs) {
        return 0;
    }

    return Math.round(((endMs - startMs) / 3_600_000) * 100) / 100;
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

export class PayrollService {
    constructor(private readonly lmsService: LmsService) {}

    private async resolvePrincipal(
        teacherIdQuery: unknown,
        usernameQuery: unknown,
        idTokenOverride?: string
    ): Promise<TeacherPrincipal> {
        const teacherId = String(teacherIdQuery ?? '').trim() || null;
        const username = String(usernameQuery ?? '').trim() || null;

        if (teacherId || username) {
            return {
                teacherId,
                username,
                source: 'query'
            };
        }

        const token = await this.lmsService.getCurrentAuthToken(idTokenOverride);
        const payload = decodeJwtPayload(token);
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

        return {
            teacherId: tokenTeacherId || null,
            username: tokenUsername || null,
            source: 'token'
        };
    }

    private collectSlotsForClass(
        cls: LmsClassRecord,
        principal: TeacherPrincipal,
        month: number,
        year: number,
        timezone: string,
        countedStatuses: Set<string>
    ): PayrollSlotItem[] {
        const slots: PayrollSlotItem[] = [];

        (cls.slots || []).forEach((slot) => {
            if (!slot._id || !slot.startTime) {
                return;
            }

            const slotStartDate = new Date(slot.startTime);
            if (Number.isNaN(slotStartDate.getTime())) {
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
            if (!countedStatuses.has(attendanceStatus)) {
                return;
            }

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
        const month = parseIntegerQuery(params.month, nowParts.month);
        const year = parseIntegerQuery(params.year, nowParts.year);
        const itemsPerPage = parseIntegerQuery(params.itemsPerPage, env.DEFAULT_ITEMS_PER_PAGE);
        const maxPages = parseIntegerQuery(params.maxPages, env.DEFAULT_MAX_PAGES);
        const countedStatusesSet = new Set(normalizeCountedStatuses(params.countedStatuses));

        if (month < 1 || month > 12) {
            throw new Error('month khong hop le (1-12)');
        }

        const principal = await this.resolvePrincipal(params.teacherId, params.username, idTokenOverride);
        if (!principal.teacherId && !principal.username) {
            throw new Error('Khong xac dinh duoc teacher. Hay truyen teacherId hoac username');
        }

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

        const allSlotItems: PayrollSlotItem[] = [];
        classes.forEach((cls) => {
            const slotItems = this.collectSlotsForClass(
                cls,
                principal,
                month,
                year,
                timezone,
                countedStatusesSet
            );
            allSlotItems.push(...slotItems);
        });

        allSlotItems.sort((a, b) => {
            const timeDiff = new Date(a.startTime).getTime() - new Date(b.startTime).getTime();
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

        const classesData = Array.from(classMap.values())
            .map((entry) => ({
                classId: entry.classId,
                className: entry.className,
                taughtSlotCount: entry.taughtSlotCount,
                totalHours: Math.round(entry.totalHours * 100) / 100,
                roles: Array.from(entry.roles.values()).sort(),
                slots: entry.slots
            }))
            .sort((a, b) => a.className.localeCompare(b.className));

        const byRole = Array.from(roleMap.values())
            .map((entry) => ({
                role: entry.role,
                slotCount: entry.slotCount,
                classCount: entry.classIds.size,
                totalHours: Math.round(entry.totalHours * 100) / 100
            }))
            .sort((a, b) => b.slotCount - a.slotCount);

        const totalHours = allSlotItems.reduce((sum, item) => sum + item.durationHours, 0);

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
                totalHours: Math.round(totalHours * 100) / 100,
                byRole
            },
            classes: classesData,
            meta: {
                fetchedPages,
                itemsPerPage,
                maxPages,
                totalRawClasses,
                totalUniqueClasses
            }
        };
    }
}
