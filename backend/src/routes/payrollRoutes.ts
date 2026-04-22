import { Router, Request, Response } from 'express';
import { PayrollService } from '../services/payrollService';

export function createPayrollRouter(payrollService: PayrollService): Router {
    const router = Router();

    router.get('/payroll/monthly', async (req: Request, res: Response) => {
        try {
            const data = await payrollService.getMonthlyPayroll({
                month: req.query.month,
                year: req.query.year,
                timezone: req.query.timezone,
                teacherId: req.query.teacherId,
                username: req.query.username,
                itemsPerPage: req.query.itemsPerPage,
                maxPages: req.query.maxPages,
                countedStatuses: req.query.countedStatuses
            });

            res.json({
                success: true,
                data
            });
        } catch (error: any) {
            const detail = error?.response?.data || error?.message || 'Payroll query failed';
            const statusCode = typeof error?.response?.status === 'number' ? error.response.status : 400;
            res.status(statusCode).json({
                success: false,
                error: 'Khong lay duoc du lieu payroll',
                detail
            });
        }
    });

    return router;
}
