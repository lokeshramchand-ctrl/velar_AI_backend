import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:monarch/other_pages/enviroment.dart';

class AuthService {
  static const String _guestName = 'Guest Explorer';

  // ================= REGISTER =================
  static Future<Map<String, dynamic>> register({
    required String displayName,
    required String password,
  }) async {
    final response = await http.post(
      Environment.authUri('/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'displayName': displayName,
        'password': password,
      }),
    );

    return _handleAuthResponse(response);
  }

  // ================= LOGIN =================
  static Future<Map<String, dynamic>> login({
    required String displayName,
    required String password,
  }) async {
    final response = await http.post(
      Environment.authUri('/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'displayName': displayName,
        'password': password,
      }),
    );

    return _handleAuthResponse(response);
  }

  // ================= GET USER =================
  static Future<Map<String, dynamic>> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('authToken');

    if (token == null) {
      return {'success': false};
    }

    final response = await http.get(
      Environment.authUri('/me'),
      headers: _authHeaders(token),
    );

    // 🔁 AUTO REFRESH
    if (response.statusCode == 401) {
      final refreshed = await _refreshToken();

      if (!refreshed) {
        await clearSession();
        return {'success': false};
      }

      token = prefs.getString('authToken');

      final retry = await http.get(
        Environment.authUri('/me'),
        headers: _authHeaders(token),
      );

      return _decodeResponse(retry);
    }

    return _decodeResponse(response);
  }

  // ================= LOGOUT =================
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refreshToken');

    try {
      await http.post(
        Environment.authUri('/logout'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );
    } catch (_) {}

    await clearSession();
  }

  // ================= REFRESH =================
  static Future<bool> _refreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refreshToken');

    if (refreshToken == null) return false;

    try {
      final response = await http.post(
        Environment.authUri('/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );

      final data = _decodeResponse(response);

      if (response.statusCode == 200 && data['success'] == true) {
        await _persistAuthData(data);
        return true;
      }
    } catch (_) {}

    return false;
  }

  // ================= HANDLE RESPONSE =================
  static Future<Map<String, dynamic>> _handleAuthResponse(
    http.Response response,
  ) async {
    final data = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['error'] ?? 'Request failed');
    }

    await _persistAuthData(data);
    return data;
  }

  // ================= SAVE SESSION =================
  static Future<void> _persistAuthData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();

    final user = data['user'];
    final token = data['token'];
    final refreshToken = data['refreshToken'];

    if (user != null) {
      await prefs.setString('userId', user['id']);
      await prefs.setString('displayName', user['displayName']);
    }

    if (token != null) {
      await prefs.setString('authToken', token);
    }

    if (refreshToken != null) {
      await prefs.setString('refreshToken', refreshToken);
    }
  }

  // ================= HEADERS =================
  static Map<String, String> _authHeaders(String? token) {
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ================= CLEAR SESSION =================
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // ================= RESPONSE PARSER =================
  static Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.body.isEmpty) return {};

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;

    return {'data': decoded};
  }

  // ================= GUEST =================
  static Future<Map<String, dynamic>> createGuestSession({
    String? displayName,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final userId = _generateGuestUserId();
    final name = (displayName?.trim().isNotEmpty ?? false)
        ? displayName!.trim()
        : _guestName;

    await prefs.setString('userId', userId);
    await prefs.setString('displayName', name);

    return {
      'success': true,
      'guest': true,
      'user': {
        'id': userId,
        'displayName': name,
      },
    };
  }

  static String _generateGuestUserId() {
    final random = Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final entropy = random.nextInt(0xFFFFFF).toRadixString(36).padLeft(5, '0');
    return 'guest_$timestamp$entropy';
  }
}