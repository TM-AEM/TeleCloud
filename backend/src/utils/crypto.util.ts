import crypto from 'crypto';
import { env } from '../config/env.js';
import { AppError } from '../errors/app-error.js';

// اشتقاق مفتاح 32 بايت (256-bit) باستخدام SHA-256 لضمان التوافق التام مع خوارزمية AES-256-GCM
const KEY = crypto.createHash('sha256').update(env.ENCRYPTION_SECRET_KEY).digest();
const ALGORITHM = 'aes-256-gcm';
const IV_LENGTH = 12; // الحجم القياسي الموصى به لـ GCM

/**
 * تشفير نص باستخدام AES-256-GCM
 */
export function encrypt(text: string): string {
  if (!text) return '';
  try {
    const iv = crypto.randomBytes(IV_LENGTH);
    const cipher = crypto.createCipheriv(ALGORITHM, KEY, iv);

    const encrypted = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
    const tag = cipher.getAuthTag();

    // تخزين الـ IV والـ Tag والبيانات المشفرة بصيغة Hex يفصل بينها النقطتان
    return `${iv.toString('hex')}:${tag.toString('hex')}:${encrypted.toString('hex')}`;
  } catch (error: any) {
    console.error('فشل تشفير البيانات:', error);
    throw AppError.internal('حدث خطأ أثناء تشفير البيانات الحساسة');
  }
}

/**
 * فك تشفير نص مشفر بـ AES-256-GCM
 */
export function decrypt(ciphertext: string): string {
  if (!ciphertext) return '';
  try {
    const parts = ciphertext.split(':');
    if (parts.length !== 3) {
      throw new Error('تنسيق البيانات المشفرة غير صالح');
    }

    const [ivHex, tagHex, encryptedHex] = parts;
    const iv = Buffer.from(ivHex, 'hex');
    const tag = Buffer.from(tagHex, 'hex');
    const encrypted = Buffer.from(encryptedHex, 'hex');

    const decipher = crypto.createDecipheriv(ALGORITHM, KEY, iv);
    decipher.setAuthTag(tag);

    const decrypted = Buffer.concat([decipher.update(encrypted), decipher.final()]);
    return decrypted.toString('utf8');
  } catch (error: any) {
    console.error('فشل فك تشفير البيانات:', error);
    throw AppError.internal('فشل في فك تشفير بيانات تيليجرام (ربما تم تغيير مفتاح التشفير)');
  }
}
