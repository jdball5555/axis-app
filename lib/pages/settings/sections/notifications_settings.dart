import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../widgets/settings_widgets.dart';
import '../widgets/notification_tile.dart';
import '../dialogs/trigger_dialog.dart';

import '../../../services/notification_service.dart';

class NotificationsSettings extends StatefulWidget {
  final List<String> knownRooms;

  const NotificationsSettings({super.key, required this.knownRooms});

  @override
  State<NotificationsSettings> createState() => _NotificationsSettingsState();
}

class _NotificationsSettingsState extends State<NotificationsSettings> {
  bool _isLoading = true;
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  // GLOBAL PREFS
  bool _inviteNotifsEnabled = true;
  bool _removedNotifsEnabled = true;
  static const String _householdItemsKey = "Household Items";

  // REPORT SETTINGS
  bool _reportEnabled = false;
  TimeOfDay _reportTime = const TimeOfDay(hour: 21, minute: 0);
  int _reportFrequency = 1;
  List<String> _reportInventoryIds = [];

  final Map<String, String> _inventoryNames = {};
  final Map<String, Map<String, dynamic>> _inventorySettingsCache = {};
  final Map<String, List<String>> _inventoryRoomsCache = {};
  List<String> _inventoryOrder = [];

  @override
  void initState() {
    super.initState();
    _loadAllSettings();
  }

  Future<void> _loadAllSettings() async {
    final user = _currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final userData = userDoc.data() ?? {};

    setState(() {
      _inviteNotifsEnabled = prefs.getBool('axis_notif_invites') ?? true;

      if (userData.containsKey('removedAlertsEnabled')) {
        _removedNotifsEnabled = userData['removedAlertsEnabled'];
      } else {
        _removedNotifsEnabled = prefs.getBool('axis_notif_removed') ?? true;
      }

      _reportEnabled =
          userData['reportEnabled'] ??
          prefs.getBool('axis_report_enabled') ??
          false;
      _reportTime = TimeOfDay(
        hour: userData['reportHour'] ?? prefs.getInt('axis_report_h') ?? 21,
        minute: 0,
      );
      _reportFrequency =
          userData['reportFrequency'] ?? prefs.getInt('axis_report_freq') ?? 1;

      if (userData['reportInventoryIds'] != null) {
        _reportInventoryIds = List<String>.from(userData['reportInventoryIds']);
      } else {
        _reportInventoryIds = prefs.getStringList('axis_report_ids') ?? [];
      }
    });

    final snapshot = await FirebaseFirestore.instance
        .collection('households')
        .where('members', arrayContains: user.uid)
        .get();

    for (var doc in snapshot.docs) {
      _inventoryNames[doc.id] = doc.data()['name'] ?? "Untitled";
    }

    for (var doc in snapshot.docs) {
      String id = doc.id;
      String key(String k) => "${k}_$id";
      final data = doc.data();

      _inventorySettingsCache[id] = {
        'runoutEnabled': prefs.getBool(key('axis_notif_runout')) ?? false,
        'usageEnabled': prefs.getBool(key('axis_notif_usage')) ?? false,
        'runoutTime': TimeOfDay(
          hour: data['runoutHour'] ?? prefs.getInt('axis_runout_h') ?? 8,
          minute: 0,
        ),
        'usageTime': TimeOfDay(
          hour: data['usageHour'] ?? prefs.getInt('axis_usage_h') ?? 18,
          minute: 0,
        ),
        'thresholds': (data['runoutThresholds'] != null)
            ? List<int>.from(data['runoutThresholds'])
            : (prefs.getStringList(key('axis_runout_thresholds')) ?? ['7'])
                  .map(int.parse)
                  .toList(),
        'runoutMuted':
            (prefs.getStringList(key('axis_muted_runout_rooms')) ?? []).toSet(),
        'usageMuted': (prefs.getStringList(key('axis_muted_usage_rooms')) ?? [])
            .toSet(),
        'runoutVisuals': prefs.getBool(key('axis_runout_enabled')) ?? true,
      };

      _inventoryRoomsCache[id] = await _fetchInventoryRooms(id);
    }

    List<String>? savedOrder = prefs.getStringList(
      'axis_inventory_notif_order',
    );
    List<String> currentIds = _inventoryNames.keys.toList();

    if (savedOrder != null) {
      _inventoryOrder = savedOrder
          .where((id) => currentIds.contains(id))
          .toList();
      for (var id in currentIds) {
        if (!_inventoryOrder.contains(id)) _inventoryOrder.add(id);
      }
    } else {
      _inventoryOrder = currentIds;
    }

    if (_reportInventoryIds.isEmpty && _inventoryNames.isNotEmpty) {
      _reportInventoryIds = _inventoryNames.keys.toList();
    }

    if (mounted) setState(() => _isLoading = false);
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

  // --- UPDATERS ---

  Future<void> _updateReport(
    bool enabled,
    TimeOfDay time,
    int freq,
    List<String> ids,
  ) async {
    setState(() {
      _reportEnabled = enabled;
      _reportTime = time;
      _reportFrequency = freq;
      _reportInventoryIds = ids;
    });

    await NotificationService().updateReportSettings(enabled, time, freq, ids);

    final user = _currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
            'reportEnabled': enabled,
            'reportHour': time.hour,
            'reportFrequency': freq,
            'reportInventoryIds': ids,
          });
    }
  }

  Future<void> _saveOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('axis_inventory_notif_order', _inventoryOrder);
  }

  Future<void> _updateSmartAlerts({
    required String invId,
    required bool runout,
    required bool usage,
    required TimeOfDay rTime,
    required TimeOfDay uTime,
  }) async {
    setState(() {
      _inventorySettingsCache[invId]?['runoutEnabled'] = runout;
      _inventorySettingsCache[invId]?['usageEnabled'] = usage;
      _inventorySettingsCache[invId]?['runoutTime'] = rTime;
      _inventorySettingsCache[invId]?['usageTime'] = uTime;
    });

    final prefs = await SharedPreferences.getInstance();
    String key(String k) => "${k}_$invId";

    await prefs.setBool(key('axis_notif_runout'), runout);
    await prefs.setBool(key('axis_notif_usage'), usage);
    await prefs.setInt('axis_runout_h', rTime.hour);
    await prefs.setInt('axis_usage_h', uTime.hour);

    await FirebaseFirestore.instance
        .collection('households')
        .doc(invId)
        .update({
          'runoutEnabled': runout,
          'usageEnabled': usage,
          'runoutHour': rTime.hour,
          'usageHour': uTime.hour,
        });
  }

  Future<void> _updateRunoutConfig(
    String invId,
    List<int> thresholds,
    bool visuals,
  ) async {
    setState(() {
      _inventorySettingsCache[invId]?['thresholds'] = thresholds;
      _inventorySettingsCache[invId]?['runoutVisuals'] = visuals;
    });
    final prefs = await SharedPreferences.getInstance();
    String key(String k) => "${k}_$invId";
    List<String> strList = thresholds.map((e) => e.toString()).toList();
    await prefs.setStringList(key('axis_runout_thresholds'), strList);
    await prefs.setBool(key('axis_runout_enabled'), visuals);

    await FirebaseFirestore.instance.collection('households').doc(invId).update(
      {'runoutThresholds': thresholds},
    );
  }

  Future<void> _updateMuted(
    String invId,
    String type,
    Set<String> newSet,
  ) async {
    setState(() {
      if (type == 'runout') {
        _inventorySettingsCache[invId]?['runoutMuted'] = newSet;
      } else {
        _inventorySettingsCache[invId]?['usageMuted'] = newSet;
      }
    });
    final prefs = await SharedPreferences.getInstance();
    String key = (type == 'runout')
        ? 'axis_muted_runout_rooms_$invId'
        : 'axis_muted_usage_rooms_$invId';
    await prefs.setStringList(key, newSet.toList());
  }

  Future<void> _toggleInviteNotifs(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('axis_notif_invites', val);
    setState(() => _inviteNotifsEnabled = val);
  }

  Future<void> _toggleRemovedNotifs(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('axis_notif_removed', val);
    setState(() => _removedNotifsEnabled = val);

    final user = _currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'removedAlertsEnabled': val},
      );
    }
  }

  Future<void> _pickHour(
    BuildContext context,
    TimeOfDay initial,
    Function(TimeOfDay) onPicked,
  ) async {
    final theme = Theme.of(context);
    final List<int> hours = List.generate(24, (index) => index);

    String getLabel(int h) {
      final tod = TimeOfDay(hour: h, minute: 0);
      final hour = tod.hourOfPeriod == 0 ? 12 : tod.hourOfPeriod;
      final period = tod.period == DayPeriod.am ? 'AM' : 'PM';
      return '$hour:00 $period';
    }

    int selectedHour = initial.hour;

    await showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext builder) {
        return SizedBox(
          height: 300,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "Select Time",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Expanded(
                child: CupertinoTheme(
                  data: CupertinoThemeData(
                    brightness: theme.brightness,
                    textTheme: CupertinoTextThemeData(
                      pickerTextStyle: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  child: CupertinoPicker(
                    itemExtent: 40,
                    scrollController: FixedExtentScrollController(
                      initialItem: initial.hour,
                    ),
                    onSelectedItemChanged: (int index) {
                      selectedHour = index;
                    },
                    children: hours.map((h) {
                      return Center(child: Text(getLabel(h)));
                    }).toList(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      onPicked(TimeOfDay(hour: selectedHour, minute: 0));
                      Navigator.pop(context);
                    },
                    child: const Text("Done"),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showReportInventoryFilter(BuildContext context) {
    List<String> tempIds = List.from(_reportInventoryIds);
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Select Inventories"),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _inventoryNames.length,
                  itemBuilder: (c, i) {
                    String id = _inventoryNames.keys.elementAt(i);
                    String name = _inventoryNames[id]!;
                    bool isChecked = tempIds.contains(id);
                    return CheckboxListTile(
                      title: Text(name),
                      value: isChecked,
                      activeColor: Theme.of(context).colorScheme.primary,
                      onChanged: (val) {
                        setStateDialog(() {
                          if (val == true) {
                            tempIds.add(id);
                          } else {
                            tempIds.remove(id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    _updateReport(
                      _reportEnabled,
                      _reportTime,
                      _reportFrequency,
                      tempIds,
                    );
                    Navigator.pop(ctx);
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddLocationDialog(
    BuildContext context,
    String inventoryId,
    List<String> knownRooms,
    Set<String> currentMuted,
    Function(String, Set<String>) onUpdate,
  ) {
    final allLocations = [_householdItemsKey, ...knownRooms];
    final availableToAdd = allLocations
        .where((loc) => currentMuted.contains(loc))
        .toList();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Enable Location"),
          content: SizedBox(
            width: double.maxFinite,
            child: availableToAdd.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      "All locations are active.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: availableToAdd.length,
                    itemBuilder: (c, i) {
                      final loc = availableToAdd[i];
                      return ListTile(
                        title: Text(loc),
                        trailing: Icon(
                          Icons.add_circle_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        onTap: () {
                          final newSet = Set<String>.from(currentMuted)
                            ..remove(loc);
                          onUpdate(inventoryId, newSet);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:00 $period';
  }

  // --- BUILDERS ---

  Widget _buildInventoryCard(BuildContext context, Widget child) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 25),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor),
      ),
      child: child,
    );
  }

  Widget _buildGradientContentBlock({
    required BuildContext context,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      margin: const EdgeInsets.only(bottom: 10, top: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            theme.colorScheme.primary.withOpacity(0.05),
            theme.colorScheme.primary.withOpacity(0.2),
          ],
          stops: const [0.0, 1.0],
        ),
        border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
      ),
      child: child,
    );
  }

  Widget _buildLocationFilterSection(
    ThemeData theme,
    String inventoryId,
    List<String> knownRooms,
    Set<String> currentMuted,
    Function(String, Set<String>) onUpdate,
  ) {
    final allLocations = [_householdItemsKey, ...knownRooms];
    final activeLocations = allLocations
        .where((loc) => !currentMuted.contains(loc))
        .toList();
    return _buildGradientContentBlock(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "ACTIVE LOCATIONS",
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              InkWell(
                onTap: () => _showAddLocationDialog(
                  context,
                  inventoryId,
                  knownRooms,
                  currentMuted,
                  onUpdate,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(
                    Icons.add_circle,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: activeLocations.map((loc) {
              return GestureDetector(
                onTap: () {
                  final newSet = Set<String>.from(currentMuted)..add(loc);
                  onUpdate(inventoryId, newSet);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        loc,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.close,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTriggersSection(
    ThemeData theme,
    String inventoryId,
    List<int> thresholds,
    bool runoutEnabled,
    bool visuals,
  ) {
    return _buildGradientContentBlock(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "NOTIFY WHEN DAYS LEFT:",
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              InkWell(
                onTap: () =>
                    showAddTriggerDialog(context, thresholds, (newList) {
                      _updateRunoutConfig(inventoryId, newList, visuals);
                    }),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(
                    Icons.add_circle,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: thresholds.map((t) {
              return GestureDetector(
                onTap: () {
                  final newList = List<int>.from(thresholds)..remove(t);
                  _updateRunoutConfig(inventoryId, newList, visuals);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.colorScheme.primary.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "$t Days",
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.close,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildReportTile(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            theme.colorScheme.primary.withOpacity(0.1),
            theme.colorScheme.primary.withOpacity(0.4),
          ],
        ),
        border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.assignment_turned_in,
              color: theme.colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Inventory Report",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  "Get a summary of your item status",
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 10),

                if (_reportEnabled)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // TIME
                        GestureDetector(
                          onTap: () => _pickHour(
                            context,
                            _reportTime,
                            (t) => _updateReport(
                              _reportEnabled,
                              t,
                              _reportFrequency,
                              _reportInventoryIds,
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.colorScheme.primary.withOpacity(
                                  0.3,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _formatTime(_reportTime),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // FREQUENCY
                        Container(
                          height: 30,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: theme.colorScheme.primary.withOpacity(0.3),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: _reportFrequency,
                              icon: Icon(
                                Icons.keyboard_arrow_down,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                              isDense: true,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                              dropdownColor: Colors.black87,
                              items: const [
                                DropdownMenuItem(
                                  value: 1,
                                  child: Text("Daily"),
                                ),
                                DropdownMenuItem(
                                  value: 3,
                                  child: Text("3 Days"),
                                ),
                                DropdownMenuItem(
                                  value: 5,
                                  child: Text("5 Days"),
                                ),
                                DropdownMenuItem(
                                  value: 7,
                                  child: Text("Weekly"),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null)
                                  _updateReport(
                                    _reportEnabled,
                                    _reportTime,
                                    val,
                                    _reportInventoryIds,
                                  );
                              },
                            ),
                          ),
                        ),

                        const SizedBox(width: 10),

                        // FILTER
                        GestureDetector(
                          onTap: () => _showReportInventoryFilter(context),
                          child: Container(
                            height: 30,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.colorScheme.primary.withOpacity(
                                  0.3,
                                ),
                              ),
                            ),
                            child: Icon(
                              Icons.list,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          Switch(
            value: _reportEnabled,
            activeColor: theme.colorScheme.primary,
            onChanged: (val) => _updateReport(
              val,
              _reportTime,
              _reportFrequency,
              _reportInventoryIds,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            "GLOBAL",
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ),

        GradientSettingsTile(
          icon: Icons.group_add,
          title: "New Invites",
          subtitle: "Notify when someone adds you",
          onTap: () => _toggleInviteNotifs(!_inviteNotifsEnabled),
          trailing: Switch(
            value: _inviteNotifsEnabled,
            activeColor: theme.colorScheme.primary,
            onChanged: _toggleInviteNotifs,
          ),
        ),

        GradientSettingsTile(
          icon: Icons.group_remove,
          title: "Removed Alerts",
          subtitle: "Notify when removed from an inventory",
          onTap: () => _toggleRemovedNotifs(!_removedNotifsEnabled),
          trailing: Switch(
            value: _removedNotifsEnabled,
            activeColor: theme.colorScheme.primary,
            onChanged: _toggleRemovedNotifs,
          ),
        ),

        _buildReportTile(theme),

        const SizedBox(height: 30),

        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            "INVENTORIES (Drag to Reorder)",
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ),

        if (_inventoryOrder.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Center(
              child: Text(
                "No inventories found.",
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          )
        else
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final item = _inventoryOrder.removeAt(oldIndex);
                _inventoryOrder.insert(newIndex, item);
              });
              _saveOrder();
            },
            children: _inventoryOrder.map((invId) {
              final String invName = _inventoryNames[invId] ?? "Unknown";
              final Map<String, dynamic> settings =
                  _inventorySettingsCache[invId] ?? {};
              final List<String> rooms = _inventoryRoomsCache[invId] ?? [];

              bool runoutEnabled = settings['runoutEnabled'] ?? false;
              bool usageEnabled = settings['usageEnabled'] ?? false;
              TimeOfDay runoutTime =
                  settings['runoutTime'] ?? const TimeOfDay(hour: 8, minute: 0);
              TimeOfDay usageTime =
                  settings['usageTime'] ?? const TimeOfDay(hour: 18, minute: 0);
              List<int> thresholds = settings['thresholds'] ?? [7];
              Set<String> runoutMuted = settings['runoutMuted'] ?? {};
              Set<String> usageMuted = settings['usageMuted'] ?? {};
              bool runoutVisuals = settings['runoutVisuals'] ?? true;

              return Container(
                key: ValueKey(invId),
                child: _buildInventoryCard(
                  context,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.drag_indicator,
                            size: 20,
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              invName,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Divider(height: 1, color: theme.dividerColor),
                      const SizedBox(height: 15),

                      NotificationTile(
                        title: "Runout Warnings",
                        subtitle: "Alert at ${_formatTime(runoutTime)}",
                        isEnabled: runoutEnabled,
                        time: runoutTime,
                        onTimeTap: () => _pickHour(
                          context,
                          runoutTime,
                          (t) => _updateSmartAlerts(
                            invId: invId,
                            runout: runoutEnabled,
                            usage: usageEnabled,
                            rTime: t,
                            uTime: usageTime,
                          ),
                        ),
                        onToggle: (val) => _updateSmartAlerts(
                          invId: invId,
                          runout: val,
                          usage: usageEnabled,
                          rTime: runoutTime,
                          uTime: usageTime,
                        ),
                      ),
                      if (runoutEnabled)
                        Column(
                          children: [
                            _buildTriggersSection(
                              theme,
                              invId,
                              thresholds,
                              runoutEnabled,
                              runoutVisuals,
                            ),
                            _buildLocationFilterSection(
                              theme,
                              invId,
                              rooms,
                              runoutMuted,
                              (id, set) => _updateMuted(id, 'runout', set),
                            ),
                          ],
                        ),

                      const SizedBox(height: 20),

                      NotificationTile(
                        title: "Usage Reminders",
                        subtitle: "Check at ${_formatTime(usageTime)}",
                        isEnabled: usageEnabled,
                        time: usageTime,
                        onTimeTap: () => _pickHour(
                          context,
                          usageTime,
                          (t) => _updateSmartAlerts(
                            invId: invId,
                            runout: runoutEnabled,
                            usage: usageEnabled,
                            rTime: runoutTime,
                            uTime: t,
                          ),
                        ),
                        onToggle: (val) => _updateSmartAlerts(
                          invId: invId,
                          runout: runoutEnabled,
                          usage: val,
                          rTime: runoutTime,
                          uTime: usageTime,
                        ),
                      ),
                      if (usageEnabled)
                        _buildLocationFilterSection(
                          theme,
                          invId,
                          rooms,
                          usageMuted,
                          (id, set) => _updateMuted(id, 'usage', set),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}
