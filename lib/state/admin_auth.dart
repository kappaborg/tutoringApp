import 'package:flutter/foundation.dart';

/// Tracks whether Teacher Mode is unlocked for the current session. We do not
/// persist the unlocked state — a kid handing the device back should lock it.
class AdminAuth extends ChangeNotifier {
  bool _unlocked = false;
  bool get isUnlocked => _unlocked;

  void unlock() {
    if (_unlocked) return;
    _unlocked = true;
    notifyListeners();
  }

  void lock() {
    if (!_unlocked) return;
    _unlocked = false;
    notifyListeners();
  }
}
