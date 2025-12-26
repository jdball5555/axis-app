import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

// Services & Models
import 'services/notification_service.dart';
import 'models/tab_data.dart';
import 'models/inventory_item.dart';

// Pages
import 'pages/home_page.dart';
import 'pages/morning_page.dart';
import 'pages/inventory_page.dart';
import 'pages/stats_page.dart';
import 'pages/night_page.dart';
import 'pages/settings_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AxisApp());
}

class AxisApp extends StatefulWidget {
  const AxisApp({super.key});

  @override
  State<AxisApp> createState() => _AxisAppState();
}

class _AxisAppState extends State<AxisApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  Color _primaryColor = const Color(0xFF00C897); // Default Teal

  @override
  void initState() {
    super.initState();
    _initServices();
    _loadTheme();
  }

  Future<void> _initServices() async {
    await NotificationService().init();
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
      home: MainShell(
        onThemeChanged: _toggleTheme,
        isLightMode: _themeMode == ThemeMode.light,
        currentPrimaryColor: _primaryColor,
        onColorChanged: _updateColor,
      ),
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
  Alignment _transitionAlignment = Alignment.center;
  Color _transitionColor = Colors.black;
  Color _baseColor = Colors.black;

  // --- SETTINGS STATE ---
  List<int> _runoutThresholds = [7];
  bool _runoutVisualsEnabled = true;
  bool _debriefEnabled = false;
  TimeOfDay _debriefTime = const TimeOfDay(hour: 21, minute: 0);
  bool _runoutNotifsEnabled = false;
  bool _usageNotifsEnabled = false;
  TimeOfDay _runoutAlertTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _usageAlertTime = const TimeOfDay(hour: 18, minute: 0);

  // UPDATED: Version bump
  final String _appVersion = "0.3.0";

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

  List<TabData> get _visibleTabs {
    return _masterTabList.where((t) => _activeTabIds.contains(t.id)).toList();
  }

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
      if (toLightMode) {
        _baseColor = Colors.black;
        _transitionColor = const Color(0xFFF2F2F2);
        _transitionAlignment = Alignment.bottomRight;
      } else {
        _baseColor = const Color(0xFFF2F2F2);
        _transitionColor = Colors.black;
        _transitionAlignment = Alignment.topLeft;
      }
    });

    _transitionController.forward();

    // Instant switch at 100ms so content is visible over the 12s wipe
    await Future.delayed(const Duration(milliseconds: 100));
    widget.onThemeChanged(toLightMode);

    await Future.delayed(const Duration(milliseconds: 11900));

    if (mounted) {
      setState(() {
        _isTransitioning = false;
        _baseColor = toLightMode ? const Color(0xFFF2F2F2) : Colors.black;
      });
    }
  }

  // ... (Standard Logic functions) ...
  Future<void> _refreshSmartNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final String? invString = prefs.getString('axis_inventory');
    if (invString == null) return;
    List<InventoryItem> items = (jsonDecode(invString) as List)
        .map((e) => InventoryItem.fromJson(e))
        .toList();
    final List<String> logs = prefs.getStringList('axis_activity_log') ?? [];
    for (var item in items) {
      if (item.type == "Room") continue;
      final itemLogs = logs
          .where((l) => l.contains("|USED|${item.name}|"))
          .toList();
      double calculatedRate = 0.0;
      if (itemLogs.length >= 2) {
        DateTime firstDate = DateTime.parse(itemLogs.first.split('|')[0]);
        DateTime lastDate = DateTime.parse(itemLogs.last.split('|')[0]);
        int daysDiff = lastDate.difference(firstDate).inDays;
        if (daysDiff < 1) daysDiff = 1;
        int totalUsed = 0;
        for (var log in itemLogs) {
          totalUsed += int.tryParse(log.split('|')[4]) ?? 0;
        }
        calculatedRate = totalUsed.abs() / daysDiff;
      }
      item.usageRate = calculatedRate;
      if (_runoutNotifsEnabled && item.usageRate > 0) {
        double currentDaysLeft = item.quantity / item.usageRate;
        for (int threshold in _runoutThresholds) {
          double daysUntilThreshold = currentDaysLeft - threshold;
          if (daysUntilThreshold > 0) {
            DateTime alertDate = DateTime.now().add(
              Duration(days: daysUntilThreshold.floor()),
            );
            int id = item.name.hashCode + threshold;
            await NotificationService().scheduleSmartAlert(
              id: id,
              title: "Low Stock: ${item.name}",
              body: "You will run out in $threshold days.",
              date: alertDate,
              time: _runoutAlertTime,
              payload: 'inventory_alert',
            );
          }
        }
      }
      if (_usageNotifsEnabled && item.usageRate > 0) {
        int daysUntilNextUse = (1 / item.usageRate).round();
        if (daysUntilNextUse < 1) daysUntilNextUse = 1;
        DateTime usageDate = DateTime.now().add(
          Duration(days: daysUntilNextUse),
        );
        int id = item.name.hashCode + 100000;
        await NotificationService().scheduleSmartAlert(
          id: id,
          title: "Use Now: ${item.name}",
          body: "Based on your habits, you should use this today.",
          date: usageDate,
          time: _usageAlertTime,
          payload: 'inventory_alert',
        );
      }
    }
  }

  void _handleNotificationPayload(String payload) async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    if (payload == 'night_debrief') {
      int idx = _visibleTabs.indexWhere((t) => t.id == 'night');
      if (idx != -1) {
        setState(() {
          _triggerNightSurvey = true;
          _currentIndex = idx;
        });
        _onTabTapped(idx);
      }
    } else if (payload == 'inventory_alert') {
      int idx = _visibleTabs.indexWhere((t) => t.id == 'inventory');
      if (idx != -1) {
        setState(() => _currentIndex = idx);
        _onTabTapped(idx);
      }
    }
  }

  void _configureNotificationListener() {
    NotificationService().selectNotificationStream.stream.listen((payload) {
      if (payload != null) _handleNotificationPayload(payload);
    });
  }

  Future<void> _checkLaunchPayload() async {
    final payload = await NotificationService().getLaunchPayload();
    if (payload != null) _handleNotificationPayload(payload);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      List<String>? savedThresholds = prefs.getStringList(
        'axis_runout_thresholds',
      );
      if (savedThresholds != null && savedThresholds.isNotEmpty) {
        _runoutThresholds = savedThresholds.map((e) => int.parse(e)).toList();
      } else {
        int oldSingle = prefs.getInt('axis_runout_threshold') ?? 7;
        _runoutThresholds = [oldSingle];
      }
      _runoutVisualsEnabled = prefs.getBool('axis_runout_enabled') ?? true;
      _debriefEnabled = prefs.getBool('axis_debrief_enabled') ?? false;
      int h = prefs.getInt('axis_debrief_hour') ?? 21;
      int m = prefs.getInt('axis_debrief_minute') ?? 0;
      _debriefTime = TimeOfDay(hour: h, minute: m);
      _runoutNotifsEnabled = prefs.getBool('axis_notif_runout') ?? false;
      _usageNotifsEnabled = prefs.getBool('axis_notif_usage') ?? false;
      _runoutAlertTime = TimeOfDay(
        hour: prefs.getInt('axis_runout_hour') ?? 8,
        minute: prefs.getInt('axis_runout_minute') ?? 0,
      );
      _usageAlertTime = TimeOfDay(
        hour: prefs.getInt('axis_usage_hour') ?? 18,
        minute: prefs.getInt('axis_usage_minute') ?? 0,
      );
    });
    _refreshSmartNotifications();
  }

  Future<void> _handleRunoutSettings(
    List<int> thresholds,
    bool visualsEnabled,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> stringList = thresholds.map((e) => e.toString()).toList();
    await prefs.setStringList('axis_runout_thresholds', stringList);
    await prefs.setBool('axis_runout_enabled', visualsEnabled);
    setState(() {
      _runoutThresholds = thresholds;
      _runoutVisualsEnabled = visualsEnabled;
    });
    _refreshSmartNotifications();
  }

  Future<void> _handleDebriefChange(bool enabled, TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('axis_debrief_enabled', enabled);
    await prefs.setInt('axis_debrief_hour', time.hour);
    await prefs.setInt('axis_debrief_minute', time.minute);
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
    await prefs.setInt('axis_runout_hour', rTime.hour);
    await prefs.setInt('axis_runout_minute', rTime.minute);
    await prefs.setInt('axis_usage_hour', uTime.hour);
    await prefs.setInt('axis_usage_minute', uTime.minute);
    setState(() {
      _runoutNotifsEnabled = runout;
      _usageNotifsEnabled = usage;
      _runoutAlertTime = rTime;
      _usageAlertTime = uTime;
    });
    _refreshSmartNotifications();
  }

  void _handleTabToggle(String id, bool active) {
    setState(() {
      if (active) {
        _activeTabIds.add(id);
      } else {
        if (_activeTabIds.length > 1) {
          _activeTabIds.remove(id);
          if (_currentIndex >= _visibleTabs.length) {
            _currentIndex = 0;
            if (_pageController.hasClients) _pageController.jumpToPage(0);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Must keep at least one page active."),
            ),
          );
        }
      }
    });
    _saveTabState();
  }

  void _updateMasterTabOrder(List<TabData> newOrder) {
    setState(() {
      _masterTabList = List.from(newOrder);
      if (_currentIndex >= _visibleTabs.length) {
        _currentIndex = 0;
        if (_pageController.hasClients) _pageController.jumpToPage(0);
      }
    });
    _saveTabState();
  }

  Future<void> _loadTabState() async {
    final prefs = await SharedPreferences.getInstance();
    final String? orderData = prefs.getString('axis_tab_master_order');
    if (orderData != null) {
      final List<dynamic> jsonList = jsonDecode(orderData);
      List<TabData> loaded = jsonList.map((e) => TabData.fromJson(e)).toList();
      for (var def in _masterTabList) {
        if (!loaded.any((t) => t.id == def.id)) {
          loaded.add(def);
        }
      }
      _masterTabList = loaded;
    }
    final List<String>? activeList = prefs.getStringList('axis_active_tab_ids');
    if (activeList != null) {
      _activeTabIds = activeList.toSet();
    }
    setState(() {});
  }

  Future<void> _saveTabState() async {
    final prefs = await SharedPreferences.getInstance();
    final String orderData = jsonEncode(
      _masterTabList.map((e) => e.toJson()).toList(),
    );
    await prefs.setString('axis_tab_master_order', orderData);
    await prefs.setStringList('axis_active_tab_ids', _activeTabIds.toList());
  }

  void _onTabTapped(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
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
          "Permanently delete inventory and logs?",
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
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('axis_inventory');
              await prefs.remove('axis_activity_log');
              setState(() => _inventoryRefreshKey++);
              if (mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  void _showCSVFormats() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text(
          "CSV Formats",
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: Text(
          "Inventory:\nName,Type,Room,Quantity\n\nLog:\nTimestamp,Action,Name,Room,Change,Total",
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            child: Text(
              "OK",
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
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
        List<InventoryItem> newItems = [];
        if (lines.isNotEmpty && !lines[0].toLowerCase().contains("name")) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Invalid CSV Header.")));
          return;
        }
        for (int i = 1; i < lines.length; i++) {
          String line = lines[i];
          if (line.trim().isEmpty) continue;
          List<String> parts = line.split(',');
          if (parts.length >= 4) {
            newItems.add(
              InventoryItem(
                name: parts[0].trim(),
                type: parts[1].trim(),
                roomLocation: parts[2].trim() == "null"
                    ? null
                    : parts[2].trim(),
                quantity: int.tryParse(parts[3].trim()) ?? 0,
              ),
            );
          }
        }
        if (newItems.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'axis_inventory',
            jsonEncode(newItems.map((e) => e.toJson()).toList()),
          );
          setState(() => _inventoryRefreshKey++);
          await _refreshSmartNotifications();
          if (mounted)
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text("Import Successful.")));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

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
        List<String> rawLogStorage = [];
        int entryCount = 0;
        if (lines.isEmpty) return;
        for (int i = 1; i < lines.length; i++) {
          String line = lines[i];
          if (line.trim().isEmpty) continue;
          List<String> parts = line.split(',');
          if (parts.length < 3) continue;
          entryCount++;
          rawLogStorage.add(
            "${parts[0].trim()}|${parts[1].trim()}|${parts[2].trim()}|${parts[3].trim()}|${parts[4].trim()}|${parts[5].trim()}|",
          );
        }
        if (entryCount > 0) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList('axis_activity_log', rawLogStorage);
          setState(() => _inventoryRefreshKey++);
          await _refreshSmartNotifications();
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Restored $entryCount logs.")),
            );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
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
        onViewAbout: () {
          Navigator.pop(ctx);
        },
        onTabToggled: _handleTabToggle,
        onTabsReordered: _updateMasterTabOrder,
        onRunoutSettingsChanged: _handleRunoutSettings,
        onDebriefChanged: _handleDebriefChange,
        onSmartAlertsChanged: _handleSmartAlertsChange,
        onImportInventory: _importInventory,
        onImportActivity: _importActivity,
        onResetData: () {
          Navigator.pop(ctx);
          _confirmReset();
        },
        onViewCSVFormats: () {
          Navigator.pop(ctx);
          _showCSVFormats();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Size screenSize = MediaQuery.of(context).size;
    final bool isLandscape = screenSize.width > screenSize.height;

    final List<TabData> currentVisibleTabs = _visibleTabs;
    final double singleTabWidth = currentVisibleTabs.isNotEmpty
        ? (screenSize.width - 60) / currentVisibleTabs.length
        : 0;
    const double indicatorSize = 40.0;
    const double railWidth = 70.0;
    const double landscapeItemHeight = 70.0;

    final Color navBarOverlay = widget.isLightMode
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
                  child: Stack(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: currentVisibleTabs.length,
                              itemBuilder: (context, index) {
                                final tab = currentVisibleTabs[index];
                                return GestureDetector(
                                  onTap: () => _onTabTapped(index),
                                  child: Container(
                                    width: singleTabWidth,
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
                      if (currentVisibleTabs.isNotEmpty)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          child: AnimatedBuilder(
                            animation: _pageController,
                            builder: (context, child) {
                              double page =
                                  _pageController.hasClients &&
                                      _pageController
                                          .position
                                          .hasContentDimensions
                                  ? _pageController.page ??
                                        _currentIndex.toDouble()
                                  : _currentIndex.toDouble();
                              double centerOffset =
                                  (singleTabWidth - indicatorSize) / 2;
                              double absoluteOffset =
                                  (page * singleTabWidth) + centerOffset;
                              return Transform.translate(
                                offset: Offset(absoluteOffset, 0),
                                child: Container(
                                  height: 3,
                                  width: indicatorSize,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(2),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

      body: Stack(
        children: [
          // LAYER 1: BASE BACKGROUND
          Positioned.fill(
            child: Container(
              color: _isTransitioning
                  ? _baseColor
                  : theme.scaffoldBackgroundColor,
            ),
          ),

          // LAYER 2: PIXEL WIPE
          if (_isTransitioning)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _transitionController,
                builder: (context, child) {
                  return CustomPaint(
                    size: Size(screenSize.width, screenSize.height),
                    painter: PixelWipePainter(
                      fraction: _transitionController.value,
                      color: _transitionColor,
                      alignment: _transitionAlignment,
                    ),
                  );
                },
              ),
            ),

          // LAYER 3: GRADIENT
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

          // LAYER 4: CONTENT
          Container(
            child: Row(
              children: [
                if (isLandscape)
                  SafeArea(
                    right: false,
                    child: Container(
                      width: railWidth,
                      decoration: BoxDecoration(
                        color: navBarOverlay,
                        border: Border(
                          right: BorderSide(
                            color: theme.dividerColor,
                            width: 1.0,
                          ),
                        ),
                      ),
                      child: Stack(
                        children: [
                          Column(
                            children: [
                              const SizedBox(height: 20),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: currentVisibleTabs.length,
                                  itemBuilder: (context, index) {
                                    final tab = currentVisibleTabs[index];
                                    return GestureDetector(
                                      onTap: () => _onTabTapped(index),
                                      child: Container(
                                        height: landscapeItemHeight,
                                        color: Colors.transparent,
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.only(
                                          left: 20,
                                        ),
                                        child: Icon(
                                          tab.icon,
                                          color: _currentIndex == index
                                              ? theme.colorScheme.primary
                                              : theme.iconTheme.color,
                                          size: 28,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Container(
                                height: railWidth,
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
                          if (currentVisibleTabs.isNotEmpty)
                            Positioned(
                              top: 20,
                              right: 0,
                              child: AnimatedBuilder(
                                animation: _pageController,
                                builder: (context, child) {
                                  double page =
                                      _pageController.hasClients &&
                                          _pageController
                                              .position
                                              .hasContentDimensions
                                      ? _pageController.page ??
                                            _currentIndex.toDouble()
                                      : _currentIndex.toDouble();
                                  double centerOffset =
                                      (landscapeItemHeight - indicatorSize) / 2;
                                  double absoluteOffset =
                                      (page * landscapeItemHeight) +
                                      centerOffset;
                                  return Transform.translate(
                                    offset: Offset(0, absoluteOffset),
                                    child: Container(
                                      width: 3,
                                      height: indicatorSize,
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        borderRadius:
                                            const BorderRadius.horizontal(
                                              left: Radius.circular(2),
                                            ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) =>
                        setState(() => _currentIndex = index),
                    itemCount: currentVisibleTabs.length,
                    itemBuilder: (context, index) {
                      final tabId = currentVisibleTabs[index].id;
                      if (tabId == 'home') return const HomeTab();
                      if (tabId == 'morning') return const MorningBriefTab();
                      if (tabId == 'night')
                        return NightDebriefTab(
                          autoStart: _triggerNightSurvey,
                          onConsumeAutoStart: () =>
                              setState(() => _triggerNightSurvey = false),
                        );
                      if (tabId == 'inventory')
                        return AxisInventoryTab(
                          key: ValueKey(_inventoryRefreshKey),
                        );
                      if (tabId == 'stats')
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
  bool shouldRepaint(PixelWipePainter oldDelegate) {
    return oldDelegate.fraction != fraction;
  }
}
