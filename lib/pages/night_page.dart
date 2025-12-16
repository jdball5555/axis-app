import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NightDebriefTab extends StatefulWidget {
  final bool autoStart;
  final VoidCallback? onConsumeAutoStart;

  const NightDebriefTab({
    super.key,
    this.autoStart = false,
    this.onConsumeAutoStart,
  });

  @override
  State<NightDebriefTab> createState() => _NightDebriefTabState();
}

class _NightDebriefTabState extends State<NightDebriefTab> {
  // --- CONFIGURATION ---
  final List<Map<String, dynamic>> _questions = [
    {"q": "How are you feeling today?", "type": "smiley"},
    {"q": "How productive were you today?", "type": "productivity"},
    {"q": "What was the biggest win of the day?", "type": "text"},
    {"q": "What is one thing you learned?", "type": "text"},
    {"q": "What is your primary focus for tomorrow?", "type": "text"},
  ];

  final List<String> _productivityOptions = [
    "Not Productive",
    "A Little Productive",
    "Somewhat Productive",
    "Productive",
    "Very Productive",
  ];

  bool _isSurveyActive = false;
  int _currentQuestionIndex = 0;
  final TextEditingController _textController = TextEditingController();
  int? _selectedScore;
  List<String> _answers = [];

  @override
  void initState() {
    super.initState();
    _checkAutoStart();
  }

  @override
  void didUpdateWidget(NightDebriefTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkAutoStart();
  }

  void _checkAutoStart() {
    if (widget.autoStart && !_isSurveyActive) {
      // Schedule the start for the next frame to avoid build collisions
      Future.microtask(() {
        _startSurvey();
        widget.onConsumeAutoStart
            ?.call(); // Tell parent to turn off the trigger
      });
    }
  }

  void _startSurvey() {
    setState(() {
      _isSurveyActive = true;
      _currentQuestionIndex = 0;
      _answers = [];
      _resetInputs();
    });
  }

  void _resetInputs() {
    _textController.clear();
    _selectedScore = null;
  }

  void _nextQuestion() {
    String currentType = _questions[_currentQuestionIndex]['type'];
    String answerToSave = "";

    if (currentType == 'text') {
      if (_textController.text.trim().isEmpty) return;
      answerToSave = _textController.text.trim();
    } else if (currentType == 'smiley') {
      if (_selectedScore == null) return;
      const moods = ["Very Bad", "Bad", "Neutral", "Good", "Great"];
      answerToSave = moods[_selectedScore! - 1];
    } else if (currentType == 'productivity') {
      if (_selectedScore == null) return;
      answerToSave = _productivityOptions[_selectedScore!];
    }

    _answers.add(answerToSave);
    _resetInputs();

    setState(() {
      if (_currentQuestionIndex < _questions.length - 1) {
        _currentQuestionIndex++;
      } else {
        _finishSurvey();
      }
    });
  }

  Future<void> _finishSurvey() async {
    await _logDebriefToHistory();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Debrief saved to History.")),
      );
      setState(() {
        _isSurveyActive = false;
      });
    }
  }

  Future<void> _logDebriefToHistory() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> logs = prefs.getStringList('axis_activity_log') ?? [];

    final DateTime now = DateTime.now();
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final String timestamp =
        "${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)} ${twoDigits(now.hour)}:${twoDigits(now.minute)}:${twoDigits(now.second)}";

    String combinedAnswers = _answers.join(" // ");
    String logEntry =
        "$timestamp|DEBRIEF COMPLETED|Nightly Review|N/A|0|0|$combinedAnswers";

    logs.add(logEntry);
    await prefs.setStringList('axis_activity_log', logs);
  }

  // --- WIDGETS ---

  Widget _buildSmileySelector() {
    const Color themeTeal = Color(0xFF00C897);
    final icons = [
      Icons.sentiment_very_dissatisfied,
      Icons.sentiment_dissatisfied,
      Icons.sentiment_neutral,
      Icons.sentiment_satisfied,
      Icons.sentiment_very_satisfied,
    ];
    final colors = [
      Colors.redAccent,
      Colors.orangeAccent,
      Colors.amber,
      const Color(0xFF66BB6A),
      themeTeal,
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(5, (index) {
        final int score = index + 1;
        final bool isSelected = _selectedScore == score;
        return GestureDetector(
          onTap: () {
            setState(() => _selectedScore = score);
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) _nextQuestion();
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors[index].withOpacity(0.2)
                  : Colors.transparent,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: colors[index], width: 2)
                  : null,
            ),
            child: Icon(
              icons[index],
              size: isSelected ? 45 : 35,
              color: isSelected ? colors[index] : Colors.white38,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildProductivitySelector() {
    const Color themeTeal = Color(0xFF00C897);
    return Column(
      children: List.generate(_productivityOptions.length, (index) {
        final bool isSelected = _selectedScore == index;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: GestureDetector(
            onTap: () {
              setState(() => _selectedScore = index);
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted) _nextQuestion();
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected
                    ? themeTeal.withOpacity(0.2)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? themeTeal : Colors.white10,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Center(
                child: Text(
                  _productivityOptions[index],
                  style: TextStyle(
                    color: isSelected ? themeTeal : Colors.white70,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color themeTeal = Color(0xFF00C897);

    if (!_isSurveyActive) {
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
            const Text(
              "Close your loops. Clear your mind.",
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 50),
            ElevatedButton(
              onPressed: _startSurvey,
              style: ElevatedButton.styleFrom(
                backgroundColor: themeTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text("Begin Debrief"),
            ),
          ],
        ),
      );
    }

    final currentQ = _questions[_currentQuestionIndex];
    final String qText = currentQ['q'];
    final String qType = currentQ['type'];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Question ${_currentQuestionIndex + 1} of ${_questions.length}",
              style: const TextStyle(
                color: themeTeal,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              qText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),
            if (qType == 'text')
              TextField(
                controller: _textController,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: "Type your response...",
                  hintStyle: TextStyle(color: Colors.white30),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: themeTeal),
                  ),
                ),
              )
            else if (qType == 'smiley')
              _buildSmileySelector()
            else if (qType == 'productivity')
              _buildProductivitySelector(),
            const SizedBox(height: 40),
            if (qType == 'text')
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _nextQuestion,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(
                    _currentQuestionIndex == _questions.length - 1
                        ? "Finish"
                        : "Next",
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
