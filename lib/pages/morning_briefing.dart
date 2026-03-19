import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class MorningBriefingView extends StatefulWidget {
  const MorningBriefingView({super.key});

  @override
  State<MorningBriefingView> createState() => _MorningBriefingViewState();
}

class _MorningBriefingViewState extends State<MorningBriefingView> {
  final PageController _pageController = PageController();
  String _userName = "David";

  String _sleepText = "Calculating...";
  bool _isLoading = true;
  bool _isSubmitting = false;

  String _sleepTimeStr = "";
  String _wakeTimeStr = "";
  String _durationStr = "";

  // Dynamic Weather State
  String _weatherTemp = "--°";
  String _weatherDesc = "Loading...";
  String _dailyHiLow = "";
  int _dailyPrecipChance = 0;
  IconData _weatherIcon = Icons.wb_sunny;
  Color _weatherIconColor = Colors.orangeAccent;
  List<Map<String, dynamic>> _hourlyForecast = [];

  @override
  void initState() {
    super.initState();
    _initializeMorning();
    _fetchWeather();
  }

  Future<void> _fetchWeather() async {
    try {
      const url =
          'https://api.open-meteo.com/v1/forecast?latitude=33.1507&longitude=-96.8236&current_weather=true&hourly=temperature_2m,precipitation_probability,weathercode&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&temperature_unit=fahrenheit&timezone=America%2FChicago';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final current = data['current_weather'];
        int currentTemp = (current['temperature'] as num).round();
        int currentCode = current['weathercode'];

        final daily = data['daily'];
        int hi = (daily['temperature_2m_max'][0] as num).round();
        int lo = (daily['temperature_2m_min'][0] as num).round();
        int precipChance = (daily['precipitation_probability_max'][0] as num)
            .round();

        final hourly = data['hourly'];
        final times = hourly['time'] as List;
        final temps = hourly['temperature_2m'] as List;
        final precips = hourly['precipitation_probability'] as List;
        final codes = hourly['weathercode'] as List;

        DateTime now = DateTime.now();
        int currentIndex = 0;

        for (int i = 0; i < times.length; i++) {
          DateTime dt = DateTime.parse(times[i]);
          if (dt.isAfter(now) || dt.hour == now.hour) {
            currentIndex = i;
            break;
          }
        }

        List<Map<String, dynamic>> upcomingHours = [];
        for (
          int i = currentIndex;
          i < currentIndex + 16 && i < times.length;
          i++
        ) {
          DateTime dt = DateTime.parse(times[i]);
          int h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
          String amPm = dt.hour >= 12 ? "PM" : "AM";

          upcomingHours.add({
            'time': "$h $amPm",
            'temp': "${(temps[i] as num).round()}°",
            'precip': (precips[i] as num).round(),
            'code': codes[i],
          });
        }

        if (mounted) {
          setState(() {
            _weatherTemp = "$currentTemp°";
            _weatherDesc = _decodeWeatherText(currentCode);
            _weatherIcon = _decodeWeatherIcon(currentCode);
            _weatherIconColor = _decodeWeatherColor(currentCode);
            _dailyHiLow = "High $hi° • Low $lo°";
            _dailyPrecipChance = precipChance;
            _hourlyForecast = upcomingHours;
          });
        }
      }
    } catch (e) {
      debugPrint("Weather fetch failed: $e");
      if (mounted) {
        setState(() {
          _weatherDesc = "Weather unavailable";
        });
      }
    }
  }

  String _decodeWeatherText(int code) {
    if (code == 0) return "Clear Skies";
    if (code == 1 || code == 2 || code == 3) return "Partly Cloudy";
    if (code == 45 || code == 48) return "Foggy";
    if (code >= 51 && code <= 67) return "Rain";
    if (code >= 71 && code <= 77) return "Snow";
    if (code >= 95) return "Storms";
    return "Cloudy";
  }

  IconData _decodeWeatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny;
    if (code == 1 || code == 2 || code == 3) return Icons.cloud;
    if (code >= 51 && code <= 67) return Icons.water_drop;
    if (code >= 71 && code <= 77) return Icons.ac_unit;
    if (code >= 95) return Icons.thunderstorm;
    return Icons.cloud;
  }

  Color _decodeWeatherColor(int code) {
    if (code == 0) return Colors.orangeAccent;
    if (code == 1 || code == 2 || code == 3) return Colors.white70;
    if (code >= 51 && code <= 67) return Colors.blueAccent;
    if (code >= 71 && code <= 77) return Colors.white;
    if (code >= 95) return Colors.yellowAccent;
    return Colors.white70;
  }

  Future<void> _initializeMorning() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.displayName != null) {
      setState(() => _userName = user.displayName!.split(' ')[0]);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      String? savedSleepStr = prefs.getString('axis_current_sleep_time');

      if (savedSleepStr == null && user != null) {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('user_analytics')
            .doc('axis_forms')
            .collection('entries')
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();

        if (snapshot.docs.isNotEmpty) {
          savedSleepStr = snapshot.docs.first.data()['createdAt'];
        }
      }

      if (savedSleepStr != null) {
        DateTime sleepTime = DateTime.parse(savedSleepStr);
        if (DateTime.now().difference(sleepTime).inHours > 24) {
          savedSleepStr = null;
        }
      }

      if (savedSleepStr != null) {
        DateTime sleepTime = DateTime.parse(savedSleepStr);
        DateTime wakeTime = DateTime.now();

        _wakeTimeStr = wakeTime.toIso8601String();
        _sleepTimeStr = sleepTime.toIso8601String();

        Duration sleepDuration = wakeTime.difference(sleepTime);
        int hours = sleepDuration.inHours;
        int minutes = sleepDuration.inMinutes.remainder(60);

        _durationStr = "${hours}h ${minutes}m";

        setState(() {
          _sleepText = "You logged $hours hours $minutes minutes of sleep.";
          _isLoading = false;
        });
      } else {
        setState(() {
          _sleepText = "No open sleep session found.";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _sleepText = "Sync error: $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _saveRatingAndNext(String ratingChoice) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    _pageController.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );

    if (_sleepTimeStr.isNotEmpty) {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (mounted) setState(() => _isSubmitting = false);
        return;
      }

      String timeCompleted = DateTime.now().toIso8601String();

      DateTime actualWakeTime = DateTime.parse(_wakeTimeStr);
      String actualWakeDateStr =
          "${actualWakeTime.year}-${actualWakeTime.month.toString().padLeft(2, '0')}-${actualWakeTime.day.toString().padLeft(2, '0')}";

      String baseDocId = actualWakeDateStr;
      String docId = baseDocId;
      int suffix = 1;

      while (true) {
        final checkSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('user_analytics')
            .doc('axis_forms')
            .collection('entries')
            .doc(docId)
            .get();

        if (!checkSnap.exists) break;

        final data = checkSnap.data() as Map<String, dynamic>;
        if (data['sleepQuality'] == null ||
            data['sleepQuality'].toString().isEmpty) {
          break;
        }

        suffix++;
        docId = "$baseDocId-$suffix";
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('user_analytics')
          .doc('axis_forms')
          .collection('entries')
          .doc(docId)
          .set({
            'logicalDate': actualWakeDateStr,
            'sleepQuality': ratingChoice,
            'sleepTime': _sleepTimeStr,
            'wakeTime': _wakeTimeStr,
            'sleepDuration': _durationStr,
            'timestamp': timeCompleted,
          }, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('axis_current_sleep_time');
    }

    if (mounted) setState(() => _isSubmitting = false);
  }

  Widget _buildChoiceList(
    String title,
    List<String> options,
    Function(String) onSelect,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
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
          SafeArea(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00C897)),
                  )
                : PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildStep1Greeting(),
                      _buildStep2Rating(),
                      _buildStep3Weather(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1Greeting() {
    return GestureDetector(
      onTap: () => _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      ),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bed, color: Color(0xFF00C897), size: 64),
          const SizedBox(height: 30),
          Text(
            "Good morning, $_userName.",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _sleepText,
            style: const TextStyle(color: Colors.white70, fontSize: 18),
          ),
          const SizedBox(height: 50),
          const Text(
            "Tap to continue",
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2Rating() {
    final options = ["Terrible", "Not great", "Pretty good", "Excellent"];

    return _buildChoiceList("How well did you sleep?", options, (choice) {
      _saveRatingAndNext(choice);
    });
  }

  Widget _buildStep3Weather() {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => Navigator.pop(context, true),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 30.0, 16.0, 20.0),
        child: Column(
          children: [
            // ==========================================
            // CENTERED PREMIUM HEADER
            // ==========================================
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(_weatherIcon, size: 70, color: _weatherIconColor),
                const SizedBox(width: 16),
                Text(
                  _weatherTemp,
                  style: const TextStyle(
                    fontSize: 70,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _weatherDesc,
              style: TextStyle(
                fontSize: 22,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Frisco, TX  •  $_dailyHiLow",
              style: const TextStyle(fontSize: 16, color: Colors.white54),
            ),
            if (_dailyPrecipChance > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.water_drop,
                    color: Colors.blueAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "$_dailyPrecipChance% Chance of Rain Today",
                    style: const TextStyle(
                      color: Colors.blueAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 30),

            // ==========================================
            // 2-COLUMN TIMELINE (NO SCROLLING)
            // ==========================================
            Expanded(
              child: _hourlyForecast.isNotEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          // Left Column (Hours 1 - 8)
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: List.generate(8, (index) {
                                if (index >= _hourlyForecast.length)
                                  return const SizedBox.shrink();
                                final hour = _hourlyForecast[index];
                                return _CompactHourlyRow(
                                  timeString: index == 0 ? "Now" : hour['time'],
                                  temperature: hour['temp'],
                                  weatherIcon: _decodeWeatherIcon(hour['code']),
                                  weatherIconColor: _decodeWeatherColor(
                                    hour['code'],
                                  ),
                                  precipChance: hour['precip'],
                                  isNow: index == 0,
                                );
                              }),
                            ),
                          ),

                          // Subtle Divider
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8.0,
                              vertical: 16.0,
                            ),
                            child: VerticalDivider(
                              color: Colors.white12,
                              width: 1,
                            ),
                          ),

                          // Right Column (Hours 9 - 16)
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: List.generate(8, (index) {
                                int realIndex = index + 8;
                                if (realIndex >= _hourlyForecast.length)
                                  return const SizedBox.shrink();
                                final hour = _hourlyForecast[realIndex];
                                return _CompactHourlyRow(
                                  timeString: hour['time'],
                                  temperature: hour['temp'],
                                  weatherIcon: _decodeWeatherIcon(hour['code']),
                                  weatherIconColor: _decodeWeatherColor(
                                    hour['code'],
                                  ),
                                  precipChance: hour['precip'],
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00C897),
                      ),
                    ),
            ),

            const SizedBox(height: 20),
            const Text(
              "Tap anywhere to start your day",
              style: TextStyle(color: Colors.white24, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// MINIMALIST TIMELINE ROW WIDGET
// ==========================================
class _CompactHourlyRow extends StatelessWidget {
  final String timeString;
  final String temperature;
  final IconData weatherIcon;
  final Color weatherIconColor;
  final int precipChance;
  final bool isNow;

  const _CompactHourlyRow({
    required this.timeString,
    required this.temperature,
    required this.weatherIcon,
    required this.weatherIconColor,
    required this.precipChance,
    this.isNow = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        // 1. Time
        SizedBox(
          width: 45,
          child: Text(
            timeString,
            style: TextStyle(
              color: isNow ? theme.colorScheme.primary : Colors.white60,
              fontWeight: isNow ? FontWeight.bold : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),

        // 2. Icon
        Icon(
          weatherIcon,
          size: 20,
          color: isNow ? theme.colorScheme.primary : weatherIconColor,
        ),
        const SizedBox(width: 8),

        // 3. Temp (Increased font size and width)
        SizedBox(
          width: 40,
          child: Text(
            temperature,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),

        // 4. Rain (Pill Shaped)
        Expanded(
          child: precipChance > 0
              ? Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10), // Pill Shape
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.water_drop,
                          color: Colors.blueAccent,
                          size: 10,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          "$precipChance%",
                          style: const TextStyle(
                            color: Colors.blueAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
