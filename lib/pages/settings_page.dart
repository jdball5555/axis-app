import 'dart:math';
import 'package:flutter/material.dart';
import '../models/tab_data.dart';

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

  static const Color _defaultColor = Color(0xFF00C897);

  @override
  void initState() {
    super.initState();
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
      if (active) {
        _activeTabIds.add(id);
      } else {
        if (_activeTabIds.length > 1) {
          _activeTabIds.remove(id);
        } else {
          active = true;
        }
      }
    });
    widget.onTabToggled(id, active);
  }

  String _formatTime(TimeOfDay t) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    String h = dt.hour > 12
        ? (dt.hour - 12).toString()
        : (dt.hour == 0 ? "12" : dt.hour.toString());
    String m = dt.minute.toString().padLeft(2, '0');
    String a = dt.hour >= 12 ? "PM" : "AM";
    return "$h:$m $a";
  }

  Future<void> _pickTime(
    TimeOfDay initial,
    Function(TimeOfDay) onPicked,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(data: Theme.of(context), child: child!);
      },
    );
    if (picked != null) {
      setState(() => onPicked(picked));
    }
  }

  void _notifySmartChanges() {
    widget.onSmartAlertsChanged(
      _runoutNotifsEnabled,
      _usageNotifsEnabled,
      _runoutTime,
      _usageTime,
    );
  }

  void _addThreshold() {
    int currentValue = 3;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          return AlertDialog(
            backgroundColor: theme.cardColor,
            title: Text(
              "Add Trigger",
              style: TextStyle(color: theme.colorScheme.onSurface),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Days Remaining:",
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.remove_circle_outline,
                        color: theme.iconTheme.color,
                      ),
                      onPressed: () {
                        if (currentValue > 1) {
                          setDialogState(() => currentValue--);
                        }
                      },
                    ),
                    Container(
                      constraints: const BoxConstraints(minWidth: 60),
                      alignment: Alignment.center,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        "$currentValue",
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.add_circle_outline,
                        color: theme.iconTheme.color,
                      ),
                      onPressed: () {
                        if (currentValue < 365) {
                          setDialogState(() => currentValue++);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                child: Text(
                  "Cancel",
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                onPressed: () => Navigator.pop(ctx),
              ),
              TextButton(
                child: Text(
                  "Add",
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () {
                  if (!_thresholds.contains(currentValue)) {
                    setState(() {
                      _thresholds.add(currentValue);
                      _thresholds.sort((a, b) => b.compareTo(a));
                    });
                    widget.onRunoutSettingsChanged(
                      _thresholds,
                      _runoutVisualsEnabled,
                    );
                  }
                  Navigator.pop(ctx);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _removeThreshold(int value) {
    setState(() => _thresholds.remove(value));
    widget.onRunoutSettingsChanged(_thresholds, _runoutVisualsEnabled);
  }

  void _showColorPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Pick Accent Color",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 250,
                width: 250,
                child: ColorWheelPicker(
                  initialColor: widget.currentPrimaryColor,
                  onColorChanged: (c) {
                    widget.onColorChanged(c);
                  },
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text("Reset"),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey),
                    onPressed: () {
                      widget.onColorChanged(_defaultColor);
                      Navigator.pop(ctx);
                    },
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Done"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- ABOUT DIALOG ---
  void _showAboutDialog(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.primary.withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/icon.png',
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Icon(
                      Icons.hub,
                      size: 40,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Axis",
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "v0.3.0",
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Icons Moved ABOVE What's New
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildAboutFeature(
                    theme,
                    Icons.privacy_tip_outlined,
                    "Local Data",
                  ),
                  _buildAboutFeature(
                    theme,
                    Icons.notifications_active,
                    "Smart Alerts",
                  ),
                  _buildAboutFeature(theme, Icons.grid_view_rounded, "Modular"),
                ],
              ),

              const SizedBox(height: 20),

              // What's New moved BELOW icons
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      "What's New",
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "• Horizontal Integration\n• Dark & Light Animation\n• Color Options",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.dividerColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    "Close",
                    style: TextStyle(color: theme.colorScheme.onSurface),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- CSV VIEWER DIALOG ---
  void _showCSVFormatsDialog(BuildContext context) {
    final theme = Theme.of(context);

    DataColumn buildCol(String label) => DataColumn(
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );

    DataRow buildRow(List<String> cells) => DataRow(
      cells: cells
          .map(
            (c) => DataCell(
              Text(c, style: TextStyle(color: theme.colorScheme.onSurface)),
            ),
          )
          .toList(),
    );

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          // Constrain height so it doesn't overflow screen
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "CSV Data Viewer",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 20),

              // Scrollable Content
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Inventory Format",
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columnSpacing: 20,
                            columns: [
                              buildCol("Name"),
                              buildCol("Type"),
                              buildCol("Room Location"),
                              buildCol("Quantity"),
                            ],
                            rows: [
                              buildRow([
                                "Coffee Beans",
                                "Consumable",
                                "Pantry",
                                "500",
                              ]),
                              buildRow(["Milk", "Consumable", "Fridge", "1.5"]),
                              buildRow([
                                "Paper Towels",
                                "Supplies",
                                "Cabinet",
                                "4",
                              ]),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Activity Log Format",
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columnSpacing: 20,
                            columns: [
                              buildCol("Timestamp"),
                              buildCol("Action"),
                              buildCol("Item Name"),
                              buildCol("Room"),
                              buildCol("Change"),
                              buildCol("Total"),
                            ],
                            rows: [
                              buildRow([
                                "2025-01-01",
                                "REMOVE",
                                "Milk",
                                "Kitchen",
                                "-0.2",
                                "1.3",
                              ]),
                              buildRow([
                                "2025-01-02",
                                "ADD",
                                "Coffee",
                                "Pantry",
                                "1000",
                                "2000",
                              ]),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.dividerColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    "Close",
                    style: TextStyle(color: theme.colorScheme.onSurface),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAboutFeature(ThemeData theme, IconData icon, String label) =>
      Column(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 24),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ],
      );

  Widget _buildSection(ThemeData theme, List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: theme.dividerColor),
    ),
    child: Column(children: children),
  );

  Widget _buildTimeBox(ThemeData theme, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      border: Border.all(color: theme.dividerColor),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
    ),
  );

  Widget _buildSmallTriggerBox(ThemeData theme, int days) => GestureDetector(
    onTap: () => _removeThreshold(days),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        "$days days",
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    ),
  );

  Widget _buildInlineNotificationRow(
    ThemeData theme, {
    required String title,
    required String subtitle,
    required bool isEnabled,
    required TimeOfDay time,
    required VoidCallback onTimeTap,
    required Function(bool) onToggle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 16,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (isEnabled)
            GestureDetector(
              onTap: onTimeTap,
              child: _buildTimeBox(theme, _formatTime(time)),
            ),
          const SizedBox(width: 8),
          Switch(
            value: isEnabled,
            activeColor: theme.colorScheme.primary,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }

  Widget _buildTriggersSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          Text(
            "Triggers:",
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _thresholds
                    .map(
                      (t) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildSmallTriggerBox(theme, t),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _addThreshold,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Icon(
                Icons.add_circle_outline,
                color: theme.colorScheme.primary,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
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
              children: [
                Text(
                  "APPEARANCE",
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),

                Container(
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: Text(
                          "Dark Mode",
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        secondary: Icon(
                          !widget.isLightMode
                              ? Icons.nightlight_round
                              : Icons.wb_sunny_outlined,
                          color: theme.iconTheme.color,
                        ),
                        value: !widget.isLightMode,
                        activeColor: theme.colorScheme.primary,
                        onChanged: (val) => widget.onThemeChanged(!val),
                      ),
                      Divider(color: theme.dividerColor, height: 1),
                      ListTile(
                        title: Text(
                          "Accent Color",
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        trailing: GestureDetector(
                          onTap: () => _showColorPicker(context),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: widget.currentPrimaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),
                Text(
                  "TABS (Drag to Reorder)",
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: _onReorder,
                    children: _orderedTabs.map((tab) {
                      final bool isActive = _activeTabIds.contains(tab.id);
                      return ListTile(
                        key: ValueKey(tab.id),
                        leading: Icon(
                          tab.icon,
                          color: isActive
                              ? theme.colorScheme.onSurface
                              : theme.disabledColor,
                          size: 20,
                        ),
                        title: Text(
                          tab.id.toUpperCase(),
                          style: TextStyle(
                            color: isActive
                                ? theme.colorScheme.onSurface
                                : theme.disabledColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: isActive,
                              activeColor: theme.colorScheme.primary,
                              onChanged: (val) =>
                                  _toggleTabLocally(tab.id, val),
                            ),
                            const SizedBox(width: 10),
                            Icon(Icons.drag_handle, color: theme.dividerColor),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 30),
                Text(
                  "NOTIFICATIONS",
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                _buildSection(theme, [
                  _buildInlineNotificationRow(
                    theme,
                    title: "Debrief",
                    subtitle: "Review your day",
                    isEnabled: _debriefEnabled,
                    time: _debriefTime,
                    onTimeTap: () => _pickTime(_debriefTime, (t) {
                      _debriefTime = t;
                      widget.onDebriefChanged(_debriefEnabled, t);
                    }),
                    onToggle: (val) {
                      setState(() => _debriefEnabled = val);
                      widget.onDebriefChanged(val, _debriefTime);
                    },
                  ),
                ]),

                const SizedBox(height: 10),
                _buildSection(theme, [
                  _buildInlineNotificationRow(
                    theme,
                    title: "Runout Warnings",
                    subtitle: "Notify before items empty",
                    isEnabled: _runoutNotifsEnabled,
                    time: _runoutTime,
                    onTimeTap: () => _pickTime(_runoutTime, (t) {
                      _runoutTime = t;
                      _notifySmartChanges();
                    }),
                    onToggle: (val) {
                      setState(() => _runoutNotifsEnabled = val);
                      _notifySmartChanges();
                    },
                  ),
                  if (_runoutNotifsEnabled) _buildTriggersSection(theme),
                  Divider(color: theme.dividerColor, height: 1),
                  _buildInlineNotificationRow(
                    theme,
                    title: "Usage Reminders",
                    subtitle: "Based on average rate",
                    isEnabled: _usageNotifsEnabled,
                    time: _usageTime,
                    onTimeTap: () => _pickTime(_usageTime, (t) {
                      _usageTime = t;
                      _notifySmartChanges();
                    }),
                    onToggle: (val) {
                      setState(() => _usageNotifsEnabled = val);
                      _notifySmartChanges();
                    },
                  ),
                ]),

                const SizedBox(height: 30),
                Text(
                  "DATA MANAGEMENT",
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                _buildSection(theme, [
                  ListTile(
                    leading: Icon(Icons.download, color: theme.iconTheme.color),
                    title: Text(
                      "Upload Inventory",
                      style: TextStyle(color: theme.colorScheme.onSurface),
                    ),
                    onTap: widget.onImportInventory,
                  ),
                  ListTile(
                    leading: Icon(Icons.history, color: theme.iconTheme.color),
                    title: Text(
                      "Upload Activity Log",
                      style: TextStyle(color: theme.colorScheme.onSurface),
                    ),
                    onTap: widget.onImportActivity,
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_forever,
                      color: Colors.redAccent,
                    ),
                    title: const Text(
                      "Reset Data",
                      style: TextStyle(color: Colors.redAccent),
                    ),
                    onTap: widget.onResetData,
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.info_outline,
                      color: theme.disabledColor,
                    ),
                    title: Text(
                      "View CSV Formats",
                      style: TextStyle(color: theme.disabledColor),
                    ),
                    // Toggle to CSV View DIALOG
                    onTap: () => _showCSVFormatsDialog(context),
                  ),
                ]),

                const SizedBox(height: 30),
                Text(
                  "APP INFO",
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                _buildSection(theme, [
                  ListTile(
                    leading: Icon(Icons.info, color: theme.iconTheme.color),
                    title: Text(
                      "About Axis",
                      style: TextStyle(color: theme.colorScheme.onSurface),
                    ),
                    onTap: () => _showAboutDialog(context),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.developer_mode,
                      color: theme.iconTheme.color,
                    ),
                    title: Text(
                      "Version",
                      style: TextStyle(color: theme.iconTheme.color),
                    ),
                    trailing: Text(
                      "v0.3.0",
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- COLOR WHEEL PICKER WIDGET ---
class ColorWheelPicker extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;

  const ColorWheelPicker({
    super.key,
    required this.initialColor,
    required this.onColorChanged,
  });

  @override
  State<ColorWheelPicker> createState() => _ColorWheelPickerState();
}

class _ColorWheelPickerState extends State<ColorWheelPicker> {
  late HSVColor _currentHSV;

  @override
  void initState() {
    super.initState();
    _currentHSV = HSVColor.fromColor(widget.initialColor);
  }

  void _onPanUpdate(Offset localPosition, Size size) {
    if (size.width == 0 || size.height == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;

    final radius = size.width / 2;
    final dist = sqrt(dx * dx + dy * dy);

    double saturation = (dist / radius).clamp(0.0, 1.0);

    double angle = atan2(dy, dx);
    if (angle < 0) angle += 2 * pi;
    double hue = (angle / (2 * pi)) * 360;

    setState(() {
      _currentHSV = HSVColor.fromAHSV(1.0, hue, saturation, 1.0);
    });

    widget.onColorChanged(_currentHSV.toColor());
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onPanUpdate: (details) =>
              _onPanUpdate(details.localPosition, constraints.biggest),
          onTapDown: (details) =>
              _onPanUpdate(details.localPosition, constraints.biggest),
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: ColorWheelPainter(_currentHSV),
          ),
        );
      },
    );
  }
}

class ColorWheelPainter extends CustomPainter {
  final HSVColor selectedColor;

  ColorWheelPainter(this.selectedColor);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Smoother gradient avoiding the harsh "Error Magenta" (0xFFFF00FF)
    final hueSweep = SweepGradient(
      colors: [
        Colors.red,
        Colors.orange,
        Colors.yellow,
        Colors.green,
        Colors.cyan,
        Colors.blue,
        Colors.purple, // Bridge to red using Purple
        Colors.pink, // ... and Pink
        Colors.red,
      ],
      stops: const [0.0, 0.1, 0.2, 0.4, 0.5, 0.6, 0.75, 0.9, 1.0],
    );

    final huePaint = Paint()..shader = hueSweep.createShader(rect);
    canvas.drawCircle(center, radius, huePaint);

    final satRadial = RadialGradient(
      colors: [Colors.white, Colors.transparent],
    );
    final satPaint = Paint()..shader = satRadial.createShader(rect);
    canvas.drawCircle(center, radius, satPaint);

    // Draw Selector
    final hueAngle = (selectedColor.hue / 360) * 2 * pi;
    final saturationRadius = selectedColor.saturation * radius;

    final selectorOffset = Offset(
      center.dx + saturationRadius * cos(hueAngle),
      center.dy + saturationRadius * sin(hueAngle),
    );

    canvas.drawCircle(selectorOffset, 12, Paint()..color = Colors.white);
    canvas.drawCircle(
      selectorOffset,
      12,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      selectorOffset,
      8,
      Paint()..color = selectedColor.toColor(),
    );
  }

  @override
  bool shouldRepaint(ColorWheelPainter oldDelegate) {
    return oldDelegate.selectedColor != selectedColor;
  }
}
