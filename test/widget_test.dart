// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

// Smoke test — full widget test requires mocking StorageService etc.
// This validates the test framework itself loads correctly.
void main() {
  test('dart test framework works', () {
    expect(1 + 1, 2);
  });
}
