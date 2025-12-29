import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

import 'services/notification_service.dart';
import 'services/firestore_service.dart';
import 'models/tab_data.dart';
import 'models/inventory_item.dart';

import 'pages/home_page.dart';
import 'pages/morning_page.dart';
import 'pages/inventory_page.dart';
import 'pages/stats_page.dart';
import 'pages/night_page.dart';
import 'pages/settings_page.dart';
import 'pages/sign_in_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService().init();
  runApp(const AxisApp());
}

class AxisApp extends StatefulWidget {
  const AxisApp({super.key});
  @override
  State<AxisApp> createState() => _AxisAppState();
}

class _AxisAppState extends State<AxisApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  Color _primaryColor = const Color(0xFF00C897);

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final bool isLight = prefs.getBool('axis_is_light_mode') ?? false;
    final int? colorValue = prefs.getInt('axis_primary_color');
    setState(() {
      _themeMode = isLight ? ThemeMode.light : ThemeMode.dark;
      if (colorValue != null) {
        _primaryColor = Color(colorValue);
      }
    });
  }

  void _toggleTheme(bool isLight) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('axis_is_light_mode', isLight);
    setState(() {
      _themeMode = isLight ? ThemeMode.light : ThemeMode.dark;
    });
  }

  void _updateColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('axis_primary_color', color.value);
    setState(() {
      _primaryColor = color;
    });
  }

  ThemeData _buildTheme(Brightness brightness, Color primary) {
    final isDark = brightness == Brightness.dark;
    final base = isDark ? ThemeData.dark() : ThemeData.light();
    return base.copyWith(
      primaryColor: primary,
      scaffoldBackgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F2),
      cardColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      dividerColor: isDark ? Colors.white24 : Colors.black12,
      colorScheme: base.colorScheme.copyWith(
        primary: primary,
        secondary: primary,
        surface: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        onSurface: isDark ? Colors.white : Colors.black,
      ),
      iconTheme: IconThemeData(color: isDark ? Colors.white70 : Colors.black87),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      color: Colors.black,
      debugShowCheckedModeBanner: false,
      title: 'Axis',
      theme: _buildTheme(Brightness.light, _primaryColor),
      darkTheme: _buildTheme(Brightness.dark, _primaryColor),
      themeMode: _themeMode,
      home: AuthGate(
        onThemeChanged: _toggleTheme,
        isLightMode: _themeMode == ThemeMode.light,
        currentPrimaryColor: _primaryColor,
        onColorChanged: _updateColor,
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  final Function(bool) onThemeChanged;
  final bool isLightMode;
  final Color currentPrimaryColor;
  final Function(Color) onColorChanged;

  const AuthGate({
    super.key,
    required this.onThemeChanged,
    required this.isLightMode,
    required this.currentPrimaryColor,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return MainShell(
            onThemeChanged: onThemeChanged,
            isLightMode: isLightMode,
            currentPrimaryColor: currentPrimaryColor,
            onColorChanged: onColorChanged,
          );
        }
        return const SignInPage();
      },
    );
  }
}

class MainShell extends StatefulWidget {
  final Function(bool) onThemeChanged;
  final bool isLightMode;
  final Color currentPrimaryColor;
  final Function(Color) onColorChanged;

  const MainShell({
    super.key,
    required this.onThemeChanged,
    required this.isLightMode,
    required this.currentPrimaryColor,
    required this.onColorChanged,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  int _inventoryRefreshKey = 0;
  bool _triggerNightSurvey = false;
  late AnimationController _transitionController;
  bool _isTransitioning = false;
  Color _transitionColor = Colors.black;
  Color _baseColor = Colors.black;
  Alignment _transitionAlignment = Alignment.center;

  // Settings State
  List<int> _runoutThresholds = [7];
  bool _runoutVisualsEnabled = true;
  bool _debriefEnabled = false;
  TimeOfDay _debriefTime = const TimeOfDay(hour: 21, minute: 0);
  bool _runoutNotifsEnabled = false;
  bool _usageNotifsEnabled = false;
  TimeOfDay _runoutAlertTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _usageAlertTime = const TimeOfDay(hour: 18, minute: 0);
  final String _appVersion = "0.4.0";

  List<TabData> _masterTabList = [
    TabData(id: 'home', icon: Icons.home_filled),
    TabData(id: 'morning', icon: Icons.wb_sunny),
    TabData(id: 'night', icon: Icons.nights_stay),
    TabData(id: 'inventory', icon: Icons.inventory_2),
    TabData(id: 'stats', icon: Icons.bar_chart),
  ];
  Set<String> _activeTabIds = {
    'home',
    'morning',
    'night',
    'inventory',
    'stats',
  };
  List<TabData> get _visibleTabs =>
      _masterTabList.where((t) => _activeTabIds.contains(t.id)).toList();

  @override
  void initState() {
    super.initState();
    _loadTabState();
    _loadSettings();
    _configureNotificationListener();
    _checkLaunchPayload();
    NotificationService().requestPermissions();
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
  }

  @override
  void dispose() {
    _transitionController.dispose();
    super.dispose();
  }

  DateTime? _parseRobustDate(String dateStr) {
    if (dateStr.trim().isEmpty) return null;
    try {
      List<String> parts = dateStr.trim().split(' ');
      if (parts.length >= 2) {
        List<String> dateParts = parts[0].split('-');
        List<String> timeParts = parts[1].split(':');
        return DateTime(
          int.parse(dateParts[0]),
          int.parse(dateParts[1]),
          int.parse(dateParts[2]),
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
          int.parse(timeParts[2]),
        );
      }
      return DateTime.parse(dateStr);
    } catch (e) {
      return null;
    }
  }

  // --- LOGIC: REFRESH NOTIFICATIONS ---
  Future<void> _refreshSmartNotifications() async {
    debugPrint("🔄 [Real-World Logic] Calculating Smart Notifications...");
    final FirestoreService db = FirestoreService();

    final invSnap = await db.inventoryCollection.get();
    final logSnap = await db.logCollection.orderBy('timestamp').get();

    if (invSnap.docs.isEmpty) {
      debugPrint("⚠️ Inventory is empty. No notifications to schedule.");
      return;
    }

    List<InventoryItem> items = invSnap.docs
        .map((d) => InventoryItem.fromJson(d.data() as Map<String, dynamic>))
        .toList();
    List<Map<String, dynamic>> logs = logSnap.docs
        .map((d) => d.data() as Map<String, dynamic>)
        .toList();

    DateTime now = DateTime.now();

    for (var item in items) {
      if (item.type == "Room") continue;

      List<DateTime> usageDates = [];
      for (var log in logs) {
        if (log['item'] == item.name &&
            (log['action'] == "USED ONE" || log['action'] == "USED")) {
          DateTime? dt = _parseRobustDate(log['timestamp'] ?? "");
          if (dt != null) usageDates.add(dt);
        }
      }

      if (usageDates.length < 2) continue;

      usageDates.sort();
      int totalDays = usageDates.last.difference(usageDates.first).inDays;
      if (totalDays < 1) totalDays = 1;
      double rate = totalDays / (usageDates.length - 1);

      double daysLeft = item.quantity * rate;
      debugPrint(
        "📊 [${item.name}] Rate: ${rate.toStringAsFixed(1)} days/use | Days Left: ${daysLeft.toStringAsFixed(1)}",
      );

      // --- A. RUNOUT ALERTS ---
      if (_runoutNotifsEnabled) {
        for (int threshold in _runoutThresholds) {
          // Check if we are approaching a specific trigger day
          // Example: If threshold is 7 days, alert if we have between 6.0 and 8.0 days left.
          if (daysLeft > (threshold - 1.0) && daysLeft <= (threshold + 1.0)) {
            debugPrint("   🚨 [${item.name}] Hit Runout Threshold: $threshold");
            await NotificationService().scheduleSmartAlert(
              id: item.name.hashCode + threshold,
              title: "Low Stock: ${item.name}",
              body: "You have about $threshold days of stock remaining.",
              date: now,
              time: _runoutAlertTime,
              payload: 'inventory_alert',
            );
          }
        }
      }

      // --- B. USAGE REMINDERS ---
      if (_usageNotifsEnabled) {
        DateTime nextDueDate = usageDates.last.add(
          Duration(days: rate.round()),
        );
        // If we are on the due date (or past it)
        if (now.isAfter(nextDueDate.subtract(const Duration(days: 1)))) {
          debugPrint("   ⏰ [${item.name}] Usage Due");
          await NotificationService().scheduleSmartAlert(
            id: item.name.hashCode + 999,
            title: "Use Now: ${item.name}",
            body: "Based on your habits, it's time to use this item.",
            date: now,
            time: _usageAlertTime,
            payload: 'inventory_alert',
          );
        }
      }
    }
    debugPrint("🏁 Smart Notification Refresh Complete.");
  }

  // --- SETTINGS HANDLERS (The Fix Is Here) ---

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      List<String>? savedT = prefs.getStringList('axis_runout_thresholds');
      if (savedT != null) _runoutThresholds = savedT.map(int.parse).toList();
      _runoutVisualsEnabled = prefs.getBool('axis_runout_enabled') ?? true;
      _debriefEnabled = prefs.getBool('axis_debrief_enabled') ?? false;
      _runoutNotifsEnabled = prefs.getBool('axis_notif_runout') ?? false;
      _usageNotifsEnabled = prefs.getBool('axis_notif_usage') ?? false;

      _debriefTime = TimeOfDay(
        hour: prefs.getInt('axis_debrief_h') ?? 21,
        minute: prefs.getInt('axis_debrief_m') ?? 0,
      );
      _runoutAlertTime = TimeOfDay(
        hour: prefs.getInt('axis_runout_h') ?? 8,
        minute: prefs.getInt('axis_runout_m') ?? 0,
      );
      _usageAlertTime = TimeOfDay(
        hour: prefs.getInt('axis_usage_h') ?? 18,
        minute: prefs.getInt('axis_usage_m') ?? 0,
      );
    });

    if (_runoutNotifsEnabled || _usageNotifsEnabled) {
      _refreshSmartNotifications();
    }
  }

  // UPDATED: Now saves to SharedPreferences AND refreshes notifications
  void _handleRunoutSettings(List<int> thresholds, bool visualsEnabled) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> strList = thresholds.map((e) => e.toString()).toList();
    await prefs.setStringList('axis_runout_thresholds', strList);
    await prefs.setBool('axis_runout_enabled', visualsEnabled);

    setState(() {
      _runoutThresholds = thresholds;
      _runoutVisualsEnabled = visualsEnabled;
    });

    debugPrint("💾 Saved Thresholds: $thresholds");

    // Immediately check if anything matches these new triggers
    if (_runoutNotifsEnabled) {
      _refreshSmartNotifications();
    }
  }

  Future<void> _handleDebriefChange(bool enabled, TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('axis_debrief_enabled', enabled);
    await prefs.setInt('axis_debrief_h', time.hour);
    await prefs.setInt('axis_debrief_m', time.minute);
    setState(() {
      _debriefEnabled = enabled;
      _debriefTime = time;
    });

    if (enabled) {
      await NotificationService().scheduleDebrief(time);
    } else {
      await NotificationService().cancelDebrief();
    }
  }

  Future<void> _handleSmartAlertsChange(
    bool runout,
    bool usage,
    TimeOfDay rTime,
    TimeOfDay uTime,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('axis_notif_runout', runout);
    await prefs.setBool('axis_notif_usage', usage);
    await prefs.setInt('axis_runout_h', rTime.hour);
    await prefs.setInt('axis_runout_m', rTime.minute);
    await prefs.setInt('axis_usage_h', uTime.hour);
    await prefs.setInt('axis_usage_m', uTime.minute);

    setState(() {
      _runoutNotifsEnabled = runout;
      _usageNotifsEnabled = usage;
      _runoutAlertTime = rTime;
      _usageAlertTime = uTime;
    });

    _refreshSmartNotifications();
  }

  // --- EXISTING LOGIC ---

  Future<void> _importActivity() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (result != null) {
        File file = File(result.files.single.path!);
        String content = await file.readAsString();
        List<String> lines = const LineSplitter().convert(content);
        List<String> validLines = [];
        Map<String, Map<String, dynamic>> latestItemState = {};
        Set<String> roomsFound = {};
        List<Map<String, dynamic>> parsedLogs = [];

        for (int i = 1; i < lines.length; i++) {
          String line = lines[i];
          if (line.trim().isEmpty) continue;

          List<String> p = [];
          if (line.contains('|')) {
            p = line.split('|');
            validLines.add(line);
          } else {
            List<String> csv = line.split(',');
            if (csv.length >= 3) {
              String timestamp = csv[0].trim();
              String action = csv[1].trim();
              String item = csv[2].trim();
              String room = csv.length > 3 ? csv[3].trim() : "N/A";
              String change = csv.length > 4 ? csv[4].trim() : "0";
              String total = csv.length > 5 ? csv[5].trim() : "0";

              DateTime? dt = _parseRobustDate(timestamp);
              String isoTimestamp = dt != null
                  ? dt.toIso8601String()
                  : timestamp;

              String newLine =
                  "$isoTimestamp|$action|$item|$room|$change|$total|";
              validLines.add(newLine);
              p = newLine.split('|');
            }
          }
          if (p.length >= 6) {
            DateTime? dt = _parseRobustDate(p[0]);
            if (dt != null) {
              parsedLogs.add({
                'date': dt,
                'item': p[2],
                'room': p[3],
                'qty': int.tryParse(p[5]) ?? 0,
              });
            }
          }
        }

        parsedLogs.sort(
          (a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime),
        );

        for (var log in parsedLogs) {
          String item = log['item'];
          String room = log['room'];
          int qty = log['qty'];
          if (room != "N/A" && room.isNotEmpty) roomsFound.add(room);
          if (item.isNotEmpty)
            latestItemState[item] = {'qty': qty, 'room': room};
        }

        if (validLines.isNotEmpty) {
          final db = FirestoreService();
          await db.batchImportLogs(validLines);
          for (var roomName in roomsFound) {
            await db.addItem(
              InventoryItem(
                name: roomName,
                type: 'Room',
                roomLocation: null,
                quantity: 0,
              ),
            );
          }
          for (var entry in latestItemState.entries) {
            String name = entry.key;
            Map<String, dynamic> data = entry.value;
            await db.addItem(
              InventoryItem(
                name: name,
                type: 'Item',
                roomLocation: data['room'] == "N/A" ? null : data['room'],
                quantity: data['qty'],
              ),
            );
          }
          setState(() => _inventoryRefreshKey++);
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "Success! Created ${latestItemState.length} items.",
                ),
              ),
            );
        }
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _handleThemeTransition(bool toLightMode) async {
    Navigator.pop(context);
    int homeIndex = _visibleTabs.indexWhere((t) => t.id == 'home');
    if (homeIndex != -1) {
      setState(() => _currentIndex = homeIndex);
      _pageController.jumpToPage(homeIndex);
    }

    _transitionController.reset();
    setState(() {
      _isTransitioning = true;
      _baseColor = toLightMode ? Colors.black : const Color(0xFFF2F2F2);
      _transitionColor = toLightMode ? const Color(0xFFF2F2F2) : Colors.black;
      _transitionAlignment = toLightMode
          ? Alignment.bottomRight
          : Alignment.topLeft;
    });

    _transitionController.forward();

    await Future.delayed(const Duration(milliseconds: 100));
    widget.onThemeChanged(toLightMode);

    await Future.delayed(const Duration(milliseconds: 11900));

    if (mounted)
      setState(() {
        _isTransitioning = false;
        _baseColor = toLightMode ? const Color(0xFFF2F2F2) : Colors.black;
      });
  }

  void _handleTabToggle(String id, bool active) {
    setState(() {
      if (active)
        _activeTabIds.add(id);
      else if (_activeTabIds.length > 1)
        _activeTabIds.remove(id);
    });
    _saveTabState();
  }

  void _updateMasterTabOrder(List<TabData> newOrder) {
    setState(() => _masterTabList = List.from(newOrder));
    _saveTabState();
  }

  Future<void> _loadTabState() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('axis_tab_master_order');
    if (s != null) {
      final l = jsonDecode(s);
      _masterTabList = (l as List).map((e) => TabData.fromJson(e)).toList();
    }
    final a = prefs.getStringList('axis_active_tab_ids');
    if (a != null) _activeTabIds = a.toSet();
    setState(() {});
  }

  Future<void> _saveTabState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'axis_tab_master_order',
      jsonEncode(_masterTabList.map((e) => e.toJson()).toList()),
    );
    await prefs.setStringList('axis_active_tab_ids', _activeTabIds.toList());
  }

  void _onTabTapped(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  Future<void> _importInventory() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (result != null) {
        File file = File(result.files.single.path!);
        String content = await file.readAsString();
        List<String> lines = const LineSplitter().convert(content);
        if (lines.isNotEmpty && !lines[0].toLowerCase().contains("name")) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Invalid CSV Header.")));
          return;
        }
        int count = 0;
        final db = FirestoreService();
        for (int i = 1; i < lines.length; i++) {
          String line = lines[i];
          if (line.trim().isEmpty) continue;
          List<String> parts = line.split(',');
          if (parts.length >= 4) {
            final item = InventoryItem(
              name: parts[0].trim(),
              type: parts[1].trim(),
              roomLocation: parts[2].trim() == "null" ? null : parts[2].trim(),
              quantity: int.tryParse(parts[3].trim()) ?? 0,
            );
            await db.addItem(item);
            count++;
          }
        }
        setState(() => _inventoryRefreshKey++);
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Uploaded $count items.")));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _confirmReset() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text(
          "Reset Data?",
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: Text(
          "Permanently delete inventory and logs from the cloud?",
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            child: Text(
              "Cancel",
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            onPressed: () => Navigator.pop(ctx),
          ),
          TextButton(
            child: const Text(
              "Delete",
              style: TextStyle(color: Colors.redAccent),
            ),
            onPressed: () async {
              final db = FirestoreService();
              final inv = await db.inventoryCollection.get();
              final batch = FirebaseFirestore.instance.batch();
              for (var doc in inv.docs) batch.delete(doc.reference);
              final logs = await db.logCollection.get();
              for (var doc in logs.docs) batch.delete(doc.reference);
              await batch.commit();
              setState(() => _inventoryRefreshKey++);
              if (mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  void _showCSVFormats() {
    /* Keep existing */
  }
  void _configureNotificationListener() {
    /* Keep existing */
  }
  Future<void> _checkLaunchPayload() async {
    /* Keep existing */
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      isScrollControlled: true,
      builder: (ctx) => SettingsSheet(
        isLightMode: widget.isLightMode,
        onThemeChanged: _handleThemeTransition,
        currentPrimaryColor: widget.currentPrimaryColor,
        onColorChanged: widget.onColorChanged,
        currentTabs: _visibleTabs,
        allPossibleTabs: _masterTabList,
        runoutThresholds: _runoutThresholds,
        runoutEnabled: _runoutVisualsEnabled,
        debriefEnabled: _debriefEnabled,
        debriefTime: _debriefTime,
        runoutNotificationsEnabled: _runoutNotifsEnabled,
        usageNotificationsEnabled: _usageNotifsEnabled,
        smartAlertTime: _runoutAlertTime,
        usageAlertTime: _usageAlertTime,
        appVersion: _appVersion,
        onViewAbout: () => Navigator.pop(ctx),
        onTabToggled: _handleTabToggle,
        onTabsReordered: _updateMasterTabOrder,
        onRunoutSettingsChanged: _handleRunoutSettings,
        onDebriefChanged: _handleDebriefChange,
        onSmartAlertsChanged: _handleSmartAlertsChange,
        onImportInventory: _importInventory,
        onImportActivity: _importActivity,
        onResetData: _confirmReset,
        onViewCSVFormats: _showCSVFormats,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final navBarOverlay = widget.isLightMode
        ? Colors.white.withOpacity(0.9)
        : Colors.black.withOpacity(0.2);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: isLandscape
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 0,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: navBarOverlay,
                    border: Border(
                      bottom: BorderSide(color: theme.dividerColor, width: 1.0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _visibleTabs.length,
                          itemBuilder: (context, index) {
                            final tab = _visibleTabs[index];
                            return GestureDetector(
                              onTap: () => _onTabTapped(index),
                              child: Container(
                                width:
                                    (MediaQuery.of(context).size.width - 60) /
                                    _visibleTabs.length,
                                color: Colors.transparent,
                                alignment: Alignment.center,
                                child: Icon(
                                  tab.icon,
                                  color: _currentIndex == index
                                      ? theme.colorScheme.primary
                                      : theme.iconTheme.color,
                                  size: 26,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Container(
                        width: 60,
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: theme.dividerColor),
                          ),
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.settings,
                            color: theme.iconTheme.color,
                          ),
                          onPressed: _openSettings,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: _isTransitioning
                  ? _baseColor
                  : theme.scaffoldBackgroundColor,
            ),
          ),
          if (_isTransitioning)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _transitionController,
                builder: (context, child) => CustomPaint(
                  size: Size(
                    MediaQuery.of(context).size.width,
                    MediaQuery.of(context).size.height,
                  ),
                  painter: PixelWipePainter(
                    fraction: _transitionController.value,
                    color: _transitionColor,
                    alignment: _transitionAlignment,
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    theme.colorScheme.primary.withOpacity(0.3),
                    theme.colorScheme.primary,
                  ],
                  stops: const [0.0, 0.2, 0.6, 1.0],
                ),
              ),
            ),
          ),
          Container(
            child: Row(
              children: [
                if (isLandscape)
                  SafeArea(
                    right: false,
                    child: Container(
                      width: 70,
                      decoration: BoxDecoration(
                        color: navBarOverlay,
                        border: Border(
                          right: BorderSide(
                            color: theme.dividerColor,
                            width: 1.0,
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          SizedBox(height: 20),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _visibleTabs.length,
                              itemBuilder: (c, i) => GestureDetector(
                                onTap: () => _onTabTapped(i),
                                child: Container(
                                  height: 70,
                                  alignment: Alignment.centerLeft,
                                  padding: EdgeInsets.only(left: 20),
                                  child: Icon(
                                    _visibleTabs[i].icon,
                                    color: _currentIndex == i
                                        ? theme.colorScheme.primary
                                        : theme.iconTheme.color,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Container(
                            height: 70,
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: theme.dividerColor),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: IconButton(
                              icon: Icon(
                                Icons.settings,
                                color: theme.iconTheme.color,
                              ),
                              onPressed: _openSettings,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (i) => setState(() => _currentIndex = i),
                    itemCount: _visibleTabs.length,
                    itemBuilder: (c, i) {
                      final id = _visibleTabs[i].id;
                      if (id == 'home') return const HomeTab();
                      if (id == 'morning') return const MorningBriefTab();
                      if (id == 'night')
                        return NightDebriefTab(
                          autoStart: _triggerNightSurvey,
                          onConsumeAutoStart: () =>
                              setState(() => _triggerNightSurvey = false),
                        );
                      if (id == 'inventory')
                        return AxisInventoryTab(
                          key: ValueKey(_inventoryRefreshKey),
                        );
                      if (id == 'stats')
                        return StatsPage(key: ValueKey(_inventoryRefreshKey));
                      return const SizedBox();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PixelWipePainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Alignment alignment;
  PixelWipePainter({
    required this.fraction,
    required this.color,
    required this.alignment,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    const double step = 10.0;
    final double maxDist = sqrt(
      size.width * size.width + size.height * size.height,
    );
    final Random random = Random(42);
    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        double dist;
        if (alignment == Alignment.topLeft) {
          dist = sqrt(x * x + y * y);
        } else {
          double dx = size.width - x;
          double dy = size.height - y;
          dist = sqrt(dx * dx + dy * dy);
        }
        double distFraction = dist / maxDist;
        double threshold = (distFraction * 0.7) + (random.nextDouble() * 0.3);
        if (fraction > threshold) {
          canvas.drawRect(Rect.fromLTWH(x, y, step + 0.5, step + 0.5), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(PixelWipePainter oldDelegate) =>
      oldDelegate.fraction != fraction;
}
