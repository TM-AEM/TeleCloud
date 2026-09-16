import dotenv from 'dotenv';
import { z } from 'zod';

dotenv.config();

const envSchema = z.object({
  PORT: z.coerce.number().default(4000),
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  DATABASE_URL: z.string().min(1, 'DATABASE_URL is required'),
  JWT_SECRET: z.string().min(16, 'JWT_SECRET is required and must be at least 16 characters'),
  JWT_EXPIRES_IN: z.string().default('7d'),
  // مفتاح تشفير بيانات تيليجرام لكل مستخدم في قاعدة البيانات (AES-256)
  ENCRYPTION_SECRET_KEY: z.string().min(16, 'ENCRYPTION_SECRET_KEY is required and must be at least 16 characters for securing user Telegram credentials'),
  TELEGRAM_API_BASE_URL: z.string().default('https://api.telegram.org'),
  APP_BASE_URL: z.string().url('APP_BASE_URL must be a valid URL').default('http://localhost:4000'),
  MAX_FILE_SIZE_BYTES: z.coerce.number().default(2 * 1024 * 1024 * 1024), // 2 GB
});

const _env = envSchema.safeParse(process.env);

if (!_env.success) {
  console.error('❌ خطأ في متغيرات البيئة (Environment variables validation failed):');
  console.error(_env.error.format());
  throw new Error('Invalid environment variables configuration.');
}

export const env = _env.data;
