import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

class ActivityLogPage extends StatefulWidget {
  const ActivityLogPage({super.key});

  @override
  State<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<ActivityLogPage> {
  final FirestoreService _db = FirestoreService();

  // --- ROBUST DATE PARSER (Fixes the "Only one date showing" bug) ---
  DateTime? _parseTimestamp(String timestamp) {
    if (timestamp.trim().isEmpty) return null;
    try {
      return DateTime.parse(timestamp);
    } catch (_) {
      try {
        // Fallback for space-separated format (2025-10-02 0:00:00)
        List<String> parts = timestamp.trim().split(' ');
        if (parts.length >= 2) {
          List<String> d = parts[0].split('-');
          List<String> t = parts[1].split(':');
          return DateTime(
            int.parse(d[0]),
            int.parse(d[1]),
            int.parse(d[2]),
            int.parse(t[0]),
            int.parse(t[1]),
            int.parse(t[2]),
          );
        }
        return null;
      } catch (e) {
        return null;
      }
    }
  }

  Color getActionColor(String action, ThemeData theme) {
    if (action.contains("DELETED") || action.contains("REMOVE"))
      return Colors.redAccent;
    if (action == "USED ONE" || action == "USED") return Colors.orangeAccent;
    if (action == "RESTOCKED" || action == "CREATED" || action == "UPDATED") {
      return theme.colorScheme.primary;
    }
    return theme.colorScheme.onSurface;
  }

  // --- REVERT LOGIC (Undoes inventory changes) ---
  Future<void> _revertInventoryChange(Map<String, dynamic> log) async {
    final String item = log['item'] ?? '';
    final int change = (log['change'] as num?)?.toInt() ?? 0;

    // Only revert if there was a valid item and a numerical change
    if (item.isNotEmpty && change != 0) {
      // 1. Fetch current inventory item
      final docRef = _db.inventoryCollection.doc(item);
      final docSnap = await docRef.get();

      if (docSnap.exists) {
        final data = docSnap.data() as Map<String, dynamic>;
        final int currentQty = (data['quantity'] as num?)?.toInt() ?? 0;

        // 2. Reverse the math
        // If log says +5 (Restocked), we subtract 5.
        // If log says -1 (Used), we add 1 (subtract -1).
        int newQty = (currentQty - change).clamp(0, 9999);

        // 3. Update DB
        await _db.updateQuantity(item, newQty);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Reverted inventory for $item.")),
          );
        }
      }
    }
  }

  void _showEditDialog(Map<String, dynamic> log) {
    final String docId = log['id'];
    final String currentNote = log['note'] ?? '';
    DateTime selectedDate = _parseTimestamp(log['timestamp']) ?? DateTime.now();
    TextEditingController noteController = TextEditingController(
      text: currentNote,
    );

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
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
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
                      final DateTime? d = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        builder: (context, child) =>
                            Theme(data: Theme.of(context), child: child!),
                      );
                      if (d != null) {
                        final TimeOfDay? t = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(selectedDate),
                          builder: (context, child) =>
                              Theme(data: Theme.of(context), child: child!),
                        );
                        if (t != null) {
                          setDialogState(() {
                            selectedDate = DateTime(
                              d.year,
                              d.month,
                              d.day,
                              t.hour,
                              t.minute,
                            );
                          });
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: noteController,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      labelText: "Note",
                      labelStyle: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      border: OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.access_time, size: 16),
                        tooltip: "Add 'Date is approximate'",
                        onPressed: () {
                          String text = noteController.text;
                          if (text.isNotEmpty) text += " ";
                          noteController.text = text + "(Date is approximate)";
                        },
                      ),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
              actions: [
                // DELETE BUTTON
                TextButton(
                  child: const Text(
                    "Delete",
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _confirmDelete(log); // Pass full log for revert logic
                  },
                ),
                // SAVE BUTTON
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text("Save"),
                  onPressed: () {
                    _db.updateLogEntry(docId, {
                      'timestamp': selectedDate.toIso8601String(),
                      'note': noteController.text.trim(),
                    });
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

  void _confirmDelete(Map<String, dynamic> log) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text(
          "Delete & Revert?",
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: Text(
          "Deleting this entry will also UNDO any inventory changes (e.g., add back used items).",
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
              Navigator.pop(ctx);
              // 1. Revert Inventory
              await _revertInventoryChange(log);
              // 2. Delete Log
              await _db.deleteLogEntry(log['id']);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _db.getLogStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          final logs = snapshot.data ?? [];

          if (logs.isEmpty) {
            return Center(
              child: Text(
                "No activity recorded.",
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: logs.length,
            separatorBuilder: (ctx, i) => Divider(color: theme.dividerColor),
            itemBuilder: (context, index) {
              final log = logs[index];
              final String timestamp = log['timestamp'] ?? '';
              final String action = log['action'] ?? 'UNKNOWN';
              final String item = log['item'] ?? 'Unknown Item';
              final String room = log['room'] ?? 'N/A';
              final String note = log['note'] ?? '';

              final int change = (log['change'] as num?)?.toInt() ?? 0;
              final int total = (log['total'] as num?)?.toInt() ?? 0;

              String timeDisplay = "--\n--";
              DateTime? dt = _parseTimestamp(timestamp);
              if (dt != null) {
                String twoDigits(int n) => n.toString().padLeft(2, '0');
                timeDisplay =
                    "${twoDigits(dt.month)}-${twoDigits(dt.day)}\n${twoDigits(dt.hour)}:${twoDigits(dt.minute)}";
              }

              return InkWell(
                onLongPress: () => _showEditDialog(log),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
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
                                color: getActionColor(action, theme),
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
                            if (note.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.sticky_note_2_outlined,
                                    size: 12,
                                    color: theme.colorScheme.primary
                                        .withOpacity(0.7),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      note,
                                      style: TextStyle(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            change == 0
                                ? "--"
                                : (change > 0 ? "+$change" : "$change"),
                            style: TextStyle(
                              color: change == 0
                                  ? theme.colorScheme.onSurfaceVariant
                                  : (change > 0
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
          );
        },
      ),
    );
  }
}
