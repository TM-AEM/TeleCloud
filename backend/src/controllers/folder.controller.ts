import { Request, Response, NextFunction } from 'express';
import { folderService } from '../services/folder.service.js';
import { AppError } from '../errors/app-error.js';

export class FolderController {
  /**
   * إنشاء مجلد وهمي يخص المستخدم الحالي
   * POST /api/folders
   */
  async create(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const userId = req.user!.id;
      const { name, parentId, parentFolderId } = req.body;
      const targetParentId = parentId || parentFolderId || null;

      if (!name || typeof name !== 'string') {
        throw AppError.badRequest('يرجى تقديم اسم صالح للمجلد');
      }

      const folder = await folderService.createFolder(userId, name, targetParentId);

      res.status(201).json({
        success: true,
        message: 'تم إنشاء المجلد بنجاح',
        data: folder,
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * جلب تفاصيل مجلد محدد للمستخدم
   * GET /api/folders/:id
   */
  async getById(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const userId = req.user!.id;
      const { id } = req.params;
      if (!id) {
        throw AppError.badRequest('معرّف المجلد مطلوب');
      }

      const folder = await folderService.getFolderById(userId, id);

      res.status(200).json({
        success: true,
        data: folder,
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * حذف مجلد يخص المستخدم الحالي
   * DELETE /api/folders/:id
   */
  async delete(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const userId = req.user!.id;
      const { id } = req.params;
      if (!id) {
        throw AppError.badRequest('معرّف المجلد مطلوب');
      }

      const telegramConfig = req.telegramConfig;
      const result = await folderService.deleteFolder(userId, id, telegramConfig);

      res.status(200).json(result);
    } catch (error) {
      next(error);
    }
  }
}

export const folderController = new FolderController();
