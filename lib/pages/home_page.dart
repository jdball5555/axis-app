import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/inventory_item.dart';

DateTime? _parseDateStatic(String dateStr) {
  try {
    return DateTime.parse(dateStr);
  } catch (_) {
    try {
      List<String> parts = dateStr.split(' ');
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

Map<String, List<Map<String, dynamic>>> _computeHomeAlerts(
  Map<String, dynamic> input,
) {
  final String invData = input['invData'];
  final List<String> logs = input['logs'];
  final int runoutThreshold = input['threshold'];
  final Set<String> ignored = Set<String>.from(input['ignored']);
  final List<dynamic> jsonList = jsonDecode(invData);
  List<InventoryItem> items = jsonList
      .map((e) => InventoryItem.fromJson(e))
      .toList();
  DateTime now = DateTime.now();
  List<Map<String, dynamic>> tempRestock = [];
  List<Map<String, dynamic>> tempUsage = [];
  for (var item in items.where((i) => i.type == 'Item')) {
    if (ignored.contains(item.name)) continue;
    List<DateTime> usageDates = [];
    for (var line in logs) {
      List<String> parts = line.split('|');
      if (parts.length >= 3) {
        String action = parts[1].trim();
        String name = parts[2].trim();
        if (name == item.name && action == "USED ONE") {
          DateTime? dt = _parseDateStatic(parts[0].trim());
          if (dt != null) usageDates.add(dt);
        }
      }
    }
    if (usageDates.length >= 2) {
      usageDates.sort();
      DateTime lastUse = usageDates.last;
      int totalSpan = lastUse.difference(usageDates.first).inDays;
      if (totalSpan == 0) totalSpan = 1;
      double avgRate = totalSpan / (usageDates.length - 1);
      double stockDuration = (item.quantity + 1) * avgRate;
      int daysSinceLast = now.difference(lastUse).inDays;
      int daysLeft = (stockDuration - daysSinceLast).round();
      if (daysLeft < runoutThreshold) {
        tempRestock.add({'item': item, 'daysLeft': daysLeft});
      }
      double bufferMultiplier = 1.5;
      if (daysSinceLast > (avgRate * bufferMultiplier)) {
        if (item.quantity > 0) {
          tempUsage.add({
            'item': item,
            'expectedDate': lastUse.add(Duration(days: avgRate.round())),
          });
        }
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

class _HomeTabState extends State<HomeTab> {
  late Timer _timer;
  DateTime _currentTime = DateTime.now();
  bool _isLoading = true;
  List<Map<String, dynamic>> _restockAlerts = [];
  List<Map<String, dynamic>> _usageAlerts = [];
  final Set<String> _ignoredUsageAlerts = {};
  final Color _themeTeal = const Color(0xFF00C897);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _currentTime = DateTime.now());
    });
    _runSmartLogic();
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
      final String? invData = prefs.getString('axis_inventory');
      final List<String> logs = prefs.getStringList('axis_activity_log') ?? [];
      if (invData == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final results = await compute(_computeHomeAlerts, {
        'invData': invData,
        'logs': logs,
        'threshold': runoutThreshold,
        'ignored': _ignoredUsageAlerts.toList(),
      });
      if (mounted) {
        setState(() {
          _restockAlerts = results['restock']!;
          _usageAlerts = results['usage']!;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading home logic: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ... (Usage/Restock Log Actions - Paster from prior version, assume same logic) ...
  // Keeping helper functions compact for display...
  Future<void> _processUsageLog(InventoryItem item) async {
    DateTime selectedDate = DateTime.now();
    bool isApproximate = false;
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              title: Text(
                "Log Usage",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "When did you use 1 '${item.name}'?",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    icon: Icon(Icons.calendar_today, color: _themeTeal),
                    label: Text(
                      DateFormat('MMMM d, yyyy').format(selectedDate),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                    onPressed: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        builder: (context, child) {
                          return Theme(data: Theme.of(context), child: child!);
                        },
                      );
                      if (picked != null) {
                        setDialogState(() {
                          final now = DateTime.now();
                          selectedDate = DateTime(
                            picked.year,
                            picked.month,
                            picked.day,
                            now.hour,
                            now.minute,
                          );
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Checkbox(
                        value: isApproximate,
                        activeColor: _themeTeal,
                        checkColor: Colors.black,
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        onChanged: (val) =>
                            setDialogState(() => isApproximate = val ?? false),
                      ),
                      Text(
                        "Date is approximate",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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
                  onPressed: () => Navigator.pop(ctx, false),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _themeTeal,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text("Confirm"),
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirm != true) return;
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final String? invData = prefs.getString('axis_inventory');
    final List<String> logs = prefs.getStringList('axis_activity_log') ?? [];
    if (invData != null) {
      List<dynamic> jsonList = jsonDecode(invData);
      List<InventoryItem> items = jsonList
          .map((e) => InventoryItem.fromJson(e))
          .toList();
      int index = items.indexWhere(
        (i) => i.name == item.name && i.type == 'Item',
      );
      if (index != -1) {
        items[index].quantity = (items[index].quantity - 1).clamp(0, 9999);
        await prefs.setString(
          'axis_inventory',
          jsonEncode(items.map((e) => e.toJson()).toList()),
        );
        String twoDigits(int n) => n.toString().padLeft(2, '0');
        final String timestamp =
            "${selectedDate.year}-${twoDigits(selectedDate.month)}-${twoDigits(selectedDate.day)} ${twoDigits(selectedDate.hour)}:${twoDigits(selectedDate.minute)}:${twoDigits(selectedDate.second)}";
        String note = "Logged from Home";
        if (isApproximate) note += " (Approximate Date)";
        String logEntry =
            "$timestamp|USED ONE|${item.name}|${item.roomLocation ?? 'Unknown'}|-1|${items[index].quantity}|$note";
        logs.add(logEntry);
        await prefs.setStringList('axis_activity_log', logs);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Logged usage for ${item.name}.")),
          );
          _ignoredUsageAlerts.add(item.name);
          _runSmartLogic();
        }
      }
    }
  }

  Future<void> _processRestock(InventoryItem item) async {
    int quantityToAdd = 1;
    DateTime selectedDate = DateTime.now();
    bool isApproximate = false;
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              title: Text(
                "Restock ${item.name}",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
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
                        onPressed: () {
                          if (quantityToAdd > 1)
                            setDialogState(() => quantityToAdd--);
                        },
                        icon: Icon(
                          Icons.remove_circle_outline,
                          color: Theme.of(context).colorScheme.onSurface,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Text(
                        "$quantityToAdd",
                        style: TextStyle(
                          color: _themeTeal,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 20),
                      IconButton(
                        onPressed: () => setDialogState(() => quantityToAdd++),
                        icon: Icon(
                          Icons.add_circle_outline,
                          color: Theme.of(context).colorScheme.onSurface,
                          size: 32,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Restock Date:",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  OutlinedButton.icon(
                    icon: Icon(Icons.calendar_today, color: _themeTeal),
                    label: Text(
                      DateFormat('MMMM d, yyyy').format(selectedDate),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Theme.of(context).dividerColor),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        builder: (context, child) {
                          return Theme(data: Theme.of(context), child: child!);
                        },
                      );
                      if (picked != null) {
                        setDialogState(() {
                          final now = DateTime.now();
                          selectedDate = DateTime(
                            picked.year,
                            picked.month,
                            picked.day,
                            now.hour,
                            now.minute,
                          );
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Checkbox(
                        value: isApproximate,
                        activeColor: _themeTeal,
                        checkColor: Colors.black,
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        onChanged: (val) =>
                            setDialogState(() => isApproximate = val ?? false),
                      ),
                      Text(
                        "Date is approximate",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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
                  onPressed: () => Navigator.pop(ctx, false),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _themeTeal,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text("Restock"),
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirm != true) return;
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final String? invData = prefs.getString('axis_inventory');
    final List<String> logs = prefs.getStringList('axis_activity_log') ?? [];
    if (invData != null) {
      List<dynamic> jsonList = jsonDecode(invData);
      List<InventoryItem> items = jsonList
          .map((e) => InventoryItem.fromJson(e))
          .toList();
      int index = items.indexWhere(
        (i) => i.name == item.name && i.type == 'Item',
      );
      if (index != -1) {
        items[index].quantity += quantityToAdd;
        await prefs.setString(
          'axis_inventory',
          jsonEncode(items.map((e) => e.toJson()).toList()),
        );
        String twoDigits(int n) => n.toString().padLeft(2, '0');
        final String timestamp =
            "${selectedDate.year}-${twoDigits(selectedDate.month)}-${twoDigits(selectedDate.day)} ${twoDigits(selectedDate.hour)}:${twoDigits(selectedDate.minute)}:${twoDigits(selectedDate.second)}";
        String note = "Restocked from Home";
        if (isApproximate) note += " (Approximate Date)";
        String logEntry =
            "$timestamp|RESTOCKED|${item.name}|${item.roomLocation ?? 'Unknown'}|$quantityToAdd|${items[index].quantity}|$note";
        logs.add(logEntry);
        await prefs.setStringList('axis_activity_log', logs);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Added $quantityToAdd to ${item.name}.")),
          );
          _runSmartLogic();
        }
      }
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
    } else {
      _processUsageLog(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final double topPadding = isLandscape ? 20.0 : 140.0;

    List<Widget> dynamicTiles = [];
    for (var alert in _restockAlerts) {
      dynamicTiles.add(
        _buildRestockAlert(
          theme,
          alert['item'] as InventoryItem,
          alert['daysLeft'] as int,
        ),
      );
    }
    for (var alert in _usageAlerts) {
      dynamicTiles.add(
        _buildUsageCheckAlert(
          theme,
          alert['item'] as InventoryItem,
          alert['expectedDate'] as DateTime,
        ),
      );
    }
    if (dynamicTiles.isEmpty && !_isLoading) {
      dynamicTiles.add(_buildAllClearTile(theme));
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
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroTile(theme),
                  const SizedBox(height: 20),
                  if (dynamicTiles.length > 1 ||
                      (dynamicTiles.isNotEmpty &&
                          dynamicTiles[0].key != const Key('all_clear')))
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
                      int columns = constraints.maxWidth > 600 ? 2 : 1;
                      if (columns == 1) return Column(children: dynamicTiles);
                      double spacing = 15.0;
                      double cardWidth =
                          (constraints.maxWidth - (spacing * (columns - 1))) /
                          columns;
                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: dynamicTiles
                            .map((w) => SizedBox(width: cardWidth, child: w))
                            .toList(),
                      );
                    },
                  ),
                ],
              ),
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
    if (daysLeft <= 0) {
      textSpans = [
        TextSpan(
          text: item.name,
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
          text: item.name,
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
                    Text(
                      "Did you use ${item.name}?",
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
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme.dividerColor),
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text("No / Ignore"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _dismissUsageAlert(item, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
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
