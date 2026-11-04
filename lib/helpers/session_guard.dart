import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'SecureStorageHelper.dart';

class SessionGuard {
  static const maxAge = Duration(hours: 6);

  static Timer? _timer;
  static bool expired = false;

  static Future<bool> signOutIfExpired() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final authTime = (await user.getIdTokenResult()).authTime;
    if (authTime != null && DateTime.now().difference(authTime) < maxAge) {
      return false;
    }

    if (FirebaseAuth.instance.currentUser?.uid != user.uid) return false;
    await signOut(expiry: true);
    return true;
  }

  static Future<void> watch({required void Function() onExpired}) async {
    expired = false;
    _timer?.cancel();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final authTime = (await user.getIdTokenResult()).authTime ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final remaining = maxAge - DateTime.now().difference(authTime);

    Future<void> expire() async {
      if (FirebaseAuth.instance.currentUser?.uid != user.uid) return;
      await signOut(expiry: true);
      onExpired();
    }

    if (remaining <= Duration.zero) {
      await expire();
    } else {
      _timer = Timer(remaining, () => unawaited(expire()));
    }
  }

  static Future<void> signOut({bool expiry = false}) async {
    expired = expiry;
    _timer?.cancel();
    _timer = null;
    await FirebaseAuth.instance.signOut();
    await SecureStorageHelper.deleteAll();
  }

  static void cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }
}
