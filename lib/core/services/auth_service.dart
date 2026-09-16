import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../backup/backup_worker.dart';

/// نموذج بيانات المستخدم المسجل
class AuthUser {
  final String id;
  final String email;
  final String username;
  final bool isTelegramConfigured;
  final String? createdAt;

  AuthUser({
    required this.id,
    required this.email,
    required this.username,
    required this.isTelegramConfigured,
    this.createdAt,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      isTelegramConfigured: json['isTelegramConfigured'] == true,
      createdAt: json['createdAt']?.toString(),
    );
  }
}

/// =========================================================================================
/// [AuthService] - خدمة إدارة جلسات الدخول والمصادقة وربط حساب تيليجرام
/// =========================================================================================
///
/// **ملاحظة حول Base URL:**
/// العنوان الافتراضي `http://10.0.2.2:5000` هو عنوان الـ Loopback للوصول إلى localhost
/// الخاص بجهاز التطوير من داخل محاكي أندرويد (Android Emulator).
/// عند نشر التطبيق (Production)، يجب استبداله بعنوان السيرفر الفعلي أو النطاق العام (Domain).
class AuthService extends ChangeNotifier {
  static const String defaultBaseUrl = 'http://10.0.2.2:5000';

  String? _currentToken;
  AuthUser? _currentUser;
  bool _isTelegramConfigured = false;
  bool _isLoading = false;
  bool _isCheckingInitialAuth = true;
  String? _errorMessage;

  String? get currentToken => _currentToken;
  AuthUser? get currentUser => _currentUser;
  bool get isTelegramConfigured => _isTelegramConfigured;
  bool get isLoading => _isLoading;
  bool get isCheckingInitialAuth => _isCheckingInitialAuth;
  String? get errorMessage => _errorMessage;

  bool get isAuthenticated => _currentToken != null && _currentToken!.isNotEmpty;

  /// الحصول على عنوان الـ Base URL المخزن أو الافتراضي
  Future<String> _getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kPrefApiBaseUrl) ?? defaultBaseUrl;
  }

  /// فحص حالة المصادقة عند بدء تشغيل التطبيق (Auto Login / Token Verification)
  Future<void> checkAuthStatus() async {
    _isCheckingInitialAuth = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString(kPrefAuthToken);

      if (savedToken == null || savedToken.isEmpty) {
        _currentToken = null;
        _currentUser = null;
        _isTelegramConfigured = false;
        _isCheckingInitialAuth = false;
        notifyListeners();
        return;
      }

      final baseUrl = await _getBaseUrl();
      final uri = Uri.parse('$baseUrl/api/auth/me');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $savedToken',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          _currentToken = savedToken;
          _currentUser = AuthUser.fromJson(data['data']);
          _isTelegramConfigured = _currentUser!.isTelegramConfigured;
          _isCheckingInitialAuth = false;
          notifyListeners();
          return;
        }
      }

      // إذا كان التوكن منتهي الصلاحية أو غير صالح (401 أو خطأ)
      debugPrint('[AuthService] Saved token invalid or expired. Removing from preferences.');
      await prefs.remove(kPrefAuthToken);
      _currentToken = null;
      _currentUser = null;
      _isTelegramConfigured = false;
    } catch (e) {
      debugPrint('[AuthService] checkAuthStatus error: $e');
      // في حال تعذر الاتصال بالسيرفر مع وجود توكن مخزن، نحتفظ به مبدئياً أو نلغيه
    } finally {
      _isCheckingInitialAuth = false;
      notifyListeners();
    }
  }

  /// تسجيل حساب جديد: POST /api/auth/register
  Future<bool> register({
    required String email,
    required String username,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final baseUrl = await _getBaseUrl();
      final uri = Uri.parse('$baseUrl/api/auth/register');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'username': username.trim(),
          'password': password,
        }),
      ).timeout(const Duration(seconds: 15));

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300 && data['success'] == true) {
        final token = data['data']?['token']?.toString();
        final userData = data['data']?['user'];

        if (token != null && userData != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(kPrefAuthToken, token);

          _currentToken = token;
          _currentUser = AuthUser.fromJson(userData);
          _isTelegramConfigured = _currentUser!.isTelegramConfigured;
          _isLoading = false;
          notifyListeners();
          return true;
        }
      }

      _errorMessage = data['message'] ?? 'فشل تسجيل الحساب، يرجى المحاولة مرة أخرى.';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('[AuthService] register error: $e');
      _errorMessage = 'تعذر الاتصال بالخادم. تأكد من تشغيل السيرفر وصحة العنوان.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// تسجيل الدخول: POST /api/auth/login
  Future<bool> login({
    required String loginInput,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final baseUrl = await _getBaseUrl();
      final uri = Uri.parse('$baseUrl/api/auth/login');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'login': loginInput.trim(),
          'password': password,
        }),
      ).timeout(const Duration(seconds: 15));

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300 && data['success'] == true) {
        final token = data['data']?['token']?.toString();
        final userData = data['data']?['user'];

        if (token != null && userData != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(kPrefAuthToken, token);

          _currentToken = token;
          _currentUser = AuthUser.fromJson(userData);
          _isTelegramConfigured = _currentUser!.isTelegramConfigured;
          _isLoading = false;
          notifyListeners();
          return true;
        }
      }

      _errorMessage = data['message'] ?? 'بيانات الدخول غير صحيحة، يرجى التحقق وإعادة المحاولة.';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('[AuthService] login error: $e');
      _errorMessage = 'تعذر الاتصال بالخادم. يرجى التحقق من اتصال الشبكة وصحة عنوان السيرفر.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// حفظ إعدادات ربط تيليجرام: POST /api/settings/telegram
  Future<bool> configureTelegram({
    required String apiId,
    required String apiHash,
    required String botToken,
    required String channelId,
  }) async {
    if (_currentToken == null || _currentToken!.isEmpty) {
      _errorMessage = 'يرجى تسجيل الدخول أولاً';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final baseUrl = await _getBaseUrl();
      final uri = Uri.parse('$baseUrl/api/settings/telegram');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_currentToken',
        },
        body: jsonEncode({
          'telegramApiId': apiId.trim(),
          'telegramApiHash': apiHash.trim(),
          'telegramBotToken': botToken.trim(),
          'telegramChannelId': channelId.trim(),
        }),
      ).timeout(const Duration(seconds: 25));

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300 && data['success'] == true) {
        _isTelegramConfigured = true;
        if (_currentUser != null) {
          _currentUser = AuthUser(
            id: _currentUser!.id,
            email: _currentUser!.email,
            username: _currentUser!.username,
            isTelegramConfigured: true,
            createdAt: _currentUser!.createdAt,
          );
        }
        _isLoading = false;
        notifyListeners();
        return true;
      }

      _errorMessage = data['message'] ?? 'تعذر حفظ بيانات تيليجرام. تأكد من صحة التوكن والقناة.';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('[AuthService] configureTelegram error: $e');
      _errorMessage = 'خطأ أثناء الاتصال بالخادم للتحقق من إعدادات تيليجرام.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// تسجيل الخروج وحذف التوكن من SharedPreferences
  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kPrefAuthToken);
    } catch (e) {
      debugPrint('[AuthService] logout remove token error: $e');
    }

    _currentToken = null;
    _currentUser = null;
    _isTelegramConfigured = false;
    _errorMessage = null;
    notifyListeners();
  }
}
