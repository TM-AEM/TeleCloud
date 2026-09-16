import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:cloud_storage_file_manager/core/services/share_service.dart';

/// شاشة استعراض روابط المشاركة النشطة وإدارتها
class ActiveSharesScreen extends StatefulWidget {
  final String fileId;
  final String fileName;

  const ActiveSharesScreen({
    super.key,
    required this.fileId,
    required this.fileName,
  });

  @override
  State<ActiveSharesScreen> createState() => _ActiveSharesScreenState();
}

class _ActiveSharesScreenState extends State<ActiveSharesScreen> {
  bool _isLoading = true;
  List<ShareLinkModel> _shares = [];

  @override
  void initState() {
    super.initState();
    _loadShares();
  }

  Future<void> _loadShares() async {
    setState(() => _isLoading = true);
    final shares = await ShareService.getFileShares(fileId: widget.fileId);
    if (mounted) {
      setState(() {
        _shares = shares;
        _isLoading = false;
      });
    }
  }

  Future<void> _revokeShare(ShareLinkModel link) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء صلاحية الرابط'),
        content: const Text(
          'هل أنت متأكد من رغبتك في إلغاء هذا الرابط فوراً؟ لن يتمكن أي شخص من تنزيل الملف بعد الآن.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إلغاء الرابط', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await ShareService.revokeShareLink(shareId: link.id);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إلغاء رابط المشاركة بنجاح.'),
            backgroundColor: Colors.teal,
          ),
        );
        _loadShares();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر إلغاء الرابط، يرجى المحاولة لاحقاً.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('روابط المشاركة النشطة', style: TextStyle(fontSize: 16)),
              Text(
                widget.fileName,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: _loadShares,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _shares.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.link_off_rounded, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          const Text(
                            'لا توجد روابط مشاركة نشطة لهذا الملف',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'يمكنك إنشاء رابط مشاركة جديد ذو صلاحية محددة بضغطة زر.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _shares.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (ctx, index) {
                      final link = _shares[index];
                      return _buildShareCard(link);
                    },
                  ),
      ),
    );
  }

  Widget _buildShareCard(ShareLinkModel link) {
    Color statusColor = Colors.green;
    String statusText = 'نشط';

    if (link.isRevoked) {
      statusColor = Colors.red;
      statusText = 'ملغى يدويًا';
    } else if (link.isExpired) {
      statusColor = Colors.orange;
      statusText = 'منتهي الصلاحية';
    } else if (link.isMaxReached) {
      statusColor = Colors.purple;
      statusText = 'اكتمل الحد الأقصى';
    }

    final formattedExpiry = DateFormat('yyyy/MM/dd HH:mm').format(link.expiresAt);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(radius: 4, backgroundColor: statusColor),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (link.isActive)
                  OutlinedButton.icon(
                    onPressed: () => _revokeShare(link),
                    icon: const Icon(Icons.block, size: 16, color: Colors.red),
                    label: const Text('إلغاء الرابط', style: TextStyle(fontSize: 12, color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                link.shareUrl.isNotEmpty ? link.shareUrl : 'Token: ${link.token}',
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  'ينتهي في: $formattedExpiry',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const Spacer(),
                Icon(Icons.download_rounded, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  link.maxDownloads != null
                      ? 'التنزيلات: ${link.downloadCount} من ${link.maxDownloads}'
                      : 'التنزيلات: ${link.downloadCount}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
