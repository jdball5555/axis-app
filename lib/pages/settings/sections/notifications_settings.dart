import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/settings_section.dart';
import '../widgets/notification_tile.dart';
import '../dialogs/trigger_dialog.dart';

class NotificationsSettings extends StatefulWidget {
  final bool debriefEnabled;
  final TimeOfDay debriefTime;
  final Function(bool, TimeOfDay) onDebriefChanged;

  final bool runoutEnabled;
  final bool runoutNotifsEnabled;
  final TimeOfDay runoutTime;
  final List<int> thresholds;
  final Function(List<int>, bool) onRunoutSettingsChanged;

  final bool usageNotifsEnabled;
  final TimeOfDay usageTime;
  final Function(bool, bool, TimeOfDay, TimeOfDay) onSmartAlertsChanged;

  final List<String> knownRooms;
  final Set<String> runoutMutedRooms;
  final Set<String> usageMutedRooms;
  final Function(Set<String>) onRunoutMutedChanged;
  final Function(Set<String>) onUsageMutedChanged;

  const NotificationsSettings({
    super.key,
    required this.debriefEnabled,
    required this.debriefTime,
    required this.onDebriefChanged,
    required this.runoutEnabled,
    required this.runoutNotifsEnabled,
    required this.runoutTime,
    required this.thresholds,
    required this.onRunoutSettingsChanged,
    required this.usageNotifsEnabled,
    required this.usageTime,
    required this.onSmartAlertsChanged,
    required this.knownRooms,
    required this.runoutMutedRooms,
    required this.usageMutedRooms,
    required this.onRunoutMutedChanged,
    required this.onUsageMutedChanged,
  });

  @override
  State<NotificationsSettings> createState() => _NotificationsSettingsState();
}

class _NotificationsSettingsState extends State<NotificationsSettings> {
  bool _inviteNotifsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadInviteSetting();
  }

  Future<void> _loadInviteSetting() async {
    final prefs = await SharedPreferences.getInstance();
    setState(
      () => _inviteNotifsEnabled = prefs.getBool('axis_notif_invites') ?? true,
    );
  }

  Future<void> _toggleInviteNotifs(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('axis_notif_invites', val);
    setState(() => _inviteNotifsEnabled = val);
  }

  Future<void> _pickTime(
    BuildContext context,
    TimeOfDay initial,
    Function(TimeOfDay) onPicked,
  ) async {
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) onPicked(picked);
  }

  void _notifySmartChanges(
    bool newRunout,
    bool newUsage,
    TimeOfDay newRunoutTime,
    TimeOfDay newUsageTime,
  ) {
    widget.onSmartAlertsChanged(
      newRunout,
      newUsage,
      newRunoutTime,
      newUsageTime,
    );
  }

  void _showAddRoomDialog(
    Set<String> currentMuted,
    Function(Set<String>) onUpdate,
  ) {
    final availableToAdd = widget.knownRooms
        .where((r) => currentMuted.contains(r))
        .toList();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Enable Room"),
          content: SizedBox(
            width: double.maxFinite,
            child: availableToAdd.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      "All rooms are active.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: availableToAdd.length,
                    itemBuilder: (c, i) {
                      final room = availableToAdd[i];
                      return ListTile(
                        title: Text(room),
                        trailing: Icon(
                          Icons.add_circle_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        onTap: () {
                          final newSet = Set<String>.from(currentMuted)
                            ..remove(room);
                          onUpdate(newSet);
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

  Widget _buildRoomFilterSection(
    ThemeData theme,
    Set<String> currentMuted,
    Function(Set<String>) onUpdate,
  ) {
    final activeRooms = widget.knownRooms
        .where((r) => !currentMuted.contains(r))
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          Text(
            "Active Rooms:",
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
                children: [
                  ...activeRooms.map(
                    (room) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          final newSet = Set<String>.from(currentMuted)
                            ..add(room);
                          onUpdate(newSet);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.dividerColor),
                            borderRadius: BorderRadius.circular(8),
                            color: theme.colorScheme.primary.withOpacity(0.1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                room,
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.close,
                                size: 12,
                                color: theme.colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ADD BUTTON MOVED HERE, outside Expanded
          InkWell(
            onTap: () => _showAddRoomDialog(currentMuted, onUpdate),
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
                children: widget.thresholds
                    .map(
                      (t) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () {
                            final newList = List<int>.from(widget.thresholds)
                              ..remove(t);
                            widget.onRunoutSettingsChanged(
                              newList,
                              widget.runoutEnabled,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: theme.dividerColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "$t days",
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          InkWell(
            onTap: () =>
                showAddTriggerDialog(context, widget.thresholds, (newList) {
                  widget.onRunoutSettingsChanged(newList, widget.runoutEnabled);
                }),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            "NOTIFICATIONS",
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ),
        SettingsSection(
          children: [
            SwitchListTile(
              title: const Text("New Invites"),
              subtitle: const Text("Notify when someone adds you"),
              secondary: Icon(Icons.group_add, color: theme.iconTheme.color),
              value: _inviteNotifsEnabled,
              activeColor: theme.colorScheme.primary,
              onChanged: _toggleInviteNotifs,
            ),
            Divider(height: 1, color: theme.dividerColor),
            NotificationTile(
              title: "Debrief",
              subtitle: "Review your day",
              isEnabled: widget.debriefEnabled,
              time: widget.debriefTime,
              onTimeTap: () => _pickTime(
                context,
                widget.debriefTime,
                (t) => widget.onDebriefChanged(widget.debriefEnabled, t),
              ),
              onToggle: (val) =>
                  widget.onDebriefChanged(val, widget.debriefTime),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // --- INVENTORY DEPENDENT SECTION START ---
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 10),
          child: Text(
            "INVENTORY DEPENDENT",
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ),

        SettingsSection(
          children: [
            // Runout
            NotificationTile(
              title: "Runout Warnings",
              subtitle: "Notify before items empty",
              isEnabled: widget.runoutNotifsEnabled,
              time: widget.runoutTime,
              onTimeTap: () => _pickTime(
                context,
                widget.runoutTime,
                (t) => _notifySmartChanges(
                  widget.runoutNotifsEnabled,
                  widget.usageNotifsEnabled,
                  t,
                  widget.usageTime,
                ),
              ),
              onToggle: (val) => _notifySmartChanges(
                val,
                widget.usageNotifsEnabled,
                widget.runoutTime,
                widget.usageTime,
              ),
            ),
            if (widget.runoutNotifsEnabled) ...[
              _buildTriggersSection(theme),
              _buildRoomFilterSection(
                theme,
                widget.runoutMutedRooms,
                widget.onRunoutMutedChanged,
              ),
            ],

            Divider(height: 1, color: theme.dividerColor),

            // Usage
            NotificationTile(
              title: "Usage Reminders",
              subtitle: "Based on average rate",
              isEnabled: widget.usageNotifsEnabled,
              time: widget.usageTime,
              onTimeTap: () => _pickTime(
                context,
                widget.usageTime,
                (t) => _notifySmartChanges(
                  widget.runoutNotifsEnabled,
                  widget.usageNotifsEnabled,
                  widget.runoutTime,
                  t,
                ),
              ),
              onToggle: (val) => _notifySmartChanges(
                widget.runoutNotifsEnabled,
                val,
                widget.runoutTime,
                widget.usageTime,
              ),
            ),
            if (widget.usageNotifsEnabled)
              _buildRoomFilterSection(
                theme,
                widget.usageMutedRooms,
                widget.onUsageMutedChanged,
              ),
          ],
        ),
      ],
    );
  }
}
