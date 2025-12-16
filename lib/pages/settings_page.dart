import 'package:flutter/material.dart';
import '../models/tab_data.dart';
import '../services/notification_service.dart';

class SettingsSheet extends StatefulWidget {
  final List<TabData> currentTabs;
  final List<TabData> allPossibleTabs;

  // State variables passed down
  final int runoutThreshold;
  final bool runoutEnabled;
  final bool debriefEnabled;
  final TimeOfDay debriefTime;

  // Callbacks
  final Function(String id, bool active) onTabToggled;
  final Function(int days, bool enabled) onRunoutChanged;
  final Function(bool enabled, TimeOfDay time) onDebriefChanged;
  final VoidCallback onImportInventory;
  final VoidCallback onImportActivity;
  final VoidCallback onResetData;
  final VoidCallback onViewCSVFormats;

  const SettingsSheet({
    super.key,
    required this.currentTabs,
    required this.allPossibleTabs,
    required this.runoutThreshold,
    required this.runoutEnabled,
    required this.debriefEnabled,
    required this.debriefTime,
    required this.onTabToggled,
    required this.onRunoutChanged,
    required this.onDebriefChanged,
    required this.onImportInventory,
    required this.onImportActivity,
    required this.onResetData,
    required this.onViewCSVFormats,
  });

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late Set<String> _localActiveTabIds;

  // We don't need local state for alerts anymore since they are disabled visually
  // but we keep the variables to prevent crashes if code references them.
  late int _localRunoutThreshold;
  late bool _localRunoutEnabled;
  late bool _localDebriefEnabled;
  late TimeOfDay _localDebriefTime;

  final Color _themeTeal = const Color(0xFF00C897);

  @override
  void initState() {
    super.initState();
    _localActiveTabIds = widget.currentTabs.map((t) => t.id).toSet();
    _localRunoutThreshold = widget.runoutThreshold;
    _localRunoutEnabled = widget.runoutEnabled;
    _localDebriefEnabled = widget.debriefEnabled;
    _localDebriefTime = widget.debriefTime;
  }

  void _handleTabSwitch(String id, bool val) {
    setState(() {
      if (val) {
        _localActiveTabIds.add(id);
      } else {
        _localActiveTabIds.remove(id);
      }
    });
    widget.onTabToggled(id, val);
  }

  // --- NEW IMPROVED ABOUT DIALOG ---
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
              // Logo from Assets
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
                        Icon(Icons.hub, size: 40, color: _themeTeal),
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

              // Version Badge
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
                child: const Text(
                  "v0.1.0", // Updated Version
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
              const SizedBox(height: 20),

              // Features Grid
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildAboutFeature(Icons.privacy_tip_outlined, "Local Data"),
                  _buildAboutFeature(Icons.construction, "Alpha Build"),
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

  // --- MAIN SETTINGS UI ---

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20),
            ],
          ),
          child: Column(
            children: [
              // Drag Handle
              Container(
                margin: const EdgeInsets.only(top: 15, bottom: 20),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Settings",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.info_outline,
                        color: Colors.white54,
                      ),
                      onPressed: () => _showAboutDialog(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Settings List
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  children: [
                    _buildSectionHeader("CUSTOMIZATION"),
                    _buildCard([
                      ExpansionTile(
                        title: const Text(
                          "Active Modules",
                          style: TextStyle(color: Colors.white),
                        ),
                        leading: const Icon(
                          Icons.dashboard_customize,
                          color: Colors.white70,
                        ),
                        iconColor: _themeTeal,
                        collapsedIconColor: Colors.white54,
                        children: widget.allPossibleTabs.map((tab) {
                          bool isActive = _localActiveTabIds.contains(tab.id);
                          return SwitchListTile(
                            title: Text(
                              tab.id.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            secondary: Icon(
                              tab.icon,
                              color: isActive ? _themeTeal : Colors.white24,
                              size: 20,
                            ),
                            activeColor: _themeTeal,
                            inactiveTrackColor: Colors.grey[800],
                            contentPadding: const EdgeInsets.only(
                              left: 16,
                              right: 16,
                            ),
                            value: isActive,
                            onChanged: (val) => _handleTabSwitch(tab.id, val),
                          );
                        }).toList(),
                      ),
                    ]),

                    _buildSectionHeader("SMART ALERTS (COMING SOON)"),
                    _buildCard([
                      // DISABLED TILE 1
                      ListTile(
                        title: const Text(
                          "Low Stock Warning",
                          style: TextStyle(color: Colors.white38),
                        ), // Dimmed text
                        subtitle: const Text(
                          "This feature will come in a future update.",
                          style: TextStyle(color: Colors.white24, fontSize: 12),
                        ),
                        leading: const Icon(
                          Icons.inventory,
                          color: Colors.white24,
                        ),
                        trailing: Switch(
                          value: false, // Force Off
                          onChanged: null, // Disabled
                          activeColor: _themeTeal,
                        ),
                      ),
                      Divider(color: Colors.grey[850], height: 1),

                      // DISABLED TILE 2
                      ListTile(
                        title: const Text(
                          "Daily Debrief",
                          style: TextStyle(color: Colors.white38),
                        ), // Dimmed text
                        subtitle: const Text(
                          "This feature will come in a future update.",
                          style: TextStyle(color: Colors.white24, fontSize: 12),
                        ),
                        leading: const Icon(
                          Icons.wb_twilight,
                          color: Colors.white24,
                        ),
                        trailing: Switch(
                          value: false, // Force Off
                          onChanged: null, // Disabled
                          activeColor: _themeTeal,
                        ),
                      ),
                      // Removed Test Button since functionality is disabled
                    ]),

                    _buildSectionHeader("DATA MANAGEMENT"),
                    _buildCard([
                      ListTile(
                        title: const Text(
                          "Import Inventory CSV",
                          style: TextStyle(color: Colors.white),
                        ),
                        leading: const Icon(
                          Icons.upload_file,
                          color: Colors.white70,
                        ),
                        onTap: widget.onImportInventory,
                      ),
                      Divider(color: Colors.grey[850], height: 1),
                      ListTile(
                        title: const Text(
                          "Import Activity Log CSV",
                          style: TextStyle(color: Colors.white),
                        ),
                        leading: const Icon(
                          Icons.history,
                          color: Colors.white70,
                        ),
                        onTap: widget.onImportActivity,
                      ),
                      Divider(color: Colors.grey[850], height: 1),
                      ListTile(
                        title: const Text(
                          "View CSV Formats",
                          style: TextStyle(color: Colors.white),
                        ),
                        leading: const Icon(
                          Icons.help_outline,
                          color: Colors.white70,
                        ),
                        onTap: widget.onViewCSVFormats,
                      ),
                    ]),

                    _buildCard([
                      ListTile(
                        title: const Text(
                          "Reset All Data",
                          style: TextStyle(color: Colors.redAccent),
                        ),
                        leading: const Icon(
                          Icons.delete_forever,
                          color: Colors.redAccent,
                        ),
                        onTap: widget.onResetData,
                      ),
                    ]),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8, left: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }
}
