import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/inventory_item.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class ConsumptionData {
  String itemName;
  int currentQuantity;
  double avgDaysPerUse;
  int daysUntilRunout;
  bool hasEnoughData;
  int usageCount;
  DateTime? projectedDate;

  ConsumptionData({
    required this.itemName,
    required this.currentQuantity,
    required this.avgDaysPerUse,
    required this.daysUntilRunout,
    required this.hasEnoughData,
    required this.usageCount,
    this.projectedDate,
  });
}

class _StatsPageState extends State<StatsPage> {
  late Future<Map<String, dynamic>> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = _calculateStats();
  }

  @override
  void didUpdateWidget(StatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh stats if the widget updates (e.g. theme change)
    if (oldWidget.key != widget.key) {
      _statsFuture = _calculateStats();
    }
  }

  String _formatSimpleDate(DateTime d) {
    return "${d.month}/${d.day}/${d.year}";
  }

  DateTime? _parseDate(String dateStr) {
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      try {
        // Fallback for space-separated timestamps
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

  Future<Map<String, dynamic>> _calculateStats() async {
    final prefs = await SharedPreferences.getInstance();

    final String? invData = prefs.getString('axis_inventory');
    List<InventoryItem> currentItems = [];
    if (invData != null) {
      final List<dynamic> jsonList = jsonDecode(invData);
      currentItems = jsonList.map((e) => InventoryItem.fromJson(e)).toList();
    }

    final List<String>? logData = prefs.getStringList('axis_activity_log');
    List<String> logs = logData ?? [];

    int tQty = 0;
    Map<String, int> roomCounts = {};

    for (var item in currentItems) {
      if (item.type == 'Room') {
        if (!roomCounts.containsKey(item.name)) roomCounts[item.name] = 0;
      } else if (item.type == 'Item') {
        tQty += item.quantity;
        String loc = item.roomLocation ?? "Unknown";
        roomCounts[loc] = (roomCounts[loc] ?? 0) + item.quantity;
      }
    }

    List<ConsumptionData> calculatedConsumption = [];
    DateTime now = DateTime.now();

    for (var item in currentItems.where((i) => i.type == 'Item')) {
      List<DateTime> usageDates = [];
      for (var line in logs) {
        List<String> parts = line.split('|');
        if (parts.length < 3) continue;
        String timestampStr = parts[0];
        String action = parts[1];
        String name = parts[2];

        // Your logic: Filter for "USED ONE" (or general USED)
        if (name == item.name && (action == "USED ONE" || action == "USED")) {
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
        int totalDaysSpan = lastUse.difference(firstUse).inDays;
        if (totalDaysSpan == 0) totalDaysSpan = 1;

        int intervals = usageDates.length - 1;
        if (intervals < 1) intervals = 1;

        avgDays = totalDaysSpan / intervals;

        double stockDurationDays = (item.quantity + 1) * avgDays;
        int daysSinceLastUse = now.difference(lastUse).inDays;
        daysLeft = (stockDurationDays - daysSinceLastUse).round();
        runoutDate = now.add(Duration(days: daysLeft));
      }

      calculatedConsumption.add(
        ConsumptionData(
          itemName: item.name,
          currentQuantity: item.quantity,
          avgDaysPerUse: avgDays,
          daysUntilRunout: daysLeft,
          hasEnoughData: hasEnough,
          usageCount: usageDates.length,
          projectedDate: runoutDate,
        ),
      );
    }

    calculatedConsumption.sort((a, b) {
      if (a.hasEnoughData && !b.hasEnoughData) return -1;
      if (!a.hasEnoughData && b.hasEnoughData) return 1;
      if (a.hasEnoughData && b.hasEnoughData) {
        return a.daysUntilRunout.compareTo(b.daysUntilRunout);
      }
      return a.itemName.compareTo(b.itemName);
    });

    return {
      'totalQuantity': tQty,
      'itemsPerRoom': roomCounts,
      'consumptionList': calculatedConsumption,
    };
  }

  @override
  Widget build(BuildContext context) {
    // --- THEME HOOKS ---
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final cardColor = theme.cardColor;
    final onSurface = theme.colorScheme.onSurface;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    final dividerColor = theme.dividerColor;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<Map<String, dynamic>>(
        future: _statsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: primaryColor),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Text(
                "Could not load stats.",
                style: TextStyle(color: onSurfaceVariant),
              ),
            );
          }

          final data = snapshot.data!;
          final int totalQuantity = data['totalQuantity'];
          final Map<String, int> itemsPerRoom = data['itemsPerRoom'];
          final List<ConsumptionData> consumptionList = data['consumptionList'];

          final bool isLandscape =
              MediaQuery.of(context).orientation == Orientation.landscape;
          // Keep your padding logic
          final double topPadding = isLandscape ? 20.0 : 140.0;

          return Padding(
            padding: EdgeInsets.fromLTRB(20, topPadding, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "My Inventory Stats",
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  "Usage & Projections",
                  style: TextStyle(color: onSurfaceVariant, fontSize: 14),
                ),
                const SizedBox(height: 20),

                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      int crossAxisCount = 1;
                      if (constraints.maxWidth > 900) {
                        crossAxisCount = 3;
                      } else if (constraints.maxWidth > 600) {
                        crossAxisCount = 2;
                      }

                      double spacing = 15.0;
                      double cardWidth =
                          (constraints.maxWidth -
                              (spacing * (crossAxisCount - 1))) /
                          crossAxisCount;

                      return SingleChildScrollView(
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Projected Runout",
                              style: TextStyle(
                                color: onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              "Based on ((Stock + 1) × Rate) - Days Since Last Use",
                              style: TextStyle(
                                color: onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 15),

                            if (consumptionList.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(20),
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(color: dividerColor),
                                ),
                                child: Text(
                                  "No items to track.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: onSurfaceVariant),
                                ),
                              )
                            else
                              Wrap(
                                spacing: spacing,
                                runSpacing: spacing,
                                children: consumptionList.map((cData) {
                                  Color statusColor;
                                  String bigText;
                                  String subText;

                                  // Determine status & color logic
                                  if (cData.hasEnoughData) {
                                    if (cData.daysUntilRunout < 0) {
                                      statusColor = Colors.redAccent;
                                      bigText = "Due";
                                      subText = "Overdue";
                                    } else if (cData.daysUntilRunout < 7) {
                                      statusColor = Colors.redAccent;
                                      bigText = "${cData.daysUntilRunout}";
                                      subText = "Days";
                                    } else if (cData.daysUntilRunout < 30) {
                                      statusColor = Colors.orangeAccent;
                                      bigText = "${cData.daysUntilRunout}";
                                      subText = "Days";
                                    } else {
                                      statusColor = primaryColor;
                                      bigText = "${cData.daysUntilRunout}";
                                      subText = "Days";
                                    }
                                  } else {
                                    statusColor = theme.disabledColor;
                                    bigText = "?";
                                    subText = "N/A";
                                  }

                                  return SizedBox(
                                    width: cardWidth,
                                    child: Container(
                                      padding: const EdgeInsets.all(15),
                                      decoration: BoxDecoration(
                                        color: cardColor,
                                        borderRadius: BorderRadius.circular(15),
                                        border: Border.all(
                                          // Highlight critical items with colored border
                                          color:
                                              (cData.daysUntilRunout < 7 &&
                                                  cData.hasEnoughData)
                                              ? statusColor.withOpacity(0.5)
                                              : dividerColor,
                                        ),
                                        boxShadow: [
                                          // Subtle glow for critical items
                                          if (cData.daysUntilRunout < 7 &&
                                              cData.hasEnoughData)
                                            BoxShadow(
                                              color: statusColor.withOpacity(
                                                0.1,
                                              ),
                                              blurRadius: 10,
                                              spreadRadius: 1,
                                            ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          // --- Days Remaining Indicator ---
                                          Container(
                                            width: 50,
                                            height: 50,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: statusColor,
                                                width: 2,
                                              ),
                                              color: statusColor.withOpacity(
                                                0.1,
                                              ),
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  bigText,
                                                  style: TextStyle(
                                                    color: statusColor,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: bigText == "Due"
                                                        ? 14
                                                        : 16,
                                                  ),
                                                ),
                                                Text(
                                                  subText,
                                                  style: TextStyle(
                                                    color: onSurface
                                                        .withOpacity(0.6),
                                                    fontSize: 8,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 15),

                                          // --- Text Details ---
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  cData.itemName,
                                                  style: TextStyle(
                                                    color: onSurface,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 4),
                                                if (cData.hasEnoughData) ...[
                                                  Text(
                                                    "Rate: 1 every ${cData.avgDaysPerUse.toStringAsFixed(1)} days",
                                                    style: TextStyle(
                                                      color: onSurfaceVariant,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  if (cData.projectedDate !=
                                                      null)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 2,
                                                          ),
                                                      child: Text(
                                                        "Empty on: ${_formatSimpleDate(cData.projectedDate!)}",
                                                        style: TextStyle(
                                                          color: statusColor,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                ] else
                                                  Text(
                                                    "Needs 2+ uses (Used ${cData.usageCount})",
                                                    style: TextStyle(
                                                      color:
                                                          theme.disabledColor,
                                                      fontSize: 12,
                                                      fontStyle:
                                                          FontStyle.italic,
                                                    ),
                                                  ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  "Reserved Stock: ${cData.currentQuantity}",
                                                  style: TextStyle(
                                                    color: onSurfaceVariant,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),

                            const SizedBox(height: 30),
                            Text(
                              "Room Distribution",
                              style: TextStyle(
                                color: onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 20),

                            if (itemsPerRoom.isEmpty)
                              Center(
                                child: Text(
                                  "No items.",
                                  style: TextStyle(color: onSurfaceVariant),
                                ),
                              )
                            else
                              // Room distribution list
                              ...itemsPerRoom.entries.map((entry) {
                                double percentage = totalQuantity > 0
                                    ? (entry.value / totalQuantity)
                                    : 0.0;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 15),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            entry.key,
                                            style: TextStyle(
                                              color: onSurface,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Text(
                                            "${entry.value} items",
                                            style: TextStyle(
                                              color: primaryColor,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        height: 8,
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: dividerColor,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: percentage,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: primaryColor,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            const SizedBox(height: 80),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
