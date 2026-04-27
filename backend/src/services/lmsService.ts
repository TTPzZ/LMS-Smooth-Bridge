import axios from 'axios';
import { env } from '../config/env';
import {
    LmsClassRecord,
    LmsSlotAttendanceCommand,
    LmsTeacherProfile,
    LmsTimesheetItem
} from '../types/lms';
import { AuthTokenService } from './authTokenService';

class LmsGraphqlError extends Error {
    isAuthError: boolean;

    constructor(message: string, isAuthError: boolean = false) {
        super(message);
        this.name = 'LmsGraphqlError';
        this.isAuthError = isAuthError;
    }
}

export class LmsClientAuthError extends Error {
    statusCode: number;

    constructor(message: string = 'Unauthorized: invalid or expired Bearer token') {
        super(message);
        this.name = 'LmsClientAuthError';
        this.statusCode = 401;
    }
}

function isAuthRelatedMessage(message: string | undefined): boolean {
    if (!message) {
        return false;
    }

    const normalized = message.toLowerCase();
    const authIndicators = [
        'unauth',
        'not authenticated',
        'jwt expired',
        'authentication failed',
        'failed to build auth user',
        'invalid token',
        'token expired',
        'id token'
    ];

    return authIndicators.some((indicator) => normalized.includes(indicator));
}

function extractAxiosErrorMessage(error: unknown): string {
    if (!axios.isAxiosError(error)) {
        return '';
    }

    const chunks: string[] = [];
    if (error.message) {
        chunks.push(error.message);
    }

    const responseData = error.response?.data;
    if (typeof responseData === 'string') {
        chunks.push(responseData);
    } else if (responseData && typeof responseData === 'object') {
        const data = responseData as { message?: unknown; error?: unknown; detail?: unknown };
        if (typeof data.message === 'string') {
            chunks.push(data.message);
        }
        if (typeof data.error === 'string') {
            chunks.push(data.error);
        }
        if (typeof data.detail === 'string') {
            chunks.push(data.detail);
        }

        try {
            chunks.push(JSON.stringify(responseData));
        } catch {
            // Ignore stringify failures.
        }
    }

    return chunks.join(' | ');
}

function isHttpStatusAuthError(error: unknown): boolean {
    if (!axios.isAxiosError(error)) {
        return false;
    }

    const statusCode = error.response?.status;
    return statusCode === 401 || statusCode === 403;
}

function isHttpAuthLikeError(error: unknown): boolean {
    if (isHttpStatusAuthError(error)) {
        return true;
    }

    const combined = extractAxiosErrorMessage(error);
    return isAuthRelatedMessage(combined);
}

function isHttpAuthError(error: unknown): boolean {
    return isHttpAuthLikeError(error);
}

function parseGraphqlErrors(errors: unknown): { message: string; isAuthError: boolean } {
    if (!Array.isArray(errors) || errors.length === 0) {
        return {
            message: 'GraphQL returned unknown errors',
            isAuthError: false
        };
    }

    const messages: string[] = [];
    let isAuthError = false;

    errors.forEach((item) => {
        const entry = item as { message?: string; extensions?: { code?: string } };
        if (entry.message) {
            messages.push(entry.message);
        }

        if (entry.extensions?.code && entry.extensions.code.toUpperCase() === 'UNAUTHENTICATED') {
            isAuthError = true;
        }
        if (isAuthRelatedMessage(entry.message)) {
            isAuthError = true;
        }
    });

    return {
        message: messages.filter(Boolean).join(' | ') || 'GraphQL returned unknown errors',
        isAuthError
    };
}

export type FetchUniqueClassesResult = {
    classes: LmsClassRecord[];
    fetchedPages: number;
    totalRawClasses: number;
    totalUniqueClasses: number;
};

type ClassQueryFilters = Record<string, unknown>;

export class LmsService {
    constructor(private readonly authTokenService: AuthTokenService) {}

    private async callLmsGraphql<T>(queryPayload: unknown, idToken: string): Promise<T> {
        const response = await axios.post(env.LMS_GRAPHQL_URL, queryPayload, {
            headers: {
                Authorization: `Bearer ${idToken}`,
                'Content-Type': 'application/json'
            }
        });

        const graphqlErrors = response.data?.errors;
        if (Array.isArray(graphqlErrors) && graphqlErrors.length > 0) {
            const { message, isAuthError } = parseGraphqlErrors(graphqlErrors);
            throw new LmsGraphqlError(message, isAuthError);
        }

        return response.data as T;
    }

    private async callLmsGraphqlWithAutoRefresh<T>(queryPayload: unknown, idTokenOverride?: string): Promise<T> {
        const normalizedOverrideToken = String(idTokenOverride ?? '').trim();
        if (normalizedOverrideToken) {
            try {
                return await this.callLmsGraphql<T>(queryPayload, normalizedOverrideToken);
            } catch (error) {
                const isAuthError =
                    (error instanceof LmsGraphqlError && error.isAuthError) || isHttpAuthError(error);
                if (isAuthError) {
                    throw new LmsClientAuthError();
                }

                throw error;
            }
        }

        const firstToken = await this.authTokenService.getValidIdToken(false);

        try {
            return await this.callLmsGraphql<T>(queryPayload, firstToken);
        } catch (error) {
            const shouldRetry =
                (error instanceof LmsGraphqlError && error.isAuthError) || isHttpAuthError(error);

            if (!shouldRetry) {
                throw error;
            }
        }

        const refreshedToken = await this.authTokenService.getValidIdToken(true);
        return this.callLmsGraphql<T>(queryPayload, refreshedToken);
    }

    async getTeacherByUserId(userId: string, idTokenOverride?: string): Promise<LmsTeacherProfile | null> {
        const normalizedUserId = String(userId ?? '').trim();
        if (!normalizedUserId) {
            return null;
        }

        const graphqlQuery = {
            operationName: 'TeacherByUserId',
            query: `query TeacherByUserId($payload: TeacherByUserIdQuery) {
              teacherByUserId(payload: $payload) {
                id
                user
                username
                fullName
                hourlyRate
                firebaseId
              }
            }`,
            variables: {
                payload: {
                    user: normalizedUserId
                }
            }
        };

        const responseData = await this.callLmsGraphqlWithAutoRefresh<{
            data?: {
                teacherByUserId?: LmsTeacherProfile | null;
            };
        }>(graphqlQuery, idTokenOverride);

        const teacher = responseData?.data?.teacherByUserId;
        if (!teacher?.id) {
            return null;
        }

        return teacher;
    }

    async findTeacherByUsername(username: string, idTokenOverride?: string): Promise<LmsTeacherProfile | null> {
        const normalizedUsername = String(username ?? '').trim();
        if (!normalizedUsername) {
            return null;
        }

        const graphqlQuery = {
            operationName: 'FindTeachersByUsername',
            query: `query FindTeachersByUsername($payload: TeacherQuery) {
              teachers(payload: $payload) {
                data {
                  id
                  user
                  username
                  fullName
                  hourlyRate
                  firebaseId
                }
              }
            }`,
            variables: {
                payload: {
                    filter_textSearch: normalizedUsername,
                    pageIndex: 0,
                    itemsPerPage: 20
                }
            }
        };

        const responseData = await this.callLmsGraphqlWithAutoRefresh<{
            data?: {
                teachers?: {
                    data?: LmsTeacherProfile[];
                };
            };
        }>(graphqlQuery, idTokenOverride);

        const teachers = responseData?.data?.teachers?.data;
        if (!Array.isArray(teachers) || teachers.length === 0) {
            return null;
        }

        const exact = teachers.find((teacher) =>
            typeof teacher?.username === 'string'
            && teacher.username.toLowerCase() === normalizedUsername.toLowerCase()
        );

        return exact || null;
    }

    async findTimesheetByTeacher(
        teacherId: string,
        startDate: string,
        endDate: string,
        idTokenOverride?: string
    ): Promise<LmsTimesheetItem[]> {
        const normalizedTeacherId = String(teacherId ?? '').trim();
        if (!normalizedTeacherId) {
            return [];
        }

        const graphqlQuery = {
            operationName: 'FindTimesheetByTeacher',
            query: `query FindTimesheetByTeacher($payload: TimesheetItemQuery) {
              findTimesheetByTeacher(payload: $payload) {
                id
                type
                date
                status
                teacher {
                  id
                  username
                  fullName
                }
                classSessionAttendance {
                  id
                  startTime
                  endTime
                  sessionHour
                  status
                  class {
                    id
                    name
                  }
                }
              }
            }`,
            variables: {
                payload: {
                    teacherId: normalizedTeacherId,
                    startDate,
                    endDate
                }
            }
        };

        const responseData = await this.callLmsGraphqlWithAutoRefresh<{
            data?: {
                findTimesheetByTeacher?: LmsTimesheetItem[];
            };
        }>(graphqlQuery, idTokenOverride);

        const items = responseData?.data?.findTimesheetByTeacher;
        if (!Array.isArray(items)) {
            return [];
        }

        return items;
    }

    async findOfficeHourTimesheetByTeacher(
        teacherId: string,
        startDate: string,
        endDate: string,
        idTokenOverride?: string
    ): Promise<LmsTimesheetItem[]> {
        const normalizedTeacherId = String(teacherId ?? '').trim();
        if (!normalizedTeacherId) {
            return [];
        }

        const graphqlQuery = {
            operationName: 'FindOfficeHourTimesheetByTeacher',
            query: `query FindOfficeHourTimesheetByTeacher($payload: TimesheetItemQuery) {
              findTimesheetByTeacher(payload: $payload) {
                id
                type
                date
                status
                teacher {
                  id
                  username
                  fullName
                }
                officeHour {
                  id
                  startTime
                  endTime
                  status
                  type
                  studentCount
                  note
                  managerNote
                  shortName
                }
              }
            }`,
            variables: {
                payload: {
                    teacherId: normalizedTeacherId,
                    startDate,
                    endDate,
                    type: 'OFFICE_HOUR'
                }
            }
        };

        const responseData = await this.callLmsGraphqlWithAutoRefresh<{
            data?: {
                findTimesheetByTeacher?: LmsTimesheetItem[];
            };
        }>(graphqlQuery, idTokenOverride);

        const items = responseData?.data?.findTimesheetByTeacher;
        if (!Array.isArray(items)) {
            return [];
        }

        return items;
    }

    async getClassesPage(pageIndex: number, itemsPerPage: number, idTokenOverride?: string): Promise<LmsClassRecord[]> {
        const graphqlQuery = {
            operationName: 'GetClasses',
            query: `query GetClasses($pageIndex: Int!, $itemsPerPage: Int!) {
              classes(payload: {pageIndex: $pageIndex, itemsPerPage: $itemsPerPage}) {
                data {
                  id
                  name
                  status
                  endDate
                  teachers {
                    _id
                    isActive
                    teacher {
                      id
                      username
                      fullName
                    }
                    role {
                      id
                      name
                      shortName
                    }
                  }
                  slots {
                    _id
                    index
                    date
                    startTime
                    endTime
                    teachers {
                      _id
                      isActive
                      teacher {
                        id
                        username
                        fullName
                      }
                      role {
                        id
                        name
                        shortName
                      }
                    }
                    studentAttendance {
                      _id
                      status
                      student {
                        id
                        fullName
                      }
                    }
                    teacherAttendance {
                      _id
                      status
                      note
                      teacher {
                        id
                        username
                        fullName
                      }
                    }
                  }
                }
              }
            }`,
            variables: {
                pageIndex,
                itemsPerPage
            }
        };

        const responseData = await this.callLmsGraphqlWithAutoRefresh<{
            data?: {
                classes?: {
                    data?: LmsClassRecord[];
                };
            };
        }>(graphqlQuery, idTokenOverride);

        const classes = responseData?.data?.classes?.data;
        if (!Array.isArray(classes)) {
            return [];
        }

        return classes as LmsClassRecord[];
    }

    async getClassesPageForPayroll(
        pageIndex: number,
        itemsPerPage: number,
        idTokenOverride?: string,
        filters?: ClassQueryFilters
    ): Promise<LmsClassRecord[]> {
        const graphqlQuery = {
            operationName: 'GetClassesForPayroll',
            query: `query GetClassesForPayroll($payload: ClassQuery) {
              classes(payload: $payload) {
                data {
                  id
                  name
                  status
                  endDate
                  teachers {
                    _id
                    isActive
                    teacher {
                      id
                      username
                      fullName
                    }
                    role {
                      id
                      name
                      shortName
                    }
                  }
                  slots {
                    _id
                    index
                    date
                    startTime
                    endTime
                    teachers {
                      _id
                      isActive
                      teacher {
                        id
                        username
                        fullName
                      }
                      role {
                        id
                        name
                        shortName
                      }
                    }
                    teacherAttendance {
                      _id
                      status
                      note
                      teacher {
                        id
                        username
                        fullName
                      }
                    }
                  }
                }
              }
            }`,
            variables: {
                payload: {
                    pageIndex,
                    itemsPerPage,
                    ...(filters || {})
                }
            }
        };

        const responseData = await this.callLmsGraphqlWithAutoRefresh<{
            data?: {
                classes?: {
                    data?: LmsClassRecord[];
                };
            };
        }>(graphqlQuery, idTokenOverride);

        const classes = responseData?.data?.classes?.data;
        if (!Array.isArray(classes)) {
            return [];
        }

        return classes as LmsClassRecord[];
    }

    async getClassByIdForAttendance(
        classId: string,
        idTokenOverride?: string
    ): Promise<LmsClassRecord | null> {
        const normalizedClassId = String(classId ?? '').trim();
        if (!normalizedClassId) {
            return null;
        }

        const graphqlQuery = {
            operationName: 'GetClassByIdForAttendance',
            query: `query GetClassByIdForAttendance($payload: ClassQuery) {
              classes(payload: $payload) {
                data {
                  id
                  name
                  status
                  endDate
                  classSites {
                    _id
                    name
                  }
                  students {
                    _id
                    activeInClass
                    classSite {
                      _id
                      name
                    }
                    student {
                      id
                      fullName
                    }
                  }
                  teachers {
                    _id
                    isActive
                    classSiteId
                    teacher {
                      id
                      username
                      fullName
                    }
                    role {
                      id
                      name
                      shortName
                    }
                  }
                  slots {
                    _id
                    index
                    date
                    startTime
                    endTime
                    teachers {
                      _id
                      isActive
                      classSiteId
                      teacher {
                        id
                        username
                        fullName
                      }
                      role {
                        id
                        name
                        shortName
                      }
                    }
                    studentAttendance {
                      _id
                      status
                      comment
                      student {
                        id
                        fullName
                      }
                    }
                    teacherAttendance {
                      _id
                      status
                      note
                      classSiteId
                      teacher {
                        id
                        username
                        fullName
                      }
                    }
                  }
                }
              }
            }`,
            variables: {
                payload: {
                    id_in: [normalizedClassId],
                    pageIndex: 0,
                    itemsPerPage: 1
                }
            }
        };

        const responseData = await this.callLmsGraphqlWithAutoRefresh<{
            data?: {
                classes?: {
                    data?: LmsClassRecord[];
                };
            };
        }>(graphqlQuery, idTokenOverride);

        const classes = responseData?.data?.classes?.data;
        if (!Array.isArray(classes) || classes.length === 0) {
            return null;
        }

        const matched = classes.find((item) => item?.id === normalizedClassId);
        return matched || classes[0] || null;
    }

    async updateSlotAttendance(
        payload: LmsSlotAttendanceCommand,
        idTokenOverride?: string
    ): Promise<{ classId: string }> {
        const graphqlMutation = {
            operationName: 'UpdateSlotAttendance',
            query: `mutation UpdateSlotAttendance($payload: SlotAttendanceCommand!) {
              classes {
                updateSlotAttendance(payload: $payload) {
                  id
                }
              }
            }`,
            variables: {
                payload
            }
        };

        const responseData = await this.callLmsGraphqlWithAutoRefresh<{
            data?: {
                classes?: {
                    updateSlotAttendance?: {
                        id?: string;
                    } | null;
                };
            };
        }>(graphqlMutation, idTokenOverride);

        const updatedClassId = responseData?.data?.classes?.updateSlotAttendance?.id;
        if (!updatedClassId) {
            throw new Error('Khong nhan duoc phan hoi updateSlotAttendance hop le');
        }

        return {
            classId: updatedClassId
        };
    }

    async fetchUniqueClasses(
        itemsPerPage: number = env.DEFAULT_ITEMS_PER_PAGE,
        maxPages: number = env.DEFAULT_MAX_PAGES,
        idTokenOverride?: string
    ): Promise<FetchUniqueClassesResult> {
        return this.fetchUniqueClassesByPageFetcher(
            (pageIndex, perPage) => this.getClassesPage(pageIndex, perPage, idTokenOverride),
            itemsPerPage,
            maxPages
        );
    }

    async fetchUniqueClassesForPayroll(
        itemsPerPage: number = env.DEFAULT_ITEMS_PER_PAGE,
        maxPages: number = env.DEFAULT_MAX_PAGES,
        idTokenOverride?: string,
        filters?: ClassQueryFilters
    ): Promise<FetchUniqueClassesResult> {
        return this.fetchUniqueClassesByPageFetcher(
            (pageIndex, perPage) => this.getClassesPageForPayroll(pageIndex, perPage, idTokenOverride, filters),
            itemsPerPage,
            maxPages
        );
    }

    private async fetchUniqueClassesByPageFetcher(
        pageFetcher: (pageIndex: number, itemsPerPage: number) => Promise<LmsClassRecord[]>,
        itemsPerPage: number,
        maxPages: number
    ): Promise<FetchUniqueClassesResult> {
        const rawClasses: LmsClassRecord[] = [];
        let fetchedPages = 0;

        for (let pageIndex = 0; pageIndex < maxPages; pageIndex += 1) {
            const pageData = await pageFetcher(pageIndex, itemsPerPage);
            fetchedPages += 1;

            if (pageData.length === 0) {
                break;
            }

            rawClasses.push(...pageData);

            if (pageData.length < itemsPerPage) {
                break;
            }
        }

        const uniqueClasses = new Map<string, LmsClassRecord>();
        rawClasses.forEach((cls) => {
            if (cls?.id && !uniqueClasses.has(cls.id)) {
                uniqueClasses.set(cls.id, cls);
            }
        });

        return {
            classes: Array.from(uniqueClasses.values()),
            fetchedPages,
            totalRawClasses: rawClasses.length,
            totalUniqueClasses: uniqueClasses.size
        };
    }

    async getCurrentAuthToken(idTokenOverride?: string): Promise<string> {
        const normalizedOverrideToken = String(idTokenOverride ?? '').trim();
        if (normalizedOverrideToken) {
            return normalizedOverrideToken;
        }

        return this.authTokenService.getValidIdToken(false);
    }
}
