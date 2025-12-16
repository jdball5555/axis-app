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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  runApp(
    const MaterialApp(home: MainShell(), debugShowCheckedModeBanner: false),
  );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool _animateGradient = false;

  // UI State
  bool _isDragging = false;
  int _inventoryRefreshKey = 0;
  bool _triggerNightSurvey = false;

  // --- SETTINGS STATE ---
  List<int> _runoutThresholds = [7];
  bool _runoutVisualsEnabled = true;

  // Notification State
  bool _debriefEnabled = false;
  TimeOfDay _debriefTime = const TimeOfDay(hour: 21, minute: 0);

  // Smart Alert State
  bool _runoutNotifsEnabled = false;
  bool _usageNotifsEnabled = false;
  TimeOfDay _smartAlertTime = const TimeOfDay(hour: 8, minute: 0);

  // --- APP VERSION STATE ---
  final String _appVersion = "0.2.0";

  List<TabData> _tabs = [];
  final List<TabData> _allPossibleTabs = [
    TabData(id: 'home', icon: Icons.home_filled),
    TabData(id: 'morning', icon: Icons.wb_sunny),
    TabData(id: 'night', icon: Icons.nights_stay),
    TabData(id: 'inventory', icon: Icons.inventory_2),
    TabData(id: 'stats', icon: Icons.bar_chart),
  ];

  @override
  void initState() {
    super.initState();
    _loadTabOrder();
    _loadSettings();
    _configureNotificationListener();
    _checkLaunchPayload();
    NotificationService().requestPermissions();

    Future.delayed(const Duration(milliseconds: 100), () {
      setState(() => _animateGradient = true);
    });
  }

  // --- LOGIC: REFRESH SMART ALERTS ---
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

      // --- CALCULATE USAGE RATE ---
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

      // --- A. MULTI-STAGE RUNOUT ALERTS ---
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
              time: _smartAlertTime,
              payload: 'inventory_alert',
            );
          }
        }
      }

      // --- B. USAGE REMINDERS ---
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
          time: _smartAlertTime,
          payload: 'inventory_alert',
        );
      }
    }
  }

  void _handleNotificationPayload(String payload) async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    if (payload == 'night_debrief') {
      int idx = _tabs.indexWhere((t) => t.id == 'night');
      if (idx != -1) {
        setState(() {
          _triggerNightSurvey = true;
          _currentIndex = idx;
        });
        _onTabTapped(idx);
      }
    } else if (payload == 'inventory_alert') {
      int idx = _tabs.indexWhere((t) => t.id == 'inventory');
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

  // --- SETTINGS LOADING ---
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
      int sh = prefs.getInt('axis_smart_hour') ?? 8;
      int sm = prefs.getInt('axis_smart_minute') ?? 0;
      _smartAlertTime = TimeOfDay(hour: sh, minute: sm);
    });

    _refreshSmartNotifications();
  }

  // --- SETTINGS SAVING ---
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
    TimeOfDay time,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('axis_notif_runout', runout);
    await prefs.setBool('axis_notif_usage', usage);
    await prefs.setInt('axis_smart_hour', time.hour);
    await prefs.setInt('axis_smart_minute', time.minute);

    setState(() {
      _runoutNotifsEnabled = runout;
      _usageNotifsEnabled = usage;
      _smartAlertTime = time;
    });
    _refreshSmartNotifications();
  }

  void _handleTabToggle(String id, bool active) {
    setState(() {
      if (active) {
        if (!_tabs.any((t) => t.id == id)) {
          _tabs.add(_allPossibleTabs.firstWhere((t) => t.id == id));
        }
      } else {
        if (_tabs.length > 1) {
          _tabs.removeWhere((t) => t.id == id);
          if (_currentIndex >= _tabs.length) _currentIndex = _tabs.length - 1;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Must keep at least one page active."),
            ),
          );
        }
      }
    });
    _saveTabOrder();
  }

  Future<void> _loadTabOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('axis_tab_order');
    if (data != null) {
      final List<dynamic> jsonList = jsonDecode(data);
      setState(() {
        _tabs = jsonList.map((e) => TabData.fromJson(e)).toList();
      });
    } else {
      setState(() => _tabs = _allPossibleTabs.take(4).toList());
    }
  }

  Future<void> _saveTabOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final String data = jsonEncode(_tabs.map((e) => e.toJson()).toList());
    await prefs.setString('axis_tab_order', data);
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final TabData item = _tabs.removeAt(oldIndex);
      _tabs.insert(newIndex, item);
      if (_currentIndex == oldIndex) {
        _currentIndex = newIndex;
      } else if (_currentIndex > oldIndex && _currentIndex <= newIndex) {
        _currentIndex--;
      } else if (_currentIndex < oldIndex && _currentIndex >= newIndex) {
        _currentIndex++;
      }
      _pageController.jumpToPage(_currentIndex);
    });
    _saveTabOrder();
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
        backgroundColor: const Color(0xFF222222),
        title: const Text("Reset Data?", style: TextStyle(color: Colors.white)),
        content: const Text(
          "Permanently delete inventory and logs?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
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
        backgroundColor: const Color(0xFF222222),
        title: const Text("CSV Formats", style: TextStyle(color: Colors.white)),
        content: const Text(
          "Inventory:\nName,Type,Room,Quantity\n\nLog:\nTimestamp,Action,Name,Room,Change,Total",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            child: const Text("OK"),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  // NOTE: The _openAboutPage function is removed since the dialog is now
  // built and shown inside SettingsSheet.

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
            String name = parts[0].trim();
            String type = parts[1].trim();
            String room = parts[2].trim();
            int qty = int.tryParse(parts[3].trim()) ?? 0;
            newItems.add(
              InventoryItem(
                name: name,
                type: type,
                roomLocation: room.isEmpty || room == "null" ? null : room,
                quantity: qty,
              ),
            );
          }
        }

        if (newItems.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          final String data = jsonEncode(
            newItems.map((e) => e.toJson()).toList(),
          );
          await prefs.setString('axis_inventory', data);
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
        List<InventoryItem> reconstructedList = [];
        List<String> rawLogStorage = [];
        int entryCount = 0;

        if (lines.isEmpty) return;

        for (int i = 1; i < lines.length; i++) {
          String line = lines[i];
          if (line.trim().isEmpty) continue;
          List<String> parts = line.split(',');
          if (parts.length < 3) continue;

          String timestamp = parts[0].trim();
          String action = parts[1].trim();
          String name = parts[2].trim();
          String room = parts.length > 3 ? parts[3].trim() : "Unknown";
          String total = parts.length > 5 ? parts[5].trim() : "0";
          String note = parts.length > 6 ? parts[6].trim() : "";
          String change = parts.length > 4 ? parts[4].trim() : "0";

          entryCount++;
          rawLogStorage.add(
            "$timestamp|$action|$name|$room|$change|$total|$note",
          );

          if (action.contains("CREATED") ||
              action.contains("RESTOCKED") ||
              action.contains("USED")) {
            int newTotal = int.tryParse(total) ?? 0;
            int index = reconstructedList.indexWhere(
              (e) => e.name == name && e.roomLocation == room,
            );

            if (index != -1) {
              reconstructedList[index].quantity = newTotal;
            } else {
              if (room != "Unknown" &&
                  !reconstructedList.any(
                    (e) => e.type == "Room" && e.name == room,
                  )) {
                reconstructedList.add(
                  InventoryItem(name: room, type: "Room", quantity: 0),
                );
              }
              reconstructedList.add(
                InventoryItem(
                  name: name,
                  type: "Item",
                  roomLocation: room,
                  quantity: newTotal,
                ),
              );
            }
          }
        }

        if (entryCount > 0) {
          final prefs = await SharedPreferences.getInstance();
          final String invData = jsonEncode(
            reconstructedList.map((e) => e.toJson()).toList(),
          );
          await prefs.setString('axis_inventory', invData);
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
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      builder: (ctx) => SettingsSheet(
        currentTabs: _tabs,
        allPossibleTabs: _allPossibleTabs,
        runoutThresholds: _runoutThresholds,
        runoutEnabled: _runoutVisualsEnabled,
        debriefEnabled: _debriefEnabled,
        debriefTime: _debriefTime,

        runoutNotificationsEnabled: _runoutNotifsEnabled,
        usageNotificationsEnabled: _usageNotifsEnabled,
        smartAlertTime: _smartAlertTime,
        appVersion: _appVersion,

        // The action is now simply closing the sheet, as the dialog is launched inside the sheet.
        onViewAbout: () {
          Navigator.pop(ctx);
        },

        onTabToggled: _handleTabToggle,
        onRunoutSettingsChanged: _handleRunoutSettings,
        onDebriefChanged: _handleDebriefChange,
        onSmartAlertsChanged: _handleSmartAlertsChange,

        onImportInventory: () {
          Navigator.pop(ctx);
          _importInventory();
        },
        onImportActivity: () {
          Navigator.pop(ctx);
          _importActivity();
        },
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
    const Color themeTeal = Color(0xFF00C897);
    final double screenWidth = MediaQuery.of(context).size.width;
    final double singleTabWidth = _tabs.isNotEmpty
        ? (screenWidth - 60) / _tabs.length
        : 0;
    const double indicatorWidth = 40.0;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              border: const Border(
                bottom: BorderSide(color: Colors.white24, width: 1.0),
              ),
            ),
            child: Stack(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ReorderableListView.builder(
                        scrollDirection: Axis.horizontal,
                        onReorderStart: (index) =>
                            setState(() => _isDragging = true),
                        onReorderEnd: (index) =>
                            setState(() => _isDragging = false),
                        onReorder: _onReorder,
                        itemCount: _tabs.length,
                        proxyDecorator: (child, index, animation) => Material(
                          color: Colors.transparent,
                          child: Container(
                            color: Colors.black54,
                            width: singleTabWidth,
                            child: child,
                          ),
                        ),
                        itemBuilder: (context, index) {
                          final tab = _tabs[index];
                          return ReorderableDragStartListener(
                            key: ValueKey(tab.id),
                            index: index,
                            child: GestureDetector(
                              onTap: () => _onTabTapped(index),
                              child: Container(
                                width: singleTabWidth,
                                color: Colors.transparent,
                                alignment: Alignment.center,
                                child: Icon(
                                  tab.icon,
                                  color: _currentIndex == index
                                      ? themeTeal
                                      : Colors.white38,
                                  size: 26,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      width: 60,
                      decoration: const BoxDecoration(
                        border: Border(left: BorderSide(color: Colors.white10)),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.settings, color: Colors.white54),
                        onPressed: _openSettings,
                      ),
                    ),
                  ],
                ),
                if (_tabs.isNotEmpty && !_isDragging)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    child: AnimatedBuilder(
                      animation: _pageController,
                      builder: (context, child) {
                        double page =
                            _pageController.hasClients &&
                                _pageController.position.hasContentDimensions
                            ? _pageController.page ?? _currentIndex.toDouble()
                            : _currentIndex.toDouble();
                        double centerOffset =
                            (singleTabWidth - indicatorWidth) / 2;
                        double absoluteOffset =
                            (page * singleTabWidth) + centerOffset;
                        return Transform.translate(
                          offset: Offset(absoluteOffset, 0),
                          child: Container(
                            height: 3,
                            width: indicatorWidth,
                            decoration: const BoxDecoration(
                              color: themeTeal,
                              borderRadius: BorderRadius.vertical(
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
      body: AnimatedContainer(
        duration: const Duration(seconds: 3),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: const [
              Colors.black,
              Color(0xFF111111),
              Color(0xFF004D40),
              themeTeal,
            ],
            stops: _animateGradient
                ? [0.0, 0.4, 0.8, 1.0]
                : [0.0, 0.95, 0.98, 1.0],
          ),
        ),
        child: PageView.builder(
          controller: _pageController,
          onPageChanged: (index) => setState(() => _currentIndex = index),
          itemCount: _tabs.length,
          itemBuilder: (context, index) {
            final tabId = _tabs[index].id;
            if (tabId == 'home') return const HomeTab();
            if (tabId == 'morning') return const MorningBriefTab();
            if (tabId == 'night')
              return NightDebriefTab(
                autoStart: _triggerNightSurvey,
                onConsumeAutoStart: () =>
                    setState(() => _triggerNightSurvey = false),
              );
            if (tabId == 'inventory')
              return AxisInventoryTab(key: ValueKey(_inventoryRefreshKey));
            if (tabId == 'stats')
              return StatsPage(key: ValueKey(_inventoryRefreshKey));
            return const SizedBox();
          },
        ),
      ),
    );
  }
}
