import { User } from '@prisma/client';

export interface DecryptedTelegramConfig {
  botToken: string;
  channelId: string;
  apiId?: string;
  apiHash?: string;
}

export interface AuthenticatedUser {
  id: string;
  email: string;
  username: string;
  isTelegramConfigured: boolean;
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthenticatedUser;
      telegramConfig?: DecryptedTelegramConfig;
    }
  }
}
