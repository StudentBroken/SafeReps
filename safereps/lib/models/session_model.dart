import 'package:flutter/widgets.dart';

class SessionModel extends ChangeNotifier {
  double? _repSpeed; // seconds per last completed rep; null = no session

  double? get repSpeed => _repSpeed;

  void reportRepSpeed(double? seconds) {
    if (_repSpeed == seconds) return;
    _repSpeed = seconds;
    notifyListeners();
  }

  void clearSession() {
    if (_repSpeed == null) return;
    _repSpeed = null;
    notifyListeners();
  }
}

class SessionScope extends InheritedNotifier<SessionModel> {
  const SessionScope({super.key, required SessionModel model, required super.child})
      : super(notifier: model);

  static SessionModel of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, 'No SessionScope found in context');
    return scope!.notifier!;
  }
}
