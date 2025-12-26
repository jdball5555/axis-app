import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/inventory_item.dart';

class ActivityLogPage extends StatefulWidget {
  const ActivityLogPage({super.key});

  @override
  State<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<ActivityLogPage> {
  List<String> logs = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      logs = prefs.getStringList('axis_activity_log') ?? [];
    });
  }

  Future<void> _saveLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('axis_activity_log', logs);
    _loadLogs();
  }

  DateTime? _parseTimestamp(String timestamp) {
    try {
      return DateTime.parse(timestamp);
    } catch (_) {
      try {
        List<String> parts = timestamp.split(' ');
        if (parts.length < 2) return null;
        List<String> dateParts = parts[0].split('-');
        List<String> timeParts = parts[1].split(':');
        String y = dateParts[0];
        String m = dateParts[1].padLeft(2, '0');
        String d = dateParts[2].padLeft(2, '0');
        String h = timeParts[0].padLeft(2, '0');
        String min = timeParts[1].padLeft(2, '0');
        String s = timeParts[2].padLeft(2, '0');
        return DateTime.parse("$y-$m-$d $h:$min:$s");
      } catch (e) {
        return null;
      }
    }
  }

  String _formatTimestampForSave(DateTime dt) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${dt.year}-${twoDigits(dt.month)}-${twoDigits(dt.day)} ${twoDigits(dt.hour)}:${twoDigits(dt.minute)}:${twoDigits(dt.second)}";
  }

  Future<void> _revertInventoryChange(String logEntry) async {
    List<String> parts = logEntry.split('|');
    if (parts.length < 5) return;
    String itemName = parts[2];
    int changeAmount = int.tryParse(parts[4]) ?? 0;
    if (changeAmount != 0) {
      final prefs = await SharedPreferences.getInstance();
      final String? invData = prefs.getString('axis_inventory');
      if (invData != null) {
        final List<dynamic> jsonList = jsonDecode(invData);
        List<InventoryItem> items = jsonList
            .map((e) => InventoryItem.fromJson(e))
            .toList();
        int itemIndex = items.indexWhere(
          (i) => i.name == itemName && i.type == 'Item',
        );
        if (itemIndex != -1) {
          int newQty = items[itemIndex].quantity - changeAmount;
          if (newQty < 0) newQty = 0;
          items[itemIndex].quantity = newQty;
          await prefs.setString(
            'axis_inventory',
            jsonEncode(items.map((e) => e.toJson()).toList()),
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Reverted inventory for $itemName.")),
            );
          }
        }
      }
    }
  }

  void _deleteLog(int originalIndex) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text(
          "Delete & Revert?",
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: Text(
          "Deleting this entry will also UNDO any inventory changes.",
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
              await _revertInventoryChange(logs[originalIndex]);
              setState(() {
                logs.removeAt(originalIndex);
              });
              _saveLogs();
              if (mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  void _editLog(
    int originalIndex,
    String currentNote,
    String currentTimestamp,
  ) {
    TextEditingController noteController = TextEditingController(
      text: currentNote,
    );
    DateTime selectedDate = _parseTimestamp(currentTimestamp) ?? DateTime.now();
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              title: Text(
                "Edit Entry",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    icon: Icon(
                      Icons.calendar_today,
                      color: Theme.of(context).primaryColor,
                    ),
                    label: Text(
                      "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')} ${selectedDate.hour.toString().padLeft(2, '0')}:${selectedDate.minute.toString().padLeft(2, '0')}",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                    onPressed: () async {
                      final DateTime? date = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        builder: (context, child) {
                          return Theme(data: Theme.of(context), child: child!);
                        },
                      );
                      if (date == null) return;
                      if (!context.mounted) return;
                      final TimeOfDay? time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(selectedDate),
                        builder: (context, child) {
                          return Theme(data: Theme.of(context), child: child!);
                        },
                      );
                      if (time == null) return;
                      setDialogState(() {
                        selectedDate = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: noteController,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    cursorColor: Theme.of(context).primaryColor,
                    decoration: InputDecoration(
                      labelText: "Note",
                      labelStyle: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).primaryColor,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
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
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text("Save"),
                  onPressed: () {
                    String oldEntry = logs[originalIndex];
                    List<String> parts = oldEntry.split('|');
                    while (parts.length < 6) parts.add("");
                    String newTimestamp = _formatTimestampForSave(selectedDate);
                    String action = parts[1];
                    String item = parts[2];
                    String room = parts[3];
                    String change = parts[4];
                    String total = parts[5];
                    String newNote = noteController.text.replaceAll('|', '');
                    String newEntry =
                        "$newTimestamp|$action|$item|$room|$change|$total|$newNote";
                    setState(() {
                      logs[originalIndex] = newEntry;
                    });
                    _saveLogs();
                    Navigator.pop(ctx);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showOptions(int reversedIndex) {
    int originalIndex = logs.length - 1 - reversedIndex;
    String currentLog = logs[originalIndex];
    List<String> parts = currentLog.split('|');
    String timestamp = parts[0];
    String currentNote = parts.length > 6 ? parts[6] : "";
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      builder: (ctx) => Wrap(
        children: [
          ListTile(
            leading: Icon(Icons.edit, color: Theme.of(context).iconTheme.color),
            title: Text(
              "Edit Date / Note",
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            onTap: () {
              Navigator.pop(ctx);
              _editLog(originalIndex, currentNote, timestamp);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.redAccent),
            title: const Text(
              "Delete & Revert",
              style: TextStyle(color: Colors.redAccent),
            ),
            onTap: () {
              Navigator.pop(ctx);
              _deleteLog(originalIndex);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayLogs = logs.reversed.toList();

    Color getActionColor(String action) {
      if (action.contains("DELETED")) return Colors.redAccent;
      if (action == "USED ONE") return Colors.orangeAccent;
      // FIX: Added "UPDATED" here so it shows Teal
      if (action == "RESTOCKED" || action == "CREATED" || action == "UPDATED") {
        return theme.colorScheme.primary;
      }
      return theme.colorScheme.onSurface;
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
        title: Text(
          "Activity Log",
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: displayLogs.isEmpty
          ? Center(
              child: Text(
                "No activity recorded.",
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: displayLogs.length,
              separatorBuilder: (ctx, i) => Divider(color: theme.dividerColor),
              itemBuilder: (context, index) {
                final parts = displayLogs[index].split('|');
                if (parts.length < 6) return const SizedBox();
                final timestamp = parts[0];
                final action = parts[1];
                final item = parts[2];
                final room = parts[3];
                final change = parts[4];
                final total = parts[5];
                final note = parts.length > 6 ? parts[6] : "";
                String timeDisplay = "";
                DateTime? dt = _parseTimestamp(timestamp);
                if (dt != null) {
                  String twoDigits(int n) => n.toString().padLeft(2, '0');
                  timeDisplay =
                      "${twoDigits(dt.month)}-${twoDigits(dt.day)}\n${twoDigits(dt.hour)}:${twoDigits(dt.minute)}";
                } else {
                  timeDisplay = "--\n--";
                }

                return GestureDetector(
                  onLongPress: () => _showOptions(index),
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 60,
                          child: Text(
                            timeDisplay,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "$action: $item",
                                style: TextStyle(
                                  color: getActionColor(action),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Room: $room",
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                              if (note.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6.0),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.sticky_note_2,
                                        size: 12,
                                        color: theme.disabledColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          note,
                                          style: TextStyle(
                                            color: theme.colorScheme.onSurface,
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              change == "-"
                                  ? "--"
                                  : (int.tryParse(change) != null &&
                                            int.parse(change) > 0
                                        ? "+$change"
                                        : change),
                              style: TextStyle(
                                color: change == "-"
                                    ? theme.colorScheme.onSurfaceVariant
                                    : (int.tryParse(change) != null &&
                                              int.parse(change) > 0
                                          ? theme.colorScheme.primary
                                          : Colors.orangeAccent),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              "Total: $total",
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
