import { Request, Response, NextFunction } from 'express';
import multer from 'multer';
import { Prisma } from '@prisma/client';
import { ZodError } from 'zod';
import { AppError } from '../errors/app-error.js';
import { env } from '../config/env.js';

export function errorHandler(
  err: any,
  _req: Request,
  res: Response,
  _next: NextFunction
): void {
  // سجل الخطأ للمطورين في وضع التطوير
  if (env.NODE_ENV !== 'test') {
    console.error('💥 Error caught by middleware:', err);
  }

  // 1. أخطاء التطبيق المخصصة
  if (err instanceof AppError) {
    res.status(err.statusCode).json({
      success: false,
      message: err.message,
      details: err.details || null,
      statusCode: err.statusCode,
    });
    return;
  }

  // 2. أخطاء رفع الملفات (Multer)
  if (err instanceof multer.MulterError) {
    let message = 'خطأ أثناء رفع الملف';
    if (err.code === 'LIMIT_FILE_SIZE') {
      message = `حجم الملف يتجاوز الحد الأقصى المسموح به (${(env.MAX_FILE_SIZE_BYTES / (1024 * 1024)).toFixed(1)} ميجابايت)`;
    }
    res.status(400).json({
      success: false,
      message,
      code: err.code,
      statusCode: 400,
    });
    return;
  }

  // 3. أخطاء التحقق من البيانات (Zod)
  if (err instanceof ZodError) {
    res.status(400).json({
      success: false,
      message: 'البيانات المدخلة غير صالحة',
      errors: err.errors.map((e) => ({
        field: e.path.join('.'),
        message: e.message,
      })),
      statusCode: 400,
    });
    return;
  }

  // 4. أخطاء قاعدة البيانات (Prisma)
  if (err instanceof Prisma.PrismaClientKnownRequestError) {
    if (err.code === 'P2025') {
      res.status(404).json({
        success: false,
        message: 'السجل المطلوب غير موجود في قاعدة البيانات',
        code: err.code,
        statusCode: 404,
      });
      return;
    }
    if (err.code === 'P2003') {
      res.status(400).json({
        success: false,
        message: 'المجلد الأصلي (parent_folder_id) غير صالح أو غير موجود',
        code: err.code,
        statusCode: 400,
      });
      return;
    }
    res.status(400).json({
      success: false,
      message: 'خطأ في استعلام قاعدة البيانات',
      code: err.code,
      statusCode: 400,
    });
    return;
  }

  // 5. خطأ عام غير متوقع (500)
  res.status(500).json({
    success: false,
    message: 'حدث خطأ داخلي في الخادم',
    details: env.NODE_ENV === 'development' ? err.message : null,
    statusCode: 500,
  });
}
