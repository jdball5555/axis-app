import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../models/inventory_item.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  static String? lastKnownName;
  static bool lastKnownShared = false;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class ConsumptionData {
  String itemName;
  String room;
  int currentQuantity;
  double avgDaysPerUse;
  int daysUntilRunout;
  bool hasEnoughData;
  int usageCount;
  DateTime? projectedDate;
  List<DateTime> history;

  ConsumptionData({
    required this.itemName,
    required this.room,
    required this.currentQuantity,
    required this.avgDaysPerUse,
    required this.daysUntilRunout,
    required this.hasEnoughData,
    required this.usageCount,
    this.projectedDate,
    required this.history,
  });
}

class AggregateStat {
  String itemName;
  int totalQuantity;
  double totalDailyUsageRate;
  int locationCount;
  int activeInUseCount;
  int totalUsageCount;

  AggregateStat({
    required this.itemName,
    this.totalQuantity = 0,
    this.totalDailyUsageRate = 0.0,
    this.locationCount = 0,
    this.activeInUseCount = 0,
    this.totalUsageCount = 0,
  });
}

class _StatsPageState extends State<StatsPage>
    with AutomaticKeepAliveClientMixin {
  final FirestoreService _db = FirestoreService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late Stream<List<InventoryItem>> _inventoryStream;
  late Stream<List<Map<String, dynamic>>> _logStream;

  StreamSubscription<DocumentSnapshot>? _householdSub;
  String _currentSubscribedId = "";
  String _householdName = StatsPage.lastKnownName ?? "My Inventory";
  bool _isShared = StatsPage.lastKnownShared;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _inventoryStream = _db.getInventoryStream();
    _logStream = _db.getLogStream();
    _checkForHouseholdUpdate();
  }

  @override
  void didUpdateWidget(StatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkForHouseholdUpdate();
  }

  @override
  void dispose() {
    _householdSub?.cancel();
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

            StatsPage.lastKnownName = newName;
            StatsPage.lastKnownShared = newShared;

            if (mounted) {
              setState(() {
                _householdName = newName;
                _isShared = newShared;
              });
            }
          }
        });
  }

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
              if (!membersSnap.hasData) {
                return const AlertDialog(
                  content: SizedBox(
                    height: 50,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }
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
    final onSurface = theme.colorScheme.onSurface;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    final primaryColor = theme.colorScheme.primary;
    final cardColor = theme.cardColor;
    final dividerColor = theme.dividerColor;

    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final double topPadding = isLandscape ? 20.0 : 140.0;

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

            final currentItems = invSnapshot.data ?? [];
            final logs = logSnapshot.data ?? [];
            DateTime now = DateTime.now();

            List<ConsumptionData> allConsumption = [];

            for (var item in currentItems.where((i) => i.type == 'Item')) {
              String roomLoc = item.roomLocation ?? "Unknown";

              List<DateTime> usageDates = [];
              for (var log in logs) {
                String logName = log['item'] ?? "";
                String logRoom = log['room'] ?? "";
                String action = log['action'] ?? "";
                String timestampStr = log['timestamp'] ?? "";

                bool matchesItem = logName == item.name;
                bool matchesRoom = logRoom == roomLoc || logRoom == "N/A";
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

                // FORMULA: (qty + 1) * rate
                double stockDuration = (item.quantity + 1) * avgDays;
                int daysSinceLast = now.difference(lastUse).inDays;
                daysLeft = (stockDuration - daysSinceLast).round();
                runoutDate = now.add(Duration(days: daysLeft));
              }

              allConsumption.add(
                ConsumptionData(
                  itemName: item.name,
                  room: roomLoc,
                  currentQuantity: item.quantity,
                  avgDaysPerUse: avgDays,
                  daysUntilRunout: daysLeft,
                  hasEnoughData: hasEnough,
                  usageCount: usageDates.length,
                  projectedDate: runoutDate,
                  history: usageDates,
                ),
              );
            }

            Map<String, AggregateStat> aggregateMap = {};
            Map<String, List<ConsumptionData>> itemsByRoom = {};

            for (var c in allConsumption) {
              itemsByRoom.putIfAbsent(c.room, () => []).add(c);

              if (!aggregateMap.containsKey(c.itemName)) {
                aggregateMap[c.itemName] = AggregateStat(itemName: c.itemName);
              }

              var agg = aggregateMap[c.itemName]!;
              agg.totalQuantity += c.currentQuantity;
              agg.locationCount++;
              agg.totalUsageCount += c.usageCount;

              if (c.currentQuantity > 0) {
                agg.activeInUseCount++;
              }

              if (c.hasEnoughData && c.avgDaysPerUse > 0) {
                agg.totalDailyUsageRate += (1 / c.avgDaysPerUse);
              }
            }

            List<AggregateStat> multiLocationItems = aggregateMap.values
                .where((a) => a.locationCount > 1)
                .toList();

            return Scaffold(
              backgroundColor: Colors.transparent,
              body: Padding(
                padding: EdgeInsets.fromLTRB(20, topPadding, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "$_householdName Stats",
                              style: TextStyle(
                                color: onSurface,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
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
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      "Inventory Forecasting",
                      style: TextStyle(color: onSurfaceVariant, fontSize: 14),
                    ),
                    const SizedBox(height: 20),

                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (multiLocationItems.isNotEmpty) ...[
                              Text(
                                "Household Overview",
                                style: TextStyle(
                                  color: primaryColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                "Aggregate stock across all rooms",
                                style: TextStyle(
                                  color: onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 15),
                              _buildAggregateGrid(
                                context,
                                multiLocationItems,
                                now,
                              ),
                              const SizedBox(height: 30),
                            ],

                            Text(
                              "Room Breakdown",
                              style: TextStyle(
                                color: onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 15),

                            if (itemsByRoom.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(20),
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: cardColor.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(color: dividerColor),
                                ),
                                child: Text(
                                  "Not enough data yet.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: onSurfaceVariant),
                                ),
                              )
                            else
                              ...itemsByRoom.entries.map((entry) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 4,
                                        bottom: 8,
                                      ),
                                      child: Text(
                                        entry.key,
                                        style: TextStyle(
                                          color: onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    _buildConsumptionGrid(context, entry.value),
                                    const SizedBox(height: 20),
                                  ],
                                );
                              }),

                            const SizedBox(height: 80),
                          ],
                        ),
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

  Widget _buildAggregateGrid(
    BuildContext context,
    List<AggregateStat> items,
    DateTime now,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int columns = constraints.maxWidth > 600 ? 2 : 1;
        double spacing = 15.0;
        double itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items.map((agg) {
            bool hasEnoughData = agg.totalDailyUsageRate > 0;
            String bigText = "?";
            String subText = "N/A";
            Color statusColor = Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withOpacity(0.3);
            String projectedStr =
                "Needs 2+ usages (Used ${agg.totalUsageCount})";

            if (hasEnoughData) {
              // Formula: (TotalQty + 1) / DailyRate - but Aggregate calculates differently above.
              // Let's rely on totalQuantity / rate for aggregate rough estimate
              // Or better, let the individual items sum up.
              // Here we use a simplified projection for aggregate.
              double daysLeftDouble =
                  (agg.totalQuantity + 1) / agg.totalDailyUsageRate;
              int daysLeft = daysLeftDouble.round();
              DateTime projectedDate = now.add(Duration(days: daysLeft));

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
                statusColor = Theme.of(context).colorScheme.primary;
                bigText = "$daysLeft";
                subText = "Days";
              }
              projectedStr = "Empty: ${_formatSimpleDate(projectedDate)}";
            }

            return SizedBox(
              width: itemWidth,
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Theme.of(context).dividerColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
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
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            subText,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            agg.itemName,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            projectedStr,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (hasEnoughData)
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: "Stock: ${agg.totalQuantity} ",
                                  ),
                                  TextSpan(
                                    text: "(+ 1 in use)",
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            )
                          else
                            Text(
                              "Stock: ${agg.totalQuantity}",
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 11,
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
        );
      },
    );
  }

  Widget _buildConsumptionGrid(
    BuildContext context,
    List<ConsumptionData> list,
  ) {
    if (list.isEmpty) return const SizedBox();

    list.sort((a, b) {
      if (a.hasEnoughData && !b.hasEnoughData) return -1;
      if (!a.hasEnoughData && b.hasEnoughData) return 1;
      if (a.hasEnoughData && b.hasEnoughData) {
        return a.daysUntilRunout.compareTo(b.daysUntilRunout);
      }
      return a.itemName.compareTo(b.itemName);
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        int columns = 1;
        if (constraints.maxWidth > 900)
          columns = 3;
        else if (constraints.maxWidth > 600)
          columns = 2;

        double spacing = 10.0;
        double itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: list.map((cData) {
            Color statusColor;
            String bigText;
            String subText;

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
                statusColor = Theme.of(context).colorScheme.primary;
                bigText = "${cData.daysUntilRunout}";
                subText = "Days";
              }
            } else {
              statusColor = Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withOpacity(0.3);
              bigText = "?";
              subText = "N/A";
            }

            return SizedBox(
              width: itemWidth,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ItemGraphPage(
                          itemName: cData.itemName,
                          usageHistory: cData.history,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
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
                                  fontSize: 12,
                                ),
                              ),
                              if (subText != "N/A")
                                Text(
                                  subText,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: 7,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cData.itemName,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              if (cData.hasEnoughData) ...[
                                Text(
                                  "Rate: 1 every ${cData.avgDaysPerUse.toStringAsFixed(1)} days",
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                                if (cData.projectedDate != null)
                                  Text(
                                    "Empty: ${_formatSimpleDate(cData.projectedDate!)}",
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ] else
                                Text(
                                  "Needs 2+ usages (Used ${cData.usageCount})",
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),

                              // FIX: Force "+ 1 in use" display when data is available
                              if (cData.hasEnoughData)
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text:
                                            "Stock: ${cData.currentQuantity} ",
                                      ),
                                      TextSpan(
                                        text: "(+ 1 in use)",
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                )
                              else
                                Text(
                                  "Stock: ${cData.currentQuantity}",
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ... (Keep ItemGraphPage and GraphTimelinePainter as is)
class ItemGraphPage extends StatelessWidget {
  final String itemName;
  final List<DateTime> usageHistory;

  const ItemGraphPage({
    super.key,
    required this.itemName,
    required this.usageHistory,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final sortedData = List<DateTime>.from(usageHistory)..sort();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(itemName),
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
