import { Request, Response, NextFunction } from 'express';
import { settingsService } from '../services/settings.service.js';
import { AppError } from '../errors/app-error.js';

/**
 * وسيط للتأكد من أن المستخدم قد قام بربط حسابه في تيليجرام وفك تشفير بياناته للاستخدام اللحظي للطلب الحالي فقط
 */
export async function requireTelegramConfig(req: Request, _res: Response, next: NextFunction): Promise<void> {
  try {
    if (!req.user?.id) {
      throw new AppError('غير مصرح لك، يرجى تسجيل الدخول أولاً', 401);
    }

    const credentials = await settingsService.getDecryptedCredentialsForUser(req.user.id);
    req.telegramConfig = credentials;
    next();
  } catch (error) {
    next(error);
  }
}
