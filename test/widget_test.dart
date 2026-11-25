import 'package:flutter_test/flutter_test.dart';
import 'package:hide_ar/main.dart';

void main() {
  testWidgets('HideArApp renders without crashing', (tester) async {
    await tester.pumpWidget(const HideArApp());
    expect(find.byType(HideArApp), findsOneWidget);
  });
}
