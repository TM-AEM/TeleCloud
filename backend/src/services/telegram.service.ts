import axios, { AxiosResponse } from 'axios';
import FormData from 'form-data';
import { Readable } from 'stream';
import { env } from '../config/env.js';
import { AppError } from '../errors/app-error.js';
import { DecryptedTelegramConfig } from '../types/express.js';

export interface TelegramUploadResult {
  fileId: string;
  fileUniqueId: string;
  messageId: number;
  fileName: string;
  fileSize: number;
  mimeType: string;
}

export interface TelegramStreamResult {
  stream: Readable;
  fileSize?: number;
}

export class TelegramService {
  private readonly rawBaseUrl: string;

  constructor() {
    // قراءة الـ Base URL من متغير البيئة TELEGRAM_API_BASE_URL مع اعتماد https://api.telegram.org كـ Fallback افتراضي
    this.rawBaseUrl = (env.TELEGRAM_API_BASE_URL || 'https://api.telegram.org').trim().replace(/\/+$/, '');
  }

  public getBaseUrl(): string {
    return this.rawBaseUrl;
  }

  /**
   * رفع الملف إلى قناة تيليجرام الخاصة بالمستخدم كـ Document
   */
  async uploadFile(file: Express.Multer.File, config: DecryptedTelegramConfig): Promise<TelegramUploadResult> {
    try {
      const baseUrl = `${this.rawBaseUrl}/bot${config.botToken}`;
      const formData = new FormData();
      formData.append('chat_id', config.channelId);
      formData.append('document', file.buffer, {
        filename: file.originalname,
        contentType: file.mimetype,
      });

      const response = await axios.post(`${baseUrl}/sendDocument`, formData, {
        headers: {
          ...formData.getHeaders(),
        },
        maxContentLength: Infinity,
        maxBodyLength: Infinity,
      });

      if (!response.data.ok || !response.data.result) {
        throw new Error(response.data.description || 'فشل رفع الملف إلى قناة تيليجرام');
      }

      const message = response.data.result;
      const document = message.document;

      if (!document) {
        throw new Error('لم يتم إرجاع بيانات الوثيقة من تيليجرام');
      }

      return {
        fileId: document.file_id,
        fileUniqueId: document.file_unique_id,
        messageId: message.message_id,
        fileName: document.file_name || file.originalname,
        fileSize: document.file_size || file.size,
        mimeType: document.mime_type || file.mimetype,
      };
    } catch (error: any) {
      const description = error.response?.data?.description || error.message;
      throw AppError.telegramError(`فشل إرسال الملف إلى قناتك في تيليجرام: ${description}`, {
        status: error.response?.status,
        data: error.response?.data,
      });
    }
  }

  /**
   * جلب مسار الملف من تيليجرام وتحويله إلى Stream باستخدام بيانات المستخدم الحالية
   */
  async getFileStream(telegramFileId: string, config: DecryptedTelegramConfig): Promise<TelegramStreamResult> {
    try {
      const baseUrl = `${this.rawBaseUrl}/bot${config.botToken}`;
      const fileBaseUrl = `${this.rawBaseUrl}/file/bot${config.botToken}`;

      // 1. استدعاء getFile للحصول على file_path
      const fileInfoRes = await axios.get(`${baseUrl}/getFile`, {
        params: { file_id: telegramFileId },
      });

      if (!fileInfoRes.data.ok || !fileInfoRes.data.result?.file_path) {
        throw new Error(fileInfoRes.data.description || 'لم يتم العثور على مسار الملف في تيليجرام');
      }

      const { file_path, file_size } = fileInfoRes.data.result;
      const downloadUrl = `${fileBaseUrl}/${file_path}`;

      // 2. طلب تدفق الملف (Stream)
      const downloadRes: AxiosResponse<Readable> = await axios.get(downloadUrl, {
        responseType: 'stream',
      });

      return {
        stream: downloadRes.data,
        fileSize: file_size,
      };
    } catch (error: any) {
      const description = error.response?.data?.description || error.message;
      throw AppError.telegramError(`فشل استرجاع الملف من تيليجرام: ${description}`);
    }
  }

  /**
   * حذف رسالة الملف من قناة المستخدم في تيليجرام
   */
  async deleteMessage(messageId: number, config: DecryptedTelegramConfig): Promise<boolean> {
    try {
      const baseUrl = `${this.rawBaseUrl}/bot${config.botToken}`;
      const response = await axios.post(`${baseUrl}/deleteMessage`, {
        chat_id: config.channelId,
        message_id: messageId,
      });

      return !!response.data.ok;
    } catch (error: any) {
      console.warn(`تحذير: تعذر حذف الرسالة ${messageId} من تيليجرام:`, error.response?.data?.description || error.message);
      return false;
    }
  }
}

export const telegramService = new TelegramService();
