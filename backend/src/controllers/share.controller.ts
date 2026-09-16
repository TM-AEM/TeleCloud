import { Request, Response, NextFunction } from 'express';
import rateLimit from 'express-rate-limit';
import { shareService } from '../services/share.service.js';
import { AppError } from '../errors/app-error.js';

/**
 * Rate Limiter للوصول العام إلى الروابط المشاركة:
 * بحد أقصى 20 محاولة كل 15 دقيقة لكل عنوان IP
 * مع رسالة خطأ عربية واضحة تمنع هجمات التخمين والقوة الغاشمة (Brute Force)
 */
export const shareRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 دقيقة
  max: 20, // 20 محاولة كحد أقصى لكل عنوان IP
  standardHeaders: true, // إرجاع ترويسات RateLimit-* المعيارية
  legacyHeaders: false, // إيقاف ترويسات X-RateLimit-* القديمة
  message: {
    success: false,
    statusCode: 429,
    message: 'تجاوزت الحد المسموح به لمحاولات الوصول إلى الروابط المشتركة (بحد أقصى 20 محاولة كل 15 دقيقة). يرجى الانتظار والمحاولة لاحقاً.',
  },
  handler: (_req: Request, res: Response, _next: NextFunction, options: any) => {
    res.status(options.statusCode).json(options.message);
  },
});

export class ShareController {
  /**
   * Rate limiting middleware متاح مباشرة عبر الـ Controller
   */
  readonly rateLimiter = shareRateLimiter;

  /**
   * إنشاء رابط مشاركة جديد لملف
   * POST /api/files/:id/share
   */
  async createShare(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const { id } = req.params;
      if (!id) {
        throw AppError.badRequest('معرّف الملف مطلوب');
      }

      const userId = req.user!.id;
      const { expiresInHours, maxDownloads } = req.body;

      if (!expiresInHours) {
        throw AppError.badRequest('يرجى تحديد مدة صلاحية الرابط بالساعات (expiresInHours)');
      }

      // تحديد أصل الطلب لتوليد الرابط الكامل
      const protocol = req.headers['x-forwarded-proto'] || req.protocol;
      const host = req.headers['x-forwarded-host'] || req.get('host');
      const origin = host ? `${protocol}://${host}` : undefined;

      const result = await shareService.createShareLink(
        userId,
        id,
        {
          expiresInHours: Number(expiresInHours),
          maxDownloads: maxDownloads !== undefined && maxDownloads !== null ? Number(maxDownloads) : null,
        },
        origin
      );

      res.status(201).json({
        success: true,
        message: 'تم إنشاء رابط المشاركة بنجاح',
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * استعراض جميع روابط المشاركة لملف معين
   * GET /api/files/:id/shares
   */
  async getFileShares(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const { id } = req.params;
      if (!id) {
        throw AppError.badRequest('معرّف الملف مطلوب');
      }

      const userId = req.user!.id;
      const protocol = req.headers['x-forwarded-proto'] || req.protocol;
      const host = req.headers['x-forwarded-host'] || req.get('host');
      const origin = host ? `${protocol}://${host}` : undefined;

      const shares = await shareService.getFileShares(userId, id, origin);

      res.status(200).json({
        success: true,
        data: shares,
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * تحميل الملف من خلال الرابط العام المباشر بدون تسجيل دخول
   * GET /api/share/:token
   */
  async downloadSharedFile(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const { token } = req.params;
      if (!token) {
        throw AppError.badRequest('رمز المشاركة مطلوب');
      }

      const { file, streamResult } = await shareService.getFileByShareToken(token);

      const encodedFilename = encodeURIComponent(file.name);

      res.setHeader('Content-Type', file.mimeType || 'application/octet-stream');
      res.setHeader(
        'Content-Disposition',
        `attachment; filename="${encodedFilename}"; filename*=UTF-8''${encodedFilename}`
      );

      if (file.size) {
        res.setHeader('Content-Length', file.size.toString());
      }

      // بث الملف مباشرة للمتصفح
      streamResult.stream.pipe(res);

      streamResult.stream.on('error', (err) => {
        console.error('خطأ أثناء بث الملف المشترك:', err);
        if (!res.headersSent) {
          next(AppError.internal('انقطع الاتصال أثناء تدفق الملف المشترك'));
        }
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * إلغاء رابط مشاركة
   * DELETE /api/shares/:shareId
   */
  async revokeShare(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const { shareId } = req.params;
      if (!shareId) {
        throw AppError.badRequest('معرّف رابط المشاركة مطلوب');
      }

      const userId = req.user!.id;
      const result = await shareService.revokeShareLink(userId, shareId);

      res.status(200).json(result);
    } catch (error) {
      next(error);
    }
  }
}

export const shareController = new ShareController();
