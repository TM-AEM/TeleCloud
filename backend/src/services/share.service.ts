import crypto from 'crypto';
import { prisma } from '../lib/prisma.js';
import { AppError } from '../errors/app-error.js';
import { env } from '../config/env.js';
import { settingsService } from './settings.service.js';
import { telegramService } from './telegram.service.js';

export interface CreateShareLinkInput {
  expiresInHours: number;
  maxDownloads?: number | null;
}

export class ShareService {
  /**
   * إنشاء رابط مشاركة جديد لملف بعد التأكد من ملكية المستخدم له
   * POST /api/files/:id/share
   */
  async createShareLink(userId: string, fileId: string, input: CreateShareLinkInput, requestOrigin?: string) {
    // 1. التحقق من وجود الملف وكونه ملكاً للمستخدم
    const file = await prisma.file.findFirst({
      where: {
        id: fileId,
        userId,
      },
    });

    if (!file) {
      throw AppError.notFound('الملف المطلوب غير موجود أو لا تملك صلاحية مشاركته');
    }

    // 2. التحقق من صحة المدخلات
    const hours = Number(input.expiresInHours);
    if (isNaN(hours) || hours <= 0) {
      throw AppError.badRequest('مدة الصلاحية بالساعات يجب أن تكون رقماً أكبر من صفر');
    }

    let maxDownloads: number | null = null;
    if (input.maxDownloads !== undefined && input.maxDownloads !== null) {
      maxDownloads = Number(input.maxDownloads);
      if (isNaN(maxDownloads) || maxDownloads <= 0) {
        throw AppError.badRequest('الحد الأقصى لعدد التنزيلات يجب أن يكون رقماً موجباً أكبر من صفر');
      }
    }

    // 3. حساب تاريخ انتهاء الصلاحية
    const expiresAt = new Date(Date.now() + hours * 60 * 60 * 1000);

    // 4. توليد رمز مميز آمن عشوائي وفريد باستخدام crypto.randomBytes(32).toString('hex')
    // ينتج 64 محرف سداسي عشري بطاقة إنتروبيا 256 بت تجعل التخمين مستحيلاً عملياً (2^256 احتمال)
    const token = crypto.randomBytes(32).toString('hex');

    // 5. حفظ سجل ShareLink في قاعدة البيانات
    const shareLink = await prisma.shareLink.create({
      data: {
        fileId: file.id,
        token,
        expiresAt,
        createdByUserId: userId,
        maxDownloads,
        downloadCount: 0,
        isRevoked: false,
      },
    });

    // 6. تحديد الـ base URL لإنشاء الرابط الكامل
    const baseUrl = requestOrigin && requestOrigin.startsWith('http')
      ? requestOrigin.replace(/\/+$/, '')
      : (env.APP_BASE_URL || 'http://localhost:4000').replace(/\/+$/, '');

    const shareUrl = `${baseUrl}/share/${token}`;

    return {
      shareLink: {
        ...shareLink,
        shareUrl,
      },
      shareUrl,
    };
  }

  /**
   * الوصول إلى الملف العام عبر الرابط وتحميله
   * GET /api/share/:token
   */
  async getFileByShareToken(token: string) {
    if (!token) {
      throw AppError.badRequest('رمز المشاركة مطلوب');
    }

    // 1. البحث عن ShareLink بواسطة token مع جلب بيانات الملف والمستخدم
    const shareLink = await prisma.shareLink.findUnique({
      where: { token },
      include: {
        file: true,
      },
    });

    if (!shareLink) {
      throw new AppError('رابط المشاركة غير موجود أو غير صالح', 404);
    }

    // 2. التحقق مما إذا كان الرابط قد أُلغي يدويًا
    if (shareLink.isRevoked) {
      throw new AppError('عذراً، تم إلغاء رابط المشاركة هذا من قبل المالك', 410);
    }

    // 3. التحقق من انتهاء الصلاحية الزمنية
    if (new Date() > new Date(shareLink.expiresAt)) {
      throw new AppError('عذراً، انتهت صلاحية رابط المشاركة هذا', 410);
    }

    // 4. التحقق من تخطي الحد الأقصى للتنزيلات إن وجد
    if (shareLink.maxDownloads !== null && shareLink.downloadCount >= shareLink.maxDownloads) {
      throw new AppError('عذراً، تم الوصول إلى الحد الأقصى لمرات التنزيل المسموح بها لهذا الرابط', 403);
    }

    // 5. التحقق من وجود الملف المرتبط
    const file = shareLink.file;
    if (!file) {
      throw AppError.notFound('الملف المرتبط بهذا الرابط لم يعد متوفراً');
    }

    // 6. جلب بيانات تيليجرام الخاصة بصاحب الملف الأصلي (وليس الزائر)
    const ownerTelegramConfig = await settingsService.getDecryptedCredentialsForUser(file.userId);

    // 7. جلب الـ Stream من تيليجرام باستخدام إعدادات المالك
    const streamResult = await telegramService.getFileStream(file.telegramFileId, ownerTelegramConfig);

    // 8. زيادة عداد التنزيلات بمقدار 1
    await prisma.shareLink.update({
      where: { id: shareLink.id },
      data: {
        downloadCount: {
          increment: 1,
        },
      },
    });

    return {
      file: {
        ...file,
        size: Number(file.size),
      },
      streamResult,
    };
  }

  /**
   * عرض جميع روابط المشاركة النشطة لملف معين للمستخدم المالك
   * GET /api/files/:id/shares
   */
  async getFileShares(userId: string, fileId: string, requestOrigin?: string) {
    const file = await prisma.file.findFirst({
      where: {
        id: fileId,
        userId,
      },
    });

    if (!file) {
      throw AppError.notFound('الملف المطلوب غير موجود أو لا تملك صلاحية الوصول إليه');
    }

    const shareLinks = await prisma.shareLink.findMany({
      where: {
        fileId,
        createdByUserId: userId,
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    const baseUrl = requestOrigin && requestOrigin.startsWith('http')
      ? requestOrigin.replace(/\/+$/, '')
      : (env.APP_BASE_URL || 'http://localhost:4000').replace(/\/+$/, '');

    const now = new Date();

    return shareLinks.map((link) => {
      const isExpired = now > new Date(link.expiresAt);
      const isMaxReached = link.maxDownloads !== null && link.downloadCount >= link.maxDownloads;
      const isActive = !link.isRevoked && !isExpired && !isMaxReached;

      return {
        ...link,
        shareUrl: `${baseUrl}/share/${link.token}`,
        isExpired,
        isMaxReached,
        isActive,
      };
    });
  }

  /**
   * إلغاء رابط مشاركة يدويًا
   * DELETE /api/shares/:shareId
   */
  async revokeShareLink(userId: string, shareId: string) {
    // التأكد من أن الرابط موجود وصاحبه هو المستخدم نفسه
    const shareLink = await prisma.shareLink.findUnique({
      where: { id: shareId },
      include: {
        file: true,
      },
    });

    if (!shareLink) {
      throw AppError.notFound('رابط المشاركة المطلوب غير موجود');
    }

    if (shareLink.createdByUserId !== userId && shareLink.file.userId !== userId) {
      throw AppError.forbidden('لا تملك الصلاحية لإلغاء رابط المشاركة هذا');
    }

    const updated = await prisma.shareLink.update({
      where: { id: shareId },
      data: {
        isRevoked: true,
      },
    });

    return {
      success: true,
      message: 'تم إلغاء رابط المشاركة بنجاح ولن يتمكن أي شخص من استخدامه بعد الآن',
      shareId: updated.id,
    };
  }

  /**
   * تنظيف الروابط المنتهية لأكثر من 7 أيام
   */
  async cleanupExpiredShares(): Promise<number> {
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);

    const deleteResult = await prisma.shareLink.deleteMany({
      where: {
        OR: [
          {
            expiresAt: {
              lt: sevenDaysAgo,
            },
          },
        ],
      },
    });

    return deleteResult.count;
  }
}

export const shareService = new ShareService();
