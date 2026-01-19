import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/inventory_item.dart';
import '../services/firestore_service.dart';

// --- BACKGROUND FUNCTIONS (ISOLATE LOGIC) ---
DateTime? _parseDateStatic(String dateStr) {
  try {
    return DateTime.parse(dateStr);
  } catch (_) {
    return null;
  }
}

Map<String, List<Map<String, dynamic>>> _computeHomeAlerts(
  Map<String, dynamic> input,
) {
  final List<dynamic> rawItems = input['items'];
  final List<dynamic> rawLogs = input['logs'];
  final int runoutThreshold = input['threshold'];
  final Set<String> ignored = Set<String>.from(input['ignored']);

  final bool runoutEnabled = true;
  final bool usageEnabled = true;

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

      bool isRoomMutedForRunout =
          item.roomLocation != null && runoutMuted.contains(item.roomLocation);
      bool showRestock = runoutEnabled && !isRoomMutedForRunout;

      if (showRestock && daysLeft < runoutThreshold) {
        tempRestock.add({'item': item, 'daysLeft': daysLeft});
      }

      bool isRoomMutedForUsage =
          item.roomLocation != null && usageMuted.contains(item.roomLocation);
      bool showUsage = usageEnabled && !isRoomMutedForUsage;

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
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with AutomaticKeepAliveClientMixin {
  late Timer _timer;
  DateTime _currentTime = DateTime.now();
  bool _isLoading = true;
  String _currentHouseholdName = "Current Household";

  List<Map<String, dynamic>> _cachedItems = [];
  List<Map<String, dynamic>> _cachedLogs = [];
  List<Map<String, dynamic>> _restockAlerts = [];
  List<Map<String, dynamic>> _usageAlerts = [];
  List<Map<String, dynamic>> _currentInvites = [];
  Set<String> _ignoredUsageAlerts = {};

  StreamSubscription? _itemSub;
  StreamSubscription? _logSub;
  late Stream<List<Map<String, dynamic>>> _inviteStream;
  String _activeStreamId = "";
  final FirestoreService _db = FirestoreService();

  List<Map<String, dynamic>> _layoutConfig = [
    {'id': 'hero', 'scale': 1.0},
    {'id': 'feed', 'scale': 1.0},
  ];
  Set<String> _activeHomeTiles = {'invitations'};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadLayoutAndPrefs();
    _loadIgnoredAlerts(); // Load ignored list
    _setupStreams();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _currentTime = DateTime.now());
        final String serviceId = _db.currentHouseholdId ?? "";
        if (serviceId.isNotEmpty && serviceId != _activeStreamId) {
          _setupStreams();
        }
      }
    });

    _inviteStream = _db.getInvitationsStream();
    _inviteStream.listen((invites) async {
      if (mounted) setState(() => _currentInvites = invites);
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    });
  }

  Future<void> _loadLayoutAndPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTiles = prefs.getStringList('axis_active_home_tiles');
    if (savedTiles != null) {
      if (mounted) setState(() => _activeHomeTiles = savedTiles.toSet());
    }

    final jsonStr = prefs.getString('axis_hp_layout_config');
    if (jsonStr != null) {
      try {
        List<dynamic> decoded = jsonDecode(jsonStr);
        if (mounted) {
          setState(() {
            _layoutConfig = decoded
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          });
        }
      } catch (e) {}
    }
  }

  // --- PERSISTENCE FOR IGNORED ALERTS ---
  Future<void> _loadIgnoredAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('axis_ignored_usage_alerts') ?? [];
    if (mounted) setState(() => _ignoredUsageAlerts = list.toSet());
  }

  Future<void> _saveIgnoredAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'axis_ignored_usage_alerts',
      _ignoredUsageAlerts.toList(),
    );
  }
  // --------------------------------------

  @override
  void didUpdateWidget(HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadLayoutAndPrefs();
  }

  @override
  void dispose() {
    _timer.cancel();
    _itemSub?.cancel();
    _logSub?.cancel();
    super.dispose();
  }

  void _setupStreams() async {
    _itemSub?.cancel();
    _logSub?.cancel();
    final String currentId = _db.currentHouseholdId ?? "";
    _activeStreamId = currentId;
    if (currentId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);

    _itemSub = _db.inventoryCollection.snapshots().listen((snapshot) {
      if (!mounted) return;

      // --- CRITICAL FIX: SANITIZE ITEMS ---
      // We must convert Timestamps in ITEMS too, not just LOGS.
      _cachedItems = snapshot.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;

        // Sanitize any timestamp fields in the Item (e.g. lastUpdated)
        data.forEach((key, value) {
          if (value is Timestamp) {
            data[key] = value.toDate().toString();
          }
        });

        return data;
      }).toList();
      // ------------------------------------

      _recalculateAlerts();
    });

    _logSub = _db.logCollection.orderBy('timestamp').snapshots().listen((
      snapshot,
    ) {
      if (!mounted) return;

      // --- SAFE LOG CONVERSION ---
      _cachedLogs = snapshot.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        if (data['timestamp'] is Timestamp) {
          data['timestamp'] = (data['timestamp'] as Timestamp)
              .toDate()
              .toString();
        }
        return data;
      }).toList();
      // ---------------------------

      _recalculateAlerts();
    });

    try {
      final doc = await FirebaseFirestore.instance
          .collection('households')
          .doc(currentId)
          .get();
      if (doc.exists && mounted) {
        setState(
          () => _currentHouseholdName = doc.data()?['name'] ?? "My Inventory",
        );
      }
    } catch (_) {}
  }

  Future<void> _recalculateAlerts() async {
    if (_cachedItems.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      String currentId = _activeStreamId;

      List<String> mutedRunoutList =
          prefs.getStringList('axis_muted_runout_rooms_$currentId') ?? [];
      List<String> mutedUsageList =
          prefs.getStringList('axis_muted_usage_rooms_$currentId') ?? [];

      List<String>? savedThresholds = prefs.getStringList(
        'axis_runout_thresholds_$currentId',
      );
      int runoutThreshold = 7;
      if (savedThresholds != null && savedThresholds.isNotEmpty) {
        runoutThreshold = savedThresholds
            .map((e) => int.parse(e))
            .reduce((a, b) => a > b ? a : b);
      }

      final results = await compute(_computeHomeAlerts, {
        'items': _cachedItems,
        'logs': _cachedLogs,
        'threshold': runoutThreshold,
        'ignored': _ignoredUsageAlerts.toList(),
        'runoutEnabled': true,
        'usageEnabled': true,
        'runoutMuted': mutedRunoutList,
        'usageMuted': mutedUsageList,
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

  void _dismissUsageAlert(InventoryItem item, bool confirmed) {
    if (!confirmed) {
      setState(() {
        _ignoredUsageAlerts.add(item.name);
        _usageAlerts.removeWhere(
          (element) => (element['item'] as InventoryItem).name == item.name,
        );
      });
      _saveIgnoredAlerts(); // Save to prefs
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
    int newQty = (item.quantity - 1).clamp(0, 9999);
    await _db.updateQuantity(item.name, item.roomLocation, newQty);
    await _db.logActivity(
      "USED ONE",
      item.name,
      item.roomLocation ?? "Unknown",
      -1,
      newQty,
    );
    // Auto-ignore after action so it doesn't show again immediately
    if (mounted) {
      setState(() => _ignoredUsageAlerts.add(item.name));
      _saveIgnoredAlerts();
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
    int newQty = item.quantity + quantityToAdd;
    await _db.updateQuantity(item.name, item.roomLocation, newQty);
    await _db.logActivity(
      "RESTOCKED",
      item.name,
      item.roomLocation ?? "Unknown",
      quantityToAdd,
      newQty,
    );
  }

  // --- DIRECT DATABASE OPERATIONS FOR HOME PAGE ---
  Future<void> _handleDecline(String inviteId) async {
    setState(() {
      _currentInvites.removeWhere((i) => i['id'] == inviteId);
    });
    await FirebaseFirestore.instance
        .collection('invitations')
        .doc(inviteId)
        .delete();
  }

  Future<void> _handleAccept(String inviteId, String householdId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _currentInvites.removeWhere((i) => i['id'] == inviteId);
    });

    await FirebaseFirestore.instance
        .collection('households')
        .doc(householdId)
        .update({
          'members': FieldValue.arrayUnion([user.uid]),
        });

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'joinedHouseholds': FieldValue.arrayUnion([householdId]),
    });

    await FirebaseFirestore.instance
        .collection('invitations')
        .doc(inviteId)
        .delete();
  }

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

    List<Widget> feedTiles = [];

    // --- CHECK PREFERENCE BEFORE SHOWING INVITES ---
    if (_activeHomeTiles.contains('invitations')) {
      for (var invite in _currentInvites) {
        feedTiles.add(_buildInviteTile(theme, invite));
      }
    }

    for (var alert in _restockAlerts)
      feedTiles.add(
        _buildRestockAlert(
          theme,
          alert['item'] as InventoryItem,
          alert['daysLeft'] as int,
          _currentHouseholdName,
        ),
      );
    for (var alert in _usageAlerts)
      feedTiles.add(
        _buildUsageCheckAlert(
          theme,
          alert['item'] as InventoryItem,
          alert['expectedDate'] as DateTime,
          _currentHouseholdName,
        ),
      );
    if (feedTiles.isEmpty && !_isLoading)
      feedTiles.add(_buildAllClearTile(theme));

    List<Widget> layoutWidgets = [];
    for (var config in _layoutConfig) {
      String id = config['id'];
      double scale = config['scale'] ?? 1.0;

      double screenWidth = MediaQuery.of(context).size.width;
      double fullWidth = screenWidth - 40;
      double currentWidth = (fullWidth * scale).clamp(100.0, fullWidth);
      double currentHeight = (160 * scale).clamp(80.0, 300.0);

      Widget content;
      if (id == 'hero') {
        content = _buildHeroTile(theme, currentHeight);
      } else {
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            ...feedTiles,
          ],
        );
      }

      layoutWidgets.add(
        SizedBox(
          width: currentWidth,
          height: id == 'hero' ? currentHeight : null,
          child: content,
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: theme.colorScheme.primary,
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 12, runSpacing: 20, children: layoutWidgets),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
      ),
    );
  }

  // ... (Keep the rest of your _build methods - they are UI and work fine) ...
  // (Paste the existing _buildInviteTile, _buildHeroTile, etc. here if re-copying)
  // ...

  // To ensure the file is complete, I will include the existing methods below:

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
                  onPressed: () => _handleDecline(invite['id']),
                  child: const Text("Decline"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () =>
                      _handleAccept(invite['id'], invite['householdId']),
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

  Widget _buildHeroTile(ThemeData theme, double height) {
    String timeString = DateFormat('h:mm').format(_currentTime);
    String amPm = DateFormat('a').format(_currentTime);
    String dateString = DateFormat('MMMM d, y').format(_currentTime);
    String dayString = DateFormat('EEEE').format(_currentTime);
    return Container(
      padding: EdgeInsets.symmetric(vertical: height * 0.1, horizontal: 20),
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
      child: FittedBox(
        fit: BoxFit.scaleDown,
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
              style: TextStyle(
                fontSize: 18,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestockAlert(
    ThemeData theme,
    InventoryItem item,
    int daysLeft,
    String householdName,
  ) {
    Color color = Colors.redAccent;
    List<TextSpan> textSpans;
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
      margin: const EdgeInsets.only(bottom: 12),
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
                    const SizedBox(height: 4),
                    Text(
                      "Inventory: $householdName",
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
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
    String householdName,
  ) {
    Color color = theme.colorScheme.primary;
    String dateStr = DateFormat('MMM d').format(expectedDate);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
                    const SizedBox(height: 2),
                    Text(
                      "Inventory: $householdName",
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
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
