import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';

class ThemeService extends ChangeNotifier {
  static const _kThemeKey = 'theme_flavor';
  
  ThemeFlavor _flavor = ThemeFlavor.pink;
  ThemeFlavor get flavor => _flavor;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kThemeKey);
    if (saved != null) {
      _flavor = ThemeFlavor.values.firstWhere(
        (e) => e.name == saved,
        orElse: () => ThemeFlavor.pink,
      );
      notifyListeners();
    }
  }

  Future<void> setFlavor(ThemeFlavor f) async {
    if (_flavor == f) return;
    _flavor = f;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeKey, f.name);
  }
}

class ThemeScope extends InheritedNotifier<ThemeService> {
  const ThemeScope({
    super.key,
    required ThemeService service,
    required super.child,
  }) : super(notifier: service);

  static ThemeService of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ThemeScope>()!.notifier!;
  }
}
