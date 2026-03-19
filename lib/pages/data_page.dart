import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'analytics_hub.dart';

// ==========================================
// INTEGRATION DATA MODEL
// ==========================================
class Integration {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  bool isConnected;
  List<String> availableData;
  List<String> selectedData;
  DateTime? lastSync;
  bool apiLimitReached;

  Integration({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    this.isConnected = false,
    required this.availableData,
    List<String>? selectedData,
    this.lastSync,
    this.apiLimitReached = false,
  }) : selectedData = selectedData ?? [];
}

// ==========================================
// DATA PAGE UI
// ==========================================
class DataPage extends StatefulWidget {
  const DataPage({super.key});

  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage>
    with AutomaticKeepAliveClientMixin {
  late List<Integration> _integrations;
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? "";

  final TextEditingController _fitbitClientIdCtrl = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _integrations = [
      Integration(
        id: 'fitbit',
        name: 'Fitbit',
        icon: Icons.watch,
        color: Colors.white,
        availableData: [
          'Sleep Time',
          'Sleep Duration',
          'Steps',
          'Floors',
          'Resting Heart Rate',
          'Heart Rate Extremes (Min/Max & Time)',
        ],
      ),
    ];
    _checkExistingConnections();
  }

  Future<void> _checkExistingConnections() async {
    if (_uid.isEmpty) return;
    var snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('integrations')
        .get();

    if (!mounted) return;

    for (var doc in snap.docs) {
      int idx = _integrations.indexWhere((i) => i.id == doc.id);
      if (idx != -1) {
        var d = doc.data();
        Timestamp? ts = d['lastSync'];

        setState(() {
          _integrations[idx].isConnected = true;
          _integrations[idx].selectedData = List<String>.from(
            d['preferences'] ?? [],
          );
          if (ts != null) _integrations[idx].lastSync = ts.toDate();
          _integrations[idx].apiLimitReached = d['apiLimitReached'] ?? false;
        });
      }
    }
  }

  @override
  void dispose() {
    _fitbitClientIdCtrl.dispose();
    super.dispose();
  }

  List<Integration> get _sortedIntegrations {
    List<Integration> sorted = List.from(_integrations);
    sorted.sort((a, b) {
      if (a.isConnected && !b.isConnected) return -1;
      if (!a.isConnected && b.isConnected) return 1;
      return a.name.compareTo(b.name);
    });
    return sorted;
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open webpage.")),
        );
      }
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    int h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    String ampm = dt.hour >= 12 ? "PM" : "AM";
    String time = "$h:${dt.minute.toString().padLeft(2, '0')} $ampm";
    if (isToday) return "Today at $time";
    return "${dt.month}/${dt.day}/${dt.year} at $time";
  }

  Widget _buildCopyableRow(String label, String textToCopy) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      textToCopy,
                      style: const TextStyle(
                        color: Color(0xFF00C897),
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: textToCopy));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Copied: $textToCopy"),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    child: const Icon(
                      Icons.copy,
                      color: Colors.white54,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _authenticateFitbit(Integration intg) async {
    final clientId = _fitbitClientIdCtrl.text.trim();
    if (clientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter your Client ID"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    try {
      final String callbackScheme = "axisapp";
      final String redirectUri = "$callbackScheme://callback";
      final String authUrl =
          "https://www.fitbit.com/oauth2/authorize?response_type=token&client_id=$clientId&redirect_uri=$redirectUri&scope=activity%20sleep%20profile%20heartrate&expires_in=31536000";

      final result = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: callbackScheme,
      );

      final fragment = Uri.parse(result).fragment;
      final params = Uri.splitQueryString(fragment);
      final accessToken = params['access_token'];

      if (accessToken != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .collection('integrations')
            .doc('fitbit')
            .set({
              'accessToken': accessToken,
              'connectedAt': FieldValue.serverTimestamp(),
              'preferences': intg.availableData,
            }, SetOptions(merge: true));

        if (!mounted) return;

        setState(() {
          intg.isConnected = true;
          intg.selectedData = List.from(intg.availableData);
        });

        Navigator.pop(context);
        _showDataSelectionModal(intg);
      }
    } catch (e) {
      debugPrint("OAuth Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Authentication Failed: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _safeApiCall(String url, String token) async {
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 429) {
        return {'RATE_LIMIT_REACHED': true};
      }
      if (res.statusCode == 200) {
        return json.decode(res.body);
      }
    } catch (e) {
      debugPrint("API Error on $url: $e");
    }
    return null;
  }

  Future<bool> _processFitbitChunk(
    String token,
    DateTime chunkStart,
    DateTime chunkEnd,
    Integration intg,
    CollectionReference fitbitRef,
    Map<String, Map<String, dynamic>> existingDataMap,
  ) async {
    bool limitReached = false;
    String startStr =
        "${chunkStart.year}-${chunkStart.month.toString().padLeft(2, '0')}-${chunkStart.day.toString().padLeft(2, '0')}";
    String endStr =
        "${chunkEnd.year}-${chunkEnd.month.toString().padLeft(2, '0')}-${chunkEnd.day.toString().padLeft(2, '0')}";

    Map<String, Map<String, dynamic>> chunkDays = {};
    for (int i = 0; i <= chunkEnd.difference(chunkStart).inDays; i++) {
      DateTime currentDay = chunkStart.add(Duration(days: i));
      String cStr =
          "${currentDay.year}-${currentDay.month.toString().padLeft(2, '0')}-${currentDay.day.toString().padLeft(2, '0')}";
      chunkDays[cStr] = {
        'logicalDate': cStr,
        'timestamp': currentDay.toIso8601String(),
      };
    }

    if (intg.selectedData.contains('Sleep Time') ||
        intg.selectedData.contains('Sleep Duration')) {
      final data = await _safeApiCall(
        "https://api.fitbit.com/1.2/user/-/sleep/date/$startStr/$endStr.json",
        token,
      );
      if (data?['RATE_LIMIT_REACHED'] == true) {
        limitReached = true;
      } else if (data != null && data['sleep'] != null) {
        for (var session in data['sleep']) {
          if (session['isMainSleep'] == true) {
            String dateOfSleep = session['dateOfSleep'];
            if (chunkDays.containsKey(dateOfSleep)) {
              if (intg.selectedData.contains('Sleep Time')) {
                chunkDays[dateOfSleep]!['sleepTime'] = session['startTime'];
                chunkDays[dateOfSleep]!['wakeTime'] = session['endTime'];
              }
              if (intg.selectedData.contains('Sleep Duration')) {
                int durationMins = session['minutesAsleep'];
                int h = durationMins ~/ 60;
                int m = durationMins % 60;
                chunkDays[dateOfSleep]!['sleepDuration'] = "${h}h ${m}m";
              }
            }
          }
        }
      }
    }

    if (!limitReached && intg.selectedData.contains('Steps')) {
      final data = await _safeApiCall(
        "https://api.fitbit.com/1/user/-/activities/steps/date/$startStr/$endStr.json",
        token,
      );
      if (data?['RATE_LIMIT_REACHED'] == true) {
        limitReached = true;
      } else if (data != null && data['activities-steps'] != null) {
        for (var dayStep in data['activities-steps']) {
          String dateOfStep = dayStep['dateTime'];
          if (chunkDays.containsKey(dateOfStep)) {
            chunkDays[dateOfStep]!['steps'] = dayStep['value'].toString();
          }
        }
      }
    }

    if (!limitReached && intg.selectedData.contains('Floors')) {
      final data = await _safeApiCall(
        "https://api.fitbit.com/1/user/-/activities/floors/date/$startStr/$endStr.json",
        token,
      );
      if (data?['RATE_LIMIT_REACHED'] == true) {
        limitReached = true;
      } else if (data != null && data['activities-floors'] != null) {
        for (var dayFloor in data['activities-floors']) {
          String dateOfFloor = dayFloor['dateTime'];
          if (chunkDays.containsKey(dateOfFloor)) {
            chunkDays[dateOfFloor]!['floors'] = dayFloor['value'].toString();
          }
        }
      }
    }

    if (!limitReached && intg.selectedData.contains('Resting Heart Rate')) {
      final data = await _safeApiCall(
        "https://api.fitbit.com/1/user/-/activities/heart/date/$startStr/$endStr.json",
        token,
      );
      if (data?['RATE_LIMIT_REACHED'] == true) {
        limitReached = true;
      } else if (data != null && data['activities-heart'] != null) {
        for (var dayHR in data['activities-heart']) {
          String dateOfHR = dayHR['dateTime'];
          if (chunkDays.containsKey(dateOfHR) && dayHR['value'] != null) {
            if (dayHR['value']['restingHeartRate'] != null) {
              chunkDays[dateOfHR]!['restingHeartRate'] =
                  dayHR['value']['restingHeartRate'].toString();
            }
          }
        }
      }
    }

    if (!limitReached &&
        intg.selectedData.contains('Heart Rate Extremes (Min/Max & Time)')) {
      DateTime today = DateTime.now();
      String todayStr =
          "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

      for (int i = chunkEnd.difference(chunkStart).inDays; i >= 0; i--) {
        if (limitReached) break;

        DateTime targetDay = chunkStart.add(Duration(days: i));
        String dateStr =
            "${targetDay.year}-${targetDay.month.toString().padLeft(2, '0')}-${targetDay.day.toString().padLeft(2, '0')}";

        bool isToday = dateStr == todayStr;
        bool needsIntraday = false;

        if (isToday) {
          needsIntraday = true;
        } else {
          var existingDay = existingDataMap[dateStr];
          if (existingDay == null ||
              ((existingDay['minHr'] == null || existingDay['minHr'] == "") &&
                  existingDay['intradayAttempted'] != true)) {
            needsIntraday = true;
          }
        }

        if (needsIntraday) {
          final data = await _safeApiCall(
            "https://api.fitbit.com/1/user/-/activities/heart/date/$dateStr/1d/1min.json",
            token,
          );

          if (data?['RATE_LIMIT_REACHED'] == true) {
            limitReached = true;
            break;
          } else if (data != null) {
            chunkDays[dateStr]!['intradayAttempted'] = true;

            if (data['activities-heart-intraday'] != null &&
                data['activities-heart-intraday']['dataset'] != null) {
              List dataset = data['activities-heart-intraday']['dataset'];
              if (dataset.isNotEmpty) {
                int minVal = 999;
                int maxVal = -1;
                String minTime = "";
                String maxTime = "";

                for (var point in dataset) {
                  int val = point['value'];
                  if (val < minVal) {
                    minVal = val;
                    minTime = point['time'];
                  }
                  if (val > maxVal) {
                    maxVal = val;
                    maxTime = point['time'];
                  }
                }

                chunkDays[dateStr]!['minHr'] = minVal.toString();
                chunkDays[dateStr]!['minTime'] = "${dateStr}T$minTime";
                chunkDays[dateStr]!['maxHr'] = maxVal.toString();
                chunkDays[dateStr]!['maxTime'] = "${dateStr}T$maxTime";
              } else {
                chunkDays[dateStr]!['minHr'] = "";
                chunkDays[dateStr]!['minTime'] = "";
                chunkDays[dateStr]!['maxHr'] = "";
                chunkDays[dateStr]!['maxTime'] = "";
              }
            }
          }
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    }

    WriteBatch batch = FirebaseFirestore.instance.batch();
    chunkDays.forEach((date, data) {
      batch.set(fitbitRef.doc(date), data, SetOptions(merge: true));
    });
    await batch.commit();

    return limitReached;
  }

  Future<void> _syncFitbitData(Integration intg) async {
    if (_uid.isEmpty) return;

    var intgDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('integrations')
        .doc('fitbit')
        .get();
    if (!intgDoc.exists) return;
    String token = intgDoc.data()?['accessToken'] ?? "";
    if (token.isEmpty) return;

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Color(0xFF00C897),
                  strokeWidth: 2,
                ),
              ),
              SizedBox(width: 15),
              Text("Syncing Fitbit data... (This may take a moment)"),
            ],
          ),
          duration: Duration(days: 1),
          backgroundColor: Color(0xFF2C2C2C),
        ),
      );
    }

    try {
      CollectionReference fitbitRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('user_analytics')
          .doc('fitbit')
          .collection('entries');

      var existingDocsSnap = await fitbitRef.get();
      Map<String, Map<String, dynamic>> existingDataMap = {};
      for (var doc in existingDocsSnap.docs) {
        existingDataMap[doc.id] = doc.data() as Map<String, dynamic>;
      }

      final profileRes = await _safeApiCall(
        "https://api.fitbit.com/1/user/-/profile.json",
        token,
      );
      DateTime profileStartDate = DateTime.now().subtract(
        const Duration(days: 365),
      );
      if (profileRes != null && profileRes['user'] != null) {
        profileStartDate = DateTime.parse(profileRes['user']['memberSince']);
      }

      DateTime today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );

      bool limitReached = false;
      DateTime chunkEnd = today;

      while (!limitReached && chunkEnd.isAfter(profileStartDate)) {
        DateTime chunkStart = chunkEnd.subtract(const Duration(days: 99));

        if (chunkStart.isBefore(profileStartDate)) {
          chunkStart = profileStartDate;
        }

        limitReached = await _processFitbitChunk(
          token,
          chunkStart,
          chunkEnd,
          intg,
          fitbitRef,
          existingDataMap,
        );

        if (!limitReached) {
          chunkEnd = chunkStart.subtract(const Duration(days: 1));
        }
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('integrations')
          .doc(intg.id)
          .update({
            'lastSync': FieldValue.serverTimestamp(),
            'apiLimitReached': limitReached,
          });

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        setState(() {
          intg.lastSync = DateTime.now();
          intg.apiLimitReached = limitReached;
        });

        if (limitReached) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Fitbit API Limit Reached. Progress saved. Re-sync in an hour to continue backfilling.",
              ),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 5),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Fitbit sync complete!"),
              backgroundColor: Color(0xFF00C897),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Sync Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Sync Error: $e"),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _connectFitbitFlow(Integration intg) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Row(
          children: [
            Icon(intg.icon, color: intg.color),
            const SizedBox(width: 10),
            const Text(
              "Fitbit Setup",
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Step 1: Register App",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                "Go to the Fitbit developer portal, log in, and click 'Register An App'.",
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              TextButton.icon(
                onPressed: () => _launchUrl('https://dev.fitbit.com/apps/new'),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text("Open dev.fitbit.com"),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF00C897),
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                ),
              ),
              const Divider(color: Colors.white12, height: 20),

              const Text(
                "Step 2: App Settings",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                "Paste these exactly into the form. Set 'Application Type' to Personal and 'Default Access' to Read-Only. (Intraday HR requires Personal type).",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),

              _buildCopyableRow("App Name", "Axis"),
              _buildCopyableRow("Description", "Personal analytics dashboard."),
              _buildCopyableRow("Organization", "Axis"),
              _buildCopyableRow("All 4 URLs", "https://google.com"),
              _buildCopyableRow("Redirect URL", "axisapp://callback"),

              const Divider(color: Colors.white12, height: 30),

              const Text(
                "Step 3: Enter Key",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                "Once saved, paste the OAuth 2.0 Client ID below to connect.",
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 15),

              _buildInputField(
                "OAuth 2.0 Client ID",
                _fitbitClientIdCtrl,
                false,
                const Color(0xFF00C897),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C897),
              foregroundColor: Colors.black,
            ),
            onPressed: () => _authenticateFitbit(intg),
            // Corrected: Bold styling must go on the Text widget!
            child: const Text(
              "Login to Fitbit",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showDataSelectionModal(Integration intg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20.0,
                right: 20.0,
                top: 20.0,
                bottom: MediaQuery.of(context).viewInsets.bottom + 30.0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${intg.name} Data",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(_uid)
                              .collection('integrations')
                              .doc(intg.id)
                              .delete();
                          if (!mounted) return;
                          setState(() {
                            intg.isConnected = false;
                            intg.selectedData.clear();
                            intg.lastSync = null;
                            intg.apiLimitReached = false;
                          });
                          Navigator.pop(context);
                        },
                        child: const Text(
                          "Disconnect",
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    "Select the data you want to automatically pull:",
                    style: TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 15),

                  ...intg.availableData.map((dataPoint) {
                    bool isSelected = intg.selectedData.contains(dataPoint);
                    return CheckboxListTile(
                      title: Text(
                        dataPoint,
                        style: const TextStyle(color: Colors.white),
                      ),
                      value: isSelected,
                      activeColor: const Color(0xFF00C897),
                      checkColor: Colors.black,
                      side: const BorderSide(color: Colors.white54),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (val) {
                        setModalState(() {
                          if (val == true) {
                            intg.selectedData.add(dataPoint);
                          } else {
                            intg.selectedData.remove(dataPoint);
                          }
                        });
                        setState(() {});
                      },
                    );
                  }),
                  const SizedBox(height: 25),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C897),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(_uid)
                            .collection('integrations')
                            .doc(intg.id)
                            .update({'preferences': intg.selectedData});
                        if (!mounted) return;
                        Navigator.pop(context);

                        if (intg.id == 'fitbit') {
                          _syncFitbitData(intg);
                        }
                      },
                      child: const Text(
                        "Save & Sync Now",
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _handleIntegrationTap(Integration intg) {
    if (intg.isConnected) {
      _showDataSelectionModal(intg);
    } else {
      if (intg.id == 'fitbit') {
        _connectFitbitFlow(intg);
      }
    }
  }

  Widget _buildIntegrationCard(Integration intg) {
    Widget subtitleContent;
    if (intg.isConnected) {
      subtitleContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "${intg.selectedData.length} data points syncing",
            style: const TextStyle(color: Color(0xFF00C897), fontSize: 12),
          ),
          if (intg.lastSync != null) ...[
            const SizedBox(height: 2),
            Text(
              "Last synced: ${_formatDate(intg.lastSync!)}",
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
          if (intg.apiLimitReached) ...[
            const SizedBox(height: 2),
            const Text(
              "Stopped: Maximum API requests reached",
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      );
    } else {
      subtitleContent = const Text(
        "Tap to connect",
        style: TextStyle(color: Colors.white54, fontSize: 12),
      );
    }

    return InkWell(
      onTap: () => _handleIntegrationTap(intg),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: intg.isConnected
                ? const Color(0xFF00C897).withOpacity(0.5)
                : Colors.white12,
            width: intg.isConnected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(intg.icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    intg.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  subtitleContent,
                ],
              ),
            ),
            const SizedBox(width: 8),
            intg.isConnected
                ? const Icon(
                    Icons.check_circle,
                    color: Color(0xFF00C897),
                    size: 26,
                  )
                : const Icon(
                    Icons.add_circle_outline,
                    color: Colors.white38,
                    size: 26,
                  ),
          ],
        ),
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, topPadding, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Analytics",
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              "Track your trends and link services",
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 30),

            // Analytics Hub Hero Button
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AnalyticsPageWrapper(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C897).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00C897).withOpacity(0.3),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C897).withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.insights,
                        color: Color(0xFF00C897),
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Analytics Hub",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "View spreadsheets & visual data",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 45),
            const Text(
              "Integrations",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),

            // Responsive Masonry List for Integrations
            LayoutBuilder(
              builder: (context, constraints) {
                int crossAxisCount = (constraints.maxWidth / 320).floor();
                if (crossAxisCount < 1) crossAxisCount = 1;

                List<List<Integration>> columns = List.generate(
                  crossAxisCount,
                  (_) => [],
                );
                for (int i = 0; i < _sortedIntegrations.length; i++) {
                  columns[i % crossAxisCount].add(_sortedIntegrations[i]);
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(crossAxisCount, (colIndex) {
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: colIndex < crossAxisCount - 1 ? 16.0 : 0.0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: columns[colIndex].map((intg) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: _buildIntegrationCard(intg),
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField(
    String label,
    TextEditingController ctrl,
    bool isObscured,
    Color activeColor,
  ) {
    return TextField(
      controller: ctrl,
      obscureText: isObscured,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        filled: true,
        fillColor: Colors.black26,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: activeColor),
        ),
      ),
    );
  }
}
