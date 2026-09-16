import { Request, Response, NextFunction } from 'express';
import { fileService } from '../services/file.service.js';
import { AppError } from '../errors/app-error.js';

export class FileController {
  /**
   * رفع ملف جديد يخص المستخدم المصرح له
   * POST /api/files/upload
   */
  async upload(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      if (!req.file) {
        throw AppError.badRequest('يرجى إرفاق ملف في حقل "file"');
      }

      const userId = req.user!.id;
      const telegramConfig = req.telegramConfig!;
      const parentFolderId = req.body.parentFolderId || req.body.parent_folder_id || null;

      const uploadedFile = await fileService.uploadFile(userId, req.file, telegramConfig, parentFolderId);

      res.status(201).json({
        success: true,
        message: 'تم رفع الملف وحفظ بياناته بنجاح',
        data: uploadedFile,
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * تنزيل ملف عبر دفق البيانات (Stream) للمستخدم صاحب الملف
   * GET /api/files/:id/download
   */
  async download(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const { id } = req.params;
      if (!id) {
        throw AppError.badRequest('معرّف الملف مطلوب');
      }

      const userId = req.user!.id;
      const telegramConfig = req.telegramConfig!;

      const { file, streamResult } = await fileService.getFileForDownload(userId, id, telegramConfig);

      // تشفير اسم الملف وفق مواصفات RFC 5987 للتعامل مع الأسماء العربية والرموز
      const encodedFilename = encodeURIComponent(file.name);

      res.setHeader('Content-Type', file.mimeType || 'application/octet-stream');
      res.setHeader(
        'Content-Disposition',
        `attachment; filename="${encodedFilename}"; filename*=UTF-8''${encodedFilename}`
      );

      if (file.size) {
        res.setHeader('Content-Length', file.size.toString());
      }

      // توجيه تدفق الملف مباشرة إلى استجابة العميل
      streamResult.stream.pipe(res);

      streamResult.stream.on('error', (err) => {
        console.error('خطأ أثناء بث الملف:', err);
        if (!res.headersSent) {
          next(AppError.internal('انقطع الاتصال أثناء تدفق الملف'));
        }
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * استعراض الملفات والمجلدات الخاصة بالمستخدم مع دعم التصفح والفلترة
   * GET /api/files
   */
  async list(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const userId = req.user!.id;
      const parentFolderId = (req.query.parentFolderId || req.query.parent_folder_id) as string | undefined;
      const page = req.query.page ? parseInt(req.query.page as string, 10) : 1;
      const limit = req.query.limit ? parseInt(req.query.limit as string, 10) : 20;
      const search = req.query.search as string | undefined;

      const result = await fileService.listItems(userId, {
        parentFolderId,
        page,
        limit,
        search,
      });

      res.status(200).json({
        success: true,
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * حذف ملف من تيليجرام وقاعدة البيانات للمستخدم المصرح له
   * DELETE /api/files/:id
   */
  async delete(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const { id } = req.params;
      if (!id) {
        throw AppError.badRequest('معرّف الملف مطلوب');
      }

      const userId = req.user!.id;
      const telegramConfig = req.telegramConfig!;

      const result = await fileService.deleteFile(userId, id, telegramConfig);

      res.status(200).json(result);
    } catch (error) {
      next(error);
    }
  }
}

export const fileController = new FileController();
