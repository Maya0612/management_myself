import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:management_myself/main.dart';

void main() {
  testWidgets('app shows login form', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const HabitTrackerApp());
    await tester.pumpAndSettle();

    expect(find.text('Chào mừng trở lại'), findsOneWidget);
    expect(find.text('Đăng nhập'), findsOneWidget);
    expect(find.textContaining('test@gmail.com'), findsOneWidget);
  });

  test('password hash verifies the original password', () {
    final hashedPassword = hashPassword('123456', salt: 'fixed-salt');

    expect(verifyPassword('123456', hashedPassword), isTrue);
    expect(verifyPassword('wrong-password', hashedPassword), isFalse);
  });

  test('reminder time preserves 24-hour and legacy 12-hour values', () {
    expect(encodeReminderTime(parseReminderTime('16:30')), '16:30');
    expect(encodeReminderTime(parseReminderTime('4:30 PM')), '16:30');
    expect(encodeReminderTime(parseReminderTime('12:15 AM')), '00:15');
  });

  test('weekly habit is due only on selected weekdays after creation', () {
    final habit = Habit(
      id: 1,
      userId: 1,
      name: 'Vận động',
      description: '',
      frequency: HabitFrequency.weekly,
      weekdays: <int>[1, 3, 5],
      reminderTime: '17:30',
      isActive: true,
      createdAt: DateTime(2026, 11, 2).toIso8601String(),
    );

    expect(habit.isDueOn(DateTime(2026, 11, 2)), isTrue);
    expect(habit.isDueOn(DateTime(2026, 11, 3)), isFalse);
    expect(habit.isDueOn(DateTime(2026, 11, 1)), isFalse);
  });
}
