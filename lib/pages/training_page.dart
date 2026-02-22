import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/ai_service.dart';

class TrainingPage extends StatefulWidget {
  const TrainingPage({super.key});

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  final AxisAIService _aiService = AxisAIService();
  bool _isLoading = true;
  Map<String, String>? _currentScenario;
  String _inventoryContext = "";

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    _inventoryContext = await _getInventoryContext();
    _loadNewScenario();
  }

  // --- FIXED CONTEXT HERE TOO ---
  Future<String> _getInventoryContext() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return "No user";
    try {
      final snap = await FirebaseFirestore.instance
          .collection('households')
          .where('members', arrayContains: user.uid)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return "Inventory is empty.";
      final invSnap = await FirebaseFirestore.instance
          .collection('households')
          .doc(snap.docs.first.id)
          .collection('inventory')
          .get();
      String ctx = "";
      for (var d in invSnap.docs) {
        if (d['type'] != 'Room') {
          String name = d['name'] ?? 'Unknown';
          var qty = d['quantity'] ?? 0;
          String room = d['room'] ?? 'Unassigned';
          ctx += "- $name (Qty: $qty) [Location: $room]\n";
        }
      }
      return ctx.isEmpty ? "Inventory is empty." : ctx;
    } catch (e) {
      return "Error loading inventory.";
    }
  }

  Future<void> _loadNewScenario() async {
    setState(() => _isLoading = true);
    final scenario = await _aiService.getNextTrainingScenario(
      _inventoryContext,
    );

    if (mounted) {
      setState(() {
        _currentScenario = scenario;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveChoice(String answer, int rating) async {
    if (_currentScenario == null) return;

    await _aiService.sendFeedback(_currentScenario!['q']!, answer, rating);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Preference saved! Axis will learn this style."),
          duration: Duration(milliseconds: 800),
        ),
      );
      _loadNewScenario();
    }
  }

  void _showCustomAnswerDialog() {
    TextEditingController customController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text(
          "Write the ideal answer:",
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: TextField(
          controller: customController,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Type exactly what you want Axis to say...",
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              if (customController.text.trim().isNotEmpty) {
                Navigator.pop(ctx);
                _saveChoice(customController.text.trim(), 5);
              }
            },
            child: const Text("Save & Learn"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Train Axis Style"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
        titleTextStyle: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentScenario == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Could not generate scenario."),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _loadNewScenario,
                    child: const Text("Retry"),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.primary.withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          "If you asked:",
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "\"${_currentScenario!['q']}\"",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  Text(
                    "Pick the best answer:",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(height: 20),

                  _buildOptionButton(theme, _currentScenario!['opt1']!),
                  const SizedBox(height: 12),
                  _buildOptionButton(theme, _currentScenario!['opt2']!),
                  const SizedBox(height: 12),
                  _buildOptionButton(theme, _currentScenario!['opt3']!),

                  const SizedBox(height: 30),

                  ElevatedButton.icon(
                    onPressed: _showCustomAnswerDialog,
                    icon: const Icon(Icons.edit),
                    label: const Text("Write my own answer"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: theme.cardColor,
                      foregroundColor: theme.colorScheme.primary,
                      side: BorderSide(color: theme.colorScheme.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),

                  const SizedBox(height: 15),

                  TextButton(
                    onPressed: _loadNewScenario,
                    child: Text(
                      "Skip / None of these",
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildOptionButton(ThemeData theme, String text) {
    return InkWell(
      onTap: () => _saveChoice(text, 1),
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: theme.dividerColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.9),
            fontSize: 15,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
