-- ==============================================================================
-- Migration: Add Full-Text Search (tsvector), GIN Index & Auto-Update Trigger on files
-- ==============================================================================

-- 1. إضافة عمود search_vector من نوع tsvector إلى جدول files إذا لم يكن موجوداً
ALTER TABLE "files" ADD COLUMN IF NOT EXISTS "search_vector" tsvector;

-- 2. تحديث السجلات الحالية لتعبئة قيمة search_vector بناءً على name و mime_type
-- مع إعطاء الأولوية القصوى لاسم الملف (Weight 'A') ولنوع الملف (Weight 'B')
UPDATE "files"
SET "search_vector" = setweight(to_tsvector('simple', coalesce("name", '')), 'A') ||
                      setweight(to_tsvector('simple', coalesce("mime_type", '')), 'B');

-- 3. إنشاء دالة Trigger لتحديث search_vector تلقائياً عند INSERT أو UPDATE
CREATE OR REPLACE FUNCTION files_search_vector_update_trigger()
RETURNS trigger AS $$
BEGIN
  NEW.search_vector :=
    setweight(to_tsvector('simple', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(NEW.mime_type, '')), 'B');
  RETURN NEW;
END
$$ LANGUAGE plpgsql;

-- 4. ربط الـ Trigger بجدول files
DROP TRIGGER IF EXISTS trigger_files_search_vector_update ON "files";

CREATE TRIGGER trigger_files_search_vector_update
BEFORE INSERT OR UPDATE OF "name", "mime_type" ON "files"
FOR EACH ROW
EXECUTE FUNCTION files_search_vector_update_trigger();

-- 5. إنشاء فهرس GIN فائق السرعة على عمود search_vector لتسريع استعلامات البحث
CREATE INDEX IF NOT EXISTS "files_search_vector_gin_idx" ON "files" USING GIN ("search_vector");
