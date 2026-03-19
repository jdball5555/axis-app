import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/tab_data.dart';

import 'sections/account_settings.dart';
import 'sections/appearance_settings.dart';
import 'sections/nav_bar_settings.dart';
import 'sections/home_page_settings.dart';
import 'sections/notifications_settings.dart';
import 'sections/data_settings.dart';
import 'sections/info_settings.dart';

// --- Import the new unified tile library ---
import 'widgets/settings_format.dart';

class SettingsPage extends StatefulWidget {
  final bool isLightMode;
  final Function(bool) onThemeChanged;
  final Color currentPrimaryColor;
  final Function(Color) onColorChanged;

  final List<TabData> currentTabs;
  final List<TabData> allPossibleTabs;
  final String appVersion;

  final List<String> knownRooms;

  final Function(String, bool) onTabToggled;
  final Function(List<TabData>) onTabsReordered;

  final VoidCallback onImportInventory;
  final VoidCallback onImportActivity;
  final VoidCallback onResetData;
  final VoidCallback onViewCSVFormats;

  const SettingsPage({
    super.key,
    required this.isLightMode,
    required this.onThemeChanged,
    required this.currentPrimaryColor,
    required this.onColorChanged,
    required this.currentTabs,
    required this.allPossibleTabs,
    required this.onTabToggled,
    required this.appVersion,
    required this.onTabsReordered,
    required this.onImportInventory,
    required this.onImportActivity,
    required this.onResetData,
    required this.onViewCSVFormats,
    required this.knownRooms,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Set<String> _activeTabIds;
  late List<TabData> _orderedTabs;

  // Inventory State (Fetched Async)
  bool _isLoadingInventories = true;
  List<InventoryConfig> _loadedInventories = [];
  Map<String, Set<String>> _runoutMutedMap = {};
  Map<String, Set<String>> _usageMutedMap = {};

  @override
  void initState() {
    super.initState();
    _activeTabIds = widget.currentTabs.map((t) => t.id).toSet();
    _orderedTabs = List.from(widget.allPossibleTabs);
    _loadAllInventoriesData();
  }

  Future<void> _loadAllInventoriesData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      final snapshot = await FirebaseFirestore.instance
          .collection('households')
          .where('members', arrayContains: user.uid)
          .get();

      List<InventoryConfig> tempInvs = [];
      Map<String, Set<String>> tempRunout = {};
      Map<String, Set<String>> tempUsage = {};

      for (var doc in snapshot.docs) {
        String id = doc.id;
        String name = doc.data()['name'] ?? "Untitled";

        List<String> rooms = await _fetchInventoryRooms(id);

        tempInvs.add(InventoryConfig(id: id, name: name, rooms: rooms));

        tempRunout[id] =
            (prefs.getStringList('axis_muted_runout_rooms_$id') ?? []).toSet();
        tempUsage[id] =
            (prefs.getStringList('axis_muted_usage_rooms_$id') ?? []).toSet();
      }

      List<String>? savedOrder = prefs.getStringList(
        'axis_home_inventory_order',
      );
      if (savedOrder != null) {
        tempInvs.sort((a, b) {
          int indexA = savedOrder.indexOf(a.id);
          int indexB = savedOrder.indexOf(b.id);
          if (indexA == -1) indexA = 999;
          if (indexB == -1) indexB = 999;
          return indexA.compareTo(indexB);
        });
      }

      if (mounted) {
        setState(() {
          _loadedInventories = tempInvs;
          _runoutMutedMap = tempRunout;
          _usageMutedMap = tempUsage;
          _isLoadingInventories = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingInventories = false);
    }
  }

  Future<List<String>> _fetchInventoryRooms(String inventoryId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('households')
          .doc(inventoryId)
          .collection('inventory')
          .get();
      Set<String> rooms = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['type'] == 'Room') {
          rooms.add(data['name']);
        } else if (data['roomLocation'] != null &&
            data['roomLocation'].toString().isNotEmpty) {
          rooms.add(data['roomLocation']);
        }
      }
      return rooms.toList()..sort();
    } catch (e) {
      return [];
    }
  }

  // --- HANDLERS ---

  Future<void> _onReorderInventories(int oldIndex, int newIndex) async {
    setState(() {
      final item = _loadedInventories.removeAt(oldIndex);
      _loadedInventories.insert(newIndex, item);
    });
    final prefs = await SharedPreferences.getInstance();
    List<String> idList = _loadedInventories.map((e) => e.id).toList();
    await prefs.setStringList('axis_home_inventory_order', idList);
  }

  Future<void> _onToggleMute(
    String type,
    String invId,
    String room,
    bool isMuted,
  ) async {
    setState(() {
      Map<String, Set<String>> targetMap = (type == 'runout')
          ? _runoutMutedMap
          : _usageMutedMap;
      if (targetMap[invId] == null) targetMap[invId] = {};

      if (isMuted)
        targetMap[invId]!.add(room);
      else
        targetMap[invId]!.remove(room);
    });

    final prefs = await SharedPreferences.getInstance();
    String key = (type == 'runout')
        ? 'axis_muted_runout_rooms_$invId'
        : 'axis_muted_usage_rooms_$invId';

    Map<String, Set<String>> targetMap = (type == 'runout')
        ? _runoutMutedMap
        : _usageMutedMap;
    await prefs.setStringList(key, targetMap[invId]!.toList());
  }

  void _pushSubPage(String title, Widget content) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(20.0), child: content),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Settings",
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ResponsiveSettingsGrid(
          children: [
            GradientSettingsTile(
              icon: Icons.person_outline,
              title: "Account",
              subtitle: "Inventories",
              onTap: () => _pushSubPage("Account", const AccountSettings()),
            ),

            GradientSettingsTile(
              icon: Icons.palette_outlined,
              title: "Appearance",
              subtitle: "Theme, Colors",
              onTap: () => _pushSubPage(
                "Appearance",
                AppearanceSettings(
                  isLightMode: widget.isLightMode,
                  onThemeChanged: widget.onThemeChanged,
                  currentPrimaryColor: widget.currentPrimaryColor,
                  onColorChanged: widget.onColorChanged,
                ),
              ),
            ),

            GradientSettingsTile(
              icon: Icons.view_sidebar_outlined,
              title: "Navigation Bar",
              subtitle: "Reorder & Toggle",
              onTap: () => _pushSubPage(
                "Navigation Bar",
                NavBarSettings(
                  orderedTabs: _orderedTabs,
                  activeTabIds: _activeTabIds,
                  onReorder: (newOrder) {
                    setState(() => _orderedTabs = newOrder);
                    widget.onTabsReordered(newOrder);
                  },
                  onToggle: (id, active) {
                    setState(() {
                      if (active)
                        _activeTabIds.add(id);
                      else if (_activeTabIds.length > 1)
                        _activeTabIds.remove(id);
                    });
                    widget.onTabToggled(id, active);
                  },
                ),
              ),
            ),

            GradientSettingsTile(
              icon: Icons.home_outlined,
              title: "Home Page",
              subtitle: "Layout & Alerts",
              onTap: () => _pushSubPage(
                "Home Page",
                _isLoadingInventories
                    ? const Center(child: CircularProgressIndicator())
                    : HomePageSettings(
                        inventories: _loadedInventories,
                        runoutMutedMap: _runoutMutedMap,
                        usageMutedMap: _usageMutedMap,
                        onReorderInventories: _onReorderInventories,
                        onToggleRunoutMute: (id, room, val) =>
                            _onToggleMute('runout', id, room, val),
                        onToggleUsageMute: (id, room, val) =>
                            _onToggleMute('usage', id, room, val),
                      ),
              ),
            ),

            GradientSettingsTile(
              icon: Icons.notifications_outlined,
              title: "Notifications",
              subtitle: "Alerts, Debriefs, Smart Triggers",
              onTap: () => _pushSubPage(
                "Notifications",
                NotificationsSettings(knownRooms: widget.knownRooms),
              ),
            ),

            GradientSettingsTile(
              icon: Icons.cloud_download_outlined,
              title: "Data",
              subtitle: "Import, Export, Reset",
              onTap: () => _pushSubPage(
                "Data",
                DataSettings(
                  onImportInventory: widget.onImportInventory,
                  onImportActivity: widget.onImportActivity,
                  onResetData: widget.onResetData,
                ),
              ),
            ),

            GradientSettingsTile(
              icon: Icons.info_outline,
              title: "Info",
              subtitle: "v${widget.appVersion}",
              onTap: () => _pushSubPage(
                "App Info",
                InfoSettings(appVersion: widget.appVersion),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
