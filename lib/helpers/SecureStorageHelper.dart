import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;

class SecureStorageHelper {
  static const _storage = FlutterSecureStorage();

  static Future<void> write(String key, String value) async {
    if (kIsWeb) {
      html.window.localStorage[key] = value;
    } else {
      await _storage.write(key: key, value: value);
    }
  }

  static Future<String?> read(String key) async {
    if (kIsWeb) {
      return html.window.localStorage[key];
    } else {
      return await _storage.read(key: key);
    }
  }

  static Future<void> delete(String key) async {
    if (kIsWeb) {
      html.window.localStorage.remove(key);
    } else {
      await _storage.delete(key: key);
    }
  }

  static Future<void> deleteAll() async {
    if (kIsWeb) {
      html.window.localStorage.clear();
    } else {
      await _storage.deleteAll();
    }
  }
}
