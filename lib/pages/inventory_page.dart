import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/inventory_item.dart';
import '../services/firestore_service.dart';
import 'activity_log_page.dart';

class AxisInventoryTab extends StatefulWidget {
  const AxisInventoryTab({super.key});

  static String? lastKnownName;
  static bool lastKnownShared = false;

  @override
  State<AxisInventoryTab> createState() => _AxisInventoryTabState();
}

class _AxisInventoryTabState extends State<AxisInventoryTab>
    with AutomaticKeepAliveClientMixin {
  final FirestoreService _db = FirestoreService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late Stream<List<InventoryItem>> _inventoryStream;
  late Stream<List<Map<String, dynamic>>> _logStream;
  Set<String> _mutedRooms = {};

  StreamSubscription<DocumentSnapshot>? _householdSub;
  String _currentSubscribedId = "";
  String _householdName = AxisInventoryTab.lastKnownName ?? "My Inventory";
  bool _isShared = AxisInventoryTab.lastKnownShared;

  bool _isFabMenuOpen = false;
  final ValueNotifier<bool> _showFabNotifier = ValueNotifier<bool>(true);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _inventoryStream = _db.getInventoryStream();
    _logStream = _db.getLogStream();
    _loadMutedRooms();
    _checkForHouseholdUpdate();
  }

  @override
  void didUpdateWidget(AxisInventoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkForHouseholdUpdate();
  }

  @override
  void dispose() {
    _householdSub?.cancel();
    _showFabNotifier.dispose();
    super.dispose();
  }

  void _checkForHouseholdUpdate() {
    final newId = _db.currentHouseholdId;
    if (newId == null || newId == _currentSubscribedId) return;

    _householdSub?.cancel();
    _currentSubscribedId = newId;

    _householdSub = _firestore
        .collection('households')
        .doc(newId)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            final data = snapshot.data() as Map<String, dynamic>;
            final newName = data['name'] ?? "My Inventory";
            final List members = data['members'] ?? [];
            final newShared = members.length > 1;

            AxisInventoryTab.lastKnownName = newName;
            AxisInventoryTab.lastKnownShared = newShared;

            if (mounted) {
              setState(() {
                _householdName = newName;
                _isShared = newShared;
              });
            }
          }
        });
  }

  Future<void> _loadMutedRooms() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        final runout = (prefs.getStringList('axis_muted_runout_rooms') ?? [])
            .toSet();
        final usage = (prefs.getStringList('axis_muted_usage_rooms') ?? [])
            .toSet();
        _mutedRooms = runout.intersection(usage);
      });
    }
  }

  void _addItem(String name, String type, String? room) {
    _db.addItem(
      InventoryItem(name: name, type: type, roomLocation: room, quantity: 0),
    );
    if (type == 'Item') {
      _db.logActivity("CREATED ITEM", name, room ?? "Unknown", 0, 0);
    } else {
      _db.logActivity("CREATED ROOM", name, "N/A", 0, 0);
    }
  }

  void _confirmUseOne(InventoryItem item, List<Map<String, dynamic>> logs) {
    if (item.quantity <= 0) {
      _showSnack("None left to use!");
      return;
    }
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            "Use Item?",
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: Text(
            "Did you use 1 '${item.name}'?",
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
              child: Text(
                "Yes, I used one",
                style: TextStyle(color: Theme.of(context).primaryColor),
              ),
              onPressed: () {
                int newQty = item.quantity - 1;
                _db.updateQuantity(item.name, item.roomLocation, newQty);
                _db.logActivity(
                  "USED ONE",
                  item.name,
                  item.roomLocation ?? "Unknown",
                  -1,
                  newQty,
                );
                Navigator.pop(ctx);

                _checkAndPromptMissingUsages(item, logs, newQty);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _checkAndPromptMissingUsages(
    InventoryItem item,
    List<Map<String, dynamic>> logs,
    int currentQty,
  ) async {
    if (currentQty <= 0) return;

    List<DateTime> usageDates = [];
    for (var log in logs) {
      String logName = log['item'] ?? "";
      String logRoom = log['room'] ?? "";
      String action = log['action'] ?? "";
      String timestampStr = log['timestamp'] ?? "";

      bool matchesItem = logName == item.name;
      bool matchesRoom = logRoom == item.roomLocation || logRoom == "N/A";
      bool isUsage = action.contains("USED");

      if (matchesItem && matchesRoom && isUsage) {
        try {
          DateTime? dt = DateTime.tryParse(timestampStr);
          if (dt == null) {
            List<String> parts = timestampStr.trim().split(' ');
            if (parts.length >= 2) {
              List<String> d = parts[0].split('-');
              List<String> t = parts[1].split(':');
              dt = DateTime(
                int.parse(d[0]),
                int.parse(d[1]),
                int.parse(d[2]),
                int.parse(t[0]),
                int.parse(t[1]),
                int.parse(t[2]),
              );
            }
          }
          if (dt != null) usageDates.add(dt);
        } catch (_) {}
      }
    }

    usageDates.sort();
    if (usageDates.isEmpty) return;

    DateTime lastUse = usageDates.last;
    DateTime today = DateTime.now();
    int daysSinceLast = today.difference(lastUse).inDays;

    if (usageDates.length < 2) return;

    DateTime firstUse = usageDates.first;
    int totalSpan = lastUse.difference(firstUse).inDays;
    int intervals = usageDates.length - 1;
    double avgDays = intervals > 0 ? totalSpan / intervals : 1.0;
    if (avgDays < 1) avgDays = 1.0;

    if (daysSinceLast >= avgDays * 1.8) {
      int expectedIntervals = (daysSinceLast / avgDays).round();
      int missingCount = expectedIntervals - 1;

      if (missingCount > currentQty) missingCount = currentQty;
      if (missingCount <= 0) return;

      double exactStep = daysSinceLast / expectedIntervals;
      List<DateTime> proposed = [];
      for (int i = 1; i <= missingCount; i++) {
        proposed.add(lastUse.add(Duration(days: (exactStep * i).round())));
      }

      final bool? confirmAdd = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MissingUsagesPage(
            item: item,
            usageHistory: usageDates,
            lastUse: lastUse,
            today: today,
            proposed: proposed,
            missingCount: missingCount,
            currentQty: currentQty,
            avgDays: avgDays,
          ),
        ),
      );

      if (confirmAdd == true) {
        int resultingQty = currentQty;
        for (var date in proposed) {
          resultingQty -= 1;
          await _logRetroactiveUsage(item, date, resultingQty);
        }
        await _db.updateQuantity(item.name, item.roomLocation, resultingQty);
        _showSnack("Logged $missingCount missed usages.");
      }
    }
  }

  Future<void> _logRetroactiveUsage(
    InventoryItem item,
    DateTime date,
    int resultingQty,
  ) async {
    if (_currentSubscribedId.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    await _firestore
        .collection('households')
        .doc(_currentSubscribedId)
        .collection('activity_log')
        .add({
          'timestamp': date.toIso8601String(),
          'action': "USED ONE",
          'item': item.name,
          'room': item.roomLocation ?? "Unknown",
          'change': -1,
          'total': resultingQty,
          'user': user?.displayName ?? user?.email ?? "Unknown",
          'notes': "Suggested by Axis, Date is approximate",
        });
  }

  void _confirmDelete(InventoryItem item) {
    final isRoom = item.type == "Room";
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            "Delete?",
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: Text(
            isRoom
                ? "WARNING: Deleting '${item.name}' will also delete ALL items in this room."
                : "Are you sure you want to delete '${item.name}'?",
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
              onPressed: () {
                if (isRoom) {
                  _db.deleteRoom(item.name);
                  _db.logActivity("ROOM DELETED", item.name, "N/A", 0, 0);
                } else {
                  _db.deleteItem(item.name, item.roomLocation);
                  _db.logActivity(
                    "DELETED",
                    item.name,
                    item.roomLocation ?? "Unknown",
                    -item.quantity,
                    0,
                  );
                }
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: isDark ? Colors.white : null),
        ),
        backgroundColor: isDark ? const Color(0xFF2C2C2C) : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showQuantityDialog(InventoryItem item, List<InventoryItem> allItems) {
    final otherSources = allItems
        .where(
          (i) =>
              i.name.trim().toLowerCase() == item.name.trim().toLowerCase() &&
              i.roomLocation != item.roomLocation &&
              i.quantity > 0,
        )
        .toList();

    String selectedSource = "NEW_PURCHASE";
    if (item.defaultSource != null && item.defaultSource != "NEW_PURCHASE") {
      final defaultExists = otherSources.any(
        (s) => s.roomLocation == item.defaultSource,
      );
      if (defaultExists) selectedSource = item.defaultSource!;
    } else if (item.defaultSource == "NEW_PURCHASE") {
      selectedSource = "NEW_PURCHASE";
    }

    int quantityToAdd = 1;
    bool setAsDefault = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final newTotal = item.quantity + quantityToAdd;
            final theme = Theme.of(context);
            final savedDefault = item.defaultSource ?? "NEW_PURCHASE";
            final bool showSetDefault = selectedSource != savedDefault;

            return AlertDialog(
              backgroundColor: theme.cardColor,
              title: Text(
                "Restock ${item.name}",
                style: TextStyle(color: theme.colorScheme.onSurface),
                textAlign: TextAlign.center,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.remove_circle_outline,
                            color: theme.iconTheme.color,
                            size: 32,
                          ),
                          onPressed: () {
                            if (quantityToAdd > 1)
                              setDialogState(() => quantityToAdd--);
                          },
                        ),
                        Container(
                          constraints: const BoxConstraints(minWidth: 60),
                          alignment: Alignment.center,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            "+$quantityToAdd",
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
                            size: 32,
                          ),
                          onPressed: () {
                            setDialogState(() => quantityToAdd++);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: theme.dividerColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Total: ",
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            "${item.quantity}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            child: Icon(
                              Icons.arrow_forward,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Text(
                            "$newTotal",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (otherSources.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Source:",
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      RadioListTile<String>(
                        value: "NEW_PURCHASE",
                        groupValue: selectedSource,
                        activeColor: theme.colorScheme.primary,
                        title: const Text("New Purchase"),
                        subtitle: const Text("Bought from store"),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) =>
                            setDialogState(() => selectedSource = val!),
                        secondary: (savedDefault == "NEW_PURCHASE")
                            ? Icon(
                                Icons.star,
                                color: theme.colorScheme.primary,
                                size: 16,
                              )
                            : null,
                      ),
                      ...otherSources.map((source) {
                        final isDefault =
                            source.roomLocation == item.defaultSource;
                        return RadioListTile<String>(
                          value: source.roomLocation ?? "Unknown",
                          groupValue: selectedSource,
                          activeColor: theme.colorScheme.primary,
                          title: Row(
                            children: [
                              Text("From ${source.roomLocation}"),
                              if (isDefault)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: Icon(
                                    Icons.star,
                                    size: 16,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text("Stock: ${source.quantity}"),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) =>
                              setDialogState(() => selectedSource = val!),
                        );
                      }),
                      if (showSetDefault)
                        CheckboxListTile(
                          value: setAsDefault,
                          activeColor: theme.colorScheme.primary,
                          title: Text(
                            selectedSource == "NEW_PURCHASE"
                                ? "Set 'New Purchase' as default?"
                                : "Set '${selectedSource}' as default?",
                            style: const TextStyle(fontSize: 12),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) =>
                              setDialogState(() => setAsDefault = val ?? false),
                        ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: Text(
                    "Cancel",
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                TextButton(
                  child: Text(
                    "Restock",
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    if (setAsDefault)
                      await _db.setItemDefaultSource(
                        item.name,
                        item.roomLocation,
                        selectedSource,
                      );

                    if (selectedSource == "NEW_PURCHASE") {
                      _db.updateQuantity(
                        item.name,
                        item.roomLocation,
                        newTotal,
                      );
                      _db.logActivity(
                        "RESTOCKED",
                        item.name,
                        item.roomLocation ?? "Unknown",
                        quantityToAdd,
                        newTotal,
                      );
                      _showSnack("Restocked $quantityToAdd ${item.name}");
                    } else {
                      final sourceItem = otherSources.firstWhere(
                        (s) => s.roomLocation == selectedSource,
                      );
                      if (sourceItem.quantity < quantityToAdd) {
                        _showSnack(
                          "Not enough stock in ${sourceItem.roomLocation}!",
                        );
                        return;
                      }
                      _processTransfer(
                        sourceItem,
                        item,
                        quantityToAdd,
                        newTotal,
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _processTransfer(
    InventoryItem sourceItem,
    InventoryItem targetItem,
    int amount,
    int targetNewTotal,
  ) async {
    int newSourceQty = (sourceItem.quantity - amount).clamp(0, 9999);
    await _db.updateQuantity(
      sourceItem.name,
      sourceItem.roomLocation,
      newSourceQty,
    );
    await _db.updateQuantity(
      targetItem.name,
      targetItem.roomLocation,
      targetNewTotal,
    );
    await _db.logActivity(
      "MOVED TO ${targetItem.roomLocation}",
      sourceItem.name,
      sourceItem.roomLocation ?? "Unknown",
      -amount,
      newSourceQty,
    );
    await _db.logActivity(
      "RESTOCKED (from ${sourceItem.roomLocation})",
      targetItem.name,
      targetItem.roomLocation ?? "Unknown",
      amount,
      targetNewTotal,
    );
    _showSnack(
      "Moved $amount ${targetItem.name} from ${sourceItem.roomLocation} to ${targetItem.roomLocation}",
    );
  }

  String _getExportTimestamp() {
    final now = DateTime.now();
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}_${twoDigits(now.hour)}-${twoDigits(now.minute)}-${twoDigits(now.second)}";
  }

  String _sanitizeName(String name) {
    return name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
  }

  Future<void> _exportInventoryCSV() async {
    final snapshot = await _db.inventoryCollection.get();
    if (snapshot.docs.isEmpty) return;
    String csvData = "Name,Type,Room Location,Quantity\n";
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      String safeName = (data['name'] ?? "").toString().replaceAll(',', '');
      String safeRoom = (data['roomLocation'] ?? "").toString().replaceAll(
        ',',
        '',
      );
      String type = data['type'] ?? "Item";
      String qty = (data['quantity'] ?? 0).toString();
      csvData += "$safeName,$type,$safeRoom,$qty\n";
    }
    final timestamp = _getExportTimestamp();
    final safeInvName = _sanitizeName(_householdName);
    await _shareFile(csvData, "${safeInvName}_axis_inventory_$timestamp.csv");
  }

  Future<void> _exportActivityLogCSV() async {
    final snapshot = await _db.logCollection
        .orderBy('timestamp', descending: true)
        .get();
    if (snapshot.docs.isEmpty) {
      _showSnack("Log is empty!");
      return;
    }
    String csvData = "Timestamp,Action,Item Name,Room,Change,Total,Notes\n";
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      String safeTs = (data['timestamp'] ?? "").toString();
      String safeAction = (data['action'] ?? "").toString().replaceAll(
        ',',
        ';',
      );
      String safeItem = (data['item'] ?? "").toString().replaceAll(',', ';');
      String safeRoom = (data['room'] ?? "").toString().replaceAll(',', ';');
      String safeChange = (data['change'] ?? "").toString();
      String safeTotal = (data['total'] ?? "").toString();

      String rawNotes = data['notes'] ?? data['note'] ?? "";
      String safeNotes = rawNotes.toString().replaceAll(',', ';');

      csvData +=
          "$safeTs,$safeAction,$safeItem,$safeRoom,$safeChange,$safeTotal,$safeNotes\n";
    }
    final timestamp = _getExportTimestamp();
    final safeInvName = _sanitizeName(_householdName);
    await _shareFile(
      csvData,
      "${safeInvName}_axis_activity_log_$timestamp.csv",
    );
  }

  Future<void> _shareFile(String content, String fileName) async {
    if (!mounted) return;
    final directory = await getTemporaryDirectory();
    final path = "${directory.path}/$fileName";
    final file = File(path);
    await file.writeAsString(content);

    final box = context.findRenderObject() as RenderBox?;
    await Share.shareXFiles(
      [XFile(path)],
      text: 'Exported from Axis',
      sharePositionOrigin: box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null,
    );
  }

  void _showExportMenu() {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (ctx) {
        final isLandscape =
            MediaQuery.of(ctx).orientation == Orientation.landscape;

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: theme.cardColor,
          title: Text(
            "Export Data",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLandscape)
                  Row(
                    children: [
                      Expanded(
                        child: _buildExportTile(
                          theme,
                          icon: Icons.table_view,
                          title: "Inventory CSV",
                          subtitle: "Current stock list",
                          onTap: () {
                            Navigator.pop(ctx);
                            _exportInventoryCSV();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildExportTile(
                          theme,
                          icon: Icons.history,
                          title: "Activity Log CSV",
                          subtitle: "History of changes & notes",
                          onTap: () {
                            Navigator.pop(ctx);
                            _exportActivityLogCSV();
                          },
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildExportTile(
                        theme,
                        icon: Icons.table_view,
                        title: "Inventory CSV",
                        subtitle: "Current stock list",
                        onTap: () {
                          Navigator.pop(ctx);
                          _exportInventoryCSV();
                        },
                      ),
                      const SizedBox(height: 10),
                      _buildExportTile(
                        theme,
                        icon: Icons.history,
                        title: "Activity Log CSV",
                        subtitle: "History of changes & notes",
                        onTap: () {
                          Navigator.pop(ctx);
                          _exportActivityLogCSV();
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                "Cancel",
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildExportTile(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
          color: theme.colorScheme.surface.withOpacity(0.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: theme.colorScheme.primary, size: 24),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.download_rounded,
              color: theme.colorScheme.onSurface.withOpacity(0.3),
            ),
          ],
        ),
      ),
    );
  }

  void _showNameInputDialog({
    required bool isRoom,
    required List<String> rooms,
    required List<String> existingItemNames,
  }) {
    final TextEditingController roomNameController = TextEditingController();
    TextEditingController? autocompleteController;
    String? selectedRoom = (!isRoom && rooms.isNotEmpty) ? rooms.first : null;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Theme(
              data: Theme.of(context),
              child: AlertDialog(
                backgroundColor: Theme.of(context).cardColor,
                title: Text(
                  isRoom ? "New Room" : "New Item",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isRoom)
                      TextField(
                        controller: roomNameController,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        decoration: InputDecoration(
                          hintText: "Enter Room Name",
                          hintStyle: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      Autocomplete<String>(
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text == '')
                            return const Iterable<String>.empty();
                          return existingItemNames.where(
                            (String option) => option.toLowerCase().contains(
                              textEditingValue.text.toLowerCase(),
                            ),
                          );
                        },
                        fieldViewBuilder:
                            (
                              context,
                              textEditingController,
                              focusNode,
                              onFieldSubmitted,
                            ) {
                              autocompleteController = textEditingController;
                              return TextField(
                                controller: textEditingController,
                                focusNode: focusNode,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                                decoration: InputDecoration(
                                  hintText: "Enter Item Name",
                                  hintStyle: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              );
                            },
                      ),
                    const SizedBox(height: 20),
                    if (!isRoom) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Select Room:",
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      DropdownButton<String>(
                        value: selectedRoom,
                        dropdownColor: Theme.of(context).cardColor,
                        isExpanded: true,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        items: rooms
                            .map(
                              (String room) => DropdownMenuItem<String>(
                                value: room,
                                child: Text(room),
                              ),
                            )
                            .toList(),
                        onChanged: (String? newValue) =>
                            setState(() => selectedRoom = newValue),
                      ),
                    ],
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
                    onPressed: () => Navigator.pop(context),
                  ),
                  TextButton(
                    child: Text(
                      "Save",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      final String enteredName = isRoom
                          ? roomNameController.text.trim()
                          : (autocompleteController?.text.trim() ?? "");
                      if (enteredName.isNotEmpty) {
                        _addItem(
                          enteredName,
                          isRoom ? "Room" : "Item",
                          selectedRoom,
                        );
                        Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showMembersDialog(String householdId) {
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<DocumentSnapshot>(
        future: _firestore.collection('households').doc(householdId).get(),
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox();
          final data = snap.data!.data() as Map<String, dynamic>;
          final ownerId = data['owner'];

          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _db.getHouseholdMembers(householdId),
            builder: (context, membersSnap) {
              if (!membersSnap.hasData)
                return const AlertDialog(
                  content: SizedBox(
                    height: 50,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              final members = membersSnap.data!;
              return AlertDialog(
                title: const Text("Shared With"),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: members.length,
                    separatorBuilder: (c, i) => const Divider(),
                    itemBuilder: (c, i) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(members[i]['displayName']),
                      subtitle: Text(
                        members[i]['uid'] == ownerId
                            ? "Owner"
                            : members[i]['email'],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Close"),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final topPadding = isLandscape ? 20.0 : 132.0;
    final currentId = _db.currentHouseholdId;

    return StreamBuilder<List<InventoryItem>>(
      stream: _inventoryStream,
      builder: (context, invSnapshot) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _logStream,
          builder: (context, logSnapshot) {
            if (invSnapshot.connectionState == ConnectionState.waiting ||
                logSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Colors.transparent,
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final inventoryList = invSnapshot.data ?? [];
            final logs = logSnapshot.data ?? [];

            final roomList = inventoryList
                .where((element) => element.type == "Room")
                .toList();
            final roomNames = roomList.map((e) => e.name).toList();
            final existingItemNames = inventoryList
                .where((i) => i.type == 'Item')
                .map((i) => i.name)
                .toSet()
                .toList();

            return Scaffold(
              backgroundColor: Colors.transparent,
              floatingActionButton: ValueListenableBuilder<bool>(
                valueListenable: _showFabNotifier,
                builder: (context, isVisible, child) {
                  return AnimatedSlide(
                    duration: const Duration(milliseconds: 250),
                    offset: isVisible ? Offset.zero : const Offset(0, 2),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: isVisible ? 1.0 : 0.0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (_isFabMenuOpen) ...[
                            FloatingActionButton.extended(
                              heroTag: 'add_room_fab',
                              onPressed: () {
                                setState(() => _isFabMenuOpen = false);
                                _showNameInputDialog(
                                  isRoom: true,
                                  rooms: roomNames,
                                  existingItemNames: existingItemNames,
                                );
                              },
                              backgroundColor: const Color(0xFF1E1E1E),
                              icon: const Icon(
                                Icons.meeting_room,
                                color: Color(0xFF00C897),
                              ),
                              label: const Text(
                                "Add Room",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            FloatingActionButton.extended(
                              heroTag: 'add_item_fab',
                              onPressed: () {
                                setState(() => _isFabMenuOpen = false);
                                _showNameInputDialog(
                                  isRoom: false,
                                  rooms: roomNames,
                                  existingItemNames: existingItemNames,
                                );
                              },
                              backgroundColor: const Color(0xFF1E1E1E),
                              icon: const Icon(
                                Icons.category,
                                color: Color(0xFF00C897),
                              ),
                              label: const Text(
                                "Add Item",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 15),
                          ],
                          FloatingActionButton(
                            heroTag: 'inventory_fab_main',
                            onPressed: () => setState(
                              () => _isFabMenuOpen = !_isFabMenuOpen,
                            ),
                            backgroundColor: theme.colorScheme.primary,
                            child: Icon(
                              _isFabMenuOpen ? Icons.close : Icons.add,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              body: Padding(
                padding: EdgeInsets.fromLTRB(20, topPadding, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  _householdName,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                              if (_isShared) ...[
                                const SizedBox(width: 10),
                                GestureDetector(
                                  onTap: () => _showMembersDialog(currentId!),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary
                                          .withOpacity(0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.group,
                                      size: 20,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.history,
                                color: theme.iconTheme.color,
                              ),
                              onPressed: () async => await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ActivityLogPage(),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _showExportMenu(),
                              icon: Icon(
                                Icons.download,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      "Track your items",
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: inventoryList.isEmpty
                          ? Center(
                              child: Text(
                                "Click + to add",
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                // INCREASED TO 420 TO PREVENT SQUISHING / EARLY JUMP TO 4 COLUMNS
                                int crossAxisCount =
                                    (constraints.maxWidth / 420).floor();
                                if (crossAxisCount < 1) crossAxisCount = 1;

                                return NotificationListener<
                                  UserScrollNotification
                                >(
                                  onNotification: (notification) {
                                    if (notification.direction ==
                                        ScrollDirection.reverse) {
                                      if (_showFabNotifier.value) {
                                        _showFabNotifier.value = false;
                                        if (_isFabMenuOpen)
                                          setState(
                                            () => _isFabMenuOpen = false,
                                          );
                                      }
                                    } else if (notification.direction ==
                                        ScrollDirection.forward) {
                                      if (!_showFabNotifier.value) {
                                        _showFabNotifier.value = true;
                                      }
                                    }
                                    return true;
                                  },
                                  child: ListView.builder(
                                    padding: const EdgeInsets.only(bottom: 80),
                                    itemCount: roomList.length,
                                    itemBuilder: (context, index) {
                                      final room = roomList[index];
                                      final roomItems = inventoryList
                                          .where(
                                            (item) =>
                                                item.type == "Item" &&
                                                item.roomLocation == room.name,
                                          )
                                          .toList();
                                      final isNotifActive = !_mutedRooms
                                          .contains(room.name);

                                      List<List<InventoryItem>> columns =
                                          List.generate(
                                            crossAxisCount,
                                            (_) => [],
                                          );
                                      for (
                                        int i = 0;
                                        i < roomItems.length;
                                        i++
                                      ) {
                                        columns[i % crossAxisCount].add(
                                          roomItems[i],
                                        );
                                      }

                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          GestureDetector(
                                            onLongPress: () =>
                                                _confirmDelete(room),
                                            child: Container(
                                              margin: const EdgeInsets.only(
                                                top: 35,
                                                bottom: 16,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: theme.dividerColor
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: theme.dividerColor,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.meeting_room,
                                                    color: theme
                                                        .colorScheme
                                                        .primary,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    room.name,
                                                    style: TextStyle(
                                                      color: theme
                                                          .colorScheme
                                                          .onSurface,
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  if (isNotifActive)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            left: 8.0,
                                                          ),
                                                      child: Icon(
                                                        Icons
                                                            .notifications_active,
                                                        size: 14,
                                                        color: theme
                                                            .colorScheme
                                                            .primary
                                                            .withOpacity(0.7),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          if (roomItems.isEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 20,
                                                bottom: 10,
                                              ),
                                              child: Text(
                                                "No items yet.",
                                                style: TextStyle(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                  fontStyle: FontStyle.italic,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            )
                                          else
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: List.generate(crossAxisCount, (
                                                colIndex,
                                              ) {
                                                return Expanded(
                                                  child: Padding(
                                                    padding: EdgeInsets.only(
                                                      right:
                                                          colIndex <
                                                              crossAxisCount - 1
                                                          ? 12.0
                                                          : 0.0,
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: columns[colIndex].map((
                                                        item,
                                                      ) {
                                                        return Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                bottom: 12.0,
                                                              ),
                                                          child: _InventoryItemCard(
                                                            item: item,
                                                            logs: logs,
                                                            onUseOne: () =>
                                                                _confirmUseOne(
                                                                  item,
                                                                  logs,
                                                                ),
                                                            onRestock: () =>
                                                                _showQuantityDialog(
                                                                  item,
                                                                  inventoryList,
                                                                ),
                                                            onDelete: () =>
                                                                _confirmDelete(
                                                                  item,
                                                                ),
                                                          ),
                                                        );
                                                      }).toList(),
                                                    ),
                                                  ),
                                                );
                                              }),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ==========================================
// FULL PAGE: SMART MISSING USAGES PROMPT
// ==========================================
class MissingUsagesPage extends StatefulWidget {
  final InventoryItem item;
  final List<DateTime> usageHistory;
  final DateTime lastUse;
  final DateTime today;
  final List<DateTime> proposed;
  final int missingCount;
  final int currentQty;
  final double avgDays;

  const MissingUsagesPage({
    super.key,
    required this.item,
    required this.usageHistory,
    required this.lastUse,
    required this.today,
    required this.proposed,
    required this.missingCount,
    required this.currentQty,
    required this.avgDays,
  });

  @override
  State<MissingUsagesPage> createState() => _MissingUsagesPageState();
}

class _MissingUsagesPageState extends State<MissingUsagesPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    List<DateTime> allDates = [
      ...widget.usageHistory,
      ...widget.proposed,
      widget.today,
    ];
    allDates.sort();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Color(0xFF00C897)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      color: Color(0xFF00C897),
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Axis found a discrepancy.",
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Text(
                  "It's been ${widget.today.difference(widget.lastUse).inDays} days since you last logged '${widget.item.name}', but you usually use it every ${widget.avgDays.toStringAsFixed(1)} days.",
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Did you forget to log ${widget.missingCount} usage(s)?",
                  style: const TextStyle(
                    color: Colors.deepPurpleAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: Center(
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: isLandscape ? Axis.horizontal : Axis.vertical,
                padding: const EdgeInsets.all(40),
                child: CustomPaint(
                  painter: MissingGraphPainter(
                    allDates: allDates,
                    proposed: widget.proposed,
                    lastUse: widget.lastUse,
                    today: widget.today,
                    mainColor: theme.colorScheme.primary,
                    proposedColor: Colors.deepPurpleAccent,
                    textColor: theme.colorScheme.onSurface,
                    isHorizontal: isLandscape,
                  ),
                  size: isLandscape
                      ? Size(allDates.length * 120.0, 300)
                      : Size(300, allDates.length * 120.0),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(30.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      side: BorderSide(
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(
                          0.5,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: Text(
                      "No, just today",
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepPurpleAccent,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      side: const BorderSide(
                        color: Colors.deepPurpleAccent,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: Text(
                      "Yes, log missed (-${widget.missingCount})",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MissingGraphPainter extends CustomPainter {
  final List<DateTime> allDates;
  final List<DateTime> proposed;
  final DateTime lastUse;
  final DateTime today;
  final Color mainColor;
  final Color proposedColor;
  final Color textColor;
  final bool isHorizontal;

  MissingGraphPainter({
    required this.allDates,
    required this.proposed,
    required this.lastUse,
    required this.today,
    required this.mainColor,
    required this.proposedColor,
    required this.textColor,
    required this.isHorizontal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (allDates.length < 2) return;

    final Paint linePaint = Paint()
      ..color = textColor.withOpacity(0.2)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final Paint borderPaint = Paint()
      ..color = textColor.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;

    final textStyle = TextStyle(
      color: textColor,
      fontSize: 12,
      fontWeight: FontWeight.bold,
    );

    final subTextStyle = TextStyle(
      color: textColor.withOpacity(0.6),
      fontSize: 10,
    );

    double step = isHorizontal
        ? size.width / (allDates.length)
        : size.height / (allDates.length);

    if (step < 80) step = 80;

    for (int i = 0; i < allDates.length; i++) {
      final double progress = i * step;
      final Offset center = isHorizontal
          ? Offset(progress + 40, size.height / 2)
          : Offset(size.width / 2, progress + 40);

      bool isProposed = proposed.contains(allDates[i]);
      Color dotColor = isProposed ? proposedColor : mainColor;

      if (i < allDates.length - 1) {
        final double nextProgress = (i + 1) * step;
        final Offset nextCenter = isHorizontal
            ? Offset(nextProgress + 40, size.height / 2)
            : Offset(size.width / 2, nextProgress + 40);

        canvas.drawLine(center, nextCenter, linePaint);

        final int daysDiff = allDates[i + 1].difference(allDates[i]).inDays;
        final String gapText = "$daysDiff days";

        final TextSpan span = TextSpan(text: gapText, style: subTextStyle);
        final TextPainter tp = TextPainter(
          text: span,
          textDirection: ui.TextDirection.ltr,
        );
        tp.layout();

        final Offset midPoint = Offset(
          (center.dx + nextCenter.dx) / 2,
          (center.dy + nextCenter.dy) / 2,
        );

        final Offset textOffset = isHorizontal
            ? Offset(midPoint.dx - (tp.width / 2), midPoint.dy - 20)
            : Offset(midPoint.dx + 15, midPoint.dy - (tp.height / 2));

        tp.paint(canvas, textOffset);
      }

      canvas.drawCircle(center, 8, borderPaint);
      canvas.drawCircle(center, 5, Paint()..color = dotColor);

      String prefix = "";
      if (allDates[i] == lastUse) prefix = "Last Log: ";
      if (allDates[i] == today) prefix = "Today: ";

      final String dateText = prefix + DateFormat('MMM d').format(allDates[i]);
      final TextSpan dSpan = TextSpan(
        text: dateText,
        style: textStyle.copyWith(
          color: isProposed ? proposedColor : textColor,
        ),
      );

      final TextPainter dTp = TextPainter(
        text: dSpan,
        textDirection: ui.TextDirection.ltr,
      );
      dTp.layout();

      final Offset labelOffset = isHorizontal
          ? Offset(center.dx - (dTp.width / 2), center.dy + 20)
          : Offset(center.dx - dTp.width - 20, center.dy - (dTp.height / 2));

      dTp.paint(canvas, labelOffset);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// --- NEW EXPANDABLE CARD WITH STATS ---
class _InventoryItemCard extends StatefulWidget {
  final InventoryItem item;
  final List<Map<String, dynamic>> logs;
  final VoidCallback onUseOne;
  final VoidCallback onRestock;
  final VoidCallback onDelete;

  const _InventoryItemCard({
    required this.item,
    required this.logs,
    required this.onUseOne,
    required this.onRestock,
    required this.onDelete,
  });

  @override
  State<_InventoryItemCard> createState() => _InventoryItemCardState();
}

class _InventoryItemCardState extends State<_InventoryItemCard> {
  bool _isExpanded = false;

  DateTime? _parseDate(String dateStr) {
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      try {
        List<String> parts = dateStr.trim().split(' ');
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

  String _formatSimpleDate(DateTime d) {
    return "${d.month}/${d.day}/${d.year}";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();

    // Calculate stats identical to stats_page.dart
    List<DateTime> usageDates = [];
    for (var log in widget.logs) {
      String logName = log['item'] ?? "";
      String logRoom = log['room'] ?? "";
      String action = log['action'] ?? "";
      String timestampStr = log['timestamp'] ?? "";

      bool matchesItem = logName == widget.item.name;
      bool matchesRoom =
          logRoom == widget.item.roomLocation || logRoom == "N/A";
      bool isUsage = action.contains("USED");

      if (matchesItem && matchesRoom && isUsage) {
        DateTime? dt = _parseDate(timestampStr);
        if (dt != null) usageDates.add(dt);
      }
    }
    usageDates.sort();

    bool hasEnough = usageDates.length >= 2;
    double avgDays = 0.0;
    int daysLeft = 0;
    DateTime? runoutDate;

    if (hasEnough) {
      DateTime firstUse = usageDates.first;
      DateTime lastUse = usageDates.last;
      int totalSpan = lastUse.difference(firstUse).inDays;
      if (totalSpan == 0) totalSpan = 1;
      int intervals = usageDates.length - 1;
      if (intervals < 1) intervals = 1;
      avgDays = totalSpan / intervals;

      double stockDuration = (widget.item.quantity + 1) * avgDays;
      int daysSinceLast = now.difference(lastUse).inDays;
      daysLeft = (stockDuration - daysSinceLast).round();
      runoutDate = now.add(Duration(days: daysLeft));
    }

    // Determine visual status
    Color statusColor;
    String bigText;
    String subText;

    if (hasEnough) {
      if (daysLeft < 0) {
        statusColor = Colors.redAccent;
        bigText = "Due";
        subText = "Overdue";
      } else if (daysLeft < 7) {
        statusColor = Colors.redAccent;
        bigText = "$daysLeft";
        subText = "Days";
      } else if (daysLeft < 30) {
        statusColor = Colors.orangeAccent;
        bigText = "$daysLeft";
        subText = "Days";
      } else {
        statusColor = theme.colorScheme.primary;
        bigText = "$daysLeft";
        subText = "Days";
      }
    } else {
      statusColor = theme.colorScheme.onSurfaceVariant.withOpacity(0.3);
      bigText = "?";
      subText = "N/A";
    }

    return GestureDetector(
      onLongPress: widget.onDelete,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          children: [
            // Main Tile Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // Leading Stats Indicators
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: statusColor, width: 2),
                          color: statusColor.withOpacity(0.1),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              bigText,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            if (subText != "N/A" && bigText != "Due")
                              Text(
                                subText,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 9,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Stock Quantity Badge
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Stock",
                            style: TextStyle(
                              fontSize: 9,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            "${widget.item.quantity}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  // Clickable Item Name Area
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          _isExpanded = !_isExpanded;
                        });
                      },
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.item.name,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            _isExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Trailing Action Buttons
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.remove_circle,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onPressed: widget.onUseOne,
                        tooltip: "Use One",
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.add,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onPressed: widget.onRestock,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Expanded Information Area
            if (_isExpanded) ...[
              Divider(height: 1, color: theme.dividerColor.withOpacity(0.5)),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: theme.dividerColor.withOpacity(0.05),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(15),
                    bottomRight: Radius.circular(15),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hasEnough) ...[
                            Text(
                              "Rate: 1 every ${avgDays.toStringAsFixed(1)} days",
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Empty Date: ${_formatSimpleDate(runoutDate!)}",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ] else
                            Text(
                              "Needs 2+ usages for stats (Used ${usageDates.length})",
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.show_chart,
                        color: theme.colorScheme.primary,
                      ),
                      tooltip: "View History Graph",
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ItemGraphPage(
                              itemName: widget.item.name,
                              usageHistory: usageDates,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ==========================================
// MOVED GRAPH LOGIC BELOW
// ==========================================

class ItemGraphPage extends StatefulWidget {
  final String itemName;
  final List<DateTime> usageHistory;

  const ItemGraphPage({
    super.key,
    required this.itemName,
    required this.usageHistory,
  });

  @override
  State<ItemGraphPage> createState() => _ItemGraphPageState();
}

class _ItemGraphPageState extends State<ItemGraphPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final sortedData = List<DateTime>.from(widget.usageHistory)..sort();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.itemName),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
        titleTextStyle: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: Center(
        child: sortedData.isEmpty
            ? Text(
                "No Data",
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              )
            : SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: isLandscape ? Axis.horizontal : Axis.vertical,
                padding: const EdgeInsets.all(40),
                child: CustomPaint(
                  painter: GraphTimelinePainter(
                    dates: sortedData,
                    color: theme.colorScheme.primary,
                    textColor: theme.colorScheme.onSurface,
                    lineColor: theme.dividerColor,
                    isHorizontal: isLandscape,
                  ),
                  size: isLandscape
                      ? Size(sortedData.length * 120.0, 300)
                      : Size(300, sortedData.length * 120.0),
                ),
              ),
      ),
    );
  }
}

class GraphTimelinePainter extends CustomPainter {
  final List<DateTime> dates;
  final Color color;
  final Color textColor;
  final Color lineColor;
  final bool isHorizontal;

  GraphTimelinePainter({
    required this.dates,
    required this.color,
    required this.textColor,
    required this.lineColor,
    required this.isHorizontal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final Paint dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final Paint borderPaint = Paint()
      ..color = textColor.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;

    final textStyle = TextStyle(
      color: textColor,
      fontSize: 12,
      fontWeight: FontWeight.bold,
    );

    final subTextStyle = TextStyle(
      color: textColor.withOpacity(0.6),
      fontSize: 10,
    );

    double step = isHorizontal
        ? size.width / (dates.length)
        : size.height / (dates.length);

    if (step < 80) step = 80;

    for (int i = 0; i < dates.length; i++) {
      final double progress = i * step;
      final Offset center = isHorizontal
          ? Offset(progress + 40, size.height / 2)
          : Offset(size.width / 2, progress + 40);

      if (i < dates.length - 1) {
        final double nextProgress = (i + 1) * step;
        final Offset nextCenter = isHorizontal
            ? Offset(nextProgress + 40, size.height / 2)
            : Offset(size.width / 2, nextProgress + 40);

        canvas.drawLine(center, nextCenter, linePaint);

        final int daysDiff = dates[i + 1].difference(dates[i]).inDays;
        final String gapText = "$daysDiff days";

        final TextSpan span = TextSpan(text: gapText, style: subTextStyle);
        final TextPainter tp = TextPainter(
          text: span,
          textDirection: ui.TextDirection.ltr,
        );
        tp.layout();

        final Offset midPoint = Offset(
          (center.dx + nextCenter.dx) / 2,
          (center.dy + nextCenter.dy) / 2,
        );

        final Offset textOffset = isHorizontal
            ? Offset(midPoint.dx - (tp.width / 2), midPoint.dy - 20)
            : Offset(midPoint.dx + 15, midPoint.dy - (tp.height / 2));

        tp.paint(canvas, textOffset);
      }

      canvas.drawCircle(center, 8, borderPaint);
      canvas.drawCircle(center, 5, dotPaint);

      final String dateText = DateFormat('MMM d').format(dates[i]);
      final TextSpan dSpan = TextSpan(text: dateText, style: textStyle);
      final TextPainter dTp = TextPainter(
        text: dSpan,
        textDirection: ui.TextDirection.ltr,
      );
      dTp.layout();

      final Offset labelOffset = isHorizontal
          ? Offset(center.dx - (dTp.width / 2), center.dy + 20)
          : Offset(center.dx - dTp.width - 20, center.dy - (dTp.height / 2));

      dTp.paint(canvas, labelOffset);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
