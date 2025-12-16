import 'package:flutter/material.dart';
import '../models/tab_data.dart';

class SettingsSheet extends StatefulWidget {
  final List<TabData> currentTabs;
  final List<TabData> allPossibleTabs;

  // Settings Data
  final List<int> runoutThresholds;
  final bool runoutEnabled;
  final bool debriefEnabled;
  final TimeOfDay debriefTime;
  final bool runoutNotificationsEnabled;
  final bool usageNotificationsEnabled;
  final TimeOfDay smartAlertTime;
  final String appVersion;

  // Callbacks
  final VoidCallback onViewAbout;
  final Function(String, bool) onTabToggled;
  final Function(List<int>, bool) onRunoutSettingsChanged;
  final Function(bool, TimeOfDay) onDebriefChanged;
  final Function(bool, bool, TimeOfDay) onSmartAlertsChanged;

  final VoidCallback onImportInventory;
  final VoidCallback onImportActivity;
  final VoidCallback onResetData;
  final VoidCallback onViewCSVFormats;

  const SettingsSheet({
    super.key,
    required this.currentTabs,
    required this.allPossibleTabs,
    required this.runoutThresholds,
    required this.runoutEnabled,
    required this.debriefEnabled,
    required this.debriefTime,
    required this.runoutNotificationsEnabled,
    required this.usageNotificationsEnabled,
    required this.smartAlertTime,
    required this.appVersion,
    required this.onViewAbout,
    required this.onTabToggled,
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

  late bool _debriefEnabled;
  late TimeOfDay _debriefTime;

  late List<int> _thresholds;
  late bool _runoutVisualsEnabled;

  late bool _runoutNotifsEnabled;
  late bool _usageNotifsEnabled;
  late TimeOfDay _smartAlertTime;

  static const Color _themeTeal = Color(0xFF00C897);

  @override
  void initState() {
    super.initState();
    _activeTabIds = widget.currentTabs.map((t) => t.id).toSet();

    _debriefEnabled = widget.debriefEnabled;
    _debriefTime = widget.debriefTime;

    _thresholds = List.from(widget.runoutThresholds)
      ..sort((a, b) => b.compareTo(a));
    _runoutVisualsEnabled = widget.runoutEnabled;

    _runoutNotifsEnabled = widget.runoutNotificationsEnabled;
    _usageNotifsEnabled = widget.usageNotificationsEnabled;
    _smartAlertTime = widget.smartAlertTime;
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

  Future<void> _pickDebriefTime() async {
    final picked = await _showTimePicker(_debriefTime);
    if (picked != null) {
      setState(() => _debriefTime = picked);
      widget.onDebriefChanged(_debriefEnabled, picked);
    }
  }

  Future<void> _pickSmartAlertTime() async {
    final picked = await _showTimePicker(_smartAlertTime);
    if (picked != null) {
      setState(() => _smartAlertTime = picked);
      widget.onSmartAlertsChanged(
        _runoutNotifsEnabled,
        _usageNotifsEnabled,
        picked,
      );
    }
  }

  Future<TimeOfDay?> _showTimePicker(TimeOfDay initial) {
    return showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _themeTeal,
              onPrimary: Colors.white,
              surface: Color(0xFF222222),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
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

  void _addThreshold() {
    int currentValue = 3;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF222222),
            title: const Text(
              "Add Trigger",
              style: TextStyle(color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Days Remaining:",
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        color: Colors.white70,
                        size: 32,
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
                        style: const TextStyle(
                          color: _themeTeal,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    IconButton(
                      icon: const Icon(
                        Icons.add_circle_outline,
                        color: Colors.white70,
                        size: 32,
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
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.white54),
                ),
                onPressed: () => Navigator.pop(ctx),
              ),
              TextButton(
                child: const Text(
                  "Add",
                  style: TextStyle(
                    color: _themeTeal,
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
                    Navigator.pop(ctx);
                  } else {
                    Navigator.pop(ctx);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _removeThreshold(int value) {
    setState(() {
      _thresholds.remove(value);
    });
    widget.onRunoutSettingsChanged(_thresholds, _runoutVisualsEnabled);
  }

  Widget _buildSmallTriggerBox(int days) {
    return GestureDetector(
      onTap: () => _removeThreshold(days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          "$days days",
          style: const TextStyle(
            color: _themeTeal,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  // --- NEW IMPROVED ABOUT DIALOG METHOD ---
  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF222222),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo from Assets (Wrapped to ensure size/shape)
              Container(
                width: 80,
                height: 80,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _themeTeal.withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/icon.png',
                    fit: BoxFit.cover,
                    // Fallback icon in case asset isn't loaded yet
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.hub, size: 40, color: _themeTeal),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // App Name
              const Text(
                "Axis",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),

              // Version Badge (Using widget.appVersion)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "v${widget.appVersion}", // Using widget.appVersion
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
              const SizedBox(height: 20),

              // Features Grid - UPDATED FEATURE LIST HERE
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildAboutFeature(Icons.privacy_tip_outlined, "Local Data"),
                  _buildAboutFeature(
                    Icons.notifications_active,
                    "Smart Notifications",
                  ), // <-- UPDATED
                  _buildAboutFeature(Icons.grid_view_rounded, "Modular"),
                ],
              ),

              const SizedBox(height: 24),
              const Text(
                "Designed to help you quantify your life and streamline your inventory. Data remains on your device.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              // Close Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white10,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    "Close",
                    style: TextStyle(color: Colors.white),
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

  Widget _buildAboutFeature(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, color: _themeTeal, size: 24),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color themeTeal = Color(0xFF00C897);

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "Settings",
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),

          Expanded(
            child: ListView(
              children: [
                // 1. VISIBLE TABS
                const Text(
                  "VISIBLE TABS",
                  style: TextStyle(
                    color: themeTeal,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: widget.allPossibleTabs.map((tab) {
                      final bool isActive = _activeTabIds.contains(tab.id);
                      return SwitchListTile(
                        activeColor: themeTeal,
                        title: Row(
                          children: [
                            Icon(
                              tab.icon,
                              color: isActive ? Colors.white : Colors.white38,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              tab.id.toUpperCase(),
                              style: TextStyle(
                                color: isActive ? Colors.white : Colors.white54,
                              ),
                            ),
                          ],
                        ),
                        value: isActive,
                        onChanged: (val) => _toggleTabLocally(tab.id, val),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 30),

                // 2. NOTIFICATIONS
                const Text(
                  "NOTIFICATIONS",
                  style: TextStyle(
                    color: themeTeal,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),

                // NIGHT DEBRIEF BLOCK
                _buildSection([
                  SwitchListTile(
                    activeColor: themeTeal,
                    title: const Text(
                      "Debrief",
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      "Review your day",
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: _debriefEnabled,
                    onChanged: (val) {
                      setState(() => _debriefEnabled = val);
                      widget.onDebriefChanged(val, _debriefTime);
                    },
                  ),
                  if (_debriefEnabled)
                    ListTile(
                      dense: true,
                      title: const Text(
                        "    Review Time",
                        style: TextStyle(color: Colors.white70),
                      ),
                      trailing: _buildTimeBox(_formatTime(_debriefTime)),
                      onTap: _pickDebriefTime,
                    ),
                ]),

                const SizedBox(height: 10),

                // SMART ALERTS BLOCK
                _buildSection([
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "SMART ALERT TIME",
                          style: TextStyle(
                            color: themeTeal,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            fontSize: 12,
                          ),
                        ),
                        GestureDetector(
                          onTap: _pickSmartAlertTime,
                          child: _buildTimeBox(_formatTime(_smartAlertTime)),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1, color: Colors.white10),

                  // Runout Warnings
                  SwitchListTile(
                    activeColor: themeTeal,
                    title: const Text(
                      "Runout Warnings",
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      "Notify before items empty",
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: _runoutNotifsEnabled,
                    onChanged: (val) {
                      setState(() => _runoutNotifsEnabled = val);
                      widget.onSmartAlertsChanged(
                        val,
                        _usageNotifsEnabled,
                        _smartAlertTime,
                      );
                    },
                  ),

                  if (_runoutNotifsEnabled)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Row(
                        children: [
                          const Text(
                            "Triggers:",
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            alignment: WrapAlignment.end,
                            children: [
                              ..._thresholds.map(
                                (t) => _buildSmallTriggerBox(t),
                              ),

                              InkWell(
                                onTap: _addThreshold,
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white38),
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    color: themeTeal,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  const Divider(color: Colors.white10, height: 1),

                  // Usage Reminders
                  SwitchListTile(
                    activeColor: themeTeal,
                    title: const Text(
                      "Usage Reminders",
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      "Based on the average rate",
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: _usageNotifsEnabled,
                    onChanged: (val) {
                      setState(() => _usageNotifsEnabled = val);
                      widget.onSmartAlertsChanged(
                        _runoutNotifsEnabled,
                        val,
                        _smartAlertTime,
                      );
                    },
                  ),
                ]),

                const SizedBox(height: 30),

                // 3. DATA
                const Text(
                  "DATA MANAGEMENT",
                  style: TextStyle(
                    color: themeTeal,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                _buildSection([
                  ListTile(
                    leading: const Icon(Icons.download, color: Colors.white),
                    title: const Text(
                      "Import Inventory",
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: widget.onImportInventory,
                  ),
                  ListTile(
                    leading: const Icon(Icons.history, color: Colors.white),
                    title: const Text(
                      "Import Log",
                      style: TextStyle(color: Colors.white),
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
                    leading: const Icon(
                      Icons.info_outline,
                      color: Colors.white54,
                    ),
                    title: const Text(
                      "View CSV Formats",
                      style: TextStyle(color: Colors.white54),
                    ),
                    onTap: widget.onViewCSVFormats,
                  ),
                ]),

                const SizedBox(height: 30),

                // --- ABOUT ---
                const Text(
                  "APP INFO",
                  style: TextStyle(
                    color: themeTeal,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                _buildSection([
                  ListTile(
                    leading: const Icon(Icons.info, color: Colors.white),
                    title: const Text(
                      "About Axis",
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: () => _showAboutDialog(context),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.developer_mode,
                      color: Colors.white54,
                    ),
                    title: const Text(
                      "Version",
                      style: TextStyle(color: Colors.white54),
                    ),
                    trailing: Text(
                      "v${widget.appVersion}",
                      style: const TextStyle(color: Colors.white70),
                    ),
                    onTap: () {},
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildTimeBox(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(color: _themeTeal, fontWeight: FontWeight.bold),
      ),
    );
  }
}
