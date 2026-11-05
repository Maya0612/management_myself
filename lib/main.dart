import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('vi_VN');
  Intl.defaultLocale = 'vi_VN';
  await AppDatabase.instance.init();
  await DemoNotificationService.initialize();
  runApp(const HabitTrackerApp());
}

class AppColors {
  static const primary = Color(0xFF176B5B);
  static const primaryDark = Color(0xFF104B41);
  static const mint = Color(0xFFDDF3EA);
  static const accent = Color(0xFFFF9B71);
  static const background = Color(0xFFF4F7F2);
  static const ink = Color(0xFF20332E);
  static const muted = Color(0xFF71827C);
  static const lavender = Color(0xFFEDE9FF);
  static const yellow = Color(0xFFFFF1C9);
}

class DemoNotificationService {
  DemoNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
  }

  static Future<bool> showDemoNotification() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError(
        'Thông báo trên thanh hệ thống hiện được hỗ trợ trên Android.',
      );
    }

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) {
      throw StateError('Không khởi tạo được dịch vụ thông báo Android.');
    }

    final permissionGranted = await androidPlugin
        .requestNotificationsPermission();
    if (permissionGranted == false) {
      return false;
    }

    await _plugin.show(
      id: 1001,
      title: 'Kỷ luật mỗi ngày',
      body: 'Hãy bắt đầu một việc tốt cho bản thân nhé!',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'habit_demo_reminders',
          'Nhắc nhở thói quen',
          channelDescription: 'Thông báo nhắc nhở dùng thử của ứng dụng.',
          importance: Importance.high,
          priority: Priority.high,
          color: AppColors.primary,
        ),
      ),
    );
    return true;
  }
}

class HabitTrackerApp extends StatelessWidget {
  const HabitTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kỷ luật mỗi ngày',
      debugShowCheckedModeBanner: false,
      locale: const Locale('vi', 'VN'),
      supportedLocales: const <Locale>[Locale('vi', 'VN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: AppColors.primary,
              surface: Colors.white,
            ).copyWith(
              primary: AppColors.primary,
              secondary: AppColors.accent,
              surface: Colors.white,
            ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.ink,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          shadowColor: AppColors.primary.withValues(alpha: 0.07),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.12),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: AppColors.mint,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              color: states.contains(WidgetState.selected)
                  ? AppColors.primary
                  : AppColors.muted,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            );
          }),
        ),
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final HabitAppController _controller = HabitAppController();

  @override
  void initState() {
    super.initState();
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (_controller.currentUser == null) {
          return AuthScreen(controller: _controller);
        }

        return HomeScreen(controller: _controller);
      },
    );
  }
}

class HabitAppController extends ChangeNotifier {
  AppUser? _currentUser;
  bool _isLoading = true;
  final List<Habit> _habits = <Habit>[];
  final Map<int, Set<String>> _completionDatesByHabit = <int, Set<String>>{};

  AppUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  List<Habit> get habits => List<Habit>.unmodifiable(_habits);

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    final userId = await AppPreferences.getCurrentUserId();
    if (userId != null) {
      final user = await AppDatabase.instance.fetchUserById(userId);
      if (user != null) {
        _currentUser = user;
      }
    }

    await refreshData();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refreshData() async {
    if (_currentUser == null) {
      _habits.clear();
      _completionDatesByHabit.clear();
      notifyListeners();
      return;
    }

    final habits = await AppDatabase.instance.fetchHabitsForUser(
      _currentUser!.id,
    );
    final completions = await AppDatabase.instance.fetchCompletionsForUser(
      _currentUser!.id,
    );

    _habits
      ..clear()
      ..addAll(habits);

    _completionDatesByHabit.clear();
    for (final completion in completions) {
      _completionDatesByHabit
          .putIfAbsent(completion.habitId, () => <String>{})
          .add(completion.dateKey);
    }

    notifyListeners();
  }

  Future<void> registerUser({
    required String username,
    required String displayName,
    required String password,
  }) async {
    final normalizedUsername = username.trim().toLowerCase();
    final normalizedDisplayName = displayName.trim();
    if (normalizedUsername.isEmpty ||
        normalizedDisplayName.isEmpty ||
        password.trim().isEmpty) {
      throw Exception('Vui lòng nhập đầy đủ email, tên hiển thị và mật khẩu.');
    }
    if (!normalizedUsername.contains('@') ||
        !normalizedUsername.contains('.')) {
      throw Exception('Vui lòng nhập địa chỉ email hợp lệ.');
    }
    if (password.length < 6) {
      throw Exception('Mật khẩu cần có ít nhất 6 ký tự.');
    }

    final existingUser = await AppDatabase.instance.fetchUserByUsername(
      normalizedUsername,
    );
    if (existingUser != null) {
      throw Exception('Email này đã được đăng ký. Hãy chọn email khác.');
    }

    final user = AppUser(
      username: normalizedUsername,
      displayName: normalizedDisplayName,
      passwordHash: hashPassword(password),
    );

    final createdId = await AppDatabase.instance.createUser(user);
    final createdUser = user.copyWith(id: createdId);
    _currentUser = createdUser;
    await AppPreferences.setCurrentUser(createdUser.id);
    await refreshData();
  }

  Future<void> loginUser({
    required String username,
    required String password,
  }) async {
    final normalizedUsername = username.trim().toLowerCase();
    if (normalizedUsername.isEmpty || password.trim().isEmpty) {
      throw Exception('Vui lòng nhập email và mật khẩu.');
    }

    final user = await AppDatabase.instance.fetchUserByUsernameAndPassword(
      normalizedUsername,
      password,
    );
    if (user == null) {
      throw Exception('Email hoặc mật khẩu không chính xác.');
    }

    _currentUser = user;
    await AppPreferences.setCurrentUser(user.id);
    await refreshData();
  }

  Future<void> logout() async {
    _currentUser = null;
    _habits.clear();
    _completionDatesByHabit.clear();
    await AppPreferences.clearCurrentUser();
    notifyListeners();
  }

  Future<void> saveHabit(Habit habit) async {
    if (_currentUser == null) {
      throw StateError('Vui lòng đăng nhập để quản lý thói quen.');
    }

    final safeHabit = habit.copyWith(userId: _currentUser!.id);
    if (safeHabit.name.trim().isEmpty) {
      throw Exception('Vui lòng nhập tên thói quen.');
    }

    if (safeHabit.frequency == HabitFrequency.weekly &&
        safeHabit.weekdays.isEmpty) {
      throw Exception('Hãy chọn ít nhất một ngày trong tuần.');
    }

    if (safeHabit.id == null || safeHabit.id == 0) {
      final newHabit = safeHabit.copyWith(
        createdAt: DateTime.now().toIso8601String(),
      );
      await AppDatabase.instance.createHabit(newHabit);
    } else {
      await AppDatabase.instance.updateHabit(safeHabit);
    }

    await refreshData();
  }

  Future<void> deleteHabit(Habit habit) async {
    final id = habit.id;
    if (id == null || id == 0) {
      return;
    }

    if (_currentUser == null || habit.userId != _currentUser!.id) {
      throw StateError('Bạn không có quyền xóa thói quen này.');
    }
    await AppDatabase.instance.deleteHabit(
      userId: _currentUser!.id,
      habitId: id,
    );
    await refreshData();
  }

  Future<void> toggleCompletion(Habit habit, DateTime date) async {
    if (_currentUser == null ||
        habit.id == null ||
        habit.userId != _currentUser!.id ||
        !habit.isActive ||
        !habit.isDueOn(date)) {
      return;
    }

    final dateKey = dateKeyFor(date);
    final set = _completionDatesByHabit.putIfAbsent(
      habit.id!,
      () => <String>{},
    );

    if (set.contains(dateKey)) {
      await AppDatabase.instance.deleteCompletion(
        userId: _currentUser!.id,
        habitId: habit.id!,
        date: date,
      );
      set.remove(dateKey);
    } else {
      await AppDatabase.instance.createCompletion(
        userId: _currentUser!.id,
        habitId: habit.id!,
        date: date,
      );
      set.add(dateKey);
    }

    notifyListeners();
  }

  bool isCompletedForDate(Habit habit, DateTime date) {
    final id = habit.id;
    if (id == null) {
      return false;
    }

    return _completionDatesByHabit[id]?.contains(dateKeyFor(date)) ?? false;
  }

  RangeSummary calculateRangeSummary(StatsPeriod period) {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final start = startOfPeriod(period, todayOnly);
    final end = todayOnly;

    int dueDays = 0;
    int completedDays = 0;

    for (final habit in _habits.where((item) => item.isActive)) {
      var cursor = start;
      while (!cursor.isAfter(end)) {
        if (!habit.isDueOn(cursor)) {
          cursor = cursor.add(const Duration(days: 1));
          continue;
        }

        dueDays += 1;
        if (isCompletedForDate(habit, cursor)) {
          completedDays += 1;
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    }

    final ratio = dueDays == 0 ? 0.0 : (completedDays / dueDays) * 100;
    return RangeSummary(
      dueDays: dueDays,
      completedDays: completedDays,
      percentage: ratio,
    );
  }
}

class HabitEditorDialog extends StatefulWidget {
  const HabitEditorDialog({super.key, this.habit});

  final Habit? habit;

  @override
  State<HabitEditorDialog> createState() => _HabitEditorDialogState();
}

class _HabitEditorDialogState extends State<HabitEditorDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _frequency = HabitFrequency.daily;
  final List<int> _selectedWeekdays = <int>[];
  TimeOfDay _selectedTime = const TimeOfDay(hour: 8, minute: 0);
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    if (widget.habit != null) {
      final habit = widget.habit!;
      _nameController.text = habit.name;
      _descriptionController.text = habit.description;
      _frequency = habit.frequency;
      _selectedWeekdays.addAll(habit.weekdays);
      _selectedTime = parseReminderTime(habit.reminderTime);
      _isActive = habit.isActive;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  void _saveHabit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên thói quen.')),
      );
      return;
    }

    if (_frequency == HabitFrequency.weekly && _selectedWeekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hãy chọn ít nhất một ngày trong tuần.')),
      );
      return;
    }

    final selectedDays = _frequency == HabitFrequency.weekly
        ? List<int>.from(_selectedWeekdays)
        : <int>[];

    final habit = Habit(
      id: widget.habit?.id,
      userId: widget.habit?.userId ?? 0,
      name: name,
      description: _descriptionController.text.trim(),
      frequency: _frequency,
      weekdays: selectedDays,
      reminderTime: encodeReminderTime(_selectedTime),
      isActive: _isActive,
      createdAt: widget.habit?.createdAt ?? DateTime.now().toIso8601String(),
    );

    Navigator.of(context).pop(habit);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.habit == null ? 'Thêm thói quen' : 'Chỉnh sửa thói quen',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Tên thói quen',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Mô tả',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey<String>(_frequency),
                initialValue: _frequency,
                items: const [
                  DropdownMenuItem(
                    value: HabitFrequency.daily,
                    child: Text('Hằng ngày'),
                  ),
                  DropdownMenuItem(
                    value: HabitFrequency.weekly,
                    child: Text('Các ngày trong tuần'),
                  ),
                ],
                decoration: const InputDecoration(
                  labelText: 'Tần suất',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _frequency = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Thời gian nhắc',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickTime,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(_selectedTime.format(context)),
                      const Icon(Icons.access_time),
                    ],
                  ),
                ),
              ),
              if (_frequency == HabitFrequency.weekly) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  'Lặp lại vào',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: List<Widget>.generate(7, (index) {
                    final weekday = index + 1;
                    final dayName = DateFormat('EEE')
                        .format(DateTime(2024, 1, weekday));
                    final selected = _selectedWeekdays.contains(weekday);
                    return FilterChip(
                      selected: selected,
                      label: Text(dayName),
                      onSelected: (_) {
                        setState(() {
                          if (selected) {
                            _selectedWeekdays.remove(weekday);
                          } else {
                            _selectedWeekdays.add(weekday);
                          }
                          _selectedWeekdays.sort();
                        });
                      },
                    );
                  }),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Đang hoạt động'),
                subtitle: const Text(
                  'Tạm dừng sẽ ẩn thói quen khỏi phần cần làm hôm nay.',
                ),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          onPressed: _saveHabit,
          icon: const Icon(Icons.save_alt),
          label: const Text('Lưu thói quen'),
        ),
      ],
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final HabitAppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  Future<void> _openHabitEditor([Habit? habit]) async {
    final result = await showDialog<Habit>(
      context: context,
      builder: (context) => HabitEditorDialog(habit: habit),
    );

    if (result == null) {
      return;
    }

    try {
      await widget.controller.saveHabit(result);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            habit == null ? 'Đã thêm thói quen.' : 'Đã cập nhật thói quen.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _confirmDelete(Habit habit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa thói quen?'),
        content: Text('Bạn có chắc muốn xóa “${habit.name}” không?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await widget.controller.deleteHabit(habit);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Đã xóa thói quen.')));
      } catch (error) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Widget _buildBody() {
    final screens = <Widget>[
      DashboardTab(controller: widget.controller),
      HabitListTab(
        controller: widget.controller,
        onAdd: () => _openHabitEditor(),
        onEdit: (habit) => _openHabitEditor(habit),
        onDelete: _confirmDelete,
      ),
      StatsTab(controller: widget.controller),
      ProfileTab(controller: widget.controller),
    ];

    return screens[_selectedIndex];
  }

  @override
  Widget build(BuildContext context) {
    final destinations = <NavigationRailDestination>[
      const NavigationRailDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: Text('Tổng quan'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.format_list_bulleted_outlined),
        selectedIcon: Icon(Icons.format_list_bulleted),
        label: Text('Thói quen'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.bar_chart_outlined),
        selectedIcon: Icon(Icons.bar_chart),
        label: Text('Thống kê'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: Text('Tài khoản'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wideLayout = constraints.maxWidth >= 780;
        if (wideLayout) {
          return Scaffold(
            body: Row(
              children: <Widget>[
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  labelType: NavigationRailLabelType.all,
                  destinations: destinations,
                ),
                Expanded(child: _buildBody()),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Kỷ luật mỗi ngày'),
            actions: <Widget>[
              IconButton(
                onPressed: () => _openHabitEditor(),
                icon: const Icon(Icons.add),
                tooltip: 'Thêm thói quen',
              ),
            ],
          ),
          body: _buildBody(),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (value) {
              setState(() {
                _selectedIndex = value;
              });
            },
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                label: 'Tổng quan',
              ),
              NavigationDestination(
                icon: Icon(Icons.format_list_bulleted_outlined),
                label: 'Thói quen',
              ),
              NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined),
                label: 'Thống kê',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                label: 'Tài khoản',
              ),
            ],
          ),
        );
      },
    );
  }
}

class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key, required this.controller});

  final HabitAppController controller;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final activeHabits = controller.habits
        .where((habit) => habit.isActive)
        .toList();
    final todayHabits = activeHabits
        .where((habit) => habit.isDueOn(today))
        .toList();
    final completedToday = todayHabits
        .where((habit) => controller.isCompletedForDate(habit, today))
        .length;
    final completionRate = todayHabits.isEmpty
        ? 0.0
        : (completedToday / todayHabits.length) * 100;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Chào ${controller.currentUser?.displayName ?? 'bạn'}!',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          DateFormat('EEEE, d MMMM', 'vi_VN').format(today),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Mỗi việc nhỏ hôm nay tạo nên phiên bản tốt hơn của bạn.',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 76,
                    height: 76,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        CircularProgressIndicator(
                          value: completionRate / 100,
                          strokeWidth: 7,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.accent,
                          ),
                        ),
                        Center(
                          child: Text(
                            '${completionRate.round()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: wide ? 4 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: wide ? 1.7 : 1.2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: <Widget>[
                _StatusCard(
                  title: 'Hôm nay',
                  value: '${todayHabits.length}',
                  subtitle: 'thói quen đến lịch',
                  icon: Icons.today_outlined,
                  tint: AppColors.mint,
                ),
                _StatusCard(
                  title: 'Hoàn thành',
                  value: '$completedToday',
                  subtitle: 'đã thực hiện',
                  icon: Icons.check_circle_outline,
                  tint: const Color(0xFFE1F4E7),
                ),
                _StatusCard(
                  title: 'Tiến độ',
                  value: '${completionRate.round()}%',
                  subtitle: 'trong hôm nay',
                  icon: Icons.trending_up,
                  tint: AppColors.lavender,
                ),
                _StatusCard(
                  title: 'Đang duy trì',
                  value: '${activeHabits.length}',
                  subtitle: 'thói quen hoạt động',
                  icon: Icons.local_fire_department_outlined,
                  tint: AppColors.yellow,
                ),
              ],
            ),
            const SizedBox(height: 22),
            Card(
              color: AppColors.yellow,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.notifications_active_outlined,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Thông báo dùng thử',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: 4),
                          Text('Gửi lời nhắc mẫu lên thanh thông báo của điện thoại.'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () async {
                        try {
                          final sent =
                              await DemoNotificationService.showDemoNotification();
                          if (!sent && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Bạn chưa cấp quyền thông báo. Hãy bật quyền trong Cài đặt của thiết bị.',
                                ),
                              ),
                            );
                          }
                        } catch (error) {
                          if (!context.mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Không gửi được thông báo: $error'),
                            ),
                          );
                        }
                      },
                      child: const Text('Thử ngay'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Việc cần làm hôm nay',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (todayHabits.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Hôm nay chưa có thói quen nào đến lịch. Thêm thói quen để bắt đầu nhé!',
                  ),
                ),
              )
            else
              ...todayHabits.map((habit) {
                final isDone = controller.isCompletedForDate(habit, today);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: Checkbox(
                      value: isDone,
                      activeColor: AppColors.primary,
                      onChanged: (_) =>
                          controller.toggleCompletion(habit, today),
                    ),
                    title: Text(
                      habit.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone ? AppColors.muted : AppColors.ink,
                      ),
                    ),
                    subtitle: Text(
                      '${habit.description.isEmpty ? 'Không có mô tả' : habit.description} • Nhắc lúc ${habit.reminderTime}',
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.value,
    required this.subtitle,
    this.icon = Icons.insights_outlined,
    this.tint = AppColors.mint,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w800),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class HabitListTab extends StatelessWidget {
  const HabitListTab({
    super.key,
    required this.controller,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final HabitAppController controller;
  final VoidCallback onAdd;
  final ValueChanged<Habit> onEdit;
  final ValueChanged<Habit> onDelete;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final habits = controller.habits;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: const Text('Thêm thói quen'),
      ),
      body: habits.isEmpty
          ? const Center(
              child: Text('Chưa có thói quen. Hãy tạo thói quen đầu tiên nhé!'),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: habits.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final habit = habits[index];
                final isDone = controller.isCompletedForDate(habit, today);
                final isDueToday = habit.isActive && habit.isDueOn(today);
                final subtitle = <String>[
                  habit.frequency == HabitFrequency.weekly
                      ? 'Theo ngày • ${habit.formatWeekdays()}'
                      : 'Hằng ngày',
                  'Nhắc lúc ${habit.reminderTime}',
                  if (!habit.isActive) 'Đang tạm dừng',
                  if (habit.isActive && !isDueToday) 'Hôm nay không đến lịch',
                ].join('  ·  ');

                return Card(
                  child: ListTile(
                    leading: Checkbox(
                      value: isDone,
                      activeColor: AppColors.primary,
                      onChanged: isDueToday
                          ? (_) => controller.toggleCompletion(habit, today)
                          : null,
                    ),
                    title: Text(
                      habit.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const SizedBox(height: 4),
                        Text(
                          habit.isActive ? 'Đang hoạt động' : 'Đã tạm dừng',
                          style: TextStyle(
                            color: habit.isActive
                                ? AppColors.primary
                                : AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (habit.description.isNotEmpty)
                          Text(habit.description),
                        const SizedBox(height: 4),
                        Text(subtitle),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Tùy chọn thói quen',
                      onSelected: (value) {
                        if (value == 'edit') {
                          onEdit(habit);
                        } else if (value == 'delete') {
                          onDelete(habit);
                        }
                      },
                      itemBuilder: (context) => const <PopupMenuEntry<String>>[
                        PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa')),
                        PopupMenuItem(value: 'delete', child: Text('Xóa')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class StatsTab extends StatefulWidget {
  const StatsTab({super.key, required this.controller});

  final HabitAppController controller;

  @override
  State<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<StatsTab> {
  StatsPeriod _period = StatsPeriod.week;

  @override
  Widget build(BuildContext context) {
    final summary = widget.controller.calculateRangeSummary(_period);
    final activeHabits = widget.controller.habits
        .where((habit) => habit.isActive)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        SegmentedButton<StatsPeriod>(
          segments: const <ButtonSegment<StatsPeriod>>[
            ButtonSegment(value: StatsPeriod.day, label: Text('Ngày')),
            ButtonSegment(value: StatsPeriod.week, label: Text('Tuần')),
            ButtonSegment(value: StatsPeriod.month, label: Text('Tháng')),
          ],
          selected: <StatsPeriod>{_period},
          onSelectionChanged: (newSelection) {
            setState(() {
              _period = newSelection.first;
            });
          },
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Tổng quan tiến độ',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _StatusCard(
                        title: 'Hoàn thành',
                        value: '${summary.completedDays}',
                        subtitle: 'lần thực hiện',
                        icon: Icons.check_circle_outline,
                        tint: AppColors.mint,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatusCard(
                        title: 'Theo lịch',
                        value: '${summary.dueDays}',
                        subtitle: 'lần cần làm',
                        icon: Icons.event_note_outlined,
                        tint: AppColors.yellow,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: summary.percentage / 100,
                  minHeight: 12,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 8),
                Text(
                  '${summary.percentage.toStringAsFixed(0)}% hoàn thành  ·  Chưa hoàn thành: ${summary.dueDays - summary.completedDays} lần',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Tiến độ từng thói quen',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (activeHabits.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Chưa có thói quen đang hoạt động để thống kê.'),
            ),
          )
        else
          ...activeHabits.map((habit) {
            final dueCount = countDueDaysForHabit(habit, _period);
            final completeCount = countCompleteDaysForHabit(
              widget.controller,
              habit,
              _period,
            );
            final percent = dueCount == 0
                ? 0.0
                : (completeCount / dueCount) * 100;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      habit.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text('Đã làm $completeCount / $dueCount lần theo lịch'),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: percent / 100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    const SizedBox(height: 8),
                    Text('${percent.toStringAsFixed(0)}%'),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key, required this.controller});

  final HabitAppController controller;

  @override
  Widget build(BuildContext context) {
    final user = controller.currentUser;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: <Widget>[
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.mint,
                  child: Icon(Icons.person, color: AppColors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        user?.displayName ?? 'Chưa rõ người dùng',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        user?.username ?? '',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Tài khoản', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: <Widget>[
              ListTile(
                leading: const Icon(
                  Icons.alternate_email,
                  color: AppColors.primary,
                ),
                title: const Text('Địa chỉ email'),
                subtitle: Text(user?.username ?? ''),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              const ListTile(
                leading: Icon(
                  Icons.notifications_active_outlined,
                  color: AppColors.primary,
                ),
                title: Text('Thông báo'),
                subtitle: Text(
                  'Có thể thử lời nhắc mẫu ngay tại màn hình Tổng quan.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () async {
            await controller.logout();
          },
          icon: const Icon(Icons.logout),
          label: const Text('Đăng xuất'),
        ),
      ],
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.controller});

  final HabitAppController controller;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isRegister = false;

  void _fillDemoCredentials() {
    setState(() {
      _usernameController.text = 'test@gmail.com';
      _passwordController.text = '123456';
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text;
    final password = _passwordController.text;

    try {
      if (_isRegister) {
        await widget.controller.registerUser(
          username: username,
          displayName: _displayNameController.text,
          password: password,
        );
      } else {
        await widget.controller.loginUser(
          username: username,
          password: password,
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      _isRegister ? 'Tạo tài khoản mới' : 'Chào mừng trở lại',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRegister
                          ? 'Tạo tài khoản để lưu thói quen riêng của bạn.'
                          : 'Đăng nhập để tiếp tục hành trình rèn luyện.',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    if (!_isRegister) ...<Widget>[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.mint,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Tài khoản dùng thử',
                              style: TextStyle(
                                color: AppColors.primaryDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text('Email: test@gmail.com  ·  Mật khẩu: 123456'),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _fillDemoCredentials,
                          icon: const Icon(Icons.bolt),
                          label: const Text('Điền tài khoản mẫu'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (_isRegister)
                      TextField(
                        controller: _displayNameController,
                        decoration: const InputDecoration(
                          labelText: 'Tên hiển thị',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    if (_isRegister) const SizedBox(height: 12),
                    TextField(
                      controller: _usernameController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email / tên đăng nhập',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Mật khẩu',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _submit,
                      child: Text(_isRegister ? 'Đăng ký' : 'Đăng nhập'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isRegister = !_isRegister;
                        });
                      },
                      child: Text(
                        _isRegister
                            ? 'Đã có tài khoản? Đăng nhập'
                            : 'Chưa có tài khoản? Đăng ký',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String hashPassword(String password, {String? salt}) {
  final actualSalt =
      salt ??
      List<int>.generate(
        16,
        (_) => Random.secure().nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  final digest = sha256.convert(utf8.encode('$actualSalt:$password'));
  return 'v1\$$actualSalt\$${digest.toString()}';
}

bool verifyPassword(String password, String encodedPassword) {
  final parts = encodedPassword.split(r'$');
  if (parts.length != 3 || parts.first != 'v1') {
    return false;
  }
  return hashPassword(password, salt: parts[1]) == encodedPassword;
}

class AppUser {
  const AppUser({
    this.id = 0,
    required this.username,
    required this.displayName,
    required this.passwordHash,
  });

  final int id;
  final String username;
  final String displayName;
  final String passwordHash;

  AppUser copyWith({int? id}) {
    return AppUser(
      id: id ?? this.id,
      username: username,
      displayName: displayName,
      passwordHash: passwordHash,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'username': username,
      'display_name': displayName,
      'password': passwordHash,
    };
  }

  factory AppUser.fromMap(Map<String, Object?> map) {
    return AppUser(
      id: map['id'] as int? ?? 0,
      username: map['username'] as String? ?? '',
      displayName: map['display_name'] as String? ?? '',
      passwordHash: map['password'] as String? ?? '',
    );
  }
}

class Habit {
  const Habit({
    this.id,
    required this.userId,
    required this.name,
    required this.description,
    required this.frequency,
    required this.weekdays,
    required this.reminderTime,
    required this.isActive,
    required this.createdAt,
  });

  final int? id;
  final int userId;
  final String name;
  final String description;
  final String frequency;
  final List<int> weekdays;
  final String reminderTime;
  final bool isActive;
  final String createdAt;

  Habit copyWith({
    int? id,
    int? userId,
    String? name,
    String? description,
    String? frequency,
    List<int>? weekdays,
    String? reminderTime,
    bool? isActive,
    String? createdAt,
  }) {
    return Habit(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      description: description ?? this.description,
      frequency: frequency ?? this.frequency,
      weekdays: weekdays ?? this.weekdays,
      reminderTime: reminderTime ?? this.reminderTime,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'user_id': userId,
      'name': name,
      'description': description,
      'frequency': frequency,
      'weekdays': weekdays.join(','),
      'reminder_time': reminderTime,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
    };
  }

  factory Habit.fromMap(Map<String, Object?> map) {
    final rawWeekdays = map['weekdays'] as String? ?? '';
    final weekdays = rawWeekdays.isEmpty
        ? <int>[]
        : rawWeekdays
              .split(',')
              .where((value) => value.isNotEmpty)
              .map(int.parse)
              .toList();

    return Habit(
      id: map['id'] as int? ?? 0,
      userId: map['user_id'] as int? ?? 0,
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      frequency: map['frequency'] as String? ?? HabitFrequency.daily,
      weekdays: weekdays,
      reminderTime: map['reminder_time'] as String? ?? '08:00',
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdAt:
          map['created_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  bool shouldOccurOn(DateTime date) {
    if (frequency == HabitFrequency.daily) {
      return true;
    }
    return weekdays.contains(date.weekday);
  }

  bool isDueOn(DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    final created = DateTime.parse(createdAt);
    final createdOnly = DateTime(created.year, created.month, created.day);
    return !dateOnly.isBefore(createdOnly) && shouldOccurOn(dateOnly);
  }

  String formatWeekdays() {
    if (weekdays.isEmpty) {
      return 'Chưa chọn ngày';
    }

    return weekdays
        .map((weekday) {
          return DateFormat('EEE', 'vi_VN').format(DateTime(2024, 1, weekday));
        })
        .join(', ');
  }
}

String encodeReminderTime(TimeOfDay time) {
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

TimeOfDay parseReminderTime(String value) {
  final match = RegExp(
    r'^(\d{1,2}):(\d{2})(?:\s*(AM|PM))?$',
    caseSensitive: false,
  ).firstMatch(value.trim());
  if (match == null) {
    return const TimeOfDay(hour: 8, minute: 0);
  }

  var hour = int.tryParse(match.group(1)!) ?? 8;
  final minute = int.tryParse(match.group(2)!) ?? 0;
  final meridiem = match.group(3)?.toUpperCase();
  if (meridiem != null) {
    if (hour < 1 || hour > 12) {
      return const TimeOfDay(hour: 8, minute: 0);
    }
    if (meridiem == 'PM' && hour != 12) {
      hour += 12;
    } else if (meridiem == 'AM' && hour == 12) {
      hour = 0;
    }
  }

  if (hour > 23 || minute > 59) {
    return const TimeOfDay(hour: 8, minute: 0);
  }
  return TimeOfDay(hour: hour, minute: minute);
}

class HabitCompletion {
  const HabitCompletion({
    this.id,
    required this.userId,
    required this.habitId,
    required this.dateKey,
    required this.createdAt,
  });

  final int? id;
  final int userId;
  final int habitId;
  final String dateKey;
  final String createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'user_id': userId,
      'habit_id': habitId,
      'completion_date': dateKey,
      'created_at': createdAt,
    };
  }

  factory HabitCompletion.fromMap(Map<String, Object?> map) {
    return HabitCompletion(
      id: map['id'] as int? ?? 0,
      userId: map['user_id'] as int? ?? 0,
      habitId: map['habit_id'] as int? ?? 0,
      dateKey: map['completion_date'] as String? ?? dateKeyFor(DateTime.now()),
      createdAt:
          map['created_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }
}

class RangeSummary {
  const RangeSummary({
    required this.dueDays,
    required this.completedDays,
    required this.percentage,
  });

  final int dueDays;
  final int completedDays;
  final double percentage;
}

enum StatsPeriod { day, week, month }

class HabitFrequency {
  static const String daily = 'daily';
  static const String weekly = 'weekly';
}

DateTime startOfPeriod(StatsPeriod period, DateTime today) {
  switch (period) {
    case StatsPeriod.day:
      return DateTime(today.year, today.month, today.day);
    case StatsPeriod.week:
      return today.subtract(Duration(days: today.weekday - 1));
    case StatsPeriod.month:
      return DateTime(today.year, today.month, 1);
  }
}

String dateKeyFor(DateTime date) {
  return DateFormat('yyyy-MM-dd')
      .format(DateTime(date.year, date.month, date.day));
}

int countDueDaysForHabit(Habit habit, StatsPeriod period) {
  final today = DateTime.now();
  final start = startOfPeriod(
    period,
    DateTime(today.year, today.month, today.day),
  );
  final end = DateTime(today.year, today.month, today.day);

  var count = 0;
  var cursor = start;
  while (!cursor.isAfter(end)) {
    if (habit.isDueOn(cursor)) {
      count += 1;
    }
    cursor = cursor.add(const Duration(days: 1));
  }
  return count;
}

int countCompleteDaysForHabit(
  HabitAppController controller,
  Habit habit,
  StatsPeriod period,
) {
  final today = DateTime.now();
  final start = startOfPeriod(
    period,
    DateTime(today.year, today.month, today.day),
  );
  final end = DateTime(today.year, today.month, today.day);

  var count = 0;
  var cursor = start;
  while (!cursor.isAfter(end)) {
    if (habit.isDueOn(cursor) && controller.isCompletedForDate(habit, cursor)) {
      count += 1;
    }
    cursor = cursor.add(const Duration(days: 1));
  }
  return count;
}

class AppPreferences {
  static const String _currentUserKey = 'current_user_id';

  static Future<int?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_currentUserKey);
  }

  static Future<void> setCurrentUser(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_currentUserKey, userId);
  }

  static Future<void> clearCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentUserKey);
  }
}

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    await init();
    return _database!;
  }

  Future<void> init() async {
    if (_database != null) {
      return;
    }

    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, 'habit_tracker.db');
    _database = await openDatabase(
      path,
      version: 2,
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
    await _ensureDemoAccount();
  }

  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      final users = await db.query(
        'users',
        columns: <String>['id', 'password'],
      );
      for (final user in users) {
        final password = user['password'] as String? ?? '';
        if (!password.startsWith('v1\$')) {
          await db.update(
            'users',
            <String, Object?>{'password': hashPassword(password)},
            where: 'id = ?',
            whereArgs: <Object>[user['id'] as int],
          );
        }
      }
    }
  }

  Future<void> _ensureDemoAccount() async {
    final db = await database;
    await db.transaction((transaction) async {
      final matches = await transaction.query(
        'users',
        where: 'LOWER(username) = ?',
        whereArgs: const <Object>['test@gmail.com'],
        limit: 1,
      );
      final int userId;
      if (matches.isEmpty) {
        userId = await transaction.insert('users', <String, Object?>{
          'username': 'test@gmail.com',
          'display_name': 'hathu',
          'password': hashPassword('123456'),
        });
      } else {
        final demoUser = AppUser.fromMap(matches.first);
        userId = demoUser.id;
        if (demoUser.displayName != 'hathu' ||
            !verifyPassword('123456', demoUser.passwordHash)) {
          await transaction.update(
            'users',
            <String, Object?>{
              'display_name': 'hathu',
              'password': verifyPassword('123456', demoUser.passwordHash)
                  ? demoUser.passwordHash
                  : hashPassword('123456'),
            },
            where: 'id = ?',
            whereArgs: <Object>[userId],
          );
        }
      }

      final existingHabits = await transaction.query(
        'habits',
        columns: <String>['id'],
        where: 'user_id = ?',
        whereArgs: <Object>[userId],
        limit: 1,
      );
      if (existingHabits.isNotEmpty) {
        return;
      }

      final createdAt = DateTime.now().toIso8601String();
      final samples = <Map<String, Object?>>[
        <String, Object?>{
          'name': 'Uống đủ 2 lít nước',
          'description': 'Uống nước đều đặn trong ngày để cơ thể luôn đủ nước.',
          'frequency': HabitFrequency.daily,
          'weekdays': '',
          'reminder_time': '08:00',
        },
        <String, Object?>{
          'name': 'Đọc sách 20 phút',
          'description': 'Dành một khoảng thời gian yên tĩnh để đọc mỗi ngày.',
          'frequency': HabitFrequency.daily,
          'weekdays': '',
          'reminder_time': '20:30',
        },
        <String, Object?>{
          'name': 'Vận động 30 phút',
          'description': 'Đi bộ, chạy bộ hoặc tập luyện nhẹ nhàng.',
          'frequency': HabitFrequency.weekly,
          'weekdays': '1,3,5',
          'reminder_time': '17:30',
        },
        <String, Object?>{
          'name': 'Thiền 10 phút',
          'description': 'Thư giãn và tập trung vào hơi thở.',
          'frequency': HabitFrequency.daily,
          'weekdays': '',
          'reminder_time': '06:30',
        },
      ];

      for (final sample in samples) {
        await transaction.insert('habits', <String, Object?>{
          ...sample,
          'user_id': userId,
          'is_active': 1,
          'created_at': createdAt,
        });
      }
    });
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        password TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE habits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        frequency TEXT NOT NULL,
        weekdays TEXT,
        reminder_time TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE habit_completions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        habit_id INTEGER NOT NULL,
        completion_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE (user_id, habit_id, completion_date),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY (habit_id) REFERENCES habits(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<int> createUser(AppUser user) async {
    final db = await database;
    return db.insert('users', user.toMap());
  }

  Future<AppUser?> fetchUserById(int userId) async {
    final db = await database;
    final rows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: <Object>[userId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return AppUser.fromMap(rows.first);
  }

  Future<AppUser?> fetchUserByUsername(String username) async {
    final db = await database;
    final rows = await db.query(
      'users',
      where: 'LOWER(username) = ?',
      whereArgs: <Object>[username.toLowerCase()],
    );
    if (rows.isEmpty) {
      return null;
    }
    return AppUser.fromMap(rows.first);
  }

  Future<AppUser?> fetchUserByUsernameAndPassword(
    String username,
    String password,
  ) async {
    final user = await fetchUserByUsername(username);
    if (user == null || !verifyPassword(password, user.passwordHash)) {
      return null;
    }
    return user;
  }

  Future<List<Habit>> fetchHabitsForUser(int userId) async {
    final db = await database;
    final rows = await db.query(
      'habits',
      where: 'user_id = ?',
      whereArgs: <Object>[userId],
      orderBy: 'created_at ASC',
    );
    return rows.map(Habit.fromMap).toList();
  }

  Future<int> createHabit(Habit habit) async {
    final db = await database;
    return db.insert('habits', habit.toMap());
  }

  Future<void> updateHabit(Habit habit) async {
    final db = await database;
    final updatedRows = await db.update(
      'habits',
      habit.toMap(),
      where: 'id = ? AND user_id = ?',
      whereArgs: <Object>[habit.id ?? 0, habit.userId],
    );
    if (updatedRows == 0) {
      throw StateError('Không tìm thấy thói quen thuộc tài khoản hiện tại.');
    }
  }

  Future<void> deleteHabit({required int userId, required int habitId}) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'habit_completions',
        where: 'habit_id = ? AND user_id = ?',
        whereArgs: <Object>[habitId, userId],
      );
      final deletedRows = await transaction.delete(
        'habits',
        where: 'id = ? AND user_id = ?',
        whereArgs: <Object>[habitId, userId],
      );
      if (deletedRows == 0) {
        throw StateError('Không tìm thấy thói quen thuộc tài khoản hiện tại.');
      }
    });
  }

  Future<List<HabitCompletion>> fetchCompletionsForUser(int userId) async {
    final db = await database;
    final rows = await db.query(
      'habit_completions',
      where: 'user_id = ?',
      whereArgs: <Object>[userId],
      orderBy: 'completion_date ASC',
    );
    return rows.map(HabitCompletion.fromMap).toList();
  }

  Future<void> createCompletion({
    required int userId,
    required int habitId,
    required DateTime date,
  }) async {
    final db = await database;
    final ownedHabit = await db.query(
      'habits',
      columns: <String>['id'],
      where: 'id = ? AND user_id = ?',
      whereArgs: <Object>[habitId, userId],
      limit: 1,
    );
    if (ownedHabit.isEmpty) {
      throw StateError('Thói quen không thuộc tài khoản hiện tại.');
    }
    final completion = HabitCompletion(
      userId: userId,
      habitId: habitId,
      dateKey: dateKeyFor(date),
      createdAt: DateTime.now().toIso8601String(),
    );

    await db.insert(
      'habit_completions',
      completion.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> deleteCompletion({
    required int userId,
    required int habitId,
    required DateTime date,
  }) async {
    final db = await database;
    await db.delete(
      'habit_completions',
      where: 'user_id = ? AND habit_id = ? AND completion_date = ?',
      whereArgs: <Object>[userId, habitId, dateKeyFor(date)],
    );
  }
}
