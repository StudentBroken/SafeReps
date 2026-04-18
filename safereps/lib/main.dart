import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'models/coach_settings.dart';
import 'models/goals_model.dart';
import 'models/history_model.dart';
import 'models/session_model.dart';
import 'services/ble_service.dart';
import 'services/theme_service.dart';
import 'shell.dart';
import 'theme.dart';

List<CameraDescription> cameras = const [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize ThemeService
  final themeService = ThemeService();
  await themeService.init();

  // Query cameras
  try {
    cameras = await availableCameras();
  } catch (_) {
    cameras = const [];
  }

  // Initialize BLE, Goals, Coach Settings, and History
  final bleService = BleService();
  final goalsModel = GoalsModel();
  await goalsModel.load();
  final coachSettings = await CoachSettings.load();
  final sessionModel = SessionModel();
  final historyModel = HistoryModel();
  await historyModel.load();

  runApp(
    ThemeScope(
      service: themeService,
      child: CoachSettingsScope(
        settings: coachSettings,
        child: GoalsScope(
          model: goalsModel,
          child: HistoryScope(
            model: historyModel,
            child: BleScope(
              ble: bleService,
              child: SessionScope(
                model: sessionModel,
                child: const SafeRepsApp(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class SafeRepsApp extends StatelessWidget {
  const SafeRepsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = ThemeScope.of(context);
    
    return ListenableBuilder(
      listenable: themeService,
      builder: (context, _) {
        return MaterialApp(
          title: 'SafeReps',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.fromFlavor(themeService.flavor),
          home: const MainShell(),
        );
      },
    );
  }
}
