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
    _loadLogs(); // Refresh UI
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

  // --- REVERT LOGIC ---
  Future<void> _revertInventoryChange(String logEntry) async {
    List<String> parts = logEntry.split('|');
    if (parts.length < 5) return;

    String itemName = parts[2];
    int changeAmount = int.tryParse(parts[4]) ?? 0;

    // Only revert if there was a numerical change
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
          // REVERSE LOGIC:
          // If we added 5, now subtract 5.
          // If we subtracted 1 (change = -1), now add 1 (change = --1 = +1).
          int newQty = items[itemIndex].quantity - changeAmount;
          if (newQty < 0) newQty = 0; // Safety check

          items[itemIndex].quantity = newQty;

          // Save back to DB
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
        backgroundColor: const Color(0xFF222222),
        title: const Text(
          "Delete & Revert?",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "Deleting this entry will also UNDO any inventory changes (e.g., add back used items).",
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
              // 1. Perform Revert Logic First
              await _revertInventoryChange(logs[originalIndex]);

              // 2. Delete the Log
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
              backgroundColor: const Color(0xFF222222),
              title: const Text(
                "Edit Entry",
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(
                      Icons.calendar_today,
                      color: Color(0xFF00C897),
                    ),
                    label: Text(
                      "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')} ${selectedDate.hour.toString().padLeft(2, '0')}:${selectedDate.minute.toString().padLeft(2, '0')}",
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                    ),
                    onPressed: () async {
                      final DateTime? date = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        builder: (context, child) {
                          return Theme(
                            data: ThemeData.dark().copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: Color(0xFF00C897),
                                onPrimary: Colors.white,
                                surface: Color(0xFF222222),
                                onSurface: Colors.white,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (date == null) return;

                      if (!context.mounted) return;
                      final TimeOfDay? time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(selectedDate),
                        builder: (context, child) {
                          return Theme(
                            data: ThemeData.dark().copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: Color(0xFF00C897),
                                onPrimary: Colors.white,
                                surface: Color(0xFF222222),
                                onSurface: Colors.white,
                              ),
                            ),
                            child: child!,
                          );
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
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Note",
                      labelStyle: TextStyle(color: Colors.white54),
                      hintText: "Add details...",
                      hintStyle: TextStyle(color: Colors.white30),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF00C897)),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF00C897)),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: const Text("Cancel"),
                  onPressed: () => Navigator.pop(ctx),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C897),
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
      backgroundColor: const Color(0xFF111111),
      builder: (ctx) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.white),
            title: const Text(
              "Edit Date / Note",
              style: TextStyle(color: Colors.white),
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
    final displayLogs = logs.reversed.toList();

    Color getActionColor(String action) {
      if (action.contains("DELETED")) return Colors.redAccent;
      if (action == "USED ONE") return Colors.orangeAccent;
      if (action == "RESTOCKED" || action == "CREATED")
        return const Color(0xFF00C897);
      return Colors.white;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "Activity Log",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: displayLogs.isEmpty
          ? const Center(
              child: Text(
                "No activity recorded.",
                style: TextStyle(color: Colors.white38),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: displayLogs.length,
              separatorBuilder: (ctx, i) =>
                  const Divider(color: Colors.white10),
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
                            style: const TextStyle(
                              color: Colors.white30,
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
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                              if (note.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6.0),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.sticky_note_2,
                                        size: 12,
                                        color: Colors.white30,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          note,
                                          style: const TextStyle(
                                            color: Colors.white70,
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
                                    ? Colors.white30
                                    : (int.tryParse(change) != null &&
                                              int.parse(change) > 0
                                          ? const Color(0xFF00C897)
                                          : Colors.orangeAccent),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              "Total: $total",
                              style: const TextStyle(
                                color: Colors.white30,
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
