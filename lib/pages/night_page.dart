import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/notification_service.dart'; // <-- ADDED IMPORT

// =========================================================
// GLOBAL MEMORY BANK
// =========================================================
class DebriefSession {
  static bool hasFetchedInitialData = false;
  static int currentIndex = 0;
  static Map<String, dynamic> answers = {};
  static Set<String> selectedMindTiles = {};
  static List<String> recentMindTiles = [];
  static List<String> todaysInventoryLogs = [];
  static DateTime? sleepTime;

  static void reset() {
    hasFetchedInitialData = false;
    currentIndex = 0;
    answers.clear();
    selectedMindTiles.clear();
    todaysInventoryLogs.clear();
    sleepTime = null;
  }
}

class NightDebriefTab extends StatefulWidget {
  final bool autoStart;
  final VoidCallback? onConsumeAutoStart;
  final VoidCallback? onGoToInventory;
  final VoidCallback? onWakeUp;

  const NightDebriefTab({
    super.key,
    this.autoStart = false,
    this.onConsumeAutoStart,
    this.onGoToInventory,
    this.onWakeUp,
  });

  @override
  State<NightDebriefTab> createState() => _NightDebriefTabState();
}

class _NightDebriefTabState extends State<NightDebriefTab> {
  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      Future.microtask(() {
        _startDebrief();
        widget.onConsumeAutoStart?.call();
      });
    }
  }

  void _startDebrief() async {
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const NightDebriefFlow(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );

    if (result == 'goto_inventory') {
      widget.onGoToInventory?.call();
    } else if (result == 'wake_up') {
      widget.onWakeUp?.call();
    } else {
      setState(() {});
    }
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          "How Data is Stored",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Your Day Rating, Productivity, and Mind logs are saved to the day you lived (Noon to Noon).\n\n"
          "Your Sleep Data is saved to the day you wake up.\n\n"
          "If you sleep on the 19th and wake up on the 20th, two folders are used. If you submit multiple times in a day, duplicates (-2, -3) are generated automatically so no data is lost.",
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text(
              "Got it",
              style: TextStyle(color: Color(0xFF00C897)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isResuming = DebriefSession.currentIndex > 0;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.nights_stay, size: 60, color: Colors.white24),
          const SizedBox(height: 20),
          const Text(
            "Nightly Debrief",
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isResuming
                ? "Your session is paused."
                : "Close your loops. Clear your mind.",
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 50),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _startDebrief,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C897),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: Text(
                  isResuming ? "Continue Debrief" : "Begin Debrief",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 15),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
                child: IconButton(
                  icon: const Icon(Icons.info_outline, color: Colors.white54),
                  onPressed: _showInfoDialog,
                  tooltip: "How data is stored",
                ),
              ),
            ],
          ),

          if (isResuming)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: TextButton(
                onPressed: () {
                  DebriefSession.reset();
                  setState(() {});
                },
                child: const Text(
                  "Start Over",
                  style: TextStyle(color: Colors.white38),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =========================================================
// FULL SCREEN FLOW
// =========================================================

class NightDebriefFlow extends StatefulWidget {
  final bool startAsleep;

  const NightDebriefFlow({super.key, this.startAsleep = false});

  @override
  State<NightDebriefFlow> createState() => _NightDebriefFlowState();
}

class _NightDebriefFlowState extends State<NightDebriefFlow>
    with SingleTickerProviderStateMixin {
  bool _isAsleep = false;
  bool _showEarlyWakeConfirm = false;
  String _userName = "David";
  late AnimationController _sleepAnimController;

  final List<String> _activeBlocks = [
    'preset_rate_day',
    'preset_ai_response_1',
    'preset_productivity',
    'preset_mind_tiles',
    'preset_interesting',
    'preset_inventory_check',
    'preset_alarm_check',
    'preset_ai_close_sleep',
  ];

  final TextEditingController _textController = TextEditingController();
  final TextEditingController _mindController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sleepAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _isAsleep = widget.startAsleep;
    if (_isAsleep) {
      _sleepAnimController.value = 1.0;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null &&
        user.displayName != null &&
        user.displayName!.isNotEmpty) {
      _userName = user.displayName!.split(' ').first;
    }

    _fetchRealData();
  }

  Future<void> _fetchRealData() async {
    final now = DateTime.now();
    final user = FirebaseAuth.instance.currentUser;

    if (!DebriefSession.hasFetchedInitialData && user != null) {
      Set<String> thirtyDayTiles = {};

      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('user_analytics')
            .doc('axis_forms')
            .collection('entries')
            .get();

        final thirtyDaysAgo = now.subtract(const Duration(days: 30));

        for (var doc in snapshot.docs) {
          final d = doc.data();
          if (d['logicalDate'] != null) {
            try {
              DateTime dt = DateTime.parse(d['logicalDate']);
              if (dt.isAfter(thirtyDaysAgo)) {
                if (d['mindTiles'] != null && d['mindTiles'] is List) {
                  for (var t in d['mindTiles']) {
                    if (t.toString().trim().isNotEmpty) {
                      thirtyDayTiles.add(t.toString().trim());
                    }
                  }
                }
              }
            } catch (e) {}
          }
        }
      } catch (e) {
        debugPrint("Error fetching tiles: $e");
      }

      DebriefSession.recentMindTiles = thirtyDayTiles.toList();
      DebriefSession.hasFetchedInitialData = true;
    }

    final prefs = await SharedPreferences.getInstance();
    List<String> activityLogs = prefs.getStringList('axis_activity_log') ?? [];
    List<String> todaysLogs = [];
    String todayStr = now.toIso8601String().split('T')[0];

    for (var log in activityLogs) {
      if (log.startsWith(todayStr)) {
        var parts = log.split('|');
        if (parts.length >= 3) {
          String action = parts[1].toUpperCase();
          String item = parts[2];
          if (action.contains("USED"))
            todaysLogs.add("Used: $item");
          else if (action.contains("RESTOCK"))
            todaysLogs.add("Restocked: $item");
        }
      }
    }
    DebriefSession.todaysInventoryLogs = todaysLogs;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sleepAnimController.dispose();
    _textController.dispose();
    _mindController.dispose();
    super.dispose();
  }

  void _nextBlock() {
    FocusScope.of(context).unfocus();
    setState(() {
      if (DebriefSession.currentIndex < _activeBlocks.length - 1) {
        DebriefSession.currentIndex++;
        _textController.clear();
      }
    });
  }

  Future<void> _submitDebriefNow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DebriefSession.sleepTime ?? DateTime.now();

    DateTime logicalDate = now.subtract(const Duration(hours: 12));
    String dateStr =
        "${logicalDate.year}-${logicalDate.month.toString().padLeft(2, '0')}-${logicalDate.day.toString().padLeft(2, '0')}";

    String baseDocId = dateStr;
    String docId = baseDocId;
    int suffix = 1;

    while (true) {
      final docSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('user_analytics')
          .doc('axis_forms')
          .collection('entries')
          .doc(docId)
          .get();

      if (!docSnap.exists) break;

      final data = docSnap.data() as Map<String, dynamic>;
      if (data['rating'] == null || data['rating'].toString().isEmpty) {
        break;
      }

      suffix++;
      docId = "$baseDocId-$suffix";
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('axis_current_doc_id', docId);
    await prefs.setString('axis_current_sleep_time', now.toIso8601String());

    final interestingStr = (DebriefSession.answers['interesting'] ?? "")
        .toString();

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('user_analytics')
        .doc('axis_forms')
        .collection('entries')
        .doc(docId)
        .set({
          'logicalDate': dateStr,
          'timestamp': now.toIso8601String(),
          'createdAt': now.toIso8601String(),
          'rating': DebriefSession.answers['rate_day'] ?? "",
          'productivity': DebriefSession.answers['productivity'] ?? "",
          'mindTiles': DebriefSession.selectedMindTiles.toList(),
          'interestingNote': interestingStr,
        }, SetOptions(merge: true));
  }

  void _wakeUp() {
    _sleepAnimController.reverse().then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('axis_is_sleeping', false);

      // <-- REMOVE THE NOTIFICATION UPON WAKING UP
      await NotificationService().cancelSleepNotification();

      DebriefSession.reset();
      if (mounted) Navigator.pop(context, 'wake_up');
    });
  }

  // --- UI PRESETS ---

  Widget _buildRateDay() {
    final options = [
      "It was horrible",
      "It was pretty terrible",
      "It wasn't great",
      "It was ok",
      "It was good",
      "It was pretty great",
      "It was amazing!",
      "Best day ever!",
    ];
    return _buildChoiceList("How would you rate today?", options, (choice) {
      DebriefSession.answers['rate_day'] = choice;
      _nextBlock();
    });
  }

  Widget _buildAIResponse1() {
    final rating = DebriefSession.answers['rate_day'] ?? "It was good";
    final random = Random();

    List<List<String>> responses;

    switch (rating) {
      case "It was horrible":
        responses = [
          [
            "I'm so sorry today was so difficult, $_userName.",
            "Take a deep breath. You survived it, and tomorrow is a new beginning.",
          ],
          [
            "That sounds incredibly tough, $_userName.",
            "Let's let it go. Tomorrow owes you nothing.",
          ],
          [
            "I hear you, $_userName. Today was a heavy one.",
            "Close the loop on it. Rest is your priority now.",
          ],
        ];
        break;
      case "It was pretty terrible":
        responses = [
          [
            "I'm sorry it was such a rough day, $_userName.",
            "You made it to the end. Let's reset your mind.",
          ],
          [
            "Days like this are exhausting, $_userName.",
            "Be kind to yourself tonight. Let's wind down.",
          ],
          [
            "That's really frustrating, $_userName.",
            "Let's put this day behind us. Tomorrow is a blank slate.",
          ],
        ];
        break;
      case "It wasn't great":
        responses = [
          [
            "I'm sorry it wasn't the best day, $_userName.",
            "Not every day can be a win. Let's prepare for a better tomorrow.",
          ],
          [
            "Those mediocre days can drain you, $_userName.",
            "Let's shake it off and get some good rest.",
          ],
          [
            "I hear you, $_userName. Tomorrow is another chance.",
            "Let's clear the noise and get ready for it.",
          ],
        ];
        break;
      case "It was ok":
        responses = [
          [
            "Sometimes 'ok' is exactly what we need, $_userName.",
            "Let's coast into the evening and recharge.",
          ],
          [
            "A steady day is a good day, $_userName.",
            "Let's log it and get you some well-deserved rest.",
          ],
          [
            "Not too bad, not too crazy, $_userName.",
            "Let's clear your mind for whatever tomorrow brings.",
          ],
        ];
        break;
      case "It was good":
        responses = [
          [
            "I'm glad you had a good day, $_userName.",
            "Let's capture those good vibes and wind down.",
          ],
          [
            "A solid day in the books, $_userName.",
            "Great work today. Let's tie off the loose ends.",
          ],
          [
            "Glad to hear it, $_userName!",
            "Let's finish up so you can enjoy your evening.",
          ],
        ];
        break;
      case "It was pretty great":
        responses = [
          [
            "That's awesome to hear, $_userName!",
            "Keep that momentum going. Let's clear your head for tomorrow.",
          ],
          [
            "Love to see a great day, $_userName.",
            "Let's lock it in and get you some rest.",
          ],
          [
            "Sounds like things really clicked today, $_userName.",
            "Let's clear your mind so you can wake up fresh.",
          ],
        ];
        break;
      case "It was amazing!":
        responses = [
          [
            "Incredible! I'm thrilled for you, $_userName.",
            "Days like this are what it's all about. Let's lock in this win.",
          ],
          [
            "Wow, what a fantastic day, $_userName!",
            "Let's log this win and celebrate with some good sleep.",
          ],
          [
            "Amazing job today, $_userName.",
            "Hold onto that feeling as you wind down tonight.",
          ],
        ];
        break;
      case "Best day ever!":
        responses = [
          [
            "That is absolutely spectacular, $_userName!",
            "I'm so happy for you. Let's end this perfect day right.",
          ],
          [
            "A top-tier day, $_userName! Incredible.",
            "Rest easy knowing you absolutely crushed it today.",
          ],
          [
            "Best day ever? That's amazing, $_userName.",
            "Let's get this logged so you can dream about the wins.",
          ],
        ];
        break;
      default:
        responses = [
          [
            "I'm glad you're here, $_userName.",
            "You showed up today, and that's enough. Let's clear your mind.",
          ],
        ];
        break;
    }

    final selectedResponse = responses[random.nextInt(responses.length)];
    final String line1 = selectedResponse[0];
    final String line2 = selectedResponse[1];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _nextBlock,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 100),
            Text(
              line1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 25),
            Text(
              line2,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            const Center(
              child: Text(
                "Tap anywhere to continue",
                style: TextStyle(color: Colors.white38, fontSize: 16),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildProductivity() {
    final options = [
      "Not productive",
      "A little productive",
      "Somewhat productive",
      "Productive",
      "Very Productive",
    ];
    return _buildChoiceList(
      "How productive would you consider your day?",
      options,
      (choice) {
        DebriefSession.answers['productivity'] = choice;
        _nextBlock();
      },
    );
  }

  Widget _buildMindTiles() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "What was on your mind today?",
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),

        if (DebriefSession.recentMindTiles.isNotEmpty)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: DebriefSession.recentMindTiles.map((tile) {
              final isSelected = DebriefSession.selectedMindTiles.contains(
                tile,
              );
              return FilterChip(
                label: Text(tile),
                selected: isSelected,
                selectedColor: const Color(0xFF00C897).withOpacity(0.3),
                checkmarkColor: const Color(0xFF00C897),
                backgroundColor: Colors.white10,
                labelStyle: TextStyle(
                  color: isSelected ? const Color(0xFF00C897) : Colors.white70,
                ),
                onSelected: (val) {
                  setState(
                    () => val
                        ? DebriefSession.selectedMindTiles.add(tile)
                        : DebriefSession.selectedMindTiles.remove(tile),
                  );
                },
              );
            }).toList(),
          ),

        const SizedBox(height: 30),
        TextField(
          controller: _mindController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Type something new...",
            suffixIcon: IconButton(
              icon: const Icon(Icons.add_circle, color: Color(0xFF00C897)),
              onPressed: () {
                String newTile = _mindController.text.trim();
                if (newTile.isNotEmpty) {
                  setState(() {
                    int idx = DebriefSession.recentMindTiles.indexWhere(
                      (t) => t.toLowerCase() == newTile.toLowerCase(),
                    );
                    if (idx != -1)
                      DebriefSession.selectedMindTiles.add(
                        DebriefSession.recentMindTiles[idx],
                      );
                    else {
                      DebriefSession.recentMindTiles.add(newTile);
                      DebriefSession.selectedMindTiles.add(newTile);
                    }
                    _mindController.clear();
                  });
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 40),
        _buildNextButton(
          "Next",
          onTap: () {
            DebriefSession.answers['mind_tiles'] = DebriefSession
                .selectedMindTiles
                .toList();
            _nextBlock();
          },
        ),
      ],
    );
  }

  Widget _buildInteresting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "What is the most interesting thing that happened today?",
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 30),
        TextField(
          controller: _textController,
          style: const TextStyle(color: Colors.white),
          maxLines: 4,
        ),
        const SizedBox(height: 40),
        _buildNextButton(
          "Next",
          onTap: () {
            DebriefSession.answers['interesting'] = _textController.text.trim();
            _nextBlock();
          },
        ),
      ],
    );
  }

  Widget _buildInventoryCheck() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Did you use or restock anything today?",
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),
        if (DebriefSession.todaysInventoryLogs.isEmpty)
          const Text(
            "No inventory activity logged today.",
            style: TextStyle(color: Colors.white54),
          )
        else
          ...DebriefSession.todaysInventoryLogs.map(
            (log) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF00C897),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    log,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 40),
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(context, 'goto_inventory'),
          icon: const Icon(Icons.inventory_2),
          label: const Text("Log a new item now"),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF00C897),
            side: const BorderSide(color: Color(0xFF00C897)),
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
          ),
        ),
        const SizedBox(height: 40),
        _buildNextButton("Next", onTap: () => _nextBlock()),
      ],
    );
  }

  Widget _buildAlarmCheck() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Is your alarm set for tomorrow?",
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "Make sure you're ready for the morning.",
          style: TextStyle(color: Colors.white54, fontSize: 16),
        ),
        const SizedBox(height: 40),
        OutlinedButton.icon(
          onPressed: () async {
            final List<String> intentStrings = [
              'intent:#Intent;action=android.intent.action.MAIN;category=android.intent.category.APP_CLOCK;end',
              'intent:#Intent;action=android.intent.action.SHOW_ALARMS;end',
              'intent:#Intent;action=android.intent.action.SET_ALARM;end',
              'intent:#Intent;package=com.google.android.deskclock;end',
              'intent:#Intent;package=com.sec.android.app.clockpackage;end',
              'intent:#Intent;package=com.oneplus.deskclock;end',
            ];

            bool launched = false;
            for (String intentStr in intentStrings) {
              try {
                launched = await launchUrl(
                  Uri.parse(intentStr),
                  mode: LaunchMode.externalApplication,
                );
                if (launched) break;
              } catch (e) {}
            }

            if (!launched && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    "Unable to auto-open the Clock app. Please open it manually.",
                  ),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          },
          icon: const Icon(Icons.alarm),
          label: const Text("Open Clock App"),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF00C897),
            side: const BorderSide(color: Color(0xFF00C897)),
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
          ),
        ),
        const SizedBox(height: 40),
        _buildNextButton("Next", onTap: () => _nextBlock()),
      ],
    );
  }

  Widget _buildCloseAndSleep() {
    final phrases = [
      "You tied off your day, $_userName.",
      "Great job today, $_userName.",
      "Rest easy, $_userName. You've earned it.",
      "The day is done. Let it go, $_userName.",
      "Close your eyes, $_userName. Tomorrow is a blank slate.",
      "All loops are closed. Time to recharge.",
      "You did your best today, $_userName. Now, rest.",
      "I'll hold down the fort. Sleep well, $_userName.",
      "Disconnecting... Sweet dreams, $_userName.",
      "Another day in the books. Goodnight, $_userName.",
    ];
    final phrase = phrases[Random().nextInt(phrases.length)];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => _sleepAnimController.value +=
          d.primaryDelta! / MediaQuery.of(context).size.height,
      onVerticalDragEnd: (d) {
        if (d.primaryVelocity! > 300 || _sleepAnimController.value > 0.3) {
          _sleepAnimController.forward().then((_) async {
            setState(() {
              _isAsleep = true;
              DebriefSession.sleepTime = DateTime.now();
            });
            // LOCKS APP INTO SLEEP MODE
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('axis_is_sleeping', true);

            // <-- FIRE THE NOTIFICATION
            await NotificationService().showSleepNotification();

            _submitDebriefNow();
          });
        } else {
          _sleepAnimController.reverse();
        }
      },
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.25),
            Text(
              phrase,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 15),
            const Text(
              "Rest well! I'll hold down the fort.",
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
            const SizedBox(height: 15),
            const Text(
              "Swipe down to sleep",
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSleepScreen() {
    if (_showEarlyWakeConfirm) {
      int sleptMins = DateTime.now()
          .difference(DebriefSession.sleepTime ?? DateTime.now())
          .inMinutes;

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "You have only been asleep for $sleptMins minutes.",
              style: const TextStyle(color: Colors.white38, fontSize: 16),
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () =>
                      setState(() => _showEarlyWakeConfirm = false),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.white24),
                  ),
                ),
                const SizedBox(width: 30),
                TextButton(
                  onPressed: _wakeUp,
                  child: const Text(
                    "Wake Up",
                    style: TextStyle(color: Colors.white24),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        if (details.delta.dy < -5) {
          if (DebriefSession.sleepTime != null) {
            int sleptMins = DateTime.now()
                .difference(DebriefSession.sleepTime!)
                .inMinutes;
            if (sleptMins < 60) {
              setState(() => _showEarlyWakeConfirm = true);
              return;
            }
          }
          _wakeUp();
        }
      },
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.nights_stay, size: 60, color: Colors.white24),
            SizedBox(height: 20),
            Text(
              "You are in sleep mode.\nSwipe UP anywhere to wake up!",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white24, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceList(
    String title,
    List<String> options,
    Function(String) onSelect,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 30),
        ...options.map(
          (opt) => Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: InkWell(
              onTap: () => onSelect(opt),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  opt,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNextButton(String label, {VoidCallback? onTap}) {
    return Align(
      alignment: Alignment.centerRight,
      child: ElevatedButton(
        onPressed: onTap ?? _nextBlock,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00C897),
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget content = const SizedBox();
    if (!_isAsleep) {
      switch (_activeBlocks[DebriefSession.currentIndex]) {
        case 'preset_rate_day':
          content = _buildRateDay();
          break;
        case 'preset_ai_response_1':
          content = _buildAIResponse1();
          break;
        case 'preset_productivity':
          content = _buildProductivity();
          break;
        case 'preset_mind_tiles':
          content = _buildMindTiles();
          break;
        case 'preset_interesting':
          content = _buildInteresting();
          break;
        case 'preset_inventory_check':
          content = _buildInventoryCheck();
          break;
        case 'preset_alarm_check':
          content = _buildAlarmCheck();
          break;
        case 'preset_ai_close_sleep':
          content = _buildCloseAndSleep();
          break;
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _sleepAnimController,
            builder: (c, _) => Transform.translate(
              offset: Offset(
                0,
                MediaQuery.of(context).size.height *
                    _sleepAnimController.value *
                    0.75,
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      theme.colorScheme.primary.withOpacity(0.3),
                      theme.colorScheme.primary,
                    ],
                    stops: const [0.0, 0.2, 0.6, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: _isAsleep
                ? _buildSleepScreen()
                : Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(30.0),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          key: ValueKey<String>(
                            _activeBlocks[DebriefSession.currentIndex],
                          ),
                          child: content,
                        ),
                      ),
                    ),
                  ),
          ),
          if (!_isAsleep)
            Positioned(
              top: 50,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ),
        ],
      ),
    );
  }
}
