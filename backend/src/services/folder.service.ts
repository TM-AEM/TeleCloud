import { prisma } from '../lib/prisma.js';
import { telegramService } from './telegram.service.js';
import { AppError } from '../errors/app-error.js';
import { DecryptedTelegramConfig } from '../types/express.js';

export class FolderService {
  /**
   * إنشاء مجلد وهمي في قاعدة البيانات يخص المستخدم
   */
  async createFolder(userId: string, name: string, parentId?: string | null) {
    if (!name || name.trim().length === 0) {
      throw AppError.badRequest('اسم المجلد مطلوب');
    }

    // التحقق من وجود المجلد الأب إذا تم تمريره وأنه يتبع نفس المستخدم
    if (parentId && parentId !== 'root') {
      const parentExists = await prisma.folder.findFirst({
        where: { id: parentId, userId },
      });
      if (!parentExists) {
        throw AppError.badRequest('المجلد الأب المحدد غير موجود أو لا تملك صلاحية الوصول إليه');
      }
    }

    const effectiveParentId = parentId === 'root' ? null : parentId || null;

    const folder = await prisma.folder.create({
      data: {
        name: name.trim(),
        userId,
        parentId: effectiveParentId,
      },
    });

    return folder;
  }

  /**
   * جلب مجلد بالمعرّف مع التحقق من ملكية المستخدم
   */
  async getFolderById(userId: string, id: string) {
    const folder = await prisma.folder.findFirst({
      where: { id, userId },
      include: {
        parent: {
          select: { id: true, name: true },
        },
      },
    });

    if (!folder) {
      throw AppError.notFound('المجلد غير موجود أو لا تملك صلاحية الوصول إليه');
    }

    return folder;
  }

  /**
   * دالة مساعدة لجلب كافة معرّفات المجلدات المتداخلة (المجلد والمجلدات الفرعية منه)
   */
  private async getAllSubfolderIds(userId: string, rootFolderId: string): Promise<string[]> {
    const allFolderIds: string[] = [rootFolderId];
    let currentLevelFolderIds = [rootFolderId];

    while (currentLevelFolderIds.length > 0) {
      const subfolders = await prisma.folder.findMany({
        where: {
          userId,
          parentId: { in: currentLevelFolderIds },
        },
        select: { id: true },
      });

      if (subfolders.length === 0) {
        break;
      }

      currentLevelFolderIds = subfolders.map((f) => f.id);
      allFolderIds.push(...currentLevelFolderIds);
    }

    return allFolderIds;
  }

  /**
   * حذف مجلد وجميع المجلدات الفرعية والملفات التابعة له للمستخدم:
   * 1. جلب كل الملفات التابعة للمجلد والمجلدات الفرعية بشكل متداخل (Recursive).
   * 2. حذف رسائل كل الملفات من قناة تيليجرام عبر telegramService.deleteMessage.
   * 3. تسجيل تحذير في حال فشل حذف رسالة معينة والاستمرار في العملية دون إيقافها.
   * 4. حذف المجلد من قاعدة البيانات (يتكفل onDelete: Cascade بحذف السجلات التابعة).
   */
  async deleteFolder(userId: string, id: string, telegramConfig?: DecryptedTelegramConfig) {
    const folder = await prisma.folder.findFirst({
      where: { id, userId },
    });

    if (!folder) {
      throw AppError.notFound('المجلد غير موجود أو لا تملك صلاحية حذفه');
    }

    // 1. جلب كافة معرفات المجلدات التابعة بشكل متداخل
    const allTargetFolderIds = await this.getAllSubfolderIds(userId, id);

    // 2. جلب كل الملفات المرتبطة بهذه المجلدات
    const filesToDelete = await prisma.file.findMany({
      where: {
        userId,
        parentFolderId: { in: allTargetFolderIds },
      },
      select: {
        id: true,
        name: true,
        telegramMessageId: true,
      },
    });

    // 3. حذف رسائل الملفات من قناة تيليجرام
    if (telegramConfig && filesToDelete.length > 0) {
      for (const file of filesToDelete) {
        try {
          await telegramService.deleteMessage(file.telegramMessageId, telegramConfig);
        } catch (error: any) {
          console.warn(
            `[FolderService.deleteFolder] تحذير: تعذر حذف رسالة الملف "${file.name}" (message_id: ${file.telegramMessageId}) من تيليجرام:`,
            error.message || error
          );
        }
      }
    }

    // 4. حذف المجلد من قاعدة البيانات (Cascade سيحذف السجلات التابعة)
    await prisma.folder.delete({
      where: { id },
    });

    return {
      success: true,
      message: 'تم حذف المجلد وكافة محتوياته ورسائله من تيليجرام بنجاح',
      deletedFilesCount: filesToDelete.length,
      deletedFolderId: id,
    };
  }
}

export const folderService = new FolderService();

