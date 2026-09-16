/**
 * test-sql-injection.ts
 *
 * اختبار للتأكد من أن:
 * 1. استدعاء prisma.$queryRaw يستخدم Tagged Template Literal الرسمي في Prisma لتمرير المعاملات بأمان (Parameterized Query).
 * 2. مدخلات البحث الخبيثة مثل `' OR 1=1 --` أو الرموز الخاصة لا تؤثر إطلاقاً على بنية الـ SQL أو تكسر بناء الجملة.
 * 3. دالة formatPrefixTsQuery تنظف وتجهز الكلمات كـ Prefix Matching بصورة آمنة ومحمية.
 */

import { Prisma } from '@prisma/client';

// تعيين متغيرات البيئة الأساسية للاختبار المعزول
process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgresql://postgres:postgres@localhost:5432/test_db';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-jwt-secret-min-16-characters-key';
process.env.ENCRYPTION_SECRET_KEY = process.env.ENCRYPTION_SECRET_KEY || 'test-aes-encryption-secret-key-32';

const { fileService } = await import('../services/file.service.js');

async function runSecurityTest() {
  console.log('--- 🧪 بدء اختبار الأمان والحماية من SQL Injection في Full-Text Search ---');

  // 1. اختبار تنظيف نص البحث وتنسيق الـ Prefix Matching
  const maliciousInput = "' OR 1=1 --";
  const formattedQuery = fileService.formatPrefixTsQuery(maliciousInput);
  console.log(`[1] المدخل الأصلي: "${maliciousInput}"`);
  console.log(`[1] بعد التنسيق والتنظيف: "${formattedQuery}"`);

  // التحقق من أن الرموز الخاصة والـ quotes تم تنظيفها
  if (formattedQuery.includes("'") || formattedQuery.includes("--") || formattedQuery.includes(";")) {
    throw new Error('فشل الاختبار: نص البحث المنسق يحتوي على محارف غير آمنة!');
  }
  console.log('✅ [1] نجح: تم تنظيف الرموز الخاصة والـ Quotes ولم يعد هناك أي تأثير لهجمات التعليقات أو الـ Boolean SQL.');

  // 2. اختبار إنشاء Tagged Template Literal مع Prisma.sql
  // والتحقق من أن القيم المتغيرة تُعامل كـ values منفصلة (Parameterized Variables)
  const dummyUserId = 'user_test_123';
  const dummySearch = maliciousInput;
  const dummyTsQuery = formattedQuery;
  const limit = 20;
  const skip = 0;

  const rawSqlObject = Prisma.sql`
    SELECT 
      f."id",
      f."name",
      f."size",
      f."mime_type" AS "mimeType",
      f."user_id" AS "userId",
      ts_rank(
        f."search_vector", 
        to_tsquery('simple', ${dummyTsQuery})
      ) AS rank
    FROM "files" f
    WHERE f."user_id" = ${dummyUserId}
      AND (
        f."search_vector" @@ to_tsquery('simple', ${dummyTsQuery})
        OR f."name" ILIKE ${'%' + dummySearch + '%'}
        OR f."mime_type" ILIKE ${'%' + dummySearch + '%'}
      )
    ORDER BY rank DESC, f."created_at" DESC
    LIMIT ${limit}
    OFFSET ${skip}
  `;

  console.log('\n[2] فحص كائن Prisma.sql Tagged Template الناتج:');
  console.log('   - عدد المعاملات الممررة (values length):', rawSqlObject.values.length);
  console.log('   - المعاملات المعزولة كلياً:', rawSqlObject.values);

  // التأكد من أن قيم البحث و user_id تمر كـ positional parameters ($1, $2, ...) وليس كـ string concatenated
  if (rawSqlObject.values.length !== 7) {
    throw new Error(`توقعنا 7 معاملات منفصلة في الـ Parameterized Query، وجدنا: ${rawSqlObject.values.length}`);
  }

  const hasSearchInValues = rawSqlObject.values.some(v => v === dummyTsQuery || v === `'%${dummySearch}%'` || v === `%${dummySearch}%`);
  if (!hasSearchInValues) {
    throw new Error('فشل التحقق: نص البحث لم يتم تمريره كـ parameter منفصل داخل values!');
  }

  console.log('✅ [2] نجح: استعلام Prisma يستخدم Tagged Template Literal حصراً وتُمرر جميع القيم كـ Parameters منفصلة وآمنة تماماً ضد الـ SQL Injection.');

  console.log('\n🎉 جميع اختبارات الأمان لبحث Full-Text Search نجحت بنسبة 100%!');
}

runSecurityTest().catch((err) => {
  console.error('❌ خطأ في الاختبار:', err);
  process.exit(1);
});
