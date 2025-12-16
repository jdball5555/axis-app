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

  ConsumptionData({
    required this.itemName,
    required this.currentQuantity,
    required this.avgDaysPerUse,
    required this.daysUntilRunout,
    required this.hasEnoughData,
    required this.usageCount,
  });
}

class _StatsPageState extends State<StatsPage> {
  // We use a future to hold the calculation result
  late Future<Map<String, dynamic>> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = _calculateStats();
  }

  // Reload when the widget updates (e.g. key change)
  @override
  void didUpdateWidget(StatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.key != widget.key) {
      _statsFuture = _calculateStats();
    }
  }

  DateTime? _parseDate(String dateStr) {
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
    int tUnique = 0;
    int tRooms = 0;
    Map<String, int> roomCounts = {};

    for (var item in currentItems) {
      if (item.type == 'Room') {
        tRooms++;
        if (!roomCounts.containsKey(item.name)) roomCounts[item.name] = 0;
      } else if (item.type == 'Item') {
        tUnique++;
        tQty += item.quantity;
        String loc = item.roomLocation ?? "Unknown";
        roomCounts[loc] = (roomCounts[loc] ?? 0) + item.quantity;
      }
    }

    String topRoom = "None";
    int maxVal = 0;
    roomCounts.forEach((key, value) {
      if (value > maxVal) {
        maxVal = value;
        topRoom = key;
      }
    });

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

        if (name == item.name && action == "USED ONE") {
          DateTime? dt = _parseDate(timestampStr);
          if (dt != null) usageDates.add(dt);
        }
      }

      usageDates.sort();

      bool hasEnough = usageDates.length >= 2;
      double avgDays = 0.0;
      int daysLeft = 0;

      if (hasEnough) {
        DateTime firstUse = usageDates.first;
        DateTime lastUse = usageDates.last;
        int totalDaysSpan = lastUse.difference(firstUse).inDays;
        if (totalDaysSpan == 0) totalDaysSpan = 1;
        int intervals = usageDates.length - 1;
        avgDays = totalDaysSpan / intervals;

        double stockDurationDays = item.quantity * avgDays;
        int daysSinceLastUse = now.difference(lastUse).inDays;
        daysLeft = (stockDurationDays - daysSinceLastUse).round();
      }

      calculatedConsumption.add(
        ConsumptionData(
          itemName: item.name,
          currentQuantity: item.quantity,
          avgDaysPerUse: avgDays,
          daysUntilRunout: daysLeft,
          hasEnoughData: hasEnough,
          usageCount: usageDates.length,
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
      'uniqueItems': tUnique,
      'totalRooms': tRooms,
      'itemsPerRoom': roomCounts,
      'mostStockedRoom': topRoom,
      'consumptionList': calculatedConsumption,
    };
  }

  @override
  Widget build(BuildContext context) {
    const Color themeTeal = Color(0xFF00C897);
    const Color cardDark = Color(0xFF222222);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "My Inventory Stats",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _statsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: themeTeal),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(
              child: Text(
                "Could not load stats.",
                style: TextStyle(color: Colors.white54),
              ),
            );
          }

          final data = snapshot.data!;
          final int totalQuantity = data['totalQuantity'];
          final int uniqueItems = data['uniqueItems'];
          final int totalRooms = data['totalRooms'];
          final String mostStockedRoom = data['mostStockedRoom'];
          final Map<String, int> itemsPerRoom = data['itemsPerRoom'];
          final List<ConsumptionData> consumptionList = data['consumptionList'];

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        "Total Items",
                        "$totalQuantity",
                        Icons.onetwothree,
                        themeTeal,
                        cardDark,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: _buildStatCard(
                        "Unique Types",
                        "$uniqueItems",
                        Icons.category,
                        Colors.orangeAccent,
                        cardDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        "Total Rooms",
                        "$totalRooms",
                        Icons.meeting_room,
                        Colors.blueAccent,
                        cardDark,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: _buildStatCard(
                        "Top Room",
                        mostStockedRoom,
                        Icons.star,
                        Colors.purpleAccent,
                        cardDark,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 30),

                const Text(
                  "Projected Runout",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  "Based on (Stock × Rate) - Days Since Last Use",
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 15),

                if (consumptionList.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Text(
                      "No items to track.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white30),
                    ),
                  )
                else
                  ...consumptionList.map((cData) {
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
                        statusColor = themeTeal;
                        bigText = "${cData.daysUntilRunout}";
                        subText = "Days";
                      }
                    } else {
                      statusColor = Colors.white24;
                      bigText = "?";
                      subText = "N/A";
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: cardDark,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.white10),
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
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  bigText,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: bigText == "Due" ? 14 : 16,
                                  ),
                                ),
                                Text(
                                  subText,
                                  style: const TextStyle(
                                    color: Colors.white38,
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
                                  cData.itemName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (cData.hasEnoughData)
                                  Text(
                                    "Rate: 1 every ${cData.avgDaysPerUse.toStringAsFixed(1)} days",
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  )
                                else
                                  Text(
                                    "Needs 2+ uses to predict (Used ${cData.usageCount})",
                                    style: const TextStyle(
                                      color: Colors.white24,
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),

                                Text(
                                  "Current Stock: ${cData.currentQuantity}",
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                const SizedBox(height: 30),

                const Text(
                  "Room Distribution",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),

                if (itemsPerRoom.isEmpty)
                  const Center(
                    child: Text(
                      "No items.",
                      style: TextStyle(color: Colors.white30),
                    ),
                  )
                else
                  ...itemsPerRoom.entries.map((entry) {
                    double percentage = totalQuantity > 0
                        ? (entry.value / totalQuantity)
                        : 0.0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                entry.key,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                "${entry.value} items",
                                style: const TextStyle(
                                  color: themeTeal,
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
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: percentage,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: themeTeal,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    Color bg,
  ) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
