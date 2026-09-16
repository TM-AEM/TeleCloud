import { Request, Response, NextFunction } from 'express';
import { settingsService } from '../services/settings.service.js';

export class SettingsController {
  async saveTelegramConfig(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const userId = req.user!.id;
      const { telegramApiId, telegramApiHash, telegramBotToken, telegramChannelId } = req.body;

      const result = await settingsService.saveTelegramConfig(userId, {
        telegramApiId,
        telegramApiHash,
        telegramBotToken,
        telegramChannelId,
      });

      res.status(200).json({
        success: true,
        message: result.message,
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  async getTelegramConfigStatus(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const userId = req.user!.id;
      const result = await settingsService.getTelegramConfigStatus(userId);
      res.status(200).json({
        success: true,
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }
}

export const settingsController = new SettingsController();
