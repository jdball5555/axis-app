import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

import 'services/notification_service.dart';
import 'services/firestore_service.dart';
import 'models/tab_data.dart';

import 'pages/home_page.dart';
import 'pages/morning_page.dart';
import 'pages/inventory_page.dart';
import 'pages/stats_page.dart';
import 'pages/night_page.dart';
import 'pages/settings/settings_page.dart';
import 'pages/settings/sections/switch_inventories_settings.dart';
import 'pages/sign_in_page.dart';

const String _appVersion = "0.6.0";

// --- BACKGROUND HANDLER ---
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("🌙 Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Register Background Handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await NotificationService().init();
  await FirestoreService().init();
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

  String? _currentHouseholdId;

  // SUBSCRIPTIONS
  StreamSubscription? _householdSub;
  StreamSubscription? _inventorySub;
  StreamSubscription? _userStateSub;
  StreamSubscription? _notificationSub;

  // STATE TRACKING
  bool _isCreatingNewHousehold = false;
  List<String> _knownRooms = [];

  List<TabData> _masterTabList = [
    TabData(id: 'home', icon: Icons.home_filled),
    TabData(id: 'inventory', icon: Icons.inventory_2),
    TabData(id: 'stats', icon: Icons.bar_chart),
    TabData(id: 'morning', icon: Icons.wb_sunny),
    TabData(id: 'night', icon: Icons.nights_stay),
  ];

  Set<String> _activeTabIds = {'home', 'inventory', 'stats'};

  List<TabData> get _visibleTabs =>
      _masterTabList.where((t) => _activeTabIds.contains(t.id)).toList();

  @override
  void initState() {
    super.initState();
    final db = FirestoreService();
    db.init();

    // 1. Listen for Household Changes
    _householdSub = db.currentHouseholdIdStream.listen((id) {
      bool isFirstLoad = _currentHouseholdId == null;

      if (id != null && id != _currentHouseholdId) {
        setState(() => _currentHouseholdId = id);
        setState(() => _inventoryRefreshKey++);
        _setupInventoryListener();

        if (mounted && !isFirstLoad) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          _switchToInventoryTab();
        }
      }
    });

    // 2. Setup Local Listeners
    _setupUserStateListener();

    // 3. Setup Notifications
    _loadTabState();
    NotificationService().requestPermissions();
    NotificationService().checkAndScheduleSmartNotifications();
    NotificationService().setupInteractedMessage();

    // 4. Listen for Notification Taps
    _notificationSub = NotificationService().selectNotificationStream.stream
        .listen((payload) {
          debugPrint("🔔 Notification Tapped with payload: $payload");

          if (payload == 'invite') {
            // CASE A: It's an Invite -> Go to Settings/Switch Inventory
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SwitchInventoriesSettings(),
              ),
            );
          } else {
            // CASE B: It's anything else -> "Open like normal" (Go to Default Startup Page)
            _loadStartupPage(forceDefault: true);
          }
        });

    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );

    _loadStartupPage();
  }

  void _setupInventoryListener() {
    _inventorySub?.cancel();
    _inventorySub = FirestoreService().getInventoryStream().listen((items) {
      Set<String> foundRooms = items
          .where((i) => i.type == 'Room')
          .map((i) => i.name)
          .toSet();
      foundRooms.addAll(items.map((i) => i.roomLocation).whereType<String>());

      setState(() {
        _knownRooms = foundRooms.toList()..sort();
      });

      NotificationService().checkAndScheduleSmartNotifications(items: items);
    });
  }

  void _setupUserStateListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _userStateSub?.cancel();
    _userStateSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) async {
          if (!snapshot.exists) return;

          List joined = snapshot.data()?['joinedHouseholds'] ?? [];
          String? currentId = FirestoreService().currentHouseholdId;

          if (joined.isEmpty) {
            if (!_isCreatingNewHousehold) {
              _isCreatingNewHousehold = true;
              debugPrint(
                "⚠️ No inventories found. Auto-creating 'My Inventory'...",
              );
              await FirestoreService().createHousehold("My Inventory");
              _isCreatingNewHousehold = false;
            }
            return;
          }

          if (currentId != null && !joined.contains(currentId)) {
            debugPrint(
              "⚠️ Removed from current inventory ($currentId). Switching...",
            );
            String nextId = joined.first;
            await FirestoreService().switchHousehold(nextId);
          }
        });
  }

  @override
  void dispose() {
    _householdSub?.cancel();
    _inventorySub?.cancel();
    _userStateSub?.cancel();
    _notificationSub?.cancel();
    _transitionController.dispose();
    super.dispose();
  }

  Future<void> _loadStartupPage({bool forceDefault = false}) async {
    final prefs = await SharedPreferences.getInstance();

    // Default to 'home' if not set
    final defaultTabId = prefs.getString('default_startup_tab') ?? 'home';

    final index = _visibleTabs.indexWhere((t) => t.id == defaultTabId);
    if (index != -1) {
      // If forced (clicked notification) OR purely startup
      if (forceDefault) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          setState(() => _currentIndex = index);
          _pageController.jumpToPage(index);
        }
      });
    }
  }

  void _switchToInventoryTab() {
    final index = _visibleTabs.indexWhere((t) => t.id == 'inventory');
    if (index != -1 && _currentIndex != index) {
      setState(() => _currentIndex = index);
      _pageController.jumpToPage(index);
    }
  }

  // --- REMOVED: void _switchToHomeTab() { ... } ---

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
        for (int i = 1; i < lines.length; i++) {
          String line = lines[i];
          if (line.trim().isNotEmpty) validLines.add(line);
        }
        if (validLines.isNotEmpty) {
          final db = FirestoreService();
          await db.batchImportLogs(validLines);
          setState(() => _inventoryRefreshKey++);
          if (mounted) {
            Navigator.pop(context);
            _switchToInventoryTab();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Success! Import complete.")),
            );
          }
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
        setState(() => _inventoryRefreshKey++);
        if (mounted) {
          Navigator.pop(context);
          _switchToInventoryTab();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Import complete.")));
        }
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
              final invSnap = await db.inventoryCollection.get();
              final logSnap = await db.logCollection.get();

              final batch = FirebaseFirestore.instance.batch();
              for (var doc in invSnap.docs) batch.delete(doc.reference);
              for (var doc in logSnap.docs) batch.delete(doc.reference);
              await batch.commit();

              setState(() => _inventoryRefreshKey++);
              if (mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(
          isLightMode: widget.isLightMode,
          onThemeChanged: _handleThemeTransition,
          currentPrimaryColor: widget.currentPrimaryColor,
          onColorChanged: widget.onColorChanged,
          currentTabs: _visibleTabs,
          allPossibleTabs: _masterTabList,
          appVersion: _appVersion,
          knownRooms: _knownRooms,
          onViewAbout: () {},
          onTabToggled: _handleTabToggle,
          onTabsReordered: _updateMasterTabOrder,
          onImportInventory: _importInventory,
          onImportActivity: _importActivity,
          onResetData: _confirmReset,
          onViewCSVFormats: () {},
        ),
      ),
    ).then((_) {
      setState(() {
        _inventoryRefreshKey++;
      });
    });
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
                          const SizedBox(height: 20),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _visibleTabs.length,
                              itemBuilder: (c, i) => GestureDetector(
                                onTap: () => _onTabTapped(i),
                                child: Container(
                                  height: 70,
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.only(left: 20),
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
