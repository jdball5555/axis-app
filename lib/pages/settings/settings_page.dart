import 'package:flutter/material.dart';
import '../../models/tab_data.dart';

import 'sections/account_settings.dart';
import 'sections/appearance_settings.dart';
import 'sections/tabs_settings.dart';
import 'sections/notifications_settings.dart';
import 'sections/data_settings.dart';
import 'sections/info_settings.dart';

class SettingsSheet extends StatefulWidget {
  final bool isLightMode;
  final Function(bool) onThemeChanged;
  final Color currentPrimaryColor;
  final Function(Color) onColorChanged;

  final List<TabData> currentTabs;
  final List<TabData> allPossibleTabs;
  final List<int> runoutThresholds;
  final bool runoutEnabled;
  final bool debriefEnabled;
  final TimeOfDay debriefTime;
  final bool runoutNotificationsEnabled;
  final bool usageNotificationsEnabled;
  final TimeOfDay smartAlertTime;
  final TimeOfDay usageAlertTime;
  final String appVersion;

  final List<String> knownRooms;
  final Set<String> runoutMutedRooms;
  final Set<String> usageMutedRooms;
  final Function(Set<String>) onRunoutMutedChanged;
  final Function(Set<String>) onUsageMutedChanged;

  final VoidCallback onViewAbout;
  final Function(String, bool) onTabToggled;
  final Function(List<TabData>) onTabsReordered;
  final Function(List<int>, bool) onRunoutSettingsChanged;
  final Function(bool, TimeOfDay) onDebriefChanged;
  final Function(bool, bool, TimeOfDay, TimeOfDay) onSmartAlertsChanged;

  final VoidCallback onImportInventory;
  final VoidCallback onImportActivity;
  final VoidCallback onResetData;
  final VoidCallback onViewCSVFormats;

  const SettingsSheet({
    super.key,
    required this.isLightMode,
    required this.onThemeChanged,
    required this.currentPrimaryColor,
    required this.onColorChanged,
    required this.currentTabs,
    required this.allPossibleTabs,
    required this.runoutThresholds,
    required this.runoutEnabled,
    required this.debriefEnabled,
    required this.debriefTime,
    required this.runoutNotificationsEnabled,
    required this.usageNotificationsEnabled,
    required this.smartAlertTime,
    required this.usageAlertTime,
    required this.appVersion,
    required this.onViewAbout,
    required this.onTabToggled,
    required this.onTabsReordered,
    required this.onRunoutSettingsChanged,
    required this.onDebriefChanged,
    required this.onSmartAlertsChanged,
    required this.onImportInventory,
    required this.onImportActivity,
    required this.onResetData,
    required this.onViewCSVFormats,
    required this.knownRooms,
    required this.runoutMutedRooms,
    required this.usageMutedRooms,
    required this.onRunoutMutedChanged,
    required this.onUsageMutedChanged,
  });

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late Set<String> _activeTabIds;
  late List<TabData> _orderedTabs;
  late bool _debriefEnabled;
  late TimeOfDay _debriefTime;
  late List<int> _thresholds;
  late bool _runoutVisualsEnabled;
  late bool _runoutNotifsEnabled;
  late bool _usageNotifsEnabled;
  late TimeOfDay _runoutTime;
  late TimeOfDay _usageTime;

  // Local state for instant updates
  late Set<String> _runoutMutedRooms;
  late Set<String> _usageMutedRooms;

  @override
  void initState() {
    super.initState();
    _initValues();
  }

  void _initValues() {
    _activeTabIds = widget.currentTabs.map((t) => t.id).toSet();
    _orderedTabs = List.from(widget.allPossibleTabs);
    _debriefEnabled = widget.debriefEnabled;
    _debriefTime = widget.debriefTime;
    _thresholds = List.from(widget.runoutThresholds)
      ..sort((a, b) => b.compareTo(a));
    _runoutVisualsEnabled = widget.runoutEnabled;
    _runoutNotifsEnabled = widget.runoutNotificationsEnabled;
    _usageNotifsEnabled = widget.usageNotificationsEnabled;
    _runoutTime = widget.smartAlertTime;
    _usageTime = widget.usageAlertTime;
    _runoutMutedRooms = Set.from(widget.runoutMutedRooms);
    _usageMutedRooms = Set.from(widget.usageMutedRooms);
  }

  @override
  void didUpdateWidget(SettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.runoutNotificationsEnabled !=
            oldWidget.runoutNotificationsEnabled ||
        widget.usageNotificationsEnabled !=
            oldWidget.usageNotificationsEnabled ||
        widget.runoutMutedRooms != oldWidget.runoutMutedRooms) {
      _initValues();
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _orderedTabs.removeAt(oldIndex);
      _orderedTabs.insert(newIndex, item);
    });
    widget.onTabsReordered(_orderedTabs);
  }

  void _toggleTabLocally(String id, bool active) {
    setState(() {
      if (active)
        _activeTabIds.add(id);
      else if (_activeTabIds.length > 1)
        _activeTabIds.remove(id);
      else
        active = true;
    });
    widget.onTabToggled(id, active);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "Settings",
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              physics: const ClampingScrollPhysics(),
              children: [
                const AccountSettings(),
                const SizedBox(height: 30),

                AppearanceSettings(
                  isLightMode: widget.isLightMode,
                  onThemeChanged: widget.onThemeChanged,
                  currentPrimaryColor: widget.currentPrimaryColor,
                  onColorChanged: widget.onColorChanged,
                ),
                const SizedBox(height: 30),

                TabsSettings(
                  orderedTabs: _orderedTabs,
                  activeTabIds: _activeTabIds,
                  onReorder: _onReorder,
                  onToggle: _toggleTabLocally,
                ),
                const SizedBox(height: 30),

                NotificationsSettings(
                  debriefEnabled: _debriefEnabled,
                  debriefTime: _debriefTime,
                  onDebriefChanged: (enabled, time) {
                    setState(() {
                      _debriefEnabled = enabled;
                      _debriefTime = time;
                    });
                    widget.onDebriefChanged(enabled, time);
                  },
                  runoutEnabled: _runoutVisualsEnabled,
                  runoutNotifsEnabled: _runoutNotifsEnabled,
                  runoutTime: _runoutTime,
                  thresholds: _thresholds,
                  onRunoutSettingsChanged: (newList, enabled) {
                    setState(() {
                      _thresholds = newList;
                      _runoutVisualsEnabled = enabled;
                    });
                    widget.onRunoutSettingsChanged(newList, enabled);
                  },
                  usageNotifsEnabled: _usageNotifsEnabled,
                  usageTime: _usageTime,
                  onSmartAlertsChanged: (runout, usage, rTime, uTime) {
                    setState(() {
                      _runoutNotifsEnabled = runout;
                      _usageNotifsEnabled = usage;
                      _runoutTime = rTime;
                      _usageTime = uTime;
                    });
                    widget.onSmartAlertsChanged(runout, usage, rTime, uTime);
                  },

                  // PASS LOCAL STATE & HANDLERS
                  knownRooms: widget.knownRooms,
                  runoutMutedRooms: _runoutMutedRooms,
                  usageMutedRooms: _usageMutedRooms,
                  onRunoutMutedChanged: (newSet) {
                    setState(() => _runoutMutedRooms = newSet);
                    widget.onRunoutMutedChanged(newSet);
                  },
                  onUsageMutedChanged: (newSet) {
                    setState(() => _usageMutedRooms = newSet);
                    widget.onUsageMutedChanged(newSet);
                  },
                ),
                const SizedBox(height: 30),

                DataSettings(
                  onImportInventory: widget.onImportInventory,
                  onImportActivity: widget.onImportActivity,
                  onResetData: widget.onResetData,
                ),
                const SizedBox(height: 30),

                InfoSettings(appVersion: widget.appVersion),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
