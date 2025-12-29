import 'dart:async';
import 'dart:ui' as ui; // Added to fix TextDirection error
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
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
  List<DateTime> history;

  ConsumptionData({
    required this.itemName,
    required this.currentQuantity,
    required this.avgDaysPerUse,
    required this.daysUntilRunout,
    required this.hasEnoughData,
    required this.usageCount,
    this.projectedDate,
    required this.history,
  });
}

class _StatsPageState extends State<StatsPage>
    with AutomaticKeepAliveClientMixin {
  final FirestoreService _db = FirestoreService();

  late Stream<List<InventoryItem>> _inventoryStream;
  late Stream<List<Map<String, dynamic>>> _logStream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _inventoryStream = _db.getInventoryStream();
    _logStream = _db.getLogStream();
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

            int tQty = 0;
            Map<String, int> roomCounts = {};

            for (var item in currentItems) {
              if (item.type == 'Room') {
                if (!roomCounts.containsKey(item.name))
                  roomCounts[item.name] = 0;
              } else if (item.type == 'Item') {
                tQty += item.quantity;
                String loc = item.roomLocation ?? "Unknown";
                roomCounts[loc] = (roomCounts[loc] ?? 0) + item.quantity;
              }
            }

            List<ConsumptionData> consumptionList = [];
            DateTime now = DateTime.now();

            for (var item in currentItems.where((i) => i.type == 'Item')) {
              List<DateTime> usageDates = [];
              for (var log in logs) {
                String name = log['item'] ?? "";
                String action = log['action'] ?? "";
                String timestampStr = log['timestamp'] ?? "";

                if (name == item.name && (action.contains("USED"))) {
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

                double stockDuration = (item.quantity + 1) * avgDays;
                int daysSinceLast = now.difference(lastUse).inDays;
                daysLeft = (stockDuration - daysSinceLast).round();
                runoutDate = now.add(Duration(days: daysLeft));
              }

              consumptionList.add(
                ConsumptionData(
                  itemName: item.name,
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

            consumptionList.sort((a, b) {
              if (a.hasEnoughData && !b.hasEnoughData) return -1;
              if (!a.hasEnoughData && b.hasEnoughData) return 1;
              if (a.hasEnoughData && b.hasEnoughData)
                return a.daysUntilRunout.compareTo(b.daysUntilRunout);
              return a.itemName.compareTo(b.itemName);
            });

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
                      child: SingleChildScrollView(
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
                              "Based on usage history",
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
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  int columns = 1;
                                  if (constraints.maxWidth > 900) {
                                    columns = 3;
                                  } else if (constraints.maxWidth > 600) {
                                    columns = 2;
                                  }

                                  double spacing = 15.0;
                                  double itemWidth =
                                      (constraints.maxWidth -
                                          (spacing * (columns - 1))) /
                                      columns;

                                  return Wrap(
                                    spacing: spacing,
                                    runSpacing: spacing,
                                    children: consumptionList.map((cData) {
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
                                          statusColor = primaryColor;
                                          bigText = "${cData.daysUntilRunout}";
                                          subText = "Days";
                                        }
                                      } else {
                                        statusColor = onSurfaceVariant
                                            .withOpacity(0.3);
                                        bigText = "?";
                                        subText = "N/A";
                                      }

                                      return SizedBox(
                                        width: itemWidth,
                                        child: Material(
                                          color: Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            15,
                                          ),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              15,
                                            ),
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      ItemGraphPage(
                                                        itemName:
                                                            cData.itemName,
                                                        usageHistory:
                                                            cData.history,
                                                      ),
                                                ),
                                              );
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(15),
                                              decoration: BoxDecoration(
                                                color: cardColor,
                                                borderRadius:
                                                    BorderRadius.circular(15),
                                                border: Border.all(
                                                  color: dividerColor,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
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
                                                      color: statusColor
                                                          .withOpacity(0.1),
                                                    ),
                                                    child: Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Text(
                                                          bigText,
                                                          style: TextStyle(
                                                            color: statusColor,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 16,
                                                          ),
                                                        ),
                                                        Text(
                                                          subText,
                                                          style: TextStyle(
                                                            color:
                                                                onSurfaceVariant,
                                                            fontSize: 8,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 15),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          cData.itemName,
                                                          style: TextStyle(
                                                            color: onSurface,
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        if (cData
                                                            .hasEnoughData) ...[
                                                          Text(
                                                            "Rate: 1 every ${cData.avgDaysPerUse.toStringAsFixed(1)} days",
                                                            style: TextStyle(
                                                              color:
                                                                  onSurfaceVariant,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                          if (cData
                                                                  .projectedDate !=
                                                              null)
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets.only(
                                                                    top: 2,
                                                                  ),
                                                              child: Text(
                                                                "Empty: ${_formatSimpleDate(cData.projectedDate!)}",
                                                                style: TextStyle(
                                                                  color:
                                                                      statusColor,
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                              ),
                                                            ),
                                                        ] else
                                                          Text(
                                                            "Needs 2+ uses (Used ${cData.usageCount})",
                                                            style: TextStyle(
                                                              color:
                                                                  onSurfaceVariant,
                                                              fontSize: 12,
                                                              fontStyle:
                                                                  FontStyle
                                                                      .italic,
                                                            ),
                                                          ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          "Stock: ${cData.currentQuantity}",
                                                          style: TextStyle(
                                                            color:
                                                                onSurfaceVariant,
                                                            fontSize: 12,
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
                            const SizedBox(height: 15),
                            if (roomCounts.isEmpty)
                              Center(
                                child: Text(
                                  "No items.",
                                  style: TextStyle(color: onSurfaceVariant),
                                ),
                              )
                            else
                              ...roomCounts.entries.map((entry) {
                                double pct = tQty > 0
                                    ? entry.value / tQty
                                    : 0.0;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            entry.key,
                                            style: TextStyle(color: onSurface),
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
                                      const SizedBox(height: 5),
                                      LinearProgressIndicator(
                                        value: pct,
                                        backgroundColor: dividerColor,
                                        color: primaryColor,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ],
                                  ),
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
}

// --- VISUAL GRAPH PAGE ---
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

    // Sort oldest to newest for the graph
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
      ..strokeWidth = 10; // Halo effect

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

    // Adjust spacing if too cramped
    if (step < 80) step = 80;

    for (int i = 0; i < dates.length; i++) {
      final double progress = i * step;
      final Offset center = isHorizontal
          ? Offset(progress + 40, size.height / 2)
          : Offset(size.width / 2, progress + 40);

      // Draw connecting line to next point
      if (i < dates.length - 1) {
        final double nextProgress = (i + 1) * step;
        final Offset nextCenter = isHorizontal
            ? Offset(nextProgress + 40, size.height / 2)
            : Offset(size.width / 2, nextProgress + 40);

        canvas.drawLine(center, nextCenter, linePaint);

        // Draw Gap Label (Days elapsed)
        final int daysDiff = dates[i + 1].difference(dates[i]).inDays;
        final String gapText = "$daysDiff days";

        final TextSpan span = TextSpan(text: gapText, style: subTextStyle);
        final TextPainter tp = TextPainter(
          text: span,
          textDirection: ui.TextDirection.ltr, // FIXED: Explicit usage
        );
        tp.layout();

        final Offset midPoint = Offset(
          (center.dx + nextCenter.dx) / 2,
          (center.dy + nextCenter.dy) / 2,
        );

        // Offset text slightly above/right of the line center
        final Offset textOffset = isHorizontal
            ? Offset(midPoint.dx - (tp.width / 2), midPoint.dy - 20)
            : Offset(midPoint.dx + 15, midPoint.dy - (tp.height / 2));

        tp.paint(canvas, textOffset);
      }

      // Draw Dot Halo
      canvas.drawCircle(center, 8, borderPaint);
      // Draw Dot
      canvas.drawCircle(center, 5, dotPaint);

      // Draw Date Label
      final String dateText = DateFormat('MMM d').format(dates[i]);
      final TextSpan dSpan = TextSpan(text: dateText, style: textStyle);
      final TextPainter dTp = TextPainter(
        text: dSpan,
        textDirection: ui.TextDirection.ltr, // FIXED: Explicit usage
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
