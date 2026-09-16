import cron from 'node-cron';
import { shareService } from '../services/share.service.js';

/**
 * جدولة مهام الخلفية للنظام
 * مهمة دورية تعمل كل ساعة ('0 * * * *') لحذف روابط المشاركة المنتهية منذ أكثر من 7 أيام
 */
export function initCronJobs() {
  cron.schedule('0 * * * *', async () => {
    try {
      console.log('⏰ [Cron] بدء تنظيف روابط المشاركة المنتهية الصلاحية...');
      const deletedCount = await shareService.cleanupExpiredShares();
      if (deletedCount > 0) {
        console.log(`🧹 [Cron] تم حذف ${deletedCount} رابط مشاركة منتهي لأكثر من 7 أيام.`);
      } else {
        console.log('✨ [Cron] لا توجد روابط منتهية بحاجة للتنظيف.');
      }
    } catch (error) {
      console.error('❌ [Cron] خطأ أثناء تنفيذ مهمة تنظيف الروابط المنتهية:', error);
    }
  });

  console.log('🕒 تم تفعيل مجدول مهام تنظيف الروابط المنتهية بنجاح (كل ساعة).');
}
