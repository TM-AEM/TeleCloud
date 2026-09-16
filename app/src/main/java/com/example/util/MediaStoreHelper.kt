package com.example.util

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

/**
 * =========================================================================================
 * MediaStoreHelper - حفظ الملفات في مجلد التنزيلات العام (Public Downloads)
 * =========================================================================================
 *
 * مقارنة تقنية بين النهجين:
 * 1. النهج الأول: استخدام MANAGE_EXTERNAL_STORAGE للكتابة المباشرة:
 *    - يتطلب طلب إذن حساس يفتح صفحة النظام.
 *    - ترفضه سياسات Google Play للتطبيقات العادية.
 *
 * 2. النهج الثاني (الموصى به رسمياً): MediaStore API (Scoped Storage):
 *    - على أندرويد 10 فما فوق (API 29+)، يتم إدراج الملف عبر ContentResolver في MediaStore.Downloads
 *      دون طلب أي صلاحيات runtime خطيرة!
 *    - متوافق بنسبة 100% مع سياسات متجر Google Play.
 */
object MediaStoreHelper {

    /**
     * حفظ ملف من مساحة التطبيق الخاصة إلى مجلد التنزيلات العام
     * @param context سياق التطبيق
     * @param sourceFile الملف المؤقت المحفوظ في مساحة التطبيق الداخلية
     * @param displayName اسم الملف المراد ظهوره للمستخدم في مجلد التنزيلات
     * @param mimeType نوع الملف (مثال: application/pdf, image/jpeg, video/mp4)
     * @return Uri للملف في مجلد التنزيلات أو null في حالة الفشل
     */
    fun saveFileToPublicDownloads(
        context: Context,
        sourceFile: File,
        displayName: String,
        mimeType: String
    ): Uri? {
        val resolver = context.contentResolver

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // أندرويد 10 فأعلى: استخدام MediaStore.Downloads بدون أذونات
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }

                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                if (uri != null) {
                    resolver.openOutputStream(uri)?.use { outputStream ->
                        FileInputStream(sourceFile).use { inputStream ->
                            inputStream.copyTo(outputStream)
                        }
                    }

                    values.clear()
                    values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                    resolver.update(uri, values, null, null)
                    uri
                } else {
                    null
                }
            } else {
                // أندرويد 9 فما دون: الكتابة في مجلد التنزيلات العام التقليدي (يتطلب WRITE_EXTERNAL_STORAGE)
                val downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                if (!downloadDir.exists()) {
                    downloadDir.mkdirs()
                }
                val targetFile = File(downloadDir, displayName)
                FileInputStream(sourceFile).use { input ->
                    FileOutputStream(targetFile).use { output ->
                        input.copyTo(output)
                    }
                }
                Uri.fromFile(targetFile)
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }
}
