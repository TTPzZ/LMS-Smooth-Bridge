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
import { parseBooleanQuery, parseIntegerQuery, sanitizePositiveInt } from '../utils/requestParsers';
import { LmsClassRecord } from '../types/lms';

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

export function createClassRouter(lmsService: LmsService): Router {
    const router = Router();

    router.get('/classes', async (req: Request, res: Response) => {
        try {
            const itemsPerPage = parseIntegerQuery(req.query.itemsPerPage, env.DEFAULT_ITEMS_PER_PAGE);
            const maxPages = parseIntegerQuery(req.query.maxPages, env.DEFAULT_MAX_PAGES);
            const activeOnly = parseBooleanQuery(req.query.activeOnly, true);
            const now = new Date();
            const nowMs = now.getTime();

            const {
                classes,
                fetchedPages,
                totalRawClasses,
                totalUniqueClasses
            } = await lmsService.fetchUniqueClasses(itemsPerPage, maxPages);

            const cleanClasses = classes
                .filter((cls) => (activeOnly ? isRunningClass(cls, now) : true))
                .map((cls) => {
                    const students = collectStudents(cls);
                    const upcomingWindows = getClassAttendanceWindows(cls, nowMs)
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
            const statusCode = error?.response?.status || 500;
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
            const itemsPerPage = parseIntegerQuery(req.query.itemsPerPage, env.DEFAULT_ITEMS_PER_PAGE);
            const maxPages = parseIntegerQuery(req.query.maxPages, env.DEFAULT_MAX_PAGES);
            const activeOnly = parseBooleanQuery(req.query.activeOnly, true);
            const lookAheadMinutes = sanitizePositiveInt(req.query.lookAheadMinutes, env.DEFAULT_LOOKAHEAD_MINUTES);
            const maxSlots = sanitizePositiveInt(req.query.maxSlots, env.DEFAULT_MAX_REMINDER_SLOTS);
            const now = new Date();
            const nowMs = now.getTime();
            const lookAheadUntilMs = nowMs + lookAheadMinutes * 60_000;

            const {
                classes,
                fetchedPages,
                totalRawClasses,
                totalUniqueClasses
            } = await lmsService.fetchUniqueClasses(itemsPerPage, maxPages);

            const filteredClasses = classes.filter((cls) => (activeOnly ? isRunningClass(cls, now) : true));
            const windows = filteredClasses.flatMap((cls) => getClassAttendanceWindows(cls, nowMs))
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
            const statusCode = error?.response?.status || 500;
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
