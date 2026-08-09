import 'package:flutter_test/flutter_test.dart';
import 'package:whatomate_app/main.dart';

void main() {
  testWidgets('Whatomate app boots', (tester) async {
    await tester.pumpWidget(const WhatomateApp());
    expect(find.text('Whatomate'), findsOneWidget);
  });
}
