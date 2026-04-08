import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:monarch/other_pages/enviroment.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Environment.authUri('/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
      }),
    );

    return _handleAuthResponse(response);
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Environment.authUri('/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    return _handleAuthResponse(response);
  }

  static Future<Map<String, dynamic>> googleTokenLogin({
    required String idToken,
    String? googleAccessToken,
    String? fallbackName,
    String? fallbackEmail,
  }) async {
    final response = await http.post(
      Environment.authUri('/google/token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    );

    return _handleAuthResponse(
      response,
      googleAccessToken: googleAccessToken,
      fallbackName: fallbackName,
      fallbackEmail: fallbackEmail,
    );
  }

  static Future<Map<String, dynamic>> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');

    final response = await http.get(
      Environment.authUri('/me'),
      headers: _authHeaders(token),
    );

    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');

    final response = await http.post(
      Environment.authUri('/logout'),
      headers: _authHeaders(token),
    );

    final data = _decodeResponse(response);
    await clearSession();
    return data;
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    await prefs.remove('name');
    await prefs.remove('email');
    await prefs.remove('authToken');
    await prefs.remove('googleAccessToken');
  }

  static Future<Map<String, dynamic>> _handleAuthResponse(
    http.Response response, {
    String? googleAccessToken,
    String? fallbackName,
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
      googleAccessToken: googleAccessToken,
      fallbackName: fallbackName,
      fallbackEmail: fallbackEmail,
    );

    return data;
  }

  static Future<void> _persistAuthData(
    Map<String, dynamic> data, {
    String? googleAccessToken,
    String? fallbackName,
    String? fallbackEmail,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final user = _extractUser(data);
    final token = _extractToken(data);

    final userId = user['_id']?.toString() ?? user['id']?.toString();
    final name = user['name']?.toString() ?? fallbackName;
    final email = user['email']?.toString() ?? fallbackEmail;

    if (userId != null && userId.isNotEmpty) {
      await prefs.setString('userId', userId);
    }
    if (name != null && name.isNotEmpty) {
      await prefs.setString('name', name);
    }
    if (email != null && email.isNotEmpty) {
      await prefs.setString('email', email);
    }
    if (token != null && token.isNotEmpty) {
      await prefs.setString('authToken', token);
    }
    if (googleAccessToken != null && googleAccessToken.isNotEmpty) {
      await prefs.setString('googleAccessToken', googleAccessToken);
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
}
