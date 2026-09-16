import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:cloud_storage_file_manager/core/services/share_service.dart';
import 'package:cloud_storage_file_manager/active_shares_screen.dart';

/// شاشة إنشاء رابط مشاركة جديد (OneDrive-style Share via Link)
class ShareFileScreen extends StatefulWidget {
  final String fileId;
  final String fileName;

  const ShareFileScreen({
    super.key,
    required this.fileId,
    required this.fileName,
  });

  @override
  State<ShareFileScreen> createState() => _ShareFileScreenState();
}

class _ShareFileScreenState extends State<ShareFileScreen> {
  // الخيارات الزمنية لصلاحية الرابط (ساعة واحدة، 24 ساعة، أسبوع)
  int _selectedHours = 24;
  int? _maxDownloads;
  final TextEditingController _maxDownloadsController = TextEditingController();

  bool _isCreating = false;
  ShareLinkModel? _createdLink;

  @override
  void dispose() {
    _maxDownloadsController.dispose();
    super.dispose();
  }

  Future<void> _generateLink() async {
    setState(() => _isCreating = true);

    int? maxDown;
    if (_maxDownloadsController.text.trim().isNotEmpty) {
      maxDown = int.tryParse(_maxDownloadsController.text.trim());
    }

    final result = await ShareService.createShareLink(
      fileId: widget.fileId,
      expiresInHours: _selectedHours,
      maxDownloads: maxDown,
    );

    if (mounted) {
      setState(() {
        _createdLink = result;
        _isCreating = false;
      });

      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إنشاء رابط المشاركة بنجاح!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _copyToClipboard(String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ الرابط إلى الحافظة بنجاح!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _shareViaSystem(String url) {
    Share.share(
      'تفضل رابط تحميل ملف "${widget.fileName}":\n$url\nصالح لمدة $_selectedHours ساعة.',
      subject: 'مشاركة ملف: ${widget.fileName}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مشاركة عبر رابط'),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ActiveSharesScreen(
                      fileId: widget.fileId,
                      fileName: widget.fileName,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.list_alt, color: Colors.indigo),
              label: const Text(
                'الروابط النشطة',
                style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // بطاقة معلومات الملف
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                color: Colors.indigo.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.link_rounded, color: Colors.indigo.shade800, size: 30),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.fileName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'أي شخص يملك هذا الرابط يمكنه تنزيل الملف مباشرة دون الحاجة لتسجيل الدخول.',
                              style: TextStyle(fontSize: 12, color: Colors.indigo.shade900),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // خيارات مدة انتهاء الصلاحية
              const Text(
                'مدة صلاحية الرابط:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildDurationOption(
                      label: 'ساعة واحدة',
                      hours: 1,
                      icon: Icons.timer_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildDurationOption(
                      label: '24 ساعة',
                      hours: 24,
                      icon: Icons.today_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildDurationOption(
                      label: 'أسبوع',
                      hours: 168, // 7 days
                      icon: Icons.date_range_outlined,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // الحد الأقصى لمرات التنزيل (اختياري)
              const Text(
                'الحد الأقصى لمرات التنزيل (اختياري):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _maxDownloadsController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'اتركه فارغاً لعدد غير محدود من التنزيلات',
                  prefixIcon: const Icon(Icons.download_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),

              const SizedBox(height: 24),

              // زر توليد الرابط
              ElevatedButton.icon(
                onPressed: _isCreating ? null : _generateLink,
                icon: _isCreating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add_link_rounded),
                label: Text(_createdLink == null ? 'إنشاء رابط المشاركة' : 'توليد رابط جديد'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),

              // بطاقة عرض الرابط المُنشأ
              if (_createdLink != null) ...[
                const SizedBox(height: 24),
                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: Colors.teal.shade300, width: 1.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle_outline, color: Colors.teal),
                            const SizedBox(width: 8),
                            const Text(
                              'الرابط جاهز للمشاركة الآن!',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.teal),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: SelectableText(
                            _createdLink!.shareUrl,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.blueAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.access_time_filled, size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Text(
                              'ينتهي في: ${DateFormat('yyyy/MM/dd HH:mm').format(_createdLink!.expiresAt)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _copyToClipboard(_createdLink!.shareUrl),
                                icon: const Icon(Icons.copy_rounded, size: 18),
                                label: const Text('نسخ الرابط'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _shareViaSystem(_createdLink!.shareUrl),
                                icon: const Icon(Icons.share_rounded, size: 18),
                                label: const Text('مشاركة الرابط'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDurationOption({
    required String label,
    required int hours,
    required IconData icon,
  }) {
    final isSelected = _selectedHours == hours;

    return InkWell(
      onTap: () => setState(() => _selectedHours = hours),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo.shade50 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.indigo : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.indigo : Colors.grey.shade600,
              size: 22,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.indigo.shade900 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
