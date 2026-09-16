import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { telegramService } from './telegram.service.js';
import { AppError } from '../errors/app-error.js';
import { DecryptedTelegramConfig } from '../types/express.js';

export interface ListStorageOptions {
  parentFolderId?: string | null;
  page?: number;
  limit?: number;
  search?: string;
}

export class FileService {
  /**
   * رفع ملف إلى تيليجرام الخاص بالمستخدم وتخزين بياناته الوصفية في PostgreSQL
   */
  async uploadFile(
    userId: string,
    file: Express.Multer.File,
    telegramConfig: DecryptedTelegramConfig,
    parentFolderId?: string | null
  ) {
    if (!file) {
      throw AppError.badRequest('يرجى اختيار ملف لرفعه');
    }

    // التحقق من وجود المجلد الأب وأنه يخص نفس المستخدم
    if (parentFolderId && parentFolderId !== 'root') {
      const folderExists = await prisma.folder.findFirst({
        where: {
          id: parentFolderId,
          userId,
        },
      });
      if (!folderExists) {
        throw AppError.badRequest('المجلد الأب المحدد غير موجود أو لا تملك صلاحية الوصول إليه');
      }
    }

    const effectiveFolderId = parentFolderId === 'root' ? null : parentFolderId || null;

    // 1. الرفع الفعلي إلى قناة تيليجرام الخاصة بالمستخدم
    const telegramResult = await telegramService.uploadFile(file, telegramConfig);

    // 2. حفظ الـ Metadata في قاعدة البيانات وربطها بـ userId
    const savedFile = await prisma.file.create({
      data: {
        name: telegramResult.fileName,
        size: BigInt(telegramResult.fileSize),
        mimeType: telegramResult.mimeType,
        userId,
        telegramFileId: telegramResult.fileId,
        telegramFileUniqueId: telegramResult.fileUniqueId,
        telegramMessageId: telegramResult.messageId,
        parentFolderId: effectiveFolderId,
      },
    });

    return {
      ...savedFile,
      size: Number(savedFile.size), // تحويل BigInt للتوافق مع JSON
    };
  }

  /**
   * جلب معلومات الملف ودفق التنزيل المباشر الخاص بالمستخدم
   */
  async getFileForDownload(userId: string, id: string, telegramConfig: DecryptedTelegramConfig) {
    const file = await prisma.file.findFirst({
      where: {
        id,
        userId,
      },
    });

    if (!file) {
      throw AppError.notFound('الملف المطلوب غير موجود أو لا تملك صلاحية الوصول إليه');
    }

    // جلب Stream من تيليجرام باستخدام توكن المستخدم
    const streamResult = await telegramService.getFileStream(file.telegramFileId, telegramConfig);

    return {
      file: {
        ...file,
        size: Number(file.size),
      },
      streamResult,
    };
  }

  /**
   * تحويل نص البحث إلى صيغة prefix matching في PostgreSQL tsquery
   * مثال: "proj note" -> "proj:* & note:*"
   * تنظيف الرموز الخاصة بـ tsquery لمنع أخطاء بناء الجملة (Syntax Errors)
   */
  public formatPrefixTsQuery(searchQuery: string): string {
    const cleaned = searchQuery.replace(/[&|!():*<>\\]/g, ' ').trim();
    if (!cleaned) return '';

    const terms = cleaned
      .split(/\s+/)
      .filter((term) => term.length > 0)
      .map((term) => `${term}:*`);

    return terms.join(' & ');
  }

  /**
   * عرض قائمة الملفات والمجلدات الخاصة بالمستخدم مع دعم:
   * 1. التصفح العادي (Pagination وفلترة حسب parent_folder_id) عندما يكون حقل البحث فارغاً.
   * 2. البحث الشامل فائق السرعة عبر PostgreSQL Full-Text Search (tsvector / ts_rank / prefix :*)
   *    عبر كل المجلدات للمستخدم عند إدخال نص بحث.
   */
  async listItems(userId: string, options: ListStorageOptions) {
    const page = Math.max(1, options.page || 1);
    const limit = Math.max(1, Math.min(100, options.limit || 20));
    const skip = (page - 1) * limit;

    const trimmedSearch = options.search ? options.search.trim() : '';

    // =========================================================================
    // الحالة الأولى: البحث النشط (Full-Text Search مع tsvector و ts_rank و prefix :*)
    // عند البحث، يتم البحث الشامل في جميع ملفات ومجلدات المستخدم عبر كل المجلدات
    // =========================================================================
    if (trimmedSearch.length > 0) {
      const formattedTsQuery = this.formatPrefixTsQuery(trimmedSearch);

      // 1. البحث في المجلدات (بحساب التطابق والترتيب الأبجدي)
      const folderWhere: any = {
        userId,
        name: { contains: trimmedSearch, mode: 'insensitive' },
      };

      // 2. البحث في الملفات باستخدام PostgreSQL Full-Text Search عبر prisma.$queryRaw
      let files: any[] = [];
      let totalFiles = 0;

      if (formattedTsQuery.length > 0) {
        // استعلام لحساب العدد الإجمالي للملفات المطابقة
        const countResult = await prisma.$queryRaw<Array<{ count: bigint }>>`
          SELECT COUNT(*)::bigint AS count
          FROM "files" f
          WHERE f."user_id" = ${userId}
            AND (
              f."search_vector" @@ to_tsquery('simple', ${formattedTsQuery})
              OR f."name" ILIKE ${'%' + trimmedSearch + '%'}
              OR f."mime_type" ILIKE ${'%' + trimmedSearch + '%'}
            )
        `;
        totalFiles = countResult.length > 0 ? Number(countResult[0].count) : 0;

        // استعلام جلب النتائج مع الترتيب حسب درجة التطابق ts_rank تنازلياً ثم تاريخ الإنشاء
        const rawFiles = await prisma.$queryRaw<Array<any>>`
          SELECT 
            f."id",
            f."name",
            f."size",
            f."mime_type" AS "mimeType",
            f."user_id" AS "userId",
            f."telegram_file_id" AS "telegramFileId",
            f."telegram_file_unique_id" AS "telegramFileUniqueId",
            f."telegram_message_id" AS "telegramMessageId",
            f."parent_folder_id" AS "parentFolderId",
            f."created_at" AS "createdAt",
            f."updated_at" AS "updatedAt",
            ts_rank(
              f."search_vector", 
              to_tsquery('simple', ${formattedTsQuery})
            ) AS rank
          FROM "files" f
          WHERE f."user_id" = ${userId}
            AND (
              f."search_vector" @@ to_tsquery('simple', ${formattedTsQuery})
              OR f."name" ILIKE ${'%' + trimmedSearch + '%'}
              OR f."mime_type" ILIKE ${'%' + trimmedSearch + '%'}
            )
          ORDER BY rank DESC, f."created_at" DESC
          LIMIT ${limit}
          OFFSET ${skip}
        `;

        files = rawFiles.map((f) => ({
          id: f.id,
          name: f.name,
          size: Number(f.size),
          mimeType: f.mimeType,
          userId: f.userId,
          telegramFileId: f.telegramFileId,
          telegramFileUniqueId: f.telegramFileUniqueId,
          telegramMessageId: f.telegramMessageId,
          parentFolderId: f.parentFolderId,
          createdAt: f.createdAt,
          updatedAt: f.updatedAt,
        }));
      }

      const [totalFolders, folders] = await Promise.all([
        prisma.folder.count({ where: folderWhere }),
        prisma.folder.findMany({
          where: folderWhere,
          orderBy: { name: 'asc' },
          take: limit,
          skip,
        }),
      ]);

      const totalItems = totalFolders + totalFiles;
      const totalPages = Math.ceil(totalItems / limit) || 1;

      return {
        parentFolderId: null, // في وضع البحث الشامل، النتائج تشمل كل المجلدات
        isGlobalSearch: true,
        searchQuery: trimmedSearch,
        folders,
        files,
        pagination: {
          page,
          limit,
          totalItems,
          totalFolders,
          totalFiles,
          totalPages,
          hasNextPage: page < totalPages,
          hasPrevPage: page > 1,
        },
      };
    }

    // =========================================================================
    // الحالة الثانية: التصفح العادي (بدون بحث) للحفاظ على أعلى أداء ممكن
    // فلترة دقيقة حسب المجلد الأب parent_folder_id و pagination
    // =========================================================================
    const parentId = options.parentFolderId === 'root' || !options.parentFolderId
      ? null
      : options.parentFolderId;

    const folderWhere: any = { userId, parentId };
    const fileWhere: any = { userId, parentFolderId: parentId };

    // استعلام متوازي لجلب المجلدات والملفات والأعداد الكلية الخاصة بالمستخدم
    const [totalFolders, totalFiles, folders, files] = await Promise.all([
      prisma.folder.count({ where: folderWhere }),
      prisma.file.count({ where: fileWhere }),
      prisma.folder.findMany({
        where: folderWhere,
        orderBy: { name: 'asc' },
        take: limit,
        skip,
      }),
      prisma.file.findMany({
        where: fileWhere,
        orderBy: { createdAt: 'desc' },
        take: limit,
        skip,
      }),
    ]);

    const totalItems = totalFolders + totalFiles;
    const totalPages = Math.ceil(totalItems / limit) || 1;

    return {
      parentFolderId: parentId,
      isGlobalSearch: false,
      searchQuery: null,
      folders,
      files: files.map((f) => ({
        ...f,
        size: Number(f.size),
      })),
      pagination: {
        page,
        limit,
        totalItems,
        totalFolders,
        totalFiles,
        totalPages,
        hasNextPage: page < totalPages,
        hasPrevPage: page > 1,
      },
    };
  }

  /**
   * حذف ملف من تيليجرام ومن قاعدة البيانات للمستخدم صاحب الملف فقط
   */
  async deleteFile(userId: string, id: string, telegramConfig: DecryptedTelegramConfig) {
    const file = await prisma.file.findFirst({
      where: {
        id,
        userId,
      },
    });

    if (!file) {
      throw AppError.notFound('الملف المطلوب غير موجود أو لا تملك صلاحية حذفه');
    }

    // 1. حذف الرسالة من قناة تيليجرام
    await telegramService.deleteMessage(file.telegramMessageId, telegramConfig);

    // 2. حذف السجل من قاعدة البيانات PostgreSQL
    await prisma.file.delete({
      where: { id },
    });

    return {
      success: true,
      message: 'تم حذف الملف من قناتك في تيليجرام وقاعدة البيانات بنجاح',
      deletedFileId: id,
    };
  }
}

export const fileService = new FileService();

