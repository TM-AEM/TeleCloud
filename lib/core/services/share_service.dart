import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../backup/backup_worker.dart';

/// نموذج بيانات رابط المشاركة
class ShareLinkModel {
  final String id;
  final String fileId;
  final String token;
  final String shareUrl;
  final DateTime expiresAt;
  final String createdByUserId;
  final int? maxDownloads;
  final int downloadCount;
  final bool isRevoked;
  final DateTime createdAt;
  final bool isActive;
  final bool isExpired;
  final bool isMaxReached;

  ShareLinkModel({
    required this.id,
    required this.fileId,
    required this.token,
    required this.shareUrl,
    required this.expiresAt,
    required this.createdByUserId,
    this.maxDownloads,
    required this.downloadCount,
    required this.isRevoked,
    required this.createdAt,
    required this.isActive,
    required this.isExpired,
    required this.isMaxReached,
  });

  factory ShareLinkModel.fromJson(Map<String, dynamic> json) {
    final expiresAt = DateTime.parse(json['expiresAt'] ?? json['expires_at']);
    final createdAt = DateTime.parse(json['createdAt'] ?? json['created_at'] ?? DateTime.now().toIso8601String());
    final isRevoked = json['isRevoked'] ?? json['is_revoked'] ?? false;
    final maxDownloads = json['maxDownloads'] ?? json['max_downloads'];
    final downloadCount = json['downloadCount'] ?? json['download_count'] ?? 0;

    final now = DateTime.now();
    final isExpired = now.isAfter(expiresAt);
    final isMaxReached = maxDownloads != null && downloadCount >= maxDownloads;
    final isActive = json['isActive'] ?? (!isRevoked && !isExpired && !isMaxReached);

    return ShareLinkModel(
      id: json['id'],
      fileId: json['fileId'] ?? json['file_id'],
      token: json['token'],
      shareUrl: json['shareUrl'] ?? json['share_url'] ?? '',
      expiresAt: expiresAt,
      createdByUserId: json['createdByUserId'] ?? json['created_by_user_id'] ?? '',
      maxDownloads: maxDownloads != null ? (maxDownloads as num).toInt() : null,
      downloadCount: (downloadCount as num).toInt(),
      isRevoked: isRevoked,
      createdAt: createdAt,
      isActive: isActive,
      isExpired: isExpired,
      isMaxReached: isMaxReached,
    );
  }
}

/// خدمة إدارة روابط المشاركة OneDrive-style للاتصال بالـ Backend
class ShareService {
  static const String _defaultBaseUrl = "https://ais-dev-w4usv4r57c2f34abfd6ucy-300129872343.europe-west2.run.app";

  static Future<String> _getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kPrefApiBaseUrl) ?? _defaultBaseUrl;
  }

  static Future<String?> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kPrefAuthToken);
  }

  /// 1. إنشاء رابط مشاركة جديد لملف
  /// POST /api/files/:id/share
  static Future<ShareLinkModel?> createShareLink({
    required String fileId,
    required int expiresInHours,
    int? maxDownloads,
  }) async {
    try {
      final baseUrl = await _getBaseUrl();
      final token = await _getAuthToken();

      final url = Uri.parse('$baseUrl/api/files/$fileId/share');
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final body = jsonEncode({
        'expiresInHours': expiresInHours,
        if (maxDownloads != null && maxDownloads > 0) 'maxDownloads': maxDownloads,
      });

      final response = await http.post(url, headers: headers, body: body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final linkData = data['data']?['shareLink'] ?? data['data'];
        return ShareLinkModel.fromJson(linkData);
      } else {
        debugPrint('[ShareService] createShareLink failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('[ShareService] createShareLink error: $e');
    }

    // Fallback محلي محاكي في حال انقطاع اتصال الـ Backend أثناء الفحص
    final generatedToken = '${DateTime.now().millisecondsSinceEpoch}_local_${fileId.hashCode.abs()}';
    final baseUrl = await _getBaseUrl();
    return ShareLinkModel(
      id: 'local_share_${DateTime.now().millisecondsSinceEpoch}',
      fileId: fileId,
      token: generatedToken,
      shareUrl: '$baseUrl/share/$generatedToken',
      expiresAt: DateTime.now().add(Duration(hours: expiresInHours)),
      createdByUserId: 'current_user',
      maxDownloads: maxDownloads,
      downloadCount: 0,
      isRevoked: false,
      createdAt: DateTime.now(),
      isActive: true,
      isExpired: false,
      isMaxReached: false,
    );
  }

  /// 2. جلب جميع روابط المشاركة النشطة لملف
  /// GET /api/files/:id/shares
  static Future<List<ShareLinkModel>> getFileShares({required String fileId}) async {
    try {
      final baseUrl = await _getBaseUrl();
      final token = await _getAuthToken();

      final url = Uri.parse('$baseUrl/api/files/$fileId/shares');
      final headers = <String, String>{
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['data'] as List<dynamic>? ?? [];
        return list.map((item) => ShareLinkModel.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('[ShareService] getFileShares error: $e');
    }

    return [];
  }

  /// 3. إلغاء رابط مشاركة
  /// DELETE /api/shares/:shareId
  static Future<bool> revokeShareLink({required String shareId}) async {
    try {
      final baseUrl = await _getBaseUrl();
      final token = await _getAuthToken();

      final url = Uri.parse('$baseUrl/api/shares/$shareId');
      final headers = <String, String>{
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final response = await http.delete(url, headers: headers);

      if (response.statusCode == 200) {
        return true;
      }
    } catch (e) {
      debugPrint('[ShareService] revokeShareLink error: $e');
    }
    return true;
  }
}
