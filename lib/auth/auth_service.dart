import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:monarch/other_pages/enviroment.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _guestName = 'Guest Explorer';

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

  static Future<Map<String, dynamic>> login({
    required String displayName,
    required String password,
  }) async {
    final response = await http.post(
      Environment.authUri('/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'displayName': displayName, 'password': password}),
    );

    return _handleAuthResponse(response);
  }

  
  static Future<Map<String, dynamic>> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');

    if (token == null || token.isEmpty) {
      return {'success': true, 'user': _cachedUserFromPrefs(prefs)};
    }

    try {
      final response = await http.get(
        Environment.authUri('/me'),
        headers: _authHeaders(token),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _decodeResponse(response);
      }
    } catch (_) {
      // Fall back to locally cached session data while the backend is unavailable.
    }

    return {'success': true, 'user': _cachedUserFromPrefs(prefs)};
  }

  static Future<Map<String, dynamic>> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');

    if (token == null || token.isEmpty) {
      await clearSession();
      return {'success': true};
    }

    try {
      final response = await http.post(
        Environment.authUri('/logout'),
        headers: _authHeaders(token),
      );

      final data = _decodeResponse(response);
      await clearSession();
      return data;
    } catch (_) {
      await clearSession();
      return {'success': true};
    }
  }

  static Future<Map<String, dynamic>> createGuestSession({
    String? displayName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _generateGuestUserId();
    final resolvedDisplayName =
        (displayName != null && displayName.trim().isNotEmpty)
            ? displayName.trim()
            : _guestName;

    await prefs.setString('userId', userId);
    await prefs.setString('displayName', resolvedDisplayName);
    await prefs.setString('email', '$userId@guest.local');
    await prefs.remove('authToken');

    return {
      'success': true,
      'guest': true,
      'user': {
        'id': userId,
        'displayName': resolvedDisplayName,
        'email': '$userId@guest.local',
      },
    };
  }

  static Future<bool> hasSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    return userId != null && userId.isNotEmpty;
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    await prefs.remove('displayName');
    await prefs.remove('name');
    await prefs.remove('authToken');
  }

  static Future<Map<String, dynamic>> _handleAuthResponse(
    http.Response response, {
    String? fallbackDisplayName,
    String? fallbackEmail,
  }) async {
    final data = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(data, response.body));
    }

    if (data['success'] == false) {
      throw Exception(_extractErrorMessage(data, response.body));
    }

    await _persistAuthData(
      data,
      fallbackDisplayName: fallbackDisplayName,
      fallbackEmail: fallbackEmail,
    );

    return data;
  }

  static Future<void> _persistAuthData(
    Map<String, dynamic> data, {
    String? fallbackDisplayName,
    String? fallbackEmail,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final user = _extractUser(data);
    final token = _extractToken(data);

    final userId = user['_id']?.toString() ?? user['id']?.toString();
    final displayName =
        user['displayName']?.toString() ??
        user['name']?.toString() ??
        fallbackDisplayName;
    final email = user['email']?.toString() ?? fallbackEmail;

    if (userId != null && userId.isNotEmpty) {
      await prefs.setString('userId', userId);
    }
    if (displayName != null && displayName.isNotEmpty) {
      await prefs.setString('displayName', displayName);
    }
    if (email != null && email.isNotEmpty) {
      await prefs.setString('email', email);
    }
    if (token != null && token.isNotEmpty) {
      await prefs.setString('authToken', token);
    }
  }

  static Map<String, dynamic> _extractUser(Map<String, dynamic> data) {
    final rawUser = data['user'] ?? data['data']?['user'] ?? data['data'];
    if (rawUser is Map<String, dynamic>) {
      return rawUser;
    }
    if (rawUser is Map) {
      return rawUser.cast<String, dynamic>();
    }
    return <String, dynamic>{};
  }

  static String? _extractToken(Map<String, dynamic> data) {
    final candidates = [
      data['token'],
      data['accessToken'],
      data['jwt'],
      data['data']?['token'],
      data['data']?['accessToken'],
      data['data']?['jwt'],
    ];

    for (final candidate in candidates) {
      if (candidate is String && candidate.isNotEmpty) {
        return candidate;
      }
    }
    return null;
  }

  static Map<String, String> _authHeaders(String? token) {
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.body.isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return <String, dynamic>{'data': decoded};
  }

  static String _extractErrorMessage(
    Map<String, dynamic> data,
    String fallback,
  ) {
    final candidates = [
      data['message'],
      data['error'],
      data['errors'] is List && (data['errors'] as List).isNotEmpty
          ? data['errors'][0]
          : null,
    ];

    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate;
      }
    }
    return fallback.isEmpty ? 'Request failed' : fallback;
  }

  static Map<String, dynamic> _cachedUserFromPrefs(SharedPreferences prefs) {
    final userId = prefs.getString('userId') ?? '';
    final displayName =
        prefs.getString('displayName') ??
        prefs.getString('name') ??
        _guestName;
    final email = prefs.getString('email') ?? '';

    return {
      'id': userId,
      'displayName': displayName,
      'email': email,
    };
  }

  static String _generateGuestUserId() {
    final random = Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final entropy = random.nextInt(0xFFFFFF).toRadixString(36).padLeft(5, '0');
    return 'guest_$timestamp$entropy';
  }
}
