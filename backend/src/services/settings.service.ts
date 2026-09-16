import axios from 'axios';
import { prisma } from '../lib/prisma.js';
import { env } from '../config/env.js';
import { encrypt, decrypt } from '../utils/crypto.util.js';
import { AppError } from '../errors/app-error.js';

export interface TelegramConfigInput {
  telegramApiId: string;
  telegramApiHash: string;
  telegramBotToken: string;
  telegramChannelId: string;
}

export class SettingsService {
  private readonly baseUrl: string;

  constructor() {
    this.baseUrl = (env.TELEGRAM_API_BASE_URL || 'https://api.telegram.org').trim().replace(/\/+$/, '');
  }

  /**
   * التحقق من بيانات تيليجرام وتشفيرها وحفظها للمستخدم
   */
  async saveTelegramConfig(userId: string, input: TelegramConfigInput) {
    const { telegramApiId, telegramApiHash, telegramBotToken, telegramChannelId } = input;

    if (!telegramApiId || !telegramApiHash || !telegramBotToken || !telegramChannelId) {
      throw AppError.badRequest('يرجى تقديم جميع البيانات المطلوبة: telegramApiId, telegramApiHash, telegramBotToken, telegramChannelId');
    }

    const cleanToken = telegramBotToken.trim();
    const cleanChannelId = telegramChannelId.trim();
    const cleanApiId = telegramApiId.toString().trim();
    const cleanApiHash = telegramApiHash.trim();

    // 1. اختبار صلاحية توكن البوت عبر getMe
    let botInfo: any;
    try {
      const getMeRes = await axios.get(`${this.baseUrl}/bot${cleanToken}/getMe`, { timeout: 10000 });
      if (!getMeRes.data.ok || !getMeRes.data.result) {
        throw new Error('رد غير صالح من تيليجرام');
      }
      botInfo = getMeRes.data.result;
    } catch (err: any) {
      const desc = err.response?.data?.description || err.message;
      throw AppError.badRequest(`توكن البوت غير صالح أو تعذر الوصول لخوادم تيليجرام: ${desc}`);
    }

    // 2. اختبار الوصول للقناة عبر getChat للتأكد من وجودها وإضافة البوت فيها
    try {
      const getChatRes = await axios.get(`${this.baseUrl}/bot${cleanToken}/getChat`, {
        params: { chat_id: cleanChannelId },
        timeout: 10000,
      });
      if (!getChatRes.data.ok) {
        throw new Error('البوت ليس مشرفاً أو القناة غير موجودة');
      }
    } catch (err: any) {
      const desc = err.response?.data?.description || err.message;
      throw AppError.badRequest(`تعذر الوصول إلى القناة (${cleanChannelId}). تأكد من إضافة البوت كـ Admin في القناة ومن صحة المعرّف: ${desc}`);
    }

    // 3. تشفير البيانات الحساسة باستخدام AES-256 قبل الحفظ في قاعدة البيانات
    const encryptedToken = encrypt(cleanToken);
    const encryptedChannel = encrypt(cleanChannelId);
    const encryptedApiId = encrypt(cleanApiId);
    const encryptedApiHash = encrypt(cleanApiHash);

    // 4. الحفظ في قاعدة البيانات وربطها بالمستخدم
    await prisma.user.update({
      where: { id: userId },
      data: {
        telegramBotToken: encryptedToken,
        telegramChannelId: encryptedChannel,
        telegramApiId: encryptedApiId,
        telegramApiHash: encryptedApiHash,
        isTelegramConfigured: true,
      },
    });

    return {
      success: true,
      message: 'تم التحقق من بيانات تيليجرام وتشفيرها وحفظها بنجاح',
      bot: {
        id: botInfo.id,
        username: botInfo.username,
        firstName: botInfo.first_name,
      },
      channelId: cleanChannelId,
    };
  }

  /**
   * استرجاع حالة إعدادات تيليجرام للمستخدم دون كشف البيانات السرية
   */
  async getTelegramConfigStatus(userId: string) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        isTelegramConfigured: true,
        telegramBotToken: true,
        telegramChannelId: true,
        telegramApiId: true,
        telegramApiHash: true,
      },
    });

    if (!user) {
      throw AppError.notFound('المستخدم غير موجود');
    }

    if (!user.isTelegramConfigured || !user.telegramBotToken) {
      return {
        isConfigured: false,
        message: 'لم يتم إعداد بيانات تيليجرام بعد',
      };
    }

    // فك التشفير محلياً لإنشاء قناع للمعلومات (Masking)
    const rawToken = decrypt(user.telegramBotToken);
    const rawChannel = decrypt(user.telegramChannelId || '');
    const rawApiId = decrypt(user.telegramApiId || '');

    const maskedToken = rawToken ? `${rawToken.substring(0, 6)}...${rawToken.substring(rawToken.length - 4)}` : '';
    const maskedChannel = rawChannel ? `${rawChannel.substring(0, 6)}...` : '';
    const maskedApiId = rawApiId ? `${rawApiId.substring(0, 3)}***` : '';

    return {
      isConfigured: true,
      maskedBotToken: maskedToken,
      maskedChannelId: maskedChannel,
      maskedApiId: maskedApiId,
    };
  }

  /**
   * جلب بيانات تيليجرام مفكوكة التشفير للاستخدام اللحظي فقط أثناء تنفيذ العمليات
   */
  async getDecryptedCredentialsForUser(userId: string) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        isTelegramConfigured: true,
        telegramBotToken: true,
        telegramChannelId: true,
        telegramApiId: true,
        telegramApiHash: true,
      },
    });

    if (!user || !user.isTelegramConfigured || !user.telegramBotToken || !user.telegramChannelId) {
      throw AppError.badRequest('يرجى إعداد بيانات حساب تيليجرام الخاص بك أولاً من قسم الإعدادات (POST /api/settings/telegram)');
    }

    return {
      botToken: decrypt(user.telegramBotToken),
      channelId: decrypt(user.telegramChannelId),
      apiId: user.telegramApiId ? decrypt(user.telegramApiId) : undefined,
      apiHash: user.telegramApiHash ? decrypt(user.telegramApiHash) : undefined,
    };
  }
}

export const settingsService = new SettingsService();
