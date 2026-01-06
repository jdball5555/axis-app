import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/inventory_item.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

// --- BACKGROUND FUNCTIONS ---

DateTime? _parseDateStatic(String dateStr) {
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

Map<String, List<Map<String, dynamic>>> _computeHomeAlerts(
  Map<String, dynamic> input,
) {
  final List<dynamic> rawItems = input['items'];
  final List<dynamic> rawLogs = input['logs'];
  final int runoutThreshold = input['threshold'];
  final Set<String> ignored = Set<String>.from(input['ignored']);

  // SEPARATE SETTINGS
  final bool runoutEnabled = input['runoutEnabled'];
  final bool usageEnabled = input['usageEnabled'];
  final Set<String> runoutMuted = Set<String>.from(input['runoutMuted']);
  final Set<String> usageMuted = Set<String>.from(input['usageMuted']);

  List<InventoryItem> items = rawItems
      .map((e) => InventoryItem.fromJson(e))
      .toList();
  DateTime now = DateTime.now();

  List<Map<String, dynamic>> tempRestock = [];
  List<Map<String, dynamic>> tempUsage = [];

  for (var item in items.where((i) => i.type == 'Item')) {
    if (ignored.contains(item.name)) continue;

    List<DateTime> usageDates = [];

    for (var log in rawLogs) {
      // Strict Match: Name + Room
      String logName = log['item'] ?? "";
      String logRoom = log['room'] ?? "";
      bool matchName = logName == item.name;
      bool matchRoom =
          logRoom == (item.roomLocation ?? "Unknown") ||
          logRoom == (item.roomLocation ?? "N/A");

      if (matchName && matchRoom && (log['action'].contains("USED"))) {
        DateTime? dt = _parseDateStatic(log['timestamp'] ?? "");
        if (dt != null) usageDates.add(dt);
      }
    }

    if (usageDates.length >= 2) {
      usageDates.sort();
      DateTime lastUse = usageDates.last;
      int totalSpan = lastUse.difference(usageDates.first).inDays;
      if (totalSpan == 0) totalSpan = 1;
      int intervals = usageDates.length - 1;
      if (intervals < 1) intervals = 1;
      double avgRate = totalSpan / intervals;
      double stockDuration = (item.quantity + 1) * avgRate;
      int daysSinceLast = now.difference(lastUse).inDays;
      int daysLeft = (stockDuration - daysSinceLast).round();

      // --- CHECK RUNOUT ---
      // Only show if feature enabled AND room not muted
      bool showRestock =
          runoutEnabled &&
          (item.roomLocation == null ||
              !runoutMuted.contains(item.roomLocation));
      if (showRestock && daysLeft < runoutThreshold) {
        tempRestock.add({'item': item, 'daysLeft': daysLeft});
      }

      // --- CHECK USAGE ---
      // Only show if feature enabled AND room not muted
      bool showUsage =
          usageEnabled &&
          (item.roomLocation == null ||
              !usageMuted.contains(item.roomLocation));
      if (showUsage && daysSinceLast > (avgRate * 1.5) && item.quantity > 0) {
        tempUsage.add({
          'item': item,
          'expectedDate': lastUse.add(Duration(days: avgRate.round())),
        });
      }
    }
  }

  tempRestock.sort(
    (a, b) => (a['daysLeft'] as int).compareTo(b['daysLeft'] as int),
  );
  return {'restock': tempRestock, 'usage': tempUsage};
}

class HomeTab extends StatefulWidget {
  final bool runoutEnabled;
  final bool usageEnabled;
  final Set<String> runoutMutedRooms;
  final Set<String> usageMutedRooms;

  const HomeTab({
    super.key,
    required this.runoutEnabled,
    required this.usageEnabled,
    required this.runoutMutedRooms,
    required this.usageMutedRooms,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with AutomaticKeepAliveClientMixin {
  late Timer _timer;
  DateTime _currentTime = DateTime.now();
  bool _isLoading = true;
  List<Map<String, dynamic>> _restockAlerts = [];
  List<Map<String, dynamic>> _usageAlerts = [];
  final Set<String> _ignoredUsageAlerts = {};

  // Invite Stream
  late Stream<List<Map<String, dynamic>>> _inviteStream;
  List<Map<String, dynamic>> _currentInvites = [];

  final FirestoreService _db = FirestoreService();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _currentTime = DateTime.now());
    });
    _runSmartLogic();

    // Setup Invite Listener
    _inviteStream = _db.getInvitationsStream();
    _inviteStream.listen((invites) async {
      if (invites.length > _currentInvites.length) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('axis_notif_invites') ?? true) {
          final newInvite = invites.first;
          NotificationService().scheduleSmartAlert(
            id: 888,
            title: "New Inventory Invite",
            body:
                "${newInvite['inviterName']} invited you to ${newInvite['householdName']}",
            date: DateTime.now(),
            time: TimeOfDay.now(),
            payload: 'invite',
          );
        }
      }
      if (mounted) setState(() => _currentInvites = invites);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _runSmartLogic() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String>? savedThresholds = prefs.getStringList(
        'axis_runout_thresholds',
      );

      int runoutThreshold = 7;
      if (savedThresholds != null && savedThresholds.isNotEmpty) {
        runoutThreshold = savedThresholds
            .map((e) => int.parse(e))
            .reduce((a, b) => a > b ? a : b);
      }

      final invSnap = await _db.inventoryCollection.get();
      final logSnap = await _db.logCollection.orderBy('timestamp').get();

      List<Map<String, dynamic>> rawItems = invSnap.docs
          .map((d) => d.data() as Map<String, dynamic>)
          .toList();
      List<Map<String, dynamic>> rawLogs = logSnap.docs
          .map((d) => d.data() as Map<String, dynamic>)
          .toList();

      if (rawItems.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final results = await compute(_computeHomeAlerts, {
        'items': rawItems,
        'logs': rawLogs,
        'threshold': runoutThreshold,
        'ignored': _ignoredUsageAlerts.toList(),

        // PASS SEPARATE CONFIGS
        'runoutEnabled': widget.runoutEnabled,
        'usageEnabled': widget.usageEnabled,
        'runoutMuted': widget.runoutMutedRooms.toList(),
        'usageMuted': widget.usageMutedRooms.toList(),
      });

      if (mounted) {
        setState(() {
          _restockAlerts = results['restock']!;
          _usageAlerts = results['usage']!;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- ACTIONS ---

  void _dismissUsageAlert(InventoryItem item, bool confirmed) {
    if (!confirmed) {
      setState(() {
        _ignoredUsageAlerts.add(item.name);
        _usageAlerts.removeWhere(
          (element) => (element['item'] as InventoryItem).name == item.name,
        );
      });
    } else {
      _processUsageLog(item);
    }
  }

  Future<void> _processUsageLog(InventoryItem item) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => _buildDateDialog(
        ctx,
        item.name,
        "When did you use 1 '${item.name}'?",
        (d, a) {},
      ),
    );

    if (confirm != true) return;
    setState(() => _isLoading = true);

    int newQty = (item.quantity - 1).clamp(0, 9999);
    await _db.updateQuantity(item.name, item.roomLocation, newQty);
    await _db.logActivity(
      "USED ONE",
      item.name,
      item.roomLocation ?? "Unknown",
      -1,
      newQty,
    );

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Logged usage for ${item.name}.")));
      _ignoredUsageAlerts.add(item.name);
      _runSmartLogic();
    }
  }

  Future<void> _processRestock(InventoryItem item) async {
    int quantityToAdd = 1;
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Theme.of(context).cardColor,
            title: Text(
              "Restock ${item.name}",
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "How many are you adding?",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => quantityToAdd > 1
                          ? setDialogState(() => quantityToAdd--)
                          : null,
                      icon: Icon(
                        Icons.remove_circle_outline,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      " $quantityToAdd ",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () => setDialogState(() => quantityToAdd++),
                      icon: Icon(
                        Icons.add_circle_outline,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                child: const Text("Cancel"),
                onPressed: () => Navigator.pop(ctx, false),
              ),
              ElevatedButton(
                child: const Text("Restock"),
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          );
        },
      ),
    );

    if (confirm != true) return;
    setState(() => _isLoading = true);

    int newQty = item.quantity + quantityToAdd;
    await _db.updateQuantity(item.name, item.roomLocation, newQty);
    await _db.logActivity(
      "RESTOCKED",
      item.name,
      item.roomLocation ?? "Unknown",
      quantityToAdd,
      newQty,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Added $quantityToAdd to ${item.name}.")),
      );
      _runSmartLogic();
    }
  }

  // --- WIDGET BUILDERS ---

  Widget _buildDatePickerButton(
    BuildContext context,
    DateTime current,
    Function(DateTime) onPick,
  ) {
    return OutlinedButton.icon(
      icon: Icon(
        Icons.calendar_today,
        color: Theme.of(context).colorScheme.primary,
      ),
      label: Text(DateFormat('MMMM d, yyyy').format(current)),
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: current,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null)
          onPick(DateTime(picked.year, picked.month, picked.day));
      },
    );
  }

  Widget _buildApproximateCheckbox(
    BuildContext context,
    bool value,
    Function(bool) onChanged,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Checkbox(
          value: value,
          activeColor: Theme.of(context).colorScheme.primary,
          onChanged: (val) => onChanged(val ?? false),
        ),
        Text(
          "Date is approximate",
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildDateDialog(
    BuildContext context,
    String title,
    String question,
    Function(DateTime, bool) onConfirmData,
  ) {
    DateTime tempDate = DateTime.now();
    bool tempApprox = false;
    return StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            title,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                question,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              _buildDatePickerButton(
                context,
                tempDate,
                (d) => setDialogState(() => tempDate = d),
              ),
              const SizedBox(height: 15),
              _buildApproximateCheckbox(
                context,
                tempApprox,
                (v) => setDialogState(() => tempApprox = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context, false),
            ),
            ElevatedButton(
              child: const Text("Confirm"),
              onPressed: () {
                onConfirmData(tempDate, tempApprox);
                Navigator.pop(context, true);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final topPadding = isLandscape ? 20.0 : 140.0;

    List<Widget> tiles = [];

    // 1. INVITE TILES (High Priority)
    for (var invite in _currentInvites) {
      tiles.add(_buildInviteTile(theme, invite));
    }

    // 2. ALERT TILES
    for (var alert in _restockAlerts) {
      tiles.add(
        _buildRestockAlert(
          theme,
          alert['item'] as InventoryItem,
          alert['daysLeft'] as int,
        ),
      );
    }
    for (var alert in _usageAlerts) {
      tiles.add(
        _buildUsageCheckAlert(
          theme,
          alert['item'] as InventoryItem,
          alert['expectedDate'] as DateTime,
        ),
      );
    }

    if (tiles.isEmpty && !_isLoading) {
      tiles.add(_buildAllClearTile(theme));
    }

    return Padding(
      padding: EdgeInsets.only(
        top: topPadding,
        left: 20,
        right: 20,
        bottom: 20,
      ),
      child: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: theme.colorScheme.primary,
              ),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroTile(theme),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 15, left: 5),
                    child: Text(
                      "INSIGHTS",
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      int cols = constraints.maxWidth > 600 ? 2 : 1;
                      if (cols == 1) return Column(children: tiles);
                      double spacing = 15.0;
                      double w =
                          (constraints.maxWidth - (spacing * (cols - 1))) /
                          cols;
                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: tiles
                            .map(
                              (w_child) => SizedBox(width: w, child: w_child),
                            )
                            .toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }

  // --- TILE DESIGNS ---

  Widget _buildInviteTile(ThemeData theme, Map<String, dynamic> invite) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mark_email_unread,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "YOU'RE INVITED",
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${invite['inviterName']} invited you to join:",
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      invite['householdName'],
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _db.declineInvitation(invite['id']),
                  child: const Text("Decline"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () =>
                      _db.acceptInvitation(invite['id'], invite['householdId']),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text("Accept"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroTile(ThemeData theme) {
    String timeString = DateFormat('h:mm').format(_currentTime);
    String amPm = DateFormat('a').format(_currentTime);
    String dateString = DateFormat('MMMM d, y').format(_currentTime);
    String dayString = DateFormat('EEEE').format(_currentTime);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                timeString,
                style: TextStyle(
                  fontSize: 70,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: -2,
                  height: 1,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                amPm,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 2, width: 60, color: theme.dividerColor),
          const SizedBox(height: 10),
          Text(
            dayString.toUpperCase(),
            style: TextStyle(
              fontSize: 14,
              letterSpacing: 3.0,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dateString,
            style: TextStyle(fontSize: 18, color: theme.colorScheme.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _buildRestockAlert(ThemeData theme, InventoryItem item, int daysLeft) {
    Color color = Colors.redAccent;
    List<TextSpan> textSpans;

    // UPDATED TEXT: Include Room Name
    String displayText = "${item.name} (${item.roomLocation ?? 'Unknown'})";

    if (daysLeft <= 0) {
      textSpans = [
        TextSpan(
          text: displayText,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const TextSpan(text: " is "),
        TextSpan(
          text: "OVERDUE",
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
        if (daysLeft < 0) TextSpan(text: " by ${daysLeft.abs()} days"),
        const TextSpan(text: "."),
      ];
    } else {
      textSpans = [
        TextSpan(
          text: displayText,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const TextSpan(text: " runs out in "),
        TextSpan(
          text: "$daysLeft days",
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
        const TextSpan(text: "."),
      ];
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.warning_rounded, color: color, size: 28),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "RESTOCK NEEDED",
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 16,
                          height: 1.2,
                        ),
                        children: textSpans,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_shopping_cart, color: Colors.white),
              label: const Text(
                "Restock Now",
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => _processRestock(item),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageCheckAlert(
    ThemeData theme,
    InventoryItem item,
    DateTime expectedDate,
  ) {
    Color color = theme.colorScheme.primary;
    String dateStr = DateFormat('MMM d').format(expectedDate);
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.history_edu, color: color, size: 28),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "USAGE CHECK",
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // UPDATED TEXT: Include Room Name
                    Text(
                      "Did you use ${item.name} in ${item.roomLocation ?? 'Unknown'}?",
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Expected usage was around $dateStr",
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _dismissUsageAlert(item, false),
                  child: const Text("No / Ignore"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () => _dismissUsageAlert(item, true),
                  child: const Text("Yes, I did"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAllClearTile(ThemeData theme) {
    return Container(
      key: const Key('all_clear'),
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline,
            color: theme.colorScheme.primary,
            size: 40,
          ),
          const SizedBox(height: 10),
          Text(
            "All Systems Normal",
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            "No immediate actions required.",
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
