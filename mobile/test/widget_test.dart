import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lms_smooth_bridge_mobile/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows login screen without stored session', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SmoothBridgeApp());
    await tester.pumpAndSettle();

    expect(find.text('LMS Smooth Bridge Login'), findsOneWidget);
  });
}
