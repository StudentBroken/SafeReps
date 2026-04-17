import 'package:flutter_test/flutter_test.dart';

import 'package:safereps/main.dart';

void main() {
  testWidgets('App boots without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const SafeRepsApp());
    expect(find.text('SafeReps · Pose Debug'), findsOneWidget);
  });
}
