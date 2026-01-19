import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class EditHPSettings extends StatefulWidget {
  final Function() onSave;

  const EditHPSettings({super.key, required this.onSave});

  @override
  State<EditHPSettings> createState() => _EditHPSettingsState();
}

class _EditHPSettingsState extends State<EditHPSettings> {
  // Store ID and Scale for each item
  List<Map<String, dynamic>> _layoutItems = [
    {'id': 'hero', 'scale': 1.0},
    {'id': 'feed', 'scale': 1.0},
  ];

  String? _editingId; // Which tile is currently in edit mode
  double _startScale = 1.0; // Helper for smooth pinching

  @override
  void initState() {
    super.initState();
    _loadLayout();
  }

  Future<void> _loadLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString('axis_hp_layout_config');
    if (jsonStr != null) {
      try {
        List<dynamic> decoded = jsonDecode(jsonStr);
        if (mounted) {
          setState(() {
            _layoutItems = decoded
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    String jsonStr = jsonEncode(_layoutItems);
    await prefs.setString('axis_hp_layout_config', jsonStr);
    widget.onSave();
    if (mounted) Navigator.pop(context);
  }

  // --- INTERACTION LOGIC ---

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _layoutItems.removeAt(oldIndex);
      _layoutItems.insert(newIndex, item);
    });
  }

  void _onPinchUpdate(String id, double scale) {
    // Smooth continuous resizing
    // Clamp between ~30% width and 100% width
    double newScale = (_startScale * scale).clamp(0.3, 1.0);
    setState(() {
      final index = _layoutItems.indexWhere((e) => e['id'] == id);
      if (index != -1) {
        _layoutItems[index]['scale'] = newScale;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          "Edit Home Layout",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              "Save",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      // Tap background to exit edit mode
      body: GestureDetector(
        onTap: () => setState(() => _editingId = null),
        behavior: HitTestBehavior.translucent,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.start,
                  children: List.generate(_layoutItems.length, (index) {
                    return _buildDraggableTile(index, theme);
                  }),
                ),
              ),
            ),
            // Instructions Footer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: theme.colorScheme.primary.withOpacity(0.1),
              child: Text(
                _editingId == null
                    ? "Long press a tile to Edit."
                    : "Edit Mode Active: Pinch to Resize, Hold to Drag.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraggableTile(int index, ThemeData theme) {
    final item = _layoutItems[index];
    final String id = item['id'];
    final double scale = item['scale'] ?? 1.0;
    final bool isEditing = _editingId == id;

    // Calculate dimensions exactly like Home Page
    double screenWidth = MediaQuery.of(context).size.width;
    double padding = 40; // 20 left + 20 right
    double maxTileWidth = screenWidth - padding;
    double currentWidth = maxTileWidth * scale;

    return DragTarget<int>(
      onWillAccept: (fromIndex) => fromIndex != null && fromIndex != index,
      onAccept: (fromIndex) => _onReorder(fromIndex, index),
      builder: (context, candidates, rejects) {
        // VISUAL CONTENT
        Widget content = _buildVisualContent(id, theme);

        // WRAPPERS
        return GestureDetector(
          onLongPress: () {
            setState(() {
              _editingId = id;
              _startScale = scale; // Capture scale at start of edit
            });
          },
          onScaleStart: (_) {
            if (isEditing) _startScale = scale;
          },
          onScaleUpdate: (details) {
            if (isEditing) _onPinchUpdate(id, details.scale);
          },
          child: LongPressDraggable<int>(
            data: index,
            // Only allow dragging if we are in edit mode
            maxSimultaneousDrags: isEditing ? 1 : 0,
            delay: const Duration(milliseconds: 100),
            feedback: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: currentWidth,
                child: Opacity(opacity: 0.8, child: content),
              ),
            ),
            childWhenDragging: SizedBox(
              width: currentWidth,
              height: 160, // Placeholder height
              child: Container(
                decoration: BoxDecoration(
                  color: theme.dividerColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 50),
              width: currentWidth,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                // Highlight border when in Edit Mode
                border: isEditing
                    ? Border.all(color: Colors.amber, width: 3)
                    : Border.all(color: Colors.transparent, width: 0),
              ),
              child: content,
            ),
          ),
        );
      },
    );
  }

  // --- EXACT REPLICAS OF HOME PAGE TILES ---

  Widget _buildVisualContent(String id, ThemeData theme) {
    if (id == 'hero') {
      return _buildHeroReplica(theme);
    } else {
      return _buildFeedReplica(theme);
    }
  }

  Widget _buildHeroReplica(ThemeData theme) {
    DateTime now = DateTime.now();
    String timeString = DateFormat('h:mm').format(now);
    String amPm = DateFormat('a').format(now);
    String dateString = DateFormat('MMMM d, y').format(now);
    String dayString = DateFormat('EEEE').format(now);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                timeString,
                style: TextStyle(
                  fontSize: 70,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: -2,
                  height: 1,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                amPm,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 2, width: 60, color: theme.dividerColor),
          const SizedBox(height: 10),
          Text(
            dayString.toUpperCase(),
            style: TextStyle(
              fontSize: 14,
              letterSpacing: 3.0,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dateString,
            style: TextStyle(fontSize: 18, color: theme.colorScheme.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedReplica(ThemeData theme) {
    return Container(
      // Fixed height for editor visualization
      height: 200,
      width: double.infinity,
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 4),
            child: Text(
              "INSIGHTS",
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
              ),
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.cardColor.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                    size: 40,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Notifications Area",
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "(Invites, Alerts, Usage)",
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
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
}
