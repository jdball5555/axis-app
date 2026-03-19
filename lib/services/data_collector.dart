import 'package:cloud_firestore/cloud_firestore.dart';

// ==========================================
// UNIFIED DATA MODEL
// ==========================================
class AnalyticsRow {
  final String docId;
  final DateTime timestamp;
  final List<String> rawData;

  // Custom UI Flags (Abstracts Widget building out of the data layer)
  final String? duplicateOrdinal;
  final bool isPrevDaySleep;

  AnalyticsRow(
    this.docId,
    this.timestamp,
    this.rawData, {
    this.duplicateOrdinal,
    this.isPrevDaySleep = false,
  });
}

// ==========================================
// FIREBASE PARSING ENGINE
// ==========================================
class DataCollector {
  // Helper to instantly wipe out legacy "N/A"s from the database
  static String _clean(dynamic val) {
    if (val == null) return "";
    String s = val.toString().trim();
    if (s == "N/A") return "";
    return s;
  }

  static String _fmtTime(String? t) {
    if (t == null || t.trim().isEmpty || t == "N/A") return "";
    try {
      DateTime dt = DateTime.parse(t);
      int h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      String amPm = dt.hour >= 12 ? "PM" : "AM";
      return "$h:${dt.minute.toString().padLeft(2, '0')} $amPm";
    } catch (_) {
      return "";
    }
  }

  static List<AnalyticsRow> parseFitbit(List<QueryDocumentSnapshot> docs) {
    List<AnalyticsRow> rows = [];
    for (var doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      DateTime rawDate = DateTime.now();
      if (d['logicalDate'] != null) {
        try {
          List<String> parts = d['logicalDate'].toString().split('-');
          if (parts.length == 3) {
            rawDate = DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            );
          }
        } catch (_) {}
      } else {
        try {
          if (doc.id.contains('_')) {
            rawDate = DateTime.parse(doc.id.split('_')[0]);
          } else {
            rawDate = DateTime.parse(doc.id);
          }
        } catch (_) {}
      }

      // Clean the values and combine them for the UI display
      String minHrVal = _clean(d['minHr']);
      String minTimeVal = _fmtTime(d['minTime']);
      String minCombined = minHrVal.isNotEmpty
          ? (minTimeVal.isNotEmpty ? "$minHrVal ($minTimeVal)" : minHrVal)
          : "";

      String maxHrVal = _clean(d['maxHr']);
      String maxTimeVal = _fmtTime(d['maxTime']);
      String maxCombined = maxHrVal.isNotEmpty
          ? (maxTimeVal.isNotEmpty ? "$maxHrVal ($maxTimeVal)" : maxHrVal)
          : "";

      rows.add(
        AnalyticsRow(doc.id, rawDate, [
          "${rawDate.month}/${rawDate.day}/${rawDate.year}",
          _fmtTime(d['sleepTime']),
          _fmtTime(d['wakeTime']),
          _clean(d['sleepDuration']),
          _clean(d['steps']),
          _clean(d['floors']),
          _clean(d['restingHeartRate']),
          minCombined,
          maxCombined,
        ]),
      );
    }
    rows.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return rows;
  }

  static List<AnalyticsRow> parseUserStats(List<QueryDocumentSnapshot> docs) {
    List<AnalyticsRow> rows = [];
    for (var doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      DateTime rawDate = DateTime.now();
      if (d['logicalDate'] != null) {
        List<String> parts = d['logicalDate'].toString().split('-');
        if (parts.length == 3) {
          rawDate = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );
        }
      } else {
        try {
          if (doc.id.contains('_')) {
            rawDate = DateTime.parse(doc.id.split('_')[0]);
          } else {
            rawDate = DateTime.parse(doc.id);
          }
        } catch (_) {}
      }

      String dateStr = "${rawDate.month}/${rawDate.day}/${rawDate.year}";
      String sleepStr = _fmtTime(d['sleepTime']);
      String mindStr = "";
      if (d['mindTiles'] != null && d['mindTiles'] is List) {
        mindStr = (d['mindTiles'] as List).join(", ");
      } else if (d['mindTiles'] != null) {
        mindStr = d['mindTiles'].toString();
      }

      String? ordinal;
      List<String> idParts = doc.id.split('-');
      if (idParts.length > 3) {
        String dupNumber = idParts[3];
        ordinal = dupNumber == "2"
            ? "2nd"
            : dupNumber == "3"
            ? "3rd"
            : "${dupNumber}th";
      }

      bool isPrevDay = false;
      if (d['sleepTime'] != null && d['sleepTime'].toString().isNotEmpty) {
        try {
          DateTime st = DateTime.parse(d['sleepTime']);
          DateTime targetDate = rawDate;
          if (d['wakeTime'] != null && d['wakeTime'].toString().isNotEmpty) {
            targetDate = DateTime.parse(d['wakeTime']);
          }
          if (st.day != targetDate.day ||
              st.month != targetDate.month ||
              st.year != targetDate.year) {
            isPrevDay = true;
          }
        } catch (_) {}
      }

      rows.add(
        AnalyticsRow(
          doc.id,
          rawDate,
          [
            dateStr,
            sleepStr,
            _fmtTime(d['wakeTime']),
            _clean(d['sleepDuration']),
            _clean(d['sleepQuality']),
            _clean(d['rating']),
            _clean(d['productivity']),
            mindStr,
          ],
          duplicateOrdinal: ordinal,
          isPrevDaySleep: isPrevDay,
        ),
      );
    }
    rows.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return rows;
  }

  static List<AnalyticsRow> parseFinances(List<QueryDocumentSnapshot> docs) {
    List<AnalyticsRow> rows = [];
    for (var doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      DateTime rawDate = DateTime.now();
      if (d['date'] != null) {
        try {
          List<String> parts = d['date'].toString().split('/');
          if (parts.length == 3) {
            rawDate = DateTime(
              int.parse(parts[2]),
              int.parse(parts[0]),
              int.parse(parts[1]),
            );
          }
        } catch (_) {}
      }

      String dateStr =
          d['date']?.toString() ??
          "${rawDate.month}/${rawDate.day}/${rawDate.year}";
      String storeStr = (d['store'] ?? "Unknown").toString();
      String totalStr = d['total'] != null
          ? "\$${(d['total'] as num).toStringAsFixed(2)}"
          : "";
      String taxStr = d['tax'] != null
          ? "\$${(d['tax'] as num).toStringAsFixed(2)}"
          : "";

      List<Map<String, dynamic>> itemsList = [];
      if (d['items'] is List) {
        for (var item in d['items']) {
          if (item is Map) {
            itemsList.add(Map<String, dynamic>.from(item));
          } else {
            itemsList.add({'name': item.toString(), 'price': 0.0});
          }
        }
      }

      if (itemsList.isEmpty) {
        rows.add(
          AnalyticsRow("${doc.id}_0", rawDate, [
            dateStr,
            storeStr,
            "No Items",
            "",
            taxStr,
            totalStr,
          ]),
        );
      } else {
        itemsList.sort((a, b) {
          double priceA =
              double.tryParse(
                a['price']?.toString().replaceAll('\$', '') ?? '0',
              ) ??
              0.0;
          double priceB =
              double.tryParse(
                b['price']?.toString().replaceAll('\$', '') ?? '0',
              ) ??
              0.0;
          return priceB.compareTo(priceA);
        });

        for (int i = 0; i < itemsList.length; i++) {
          final item = itemsList[i];
          String itemName = item['name']?.toString() ?? "Item";
          double price =
              double.tryParse(
                item['price']?.toString().replaceAll('\$', '') ?? '0',
              ) ??
              0.0;
          String costStr = "\$${price.toStringAsFixed(2)}";

          if (i == 0) {
            rows.add(
              AnalyticsRow("${doc.id}_$i", rawDate, [
                dateStr,
                storeStr,
                itemName,
                costStr,
                taxStr,
                totalStr,
              ]),
            );
          } else {
            rows.add(
              AnalyticsRow("${doc.id}_$i", rawDate, [
                "",
                "",
                itemName,
                costStr,
                "",
                "",
              ]),
            );
          }
        }
      }
    }
    rows.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return rows;
  }

  static List<AnalyticsRow> parseActivity(List<QueryDocumentSnapshot> docs) {
    List<AnalyticsRow> rows = [];
    for (var doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      dynamic rawTime = d['timestamp'];
      DateTime dt = DateTime.now();
      if (rawTime is String) {
        dt = DateTime.tryParse(rawTime) ?? DateTime.now();
      } else if (rawTime is Timestamp) {
        dt = rawTime.toDate();
      }

      String dateStr = "${dt.month}/${dt.day}/${dt.year}";
      int h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      String timeStr =
          "$h:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? "PM" : "AM"}";

      String qtyStr = _clean(d['change']);
      if (d['change'] != null &&
          d['change'] is num &&
          (d['change'] as num) > 0) {
        qtyStr = "+$qtyStr";
      }

      rows.add(
        AnalyticsRow(doc.id, dt, [
          dateStr,
          timeStr,
          (d['user'] ?? "Unknown").toString(),
          (d['action'] ?? "").toString().toUpperCase(),
          qtyStr,
          _clean(d['total']),
          _clean(d['item']),
        ]),
      );
    }
    rows.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return rows;
  }
}
