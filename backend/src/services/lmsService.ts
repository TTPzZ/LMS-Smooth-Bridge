import axios from 'axios';
import { env } from '../config/env';
import { LmsClassRecord } from '../types/lms';
import { AuthTokenService } from './authTokenService';

class LmsGraphqlError extends Error {
    isAuthError: boolean;

    constructor(message: string, isAuthError: boolean = false) {
        super(message);
        this.name = 'LmsGraphqlError';
        this.isAuthError = isAuthError;
    }
}

function isAuthRelatedMessage(message: string | undefined): boolean {
    if (!message) {
        return false;
    }

    const normalized = message.toLowerCase();
    return normalized.includes('unauth')
        || normalized.includes('not authenticated')
        || normalized.includes('jwt expired');
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

function isHttpAuthError(error: unknown): boolean {
    if (!axios.isAxiosError(error)) {
        return false;
    }

    const statusCode = error.response?.status;
    return statusCode === 401 || statusCode === 403;
}

export type FetchUniqueClassesResult = {
    classes: LmsClassRecord[];
    fetchedPages: number;
    totalRawClasses: number;
    totalUniqueClasses: number;
};

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

    private async callLmsGraphqlWithAutoRefresh<T>(queryPayload: unknown): Promise<T> {
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

    async getClassesPage(pageIndex: number, itemsPerPage: number): Promise<LmsClassRecord[]> {
        const graphqlQuery = {
            operationName: 'GetClasses',
            query: `query GetClasses($pageIndex: Int!, $itemsPerPage: Int!) {
              classes(payload: {pageIndex: $pageIndex, itemsPerPage: $itemsPerPage}) {
                data {
                  id
                  name
                  status
                  endDate
                  slots {
                    _id
                    index
                    date
                    startTime
                    endTime
                    studentAttendance {
                      _id
                      status
                      student {
                        id
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
        }>(graphqlQuery);

        const classes = responseData?.data?.classes?.data;
        if (!Array.isArray(classes)) {
            return [];
        }

        return classes as LmsClassRecord[];
    }

    async getClassesPageForPayroll(pageIndex: number, itemsPerPage: number): Promise<LmsClassRecord[]> {
        const graphqlQuery = {
            operationName: 'GetClassesForPayroll',
            query: `query GetClassesForPayroll($pageIndex: Int!, $itemsPerPage: Int!) {
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
        }>(graphqlQuery);

        const classes = responseData?.data?.classes?.data;
        if (!Array.isArray(classes)) {
            return [];
        }

        return classes as LmsClassRecord[];
    }

    async fetchUniqueClasses(
        itemsPerPage: number = env.DEFAULT_ITEMS_PER_PAGE,
        maxPages: number = env.DEFAULT_MAX_PAGES
    ): Promise<FetchUniqueClassesResult> {
        return this.fetchUniqueClassesByPageFetcher(
            (pageIndex, perPage) => this.getClassesPage(pageIndex, perPage),
            itemsPerPage,
            maxPages
        );
    }

    async fetchUniqueClassesForPayroll(
        itemsPerPage: number = env.DEFAULT_ITEMS_PER_PAGE,
        maxPages: number = env.DEFAULT_MAX_PAGES
    ): Promise<FetchUniqueClassesResult> {
        return this.fetchUniqueClassesByPageFetcher(
            (pageIndex, perPage) => this.getClassesPageForPayroll(pageIndex, perPage),
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

    async getCurrentAuthToken(): Promise<string> {
        return this.authTokenService.getValidIdToken(false);
    }
}
