import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;

import '../services/data_collector.dart';

// ==========================================
// 1. WRAPPER FOR ANALYTICS VIEW
// ==========================================

class AnalyticsPageWrapper extends StatelessWidget {
  const AnalyticsPageWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return const UserAnalyticsView();
  }
}

// ==========================================
// 2. CUSTOM TOP-LEFT ANGLE ICON
// ==========================================
class TopLeftAngleIcon extends StatelessWidget {
  final Color color;
  final double size;
  const TopLeftAngleIcon({super.key, required this.color, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _AnglePainter(color: color),
    );
  }
}

class _AnglePainter extends CustomPainter {
  final Color color;
  _AnglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(size.width * 0.9, size.height * 0.2)
      ..lineTo(size.width * 0.2, size.height * 0.2)
      ..lineTo(size.width * 0.2, size.height * 0.9);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==========================================
// TABLE ROW WRAPPER FOR GROUPING
// ==========================================
class _TableRow {
  final AnalyticsRow? originalRow;
  final bool isGroupHeader;
  final String groupKey;
  final List<String> displayData;

  _TableRow({
    this.originalRow,
    this.isGroupHeader = false,
    required this.groupKey,
    required this.displayData,
  });
}

// ==========================================
// 3. USER ANALYTICS VIEW
// ==========================================

class UserAnalyticsView extends StatefulWidget {
  const UserAnalyticsView({super.key});

  @override
  State<UserAnalyticsView> createState() => _UserAnalyticsViewState();
}

class _UserAnalyticsViewState extends State<UserAnalyticsView> {
  String _viewType = "Axis Forms";
  String? _selectedHousehold;
  String _selectedHouseholdName = "Household";
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? "";

  bool _isSearching = false;
  bool _isEditMode = false;
  bool _isDateLocked = true;

  String _groupBy = "No Group";
  final Set<String> _expandedGroups = {};
  String? _flashingRowKey; // Syncs the flash animation across panes

  final ValueNotifier<bool> _isPannedNotifier = ValueNotifier<bool>(false);

  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  DateTimeRange? _dateRange;

  List<String> _currentColumns = [];
  List<AnalyticsRow> _rawRows = [];

  // First index is ignored now, as it is dynamically calculated.
  final List<double> _colFlex = [1.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 3.0];

  final TransformationController _mainCtrl = TransformationController();
  final TransformationController _headerCtrl = TransformationController();
  final TransformationController _leftCtrl = TransformationController();
  final TransformationController _cornerCtrl = TransformationController();

  @override
  void initState() {
    super.initState();
    _migrateDataToNewStructure();

    _mainCtrl.addListener(() {
      final double actualX = _mainCtrl.value.getTranslation().x;
      final double actualY = _mainCtrl.value.getTranslation().y;

      final Matrix4 mHeader = _mainCtrl.value.clone();
      mHeader[13] = 0.0;
      _headerCtrl.value = mHeader;

      final Matrix4 mLeft = _mainCtrl.value.clone();
      mLeft[12] = 0.0;
      _leftCtrl.value = mLeft;

      final Matrix4 mCorner = _mainCtrl.value.clone();
      mCorner[12] = 0.0;
      mCorner[13] = 0.0;
      _cornerCtrl.value = mCorner;

      bool isMoved = actualX.abs() > 3.0 || actualY.abs() > 3.0;

      if (_isPannedNotifier.value != isMoved) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _isPannedNotifier.value = isMoved;
        });
      }
    });
  }

  Future<void> _migrateDataToNewStructure() async {
    if (_uid.isEmpty) return;

    final oldCol = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('user_analytics');
    final newCol = oldCol.doc('axis_forms').collection('entries');

    try {
      final oldDocs = await oldCol.get();
      if (oldDocs.docs.isEmpty) return;

      WriteBatch batch = FirebaseFirestore.instance.batch();
      int count = 0;

      for (var doc in oldDocs.docs) {
        if (doc.id == 'axis_forms' || doc.id == 'fitbit') continue;

        batch.set(newCol.doc(doc.id), doc.data());
        batch.delete(doc.reference);
        count++;
      }

      if (count > 0) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint("Migration error: $e");
    }
  }

  @override
  void dispose() {
    _mainCtrl.dispose();
    _headerCtrl.dispose();
    _leftCtrl.dispose();
    _cornerCtrl.dispose();
    _searchController.dispose();
    _isPannedNotifier.dispose();
    super.dispose();
  }

  // --- SMART AVERAGING ENGINE ---
  String _getGroupKey(DateTime dt) {
    if (_groupBy == 'Month') {
      const months = [
        'Jan.',
        'Feb.',
        'Mar.',
        'Apr.',
        'May',
        'Jun.',
        'Jul.',
        'Aug.',
        'Sep.',
        'Oct.',
        'Nov.',
        'Dec.',
      ];
      return "${months[dt.month - 1]} ${dt.year}";
    } else if (_groupBy == 'Year') {
      return "${dt.year}";
    }
    return "";
  }

  String _calculateAverage(List<String> values) {
    var validVals = values
        .where((v) => v.trim().isNotEmpty && v != "N/A")
        .toList();
    if (validVals.isEmpty) return "";

    // 1. Averages for Money ($45.00)
    if (validVals.any((v) => v.trim().startsWith('\$'))) {
      double sum = 0;
      for (var v in validVals) {
        sum += double.tryParse(v.replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0.0;
      }
      return "\$${(sum / validVals.length).toStringAsFixed(2)}";
    }

    // 2. Averages for Durations (7h 30m)
    if (validVals.any((v) => v.contains('h') || v.contains('m'))) {
      int totalMins = 0;
      final regex = RegExp(r'(?:(\d+)h)?\s*(?:(\d+)m)?');
      for (var v in validVals) {
        final match = regex.firstMatch(v.toLowerCase());
        if (match != null) {
          int h = int.tryParse(match.group(1) ?? '0') ?? 0;
          int m = int.tryParse(match.group(2) ?? '0') ?? 0;
          totalMins += (h * 60 + m);
        }
      }
      int avgMins = totalMins ~/ validVals.length;
      return "${avgMins ~/ 60}h ${avgMins % 60}m";
    }

    // 3. Clock Times (11:30 PM) using Circular Math
    final timeRegex = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
      caseSensitive: false,
    );
    if (validVals.any((v) => timeRegex.hasMatch(v.trim()))) {
      double sumSin = 0;
      double sumCos = 0;
      int count = 0;
      for (var v in validVals) {
        var m = timeRegex.firstMatch(v.trim());
        if (m != null) {
          int h = int.parse(m.group(1)!);
          int min = int.parse(m.group(2)!);
          String ampm = m.group(3)!.toUpperCase();
          if (ampm == 'PM' && h < 12) h += 12;
          if (ampm == 'AM' && h == 12) h = 0;

          double angle = ((h * 60 + min) / (24 * 60)) * 2 * math.pi;
          sumSin += math.sin(angle);
          sumCos += math.cos(angle);
          count++;
        }
      }
      if (count > 0) {
        double avgAngle = math.atan2(sumSin / count, sumCos / count);
        if (avgAngle < 0) avgAngle += 2 * math.pi;
        int avgMins = ((avgAngle / (2 * math.pi)) * 24 * 60).round();
        if (avgMins >= 1440) avgMins -= 1440;
        int h = avgMins ~/ 60;
        int min = avgMins % 60;
        String ampm = h >= 12 ? "PM" : "AM";
        if (h > 12) h -= 12;
        if (h == 0) h = 12;
        return "$h:${min.toString().padLeft(2, '0')} $ampm";
      }
    }

    // 4. Min/Max HR "55 (6:30 AM)"
    final minMaxRegex = RegExp(r'^(\d+)\s*\(');
    if (validVals.any((v) => minMaxRegex.hasMatch(v.trim()))) {
      double sum = 0;
      for (var v in validVals) {
        final match = minMaxRegex.firstMatch(v.trim());
        if (match != null) {
          sum += double.tryParse(match.group(1)!) ?? 0.0;
        } else {
          sum += double.tryParse(v.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
        }
      }
      return "${(sum / validVals.length).round()} avg";
    }

    // 5. Standard Numbers
    double sum = 0;
    int validNumberCount = 0;
    for (var v in validVals) {
      String cleanNum = v.replaceAll(RegExp(r'[^\d.\-+]'), '');
      if (cleanNum.isNotEmpty) {
        double? val = double.tryParse(cleanNum);
        if (val != null) {
          sum += val;
          validNumberCount++;
        }
      }
    }

    if (validNumberCount > 0 && validNumberCount >= (validVals.length / 2)) {
      double avg = sum / validNumberCount;
      if (avg == avg.roundToDouble()) return avg.round().toString();
      return avg.toStringAsFixed(1);
    }

    return "";
  }

  // --- DYNAMIC COLUMN WIDTH ENGINE ---
  double _calculateFirstColumnWidth(
    BuildContext context,
    List<_TableRow> rows,
    String headerName,
  ) {
    double maxWidth = 0.0;
    // Queries exact device scaling to ensure text math is physically accurate
    final double textScale = MediaQuery.of(context).textScaleFactor;
    final TextPainter textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textScaleFactor: textScale,
    );

    // Measure Header Text
    textPainter.text = TextSpan(
      text: headerName,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
        fontSize: 12.0,
      ),
    );
    textPainter.layout();
    maxWidth = math.max(maxWidth, textPainter.width);

    // Measure all rows to find the longest string
    for (var row in rows) {
      double rowWidth = 0.0;
      String text = row.displayData.isNotEmpty ? row.displayData[0] : "";
      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 15.0,
          fontWeight: row.isGroupHeader ? FontWeight.bold : FontWeight.normal,
        ),
      );
      textPainter.layout();
      rowWidth += textPainter.width;

      // Add width for UI icons to prevent squishing
      if (row.isGroupHeader) {
        rowWidth += 18.0 + 4.0; // Dropdown Icon + spacing
      } else if (_viewType == "Axis Forms" && row.originalRow != null) {
        if (row.originalRow!.duplicateOrdinal != null) {
          rowWidth += 10.0 + 8.0; // Circle icon + spacing
        }
      }
      maxWidth = math.max(maxWidth, rowWidth);
    }

    // Add exact right padding (16.0) + an extra buffer (12.0) to be completely safe
    return maxWidth + 28.0;
  }

  List<AnalyticsRow> _getFilteredRows() {
    List<AnalyticsRow> filtered = _rawRows;
    if (_dateRange != null) {
      filtered = filtered
          .where(
            (r) =>
                r.timestamp.isAfter(
                  _dateRange!.start.subtract(const Duration(days: 1)),
                ) &&
                r.timestamp.isBefore(
                  _dateRange!.end.add(const Duration(days: 1)),
                ),
          )
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (r) => r.rawData.any(
              (c) => c.toLowerCase().contains(_searchQuery.toLowerCase()),
            ),
          )
          .toList();
    }
    return filtered;
  }

  String _generateDefaultFileName() {
    final now = DateTime.now();
    String timeStamp =
        "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}";

    String prefix = _viewType.toLowerCase().replaceAll(" ", "_");

    if (_viewType == "Inventory History") {
      String house = _selectedHouseholdName.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]'),
        '_',
      );
      return "${prefix}_${house}_$timeStamp.csv";
    }

    return "${prefix}_$timeStamp.csv";
  }

  Future<void> _initiateExport() async {
    List<AnalyticsRow> dataToExportRows = _getFilteredRows();
    if (dataToExportRows.isEmpty) {
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            "No Data Displayed",
            style: TextStyle(color: Colors.redAccent),
          ),
          content: const Text(
            "There are no records visible to export.\nPlease adjust your filters or search terms.",
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text("OK", style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      );
      return;
    }

    String defaultName = _generateDefaultFileName();
    TextEditingController filenameController = TextEditingController(
      text: defaultName.replaceAll(".csv", ""),
    );

    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          "Export to CSV",
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "File Name:",
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: filenameController,
              style: const TextStyle(color: Color(0xFF00C897)),
              decoration: const InputDecoration(
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF00C897)),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                suffixText: ".csv",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C897),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.pop(c);
              _processDownload(filenameController.text, dataToExportRows);
            },
            child: const Text("Download"),
          ),
        ],
      ),
    );
  }

  void _processDownload(String fileName, List<AnalyticsRow> rows) {
    if (!fileName.toLowerCase().endsWith(".csv")) {
      fileName = "$fileName.csv";
    }

    List<List<String>> csvDataLists = [
      _currentColumns,
      ...rows.map((r) => r.rawData),
    ];
    String csvData = csvDataLists.map((row) => row.join(",")).join("\n");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("CSV Export is ready for $fileName."),
        backgroundColor: const Color(0xFF00C897),
        duration: const Duration(seconds: 4),
      ),
    );
    debugPrint(csvData);
  }

  Future<void> _deleteRow(String fullDocId) async {
    String docId = fullDocId.split('_').first;

    bool confirm =
        await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text(
              "Delete Record?",
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              "This action cannot be undone.",
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text(
                  "Delete",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    if (_viewType == "Axis Forms") {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('user_analytics')
          .doc('axis_forms')
          .collection('entries')
          .doc(docId)
          .delete();
    } else if (_viewType == "Fitbit") {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('user_analytics')
          .doc('fitbit')
          .collection('entries')
          .doc(docId)
          .delete();
    } else if (_viewType == "Finances") {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('finances')
          .doc(docId)
          .delete();
    } else if (_selectedHousehold != null) {
      await FirebaseFirestore.instance
          .collection('households')
          .doc(_selectedHousehold)
          .collection('activity_log')
          .doc(docId)
          .delete();
    }
  }

  double? _parseMoney(String s) {
    if (s.isEmpty) return null;
    return double.tryParse(s.replaceAll('\$', '').trim());
  }

  DateTime? _parseTime(String s, DateTime baseDate) {
    if (s.isEmpty) return null;
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
      caseSensitive: false,
    ).firstMatch(s.trim());
    if (match == null) return null;
    int h = int.parse(match.group(1)!);
    int min = int.parse(match.group(2)!);
    String ampm = match.group(3)!.toUpperCase();
    if (ampm == 'PM' && h < 12) h += 12;
    if (ampm == 'AM' && h == 12) h = 0;
    return DateTime(baseDate.year, baseDate.month, baseDate.day, h, min, 0);
  }

  DateTime? _parseDate(String s) {
    if (s.isEmpty) return null;
    List<String> p = s.split('/');
    if (p.length != 3) return null;
    int? m = int.tryParse(p[0]);
    int? d = int.tryParse(p[1]);
    int? y = int.tryParse(p[2]);
    if (m == null || d == null || y == null) return null;
    return DateTime(y, m, d);
  }

  Future<void> _editCell(
    String fullDocId,
    String field,
    String currentValue,
    DateTime baseDate,
  ) async {
    String docId = fullDocId.split('_').first;

    String? val = await showDialog<String>(
      context: context,
      builder: (context) =>
          _SmartEditCellDialog(field: field, initialValue: currentValue),
    );

    if (val == null) return;
    if (!mounted) return;

    Map<String, dynamic> updateData = {};
    bool isFormatError = false;
    bool shouldDelete = val == "__DELETE__";

    if (_viewType == "Finances") {
      int idx =
          int.tryParse(
            fullDocId.split('_').length > 1 ? fullDocId.split('_')[1] : "0",
          ) ??
          0;
      DocumentReference docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('finances')
          .doc(docId);

      if (field == "ITEM NAME" || field == "COST") {
        var snap = await docRef.get();
        if (snap.exists) {
          List items = List.from((snap.data() as Map)['items'] ?? []);
          if (shouldDelete) {
            if (idx < items.length) {
              if (field == "ITEM NAME") items[idx].remove('name');
              if (field == "COST") items[idx].remove('price');
              if (!items[idx].containsKey('name') &&
                  !items[idx].containsKey('price')) {
                items.removeAt(idx);
              }
            }
          } else {
            if (field == "COST") {
              double? cost = _parseMoney(val);
              if (cost == null) {
                isFormatError = true;
              } else {
                if (idx < items.length) {
                  items[idx]['price'] = cost;
                } else {
                  items.add({'name': 'Item', 'price': cost});
                }
              }
            } else if (field == "ITEM NAME") {
              if (idx < items.length) {
                items[idx]['name'] = val;
              } else {
                items.add({'name': val, 'price': 0.0});
              }
            }
          }
          if (!isFormatError) await docRef.update({'items': items});
        }
      } else {
        if (shouldDelete) {
          String key = field.toLowerCase();
          updateData[key] = FieldValue.delete();
        } else {
          if (field == "DATE") {
            if (_parseDate(val) == null) {
              isFormatError = true;
            } else {
              updateData['date'] = val;
            }
          } else if (field == "TAX") {
            double? tax = _parseMoney(val);
            if (tax == null) {
              isFormatError = true;
            } else {
              updateData['tax'] = tax;
            }
          } else if (field == "TOTAL") {
            double? total = _parseMoney(val);
            if (total == null) {
              isFormatError = true;
            } else {
              updateData['total'] = total;
            }
          } else if (field == "STORE") {
            updateData['store'] = val;
          }
        }
        if (!isFormatError && updateData.isNotEmpty) {
          await docRef.update(updateData);
        }
      }
    } else if ((_viewType == "Axis Forms" || _viewType == "Fitbit") &&
        field == "DATE") {
      final String folderName = _viewType == "Fitbit" ? "fitbit" : "axis_forms";
      final entriesRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('user_analytics')
          .doc(folderName)
          .collection('entries');

      if (shouldDelete) {
        await entriesRef.doc(docId).delete();
      } else {
        DateTime? d = _parseDate(val);
        if (d == null) {
          isFormatError = true;
        } else {
          String newDocBase =
              "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

          var oldDocSnap = await entriesRef.doc(docId).get();
          if (oldDocSnap.exists) {
            Map<String, dynamic> data = oldDocSnap.data()!;
            data['logicalDate'] = newDocBase;

            String finalNewDocId = newDocBase;
            if (finalNewDocId != docId) {
              var checkSnap = await entriesRef.doc(finalNewDocId).get();
              int counter = 2;
              while (checkSnap.exists) {
                finalNewDocId = "$newDocBase-$counter";
                checkSnap = await entriesRef.doc(finalNewDocId).get();
                counter++;
              }
              await entriesRef.doc(finalNewDocId).set(data);
              await entriesRef.doc(docId).delete();
            } else {
              await entriesRef.doc(docId).update({'logicalDate': newDocBase});
            }
          }
        }
      }
    } else {
      String key = field.toLowerCase();
      if (field == "QTY") key = "change";
      if (field == "DAY RATING") key = "rating";
      if (field == "SLEEP QUALITY") key = "sleepQuality";
      if (field == "SLEEP DURATION") key = "sleepDuration";
      if (field == "SLEEP") key = "sleepTime";
      if (field == "WAKE") key = "wakeTime";
      if (field == "PRODUCTIVITY") key = "productivity";
      if (field == "MIND") key = "mindTiles";
      if (field == "STEPS") key = "steps";
      if (field == "FLOORS") key = "floors";
      if (field == "RHR") key = "restingHeartRate";

      if (shouldDelete) {
        if (field == "MIN HR" || field == "MAX HR") {
          String hrKey = field == "MIN HR" ? "minHr" : "maxHr";
          String timeKey = field == "MIN HR" ? "minTime" : "maxTime";
          updateData[hrKey] = FieldValue.delete();
          updateData[timeKey] = FieldValue.delete();
        } else {
          updateData[key] = FieldValue.delete();
        }
      } else {
        if (field == "MIND") {
          updateData[key] = val
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        } else if (field == "SLEEP" || field == "WAKE" || field == "TIME") {
          DateTime? t = _parseTime(val, baseDate);
          if (t == null) {
            isFormatError = true;
          } else {
            updateData[key] = t.toIso8601String();
          }
        } else if (field == "DATE") {
          if (_parseDate(val) == null) {
            isFormatError = true;
          } else {
            updateData[key] = val;
          }
        } else if (field == "MIN HR" || field == "MAX HR") {
          String hrKey = field == "MIN HR" ? "minHr" : "maxHr";
          String timeKey = field == "MIN HR" ? "minTime" : "maxTime";

          final match = RegExp(
            r'^(\d+)(?:\s*\((.*?)\))?$',
          ).firstMatch(val.trim());
          if (match != null) {
            updateData[hrKey] = match.group(1);
            if (match.group(2) != null && match.group(2)!.isNotEmpty) {
              DateTime? t = _parseTime(match.group(2)!, baseDate);
              if (t != null) {
                updateData[timeKey] = t.toIso8601String();
              } else {
                updateData[timeKey] = "";
              }
            } else {
              updateData[timeKey] = "";
            }
          } else {
            updateData[hrKey] = val;
          }
        } else if (field == "SLEEP DURATION") {
          updateData[key] = val;
        } else if (field == "QTY" ||
            field == "STEPS" ||
            field == "FLOORS" ||
            field == "RHR") {
          int? numVal = int.tryParse(val);
          if (numVal == null) {
            isFormatError = true;
          } else {
            updateData[key] = numVal.toString();
          }
        } else {
          updateData[key] = val;
        }
      }

      if (!isFormatError && updateData.isNotEmpty) {
        if (_viewType == "Axis Forms" || _viewType == "Fitbit") {
          final String folderName = _viewType == "Fitbit"
              ? "fitbit"
              : "axis_forms";
          final entriesRef = FirebaseFirestore.instance
              .collection('users')
              .doc(_uid)
              .collection('user_analytics')
              .doc(folderName)
              .collection('entries');

          if (field == "SLEEP" || field == "WAKE") {
            if (shouldDelete) {
              updateData['sleepDuration'] = FieldValue.delete();
            } else {
              var docSnap = await entriesRef.doc(docId).get();
              if (docSnap.exists) {
                Map<String, dynamic> existingData = docSnap.data()!;
                String? currentSleep = updateData.containsKey('sleepTime')
                    ? updateData['sleepTime']
                    : existingData['sleepTime'];
                String? currentWake = updateData.containsKey('wakeTime')
                    ? updateData['wakeTime']
                    : existingData['wakeTime'];

                if (currentSleep != null &&
                    currentSleep.isNotEmpty &&
                    currentWake != null &&
                    currentWake.isNotEmpty) {
                  try {
                    DateTime st = DateTime.parse(currentSleep);
                    DateTime wt = DateTime.parse(currentWake);

                    if (st.isAfter(wt)) {
                      st = st.subtract(const Duration(days: 1));
                      updateData['sleepTime'] = st.toIso8601String();
                    }

                    int durationMins = wt.difference(st).inMinutes;
                    if (durationMins >= 0) {
                      int h = durationMins ~/ 60;
                      int m = durationMins % 60;
                      updateData['sleepDuration'] = "${h}h ${m}m";
                    }
                  } catch (_) {}
                }
              }
            }
          }

          await entriesRef.doc(docId).update(updateData);
        } else if (_selectedHousehold != null) {
          await FirebaseFirestore.instance
              .collection('households')
              .doc(_selectedHousehold)
              .collection('activity_log')
              .doc(docId)
              .update(updateData);
        }
      }
    }

    if (isFormatError && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Incorrect data format for this column",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _dateRange,
      initialEntryMode: DatePickerEntryMode.input,
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00C897),
            onPrimary: Colors.black,
            surface: Color(0xFF1E1E1E),
            onSurface: Colors.white,
            secondaryContainer: Color(0xFF00C897),
            onSecondaryContainer: Colors.black,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF00C897),
            ),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF00C897)),
            ),
          ),
        ),
        child: child!,
      ),
    );

    if (!mounted) return;

    if (picked != null) {
      setState(() {
        _dateRange = picked;
      });
    }
  }

  void _revertFilters() {
    setState(() {
      _searchQuery = "";
      _searchController.clear();
      _dateRange = null;
      _isSearching = false;
    });
  }

  Widget _buildCellContent(_TableRow row, int cellIndex) {
    Widget textCell = Text(
      row.displayData[cellIndex],
      // CRITICAL FIX: Ensure the text widget never wraps or causes an overflow boundary
      maxLines: cellIndex == 0 ? 1 : null,
      softWrap: cellIndex == 0 ? false : true,
      style: TextStyle(
        color: row.isGroupHeader
            ? Colors.white
            : (_isEditMode ? Colors.white : const Color(0xFF00C897)),
        fontSize: 15.0,
        fontWeight: row.isGroupHeader ? FontWeight.bold : FontWeight.normal,
        decoration: _isEditMode && !row.isGroupHeader
            ? TextDecoration.underline
            : TextDecoration.none,
        decorationColor: Colors.white38,
      ),
    );

    if (row.isGroupHeader && cellIndex == 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _expandedGroups.contains(row.groupKey)
                ? Icons.keyboard_arrow_down
                : Icons.keyboard_arrow_right,
            color: Colors.white,
            size: 18.0,
          ),
          const SizedBox(width: 4.0),
          textCell, // Removed Expanded to prevent wrap rendering bounds
        ],
      );
    }

    if (_viewType == "Axis Forms" &&
        !row.isGroupHeader &&
        row.originalRow != null) {
      if (cellIndex == 0 && row.originalRow!.duplicateOrdinal != null) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            textCell, // Removed Expanded
            const SizedBox(width: 8.0),
            Tooltip(
              message:
                  "This is the ${row.originalRow!.duplicateOrdinal} duplicate of this date",
              triggerMode: TooltipTriggerMode.tap,
              showDuration: const Duration(seconds: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2D0A0A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF990000)),
              ),
              textStyle: const TextStyle(
                color: Color(0xFFFF8A80),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              child: const Icon(
                Icons.circle,
                color: Color(0xFF990000),
                size: 10.0,
              ),
            ),
          ],
        );
      }

      if (cellIndex == 1 && row.originalRow!.isPrevDaySleep) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            textCell, // Removed Expanded
            const SizedBox(width: 8.0),
            Tooltip(
              message: "Sleep session started the day prior",
              triggerMode: TooltipTriggerMode.tap,
              showDuration: const Duration(seconds: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2D0A0A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF990000)),
              ),
              textStyle: const TextStyle(
                color: Color(0xFFFF8A80),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              child: const Icon(
                Icons.circle,
                color: Color(0xFF990000),
                size: 10.0,
              ),
            ),
          ],
        );
      }
    }

    return textCell;
  }

  Widget _buildStickyTable({List<double>? flexOverride}) {
    List<AnalyticsRow> baseFiltered = _getFilteredRows();
    if (baseFiltered.isEmpty) {
      return const Center(
        child: Text(
          "No results found.",
          style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic),
        ),
      );
    }

    // Apply Grouping Engine
    List<_TableRow> renderRows = [];

    if (_groupBy == 'No Group') {
      renderRows = baseFiltered
          .map(
            (r) =>
                _TableRow(originalRow: r, groupKey: '', displayData: r.rawData),
          )
          .toList();
    } else {
      Map<String, List<AnalyticsRow>> groupedMap = {};
      for (var r in baseFiltered) {
        String gKey = _getGroupKey(r.timestamp);
        if (!groupedMap.containsKey(gKey)) groupedMap[gKey] = [];
        groupedMap[gKey]!.add(r);
      }

      for (var entry in groupedMap.entries) {
        String gKey = entry.key;
        List<AnalyticsRow> gRows = entry.value;

        List<String> avgData = List.filled(_currentColumns.length, "");
        avgData[0] = gKey;
        for (int i = 1; i < _currentColumns.length; i++) {
          List<String> colVals = gRows
              .map((r) => r.rawData.length > i ? r.rawData[i] : "")
              .toList();
          avgData[i] = _calculateAverage(colVals);
        }

        renderRows.add(
          _TableRow(isGroupHeader: true, groupKey: gKey, displayData: avgData),
        );

        if (_expandedGroups.contains(gKey)) {
          for (var r in gRows) {
            renderRows.add(
              _TableRow(originalRow: r, groupKey: gKey, displayData: r.rawData),
            );
          }
        }
      }
    }

    final List<double> flex = flexOverride ?? _colFlex;

    // Calculates exact required width dynamically based on user's exact font sizes
    final double firstColWidth = _calculateFirstColumnWidth(
      context,
      renderRows,
      _currentColumns.isNotEmpty ? _currentColumns[0] : "DATE",
    );

    double remainingFlex = 0.0;
    for (int i = 1; i < _currentColumns.length; i++) {
      remainingFlex += flex.length > i ? flex[i] : 1.0;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double baseRemainingWidth = remainingFlex * 85.0;
        final double baseTableWidth = firstColWidth + baseRemainingWidth;
        final double tableWidth =
            math.max(constraints.maxWidth, baseTableWidth) +
            (_isEditMode ? 40.0 : 0.0);

        final double exactMinScale = constraints.maxWidth / tableWidth;

        final double requiredHeight = constraints.maxHeight / exactMinScale;
        final double contentHeight = 45.0 + (renderRows.length * 65.0) + 150.0;
        final double finalHeight = math.max(requiredHeight, contentHeight);

        List<double> colWidths = [firstColWidth];
        double availableRemainingWidth =
            tableWidth - firstColWidth - (_isEditMode ? 40.0 : 0.0);

        for (int i = 1; i < _currentColumns.length; i++) {
          double f = flex.length > i ? flex[i] : 1.0;
          colWidths.add(availableRemainingWidth * (f / remainingFlex));
        }

        Widget fullTable = ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: tableWidth,
            maxWidth: tableWidth,
            minHeight: finalHeight,
            maxHeight: finalHeight,
          ),
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.only(top: 45.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: renderRows.map((row) {
                bool isFlashing =
                    _flashingRowKey == row.groupKey && row.isGroupHeader;
                Color rowBgColor = row.isGroupHeader
                    ? (isFlashing
                          ? const Color(0xFF00C897).withOpacity(0.5)
                          : const Color(0xFF00B0B9).withOpacity(0.15))
                    : Colors.transparent;

                Widget rowContent = AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  color: rowBgColor,
                  child: Row(
                    children: [
                      ...List.generate(row.displayData.length, (cellIndex) {
                        return Container(
                          width: colWidths[cellIndex],
                          padding: EdgeInsets.only(
                            top: 12.0,
                            bottom: 12.0,
                            right: cellIndex == 0 ? 16.0 : 16.0,
                            left: cellIndex == 0 ? 0.0 : 16.0,
                          ),
                          decoration: cellIndex == 0
                              ? const BoxDecoration(
                                  border: Border(
                                    right: BorderSide(
                                      color: Colors.white24,
                                      width: 1.0,
                                    ),
                                  ),
                                )
                              : null,
                          child: row.isGroupHeader
                              ? _buildCellContent(row, cellIndex)
                              : InkWell(
                                  onTap:
                                      (_isEditMode && row.originalRow != null)
                                      ? () => _editCell(
                                          row.originalRow!.docId,
                                          _currentColumns[cellIndex],
                                          row.displayData[cellIndex],
                                          row.originalRow!.timestamp,
                                        )
                                      : null,
                                  child: _buildCellContent(row, cellIndex),
                                ),
                        );
                      }),
                      if (_isEditMode)
                        SizedBox(
                          width: 40.0,
                          child: row.isGroupHeader
                              ? const SizedBox.shrink()
                              : IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                    size: 20.0,
                                  ),
                                  onPressed: () =>
                                      _deleteRow(row.originalRow!.docId),
                                ),
                        ),
                    ],
                  ),
                );

                if (row.isGroupHeader) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        _flashingRowKey = row.groupKey;
                      });
                      Future.delayed(const Duration(milliseconds: 100), () {
                        if (!mounted) return;
                        setState(() {
                          _flashingRowKey = null;
                          if (_expandedGroups.contains(row.groupKey)) {
                            _expandedGroups.remove(row.groupKey);
                          } else {
                            _expandedGroups.add(row.groupKey);
                          }
                        });
                      });
                    },
                    child: rowContent,
                  );
                }
                return rowContent;
              }).toList(),
            ),
          ),
        );

        Widget headerTree = ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: tableWidth,
            maxWidth: tableWidth,
            minHeight: finalHeight,
            maxHeight: finalHeight,
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              height: 45.0,
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.white24, width: 1.0),
                ),
              ),
              child: Row(
                children: [
                  ...List.generate(_currentColumns.length, (index) {
                    return Container(
                      width: colWidths[index],
                      padding: EdgeInsets.only(
                        top: 12.0,
                        bottom: 12.0,
                        right: index == 0 ? 16.0 : 16.0,
                        left: index == 0 ? 0.0 : 16.0,
                      ),
                      decoration: index == 0
                          ? const BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                  color: Colors.white24,
                                  width: 1.0,
                                ),
                              ),
                            )
                          : null,
                      child: Text(
                        _currentColumns[index],
                        style: const TextStyle(
                          color: Colors.white38,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          fontSize: 12.0,
                        ),
                      ),
                    );
                  }),
                  if (_isEditMode) const SizedBox(width: 40.0),
                ],
              ),
            ),
          ),
        );

        return Stack(
          children: [
            ValueListenableBuilder<Matrix4>(
              valueListenable: _mainCtrl,
              builder: (context, matrix, _) {
                final double scale = matrix.getMaxScaleOnAxis();
                final double topClipThreshold = 45.0 * scale;
                final double activeLeftClip = _isDateLocked
                    ? (firstColWidth * scale)
                    : 0.0;

                return Stack(
                  children: [
                    ClipRect(
                      clipper: _QuadrantClipper(
                        activeLeftClip,
                        topClipThreshold,
                        double.infinity,
                        double.infinity,
                      ),
                      child: InteractiveViewer(
                        transformationController: _mainCtrl,
                        alignment: Alignment.topLeft,
                        constrained: false,
                        boundaryMargin: EdgeInsets.zero,
                        minScale: exactMinScale,
                        maxScale: 2.0,
                        child: fullTable,
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ClipRect(
                          clipper: _QuadrantClipper(
                            activeLeftClip,
                            0.0,
                            double.infinity,
                            topClipThreshold,
                          ),
                          child: InteractiveViewer(
                            transformationController: _headerCtrl,
                            alignment: Alignment.topLeft,
                            constrained: false,
                            panEnabled: false,
                            scaleEnabled: false,
                            boundaryMargin: EdgeInsets.zero,
                            minScale: exactMinScale,
                            maxScale: 2.0,
                            child: headerTree,
                          ),
                        ),
                      ),
                    ),
                    if (_isDateLocked) ...[
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: !_isEditMode && _groupBy == 'No Group',
                          child: ClipRect(
                            clipper: _QuadrantClipper(
                              0.0,
                              topClipThreshold,
                              activeLeftClip,
                              double.infinity,
                            ),
                            child: InteractiveViewer(
                              transformationController: _leftCtrl,
                              alignment: Alignment.topLeft,
                              constrained: false,
                              panEnabled: false,
                              scaleEnabled: false,
                              boundaryMargin: EdgeInsets.zero,
                              minScale: exactMinScale,
                              maxScale: 2.0,
                              child: fullTable,
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ClipRect(
                            clipper: _QuadrantClipper(
                              0.0,
                              0.0,
                              activeLeftClip,
                              topClipThreshold,
                            ),
                            child: InteractiveViewer(
                              transformationController: _cornerCtrl,
                              alignment: Alignment.topLeft,
                              constrained: false,
                              panEnabled: false,
                              scaleEnabled: false,
                              boundaryMargin: EdgeInsets.zero,
                              minScale: exactMinScale,
                              maxScale: 2.0,
                              child: headerTree,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtleTealColor = const Color(0xFF00C897).withOpacity(0.6);
    final borderTealColor = const Color(0xFF00C897).withOpacity(0.3);
    bool isFilterActive = _searchQuery.isNotEmpty || _dateRange != null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Color(0xFF00C897)),
        title: const Text(
          "Analytics Hub",
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.bottomRight,
                    radius: 3.5,
                    colors: [
                      const Color(0xFF00C897).withOpacity(0.4),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C897).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: borderTealColor),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(48),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ValueListenableBuilder<bool>(
                                    valueListenable: _isPannedNotifier,
                                    builder: (context, isPanned, child) {
                                      if (!isPanned)
                                        return const SizedBox.shrink();
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8.0,
                                        ),
                                        child: Tooltip(
                                          message: "Jump to Top Left",
                                          child: InkWell(
                                            onTap: () {
                                              final Matrix4 m = _mainCtrl.value
                                                  .clone();
                                              m.setTranslationRaw(
                                                0.0,
                                                0.0,
                                                0.0,
                                              );
                                              _mainCtrl.value = m;
                                            },
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF1E1E1E),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFF00C897,
                                                  ).withOpacity(0.8),
                                                  width: 1.5,
                                                ),
                                                boxShadow: const [
                                                  BoxShadow(
                                                    color: Colors.black54,
                                                    blurRadius: 4,
                                                    offset: Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              padding: const EdgeInsets.all(8),
                                              child: const TopLeftAngleIcon(
                                                color: Color(0xFF00C897),
                                                size: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  _buildPillDropdown(
                                    value: _viewType,
                                    items: [
                                      "Axis Forms",
                                      "Fitbit",
                                      "Inventory History",
                                      "Finances",
                                    ],
                                    color: subtleTealColor,
                                    onChanged: (v) {
                                      setState(() {
                                        _viewType = v!;
                                        _selectedHousehold = null;
                                        _rawRows.clear();
                                        _currentColumns.clear();
                                        _expandedGroups.clear();

                                        // Jump to top when changing view
                                        final Matrix4 m = _mainCtrl.value
                                            .clone();
                                        final double currentX = m
                                            .getTranslation()
                                            .x;
                                        m.setTranslationRaw(currentX, 0.0, 0.0);
                                        _mainCtrl.value = m;
                                      });
                                    },
                                  ),
                                  if (_viewType == "Inventory History") ...[
                                    VerticalDivider(
                                      color: borderTealColor,
                                      indent: 12,
                                      endIndent: 12,
                                      width: 24,
                                    ),
                                    Text(
                                      "House: ",
                                      style: TextStyle(
                                        color: subtleTealColor,
                                        fontSize: 14,
                                      ),
                                    ),
                                    _buildHouseholdDropdown(subtleTealColor),
                                  ],
                                  VerticalDivider(
                                    color: borderTealColor,
                                    indent: 12,
                                    endIndent: 12,
                                    width: 24,
                                  ),
                                  _buildPillDropdown(
                                    value: _groupBy,
                                    items: ["No Group", "Month", "Year"],
                                    color: _groupBy == 'No Group'
                                        ? subtleTealColor
                                        : const Color(0xFF00C897),
                                    prefix: "Group: ",
                                    onChanged: (v) {
                                      setState(() {
                                        _groupBy = v!;
                                        _expandedGroups.clear();

                                        // Jump to top when changing group
                                        final Matrix4 m = _mainCtrl.value
                                            .clone();
                                        final double currentX = m
                                            .getTranslation()
                                            .x;
                                        m.setTranslationRaw(currentX, 0.0, 0.0);
                                        _mainCtrl.value = m;
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(width: 40),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isSearching)
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      width: 200,
                                      child: TextField(
                                        controller: _searchController,
                                        autofocus: true,
                                        style: TextStyle(
                                          color: subtleTealColor,
                                          fontSize: 14,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: "Search...",
                                          hintStyle: TextStyle(
                                            color: subtleTealColor.withOpacity(
                                              0.5,
                                            ),
                                          ),
                                          border: InputBorder.none,
                                          isDense: true,
                                        ),
                                        onChanged: (val) {
                                          setState(() {
                                            _searchQuery = val;
                                          });
                                        },
                                      ),
                                    ),
                                  _buildSubtleIconButton(
                                    icon: _isSearching
                                        ? Icons.close
                                        : Icons.search,
                                    color: _isSearching
                                        ? Colors.white54
                                        : subtleTealColor,
                                    tooltip: "Search Data",
                                    onTap: () {
                                      setState(() {
                                        _isSearching = !_isSearching;
                                        if (!_isSearching) {
                                          _searchQuery = "";
                                          _searchController.clear();
                                        }
                                      });
                                    },
                                  ),
                                  _buildSubtleIconButton(
                                    icon: Icons.calendar_month,
                                    color: _dateRange != null
                                        ? const Color(0xFF00C897)
                                        : subtleTealColor,
                                    tooltip: "Filter by Date Range",
                                    onTap: () {
                                      _pickDateRange();
                                    },
                                  ),
                                  if (isFilterActive) ...[
                                    const SizedBox(width: 8),
                                    Tooltip(
                                      message: "Clear Date/Search Filters",
                                      child: ElevatedButton(
                                        onPressed: _revertFilters,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.redAccent
                                              .withOpacity(0.2),
                                          foregroundColor: Colors.redAccent,
                                          minimumSize: const Size(0, 32),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 0,
                                          ),
                                          shape: const StadiumBorder(),
                                          elevation: 0,
                                        ),
                                        child: const Text(
                                          "Revert",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  _buildSubtleIconButton(
                                    icon: Icons.download,
                                    color: subtleTealColor,
                                    tooltip: "Export to CSV",
                                    onTap: () {
                                      _initiateExport();
                                    },
                                  ),
                                  VerticalDivider(
                                    color: borderTealColor,
                                    indent: 12,
                                    endIndent: 12,
                                    width: 24,
                                  ),
                                  _buildSubtleIconButton(
                                    icon: _isDateLocked
                                        ? Icons.lock
                                        : Icons.lock_open,
                                    color: _isDateLocked
                                        ? const Color(0xFF00C897)
                                        : subtleTealColor,
                                    tooltip: _isDateLocked
                                        ? "Unlock Left Column"
                                        : "Lock Left Column",
                                    onTap: () {
                                      setState(() {
                                        _isDateLocked = !_isDateLocked;
                                      });
                                    },
                                  ),
                                  _buildSubtleIconButton(
                                    icon: _isEditMode
                                        ? Icons.edit_off
                                        : Icons.edit,
                                    color: _isEditMode
                                        ? const Color(0xFF00C897)
                                        : subtleTealColor,
                                    tooltip: _isEditMode
                                        ? "Exit Edit Mode"
                                        : "Enter Edit Mode",
                                    onTap: () {
                                      setState(() {
                                        _isEditMode = !_isEditMode;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  Expanded(
                    child: _viewType == "Axis Forms"
                        ? _buildUserStatsTable()
                        : _viewType == "Fitbit"
                        ? _buildFitbitTable()
                        : _viewType == "Finances"
                        ? _buildFinancesTable()
                        : _buildActivityTable(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillDropdown({
    required String? value,
    required List<String> items,
    required Color color,
    required Function(String?) onChanged,
    String prefix = "",
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(50),
      clipBehavior: Clip.antiAlias,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: const Color(0xFF1E1E1E),
          focusColor: color.withOpacity(0.1),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          borderRadius: BorderRadius.circular(16),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          icon: Icon(Icons.keyboard_arrow_down, color: color, size: 20),
          items: items
              .map((s) => DropdownMenuItem(value: s, child: Text("$prefix$s")))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildSubtleIconButton({
    IconData? icon,
    Widget? customIcon,
    required Color color,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            hoverColor: const Color(0xFF00C897).withOpacity(0.1),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              child: customIcon ?? Icon(icon, color: color, size: 20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHouseholdDropdown(Color subtleColor) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('households')
          .where('members', arrayContains: _uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return Text("Loading...", style: TextStyle(color: subtleColor));
        if (snapshot.data!.docs.isEmpty)
          return Text("No Houses", style: TextStyle(color: subtleColor));
        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(50),
          clipBehavior: Clip.antiAlias,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedHousehold,
              hint: Text(
                "Select...",
                style: TextStyle(
                  color: subtleColor.withOpacity(0.5),
                  fontSize: 14,
                ),
              ),
              dropdownColor: const Color(0xFF1E1E1E),
              focusColor: subtleColor.withOpacity(0.1),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              borderRadius: BorderRadius.circular(16),
              style: TextStyle(
                color: subtleColor,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              icon: Icon(
                Icons.keyboard_arrow_down,
                color: subtleColor,
                size: 20,
              ),
              items: snapshot.data!.docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return DropdownMenuItem(
                  value: doc.id,
                  child: Text(data['name'] ?? 'Unknown House'),
                );
              }).toList(),
              onChanged: (v) {
                final selectedDoc = snapshot.data!.docs.firstWhere(
                  (d) => d.id == v,
                );
                final selectedName =
                    (selectedDoc.data() as Map<String, dynamic>)['name'] ??
                    "Household";
                setState(() {
                  _selectedHousehold = v;
                  _selectedHouseholdName = selectedName;
                });
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildFitbitTable() {
    return StreamBuilder<QuerySnapshot>(
      key: ValueKey(_viewType),
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('user_analytics')
          .doc('fitbit')
          .collection('entries')
          .orderBy('logicalDate', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00C897)),
          );
        }
        if (snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              "No Fitbit data found.",
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        _currentColumns = [
          "DATE",
          "SLEEP",
          "WAKE",
          "DURATION",
          "STEPS",
          "FLOORS",
          "RHR",
          "MIN HR",
          "MAX HR",
        ];
        _rawRows = DataCollector.parseFitbit(snapshot.data!.docs);

        return _buildStickyTable(
          flexOverride: [1.0, 2.0, 2.0, 3.0, 2.0, 2.0, 2.0, 3.0, 3.0],
        );
      },
    );
  }

  Widget _buildUserStatsTable() {
    return StreamBuilder<QuerySnapshot>(
      key: ValueKey(_viewType),
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('user_analytics')
          .doc('axis_forms')
          .collection('entries')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00C897)),
          );
        }
        if (snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              "No user data found.",
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        _currentColumns = [
          "DATE",
          "SLEEP",
          "WAKE",
          "SLEEP DURATION",
          "SLEEP QUALITY",
          "DAY RATING",
          "PRODUCTIVITY",
          "MIND",
        ];
        _rawRows = DataCollector.parseUserStats(snapshot.data!.docs);

        return _buildStickyTable(
          flexOverride: [1.0, 2.0, 2.0, 3.0, 3.0, 2.0, 3.0, 4.0],
        );
      },
    );
  }

  Widget _buildFinancesTable() {
    return StreamBuilder<QuerySnapshot>(
      key: ValueKey(_viewType),
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('finances')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00C897)),
          );
        }
        if (snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              "No finances found.",
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        _currentColumns = [
          "DATE",
          "STORE",
          "ITEM NAME",
          "COST",
          "TAX",
          "TOTAL",
        ];
        _rawRows = DataCollector.parseFinances(snapshot.data!.docs);

        return _buildStickyTable(flexOverride: [1.0, 3.0, 4.0, 2.0, 2.0, 2.0]);
      },
    );
  }

  Widget _buildActivityTable() {
    if (_selectedHousehold == null) {
      return const Center(
        child: Text(
          "Select a household.",
          style: TextStyle(color: Colors.white38),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      key: ValueKey(_viewType),
      stream: FirebaseFirestore.instance
          .collection('households')
          .doc(_selectedHousehold)
          .collection('activity_log')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00C897)),
          );
        }
        if (snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              "No activity history found.",
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        _currentColumns = [
          "DATE",
          "TIME",
          "USER",
          "ACTION",
          "QTY",
          "TOTAL",
          "ITEM",
        ];
        _rawRows = DataCollector.parseActivity(snapshot.data!.docs);

        return _buildStickyTable(
          flexOverride: [1.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0],
        );
      },
    );
  }
}

class _QuadrantClipper extends CustomClipper<Rect> {
  final double left, top, right, bottom;
  _QuadrantClipper(this.left, this.top, this.right, this.bottom);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(
      left,
      top,
      right == double.infinity ? size.width : right,
      bottom == double.infinity ? size.height : bottom,
    );
  }

  @override
  bool shouldReclip(_QuadrantClipper oldClipper) {
    return oldClipper.left != left ||
        oldClipper.top != top ||
        oldClipper.right != right ||
        oldClipper.bottom != bottom;
  }
}

enum EditMode { time, duration, date, money, text }

class _SmartEditCellDialog extends StatefulWidget {
  final String field;
  final String initialValue;

  const _SmartEditCellDialog({required this.field, required this.initialValue});

  @override
  State<_SmartEditCellDialog> createState() => _SmartEditCellDialogState();
}

class _SmartEditCellDialogState extends State<_SmartEditCellDialog> {
  late EditMode _mode;

  final TextEditingController _c1 = TextEditingController();
  final TextEditingController _c2 = TextEditingController();
  final TextEditingController _c3 = TextEditingController();

  final FocusNode _fn1 = FocusNode();
  final FocusNode _fn2 = FocusNode();
  final FocusNode _fn3 = FocusNode();

  bool _isPM = false;

  bool _hasErr1 = false;
  bool _hasErr2 = false;
  bool _hasErr3 = false;

  @override
  void initState() {
    super.initState();
    String f = widget.field;
    String val = widget.initialValue.trim();

    if (f == "SLEEP" || f == "WAKE" || f == "TIME") {
      _mode = EditMode.time;
      final match = RegExp(
        r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
        caseSensitive: false,
      ).firstMatch(val);
      if (match != null) {
        _c1.text = match.group(1)!;
        _c2.text = match.group(2)!;
        _isPM = match.group(3)!.toUpperCase() == 'PM';
      }
    } else if (f == "SLEEP DURATION") {
      _mode = EditMode.duration;
      final match = RegExp(
        r'(?:(\d+)h)?\s*(?:(\d+)m)?',
      ).firstMatch(val.toLowerCase());
      if (match != null) {
        if (match.group(1) != null) _c1.text = match.group(1)!;
        if (match.group(2) != null) _c2.text = match.group(2)!;
      }
    } else if (f == "DATE") {
      _mode = EditMode.date;
      List<String> parts = val.split('/');
      if (parts.length == 3) {
        _c1.text = parts[0];
        _c2.text = parts[1];
        _c3.text = parts[2];
      }
    } else if (f == "COST" || f == "TAX" || f == "TOTAL") {
      _mode = EditMode.money;
      _c1.text = val.replaceAll('\$', '').trim();
    } else {
      _mode = EditMode.text;
      _c1.text = val;
    }
  }

  @override
  void dispose() {
    _fn1.dispose();
    _fn2.dispose();
    _fn3.dispose();
    super.dispose();
  }

  void _save() {
    if (_hasErr1 || _hasErr2 || _hasErr3) return;

    String out = "";
    if (_mode == EditMode.time) {
      if (_c1.text.isNotEmpty || _c2.text.isNotEmpty) {
        out = "${_c1.text}:${_c2.text.padLeft(2, '0')} ${_isPM ? 'PM' : 'AM'}";
      }
    } else if (_mode == EditMode.duration) {
      int h = int.tryParse(_c1.text) ?? 0;
      int m = int.tryParse(_c2.text) ?? 0;
      if (_c1.text.isNotEmpty || _c2.text.isNotEmpty) {
        out = "${h}h ${m}m";
      }
    } else if (_mode == EditMode.date) {
      if (_c1.text.isNotEmpty || _c2.text.isNotEmpty || _c3.text.isNotEmpty) {
        out = "${_c1.text}/${_c2.text}/${_c3.text}";
      }
    } else {
      out = _c1.text.trim();
    }

    if (out.trim().isEmpty) {
      Navigator.pop(context, "__DELETE__");
    } else {
      Navigator.pop(context, out);
    }
  }

  void _validateTime1(String v) {
    int val = int.tryParse(v) ?? 0;
    bool err = v.isNotEmpty && (val < 1 || val > 12);
    setState(() => _hasErr1 = err);
    if (!err && v.isNotEmpty) {
      if (v.length == 2) {
        if (v.startsWith('0')) {
          _c1.value = TextEditingValue(
            text: val.toString(),
            selection: TextSelection.collapsed(offset: val.toString().length),
          );
        }
        _fn2.requestFocus();
      } else if (val > 1) {
        _fn2.requestFocus();
      }
    }
  }

  void _validateTime2(String v) {
    int val = int.tryParse(v) ?? 0;
    bool err = v.isNotEmpty && (val > 59 || (v.length == 1 && val >= 6));
    setState(() => _hasErr2 = err);
    if (!err && v.length == 2) FocusScope.of(context).unfocus();
  }

  void _validateDate1(String v) {
    int val = int.tryParse(v) ?? 0;
    bool err = v.isNotEmpty && (val < 1 || val > 12);
    setState(() => _hasErr1 = err);
    if (!err && v.isNotEmpty) {
      if (v.length == 2) {
        if (v.startsWith('0')) {
          _c1.value = TextEditingValue(
            text: val.toString(),
            selection: TextSelection.collapsed(offset: val.toString().length),
          );
        }
        _fn2.requestFocus();
      } else if (val > 1)
        _fn2.requestFocus();
    }
  }

  void _validateDate2(String v) {
    int val = int.tryParse(v) ?? 0;
    bool err = v.isNotEmpty && (val < 1 || val > 31);
    setState(() => _hasErr2 = err);
    if (!err && v.isNotEmpty) {
      if (v.length == 2) {
        if (v.startsWith('0')) {
          _c2.value = TextEditingValue(
            text: val.toString(),
            selection: TextSelection.collapsed(offset: val.toString().length),
          );
        }
        _fn3.requestFocus();
      } else if (val > 3)
        _fn3.requestFocus();
    }
  }

  void _validateDate3(String v) {
    if (v.length == 4) FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text(
        "Edit ${widget.field}",
        style: const TextStyle(color: Colors.white),
      ),
      content: SingleChildScrollView(child: _buildInputFields()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, "__DELETE__"),
          child: const Text(
            "Delete Data",
            style: TextStyle(color: Colors.redAccent),
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00C897),
            foregroundColor: Colors.black,
          ),
          onPressed: (_hasErr1 || _hasErr2 || _hasErr3) ? null : _save,
          child: const Text("Save"),
        ),
      ],
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  Widget _buildInputFields() {
    if (_mode == EditMode.time) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 45,
            child: _buildBox(
              _c1,
              "HH",
              focusNode: _fn1,
              maxLength: 2,
              onChanged: _validateTime1,
              hasError: _hasErr1,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              ":",
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
          ),
          SizedBox(
            width: 45,
            child: _buildBox(
              _c2,
              "MM",
              focusNode: _fn2,
              maxLength: 2,
              onChanged: _validateTime2,
              hasError: _hasErr2,
            ),
          ),
          const SizedBox(width: 15),
          GestureDetector(
            onTap: () => setState(() => _isPM = !_isPM),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF00C897).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _isPM ? "PM" : "AM",
                style: const TextStyle(
                  color: Color(0xFF00C897),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    } else if (_mode == EditMode.duration) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 50,
            child: _buildBox(
              _c1,
              "0",
              focusNode: _fn1,
              maxLength: 2,
              onChanged: (v) {
                if (v.length == 2) _fn2.requestFocus();
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              "h",
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ),
          SizedBox(
            width: 50,
            child: _buildBox(
              _c2,
              "0",
              focusNode: _fn2,
              maxLength: 2,
              onChanged: _validateTime2,
              hasError: _hasErr2,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              "m",
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ),
        ],
      );
    } else if (_mode == EditMode.date) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 45,
            child: _buildBox(
              _c1,
              "MM",
              focusNode: _fn1,
              maxLength: 2,
              onChanged: _validateDate1,
              hasError: _hasErr1,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text("/", style: TextStyle(color: Colors.white54)),
          ),
          SizedBox(
            width: 45,
            child: _buildBox(
              _c2,
              "DD",
              focusNode: _fn2,
              maxLength: 2,
              onChanged: _validateDate2,
              hasError: _hasErr2,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text("/", style: TextStyle(color: Colors.white54)),
          ),
          SizedBox(
            width: 60,
            child: _buildBox(
              _c3,
              "YYYY",
              focusNode: _fn3,
              maxLength: 4,
              onChanged: _validateDate3,
              hasError: _hasErr3,
            ),
          ),
        ],
      );
    } else if (_mode == EditMode.money) {
      return Row(
        children: [
          const Text(
            "\$ ",
            style: TextStyle(
              color: Color(0xFF00C897),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(child: _buildBox(_c1, "0.00", focusNode: _fn1)),
        ],
      );
    }

    return _buildBox(_c1, "Enter Text", focusNode: _fn1);
  }

  Widget _buildBox(
    TextEditingController ctrl,
    String hint, {
    FocusNode? focusNode,
    int? maxLength,
    Function(String)? onChanged,
    bool hasError = false,
  }) {
    return TextField(
      controller: ctrl,
      focusNode: focusNode,
      autofocus: focusNode == null || focusNode == _fn1,
      keyboardType: _mode == EditMode.text
          ? TextInputType.text
          : TextInputType.number,
      textAlign: _mode == EditMode.text ? TextAlign.left : TextAlign.center,
      style: TextStyle(
        color: hasError ? Colors.redAccent : Colors.white,
        fontSize: 16,
      ),
      maxLength: maxLength,
      onChanged: onChanged,
      decoration: InputDecoration(
        counterText: "",
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(
            color: hasError ? Colors.redAccent : Colors.white24,
          ),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(
            color: hasError ? Colors.redAccent : const Color(0xFF00C897),
          ),
        ),
      ),
    );
  }
}
