import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/tab_data.dart';
import '../widgets/settings_widgets.dart';

class NavBarSettings extends StatefulWidget {
  final List<TabData> orderedTabs;
  final Set<String> activeTabIds;
  final Function(List<TabData>) onReorder;
  final Function(String, bool) onToggle;

  const NavBarSettings({
    super.key,
    required this.orderedTabs,
    required this.activeTabIds,
    required this.onReorder,
    required this.onToggle,
  });

  @override
  State<NavBarSettings> createState() => _NavBarSettingsState();
}

class _NavBarSettingsState extends State<NavBarSettings> {
  late List<TabData> _localOrderedTabs;
  late Set<String> _localActiveTabIds;
  String? _defaultTabId;

  // REMOVED: final Set<String> _betaTabs = ... (No longer needed!)

  @override
  void initState() {
    super.initState();
    _localOrderedTabs = List.from(widget.orderedTabs);
    _localActiveTabIds = Set.from(widget.activeTabIds);
    _loadDefaultTab();
  }

  Future<void> _loadDefaultTab() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _defaultTabId =
          prefs.getString('default_startup_tab') ??
          (widget.orderedTabs.isNotEmpty ? widget.orderedTabs.first.id : null);
    });
  }

  Future<void> _updateDefaultTab(String newId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_startup_tab', newId);
    setState(() {
      _defaultTabId = newId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Filter to only active tabs for the startup dropdown
    final availableStartupTabs = _localOrderedTabs
        .where((tab) => _localActiveTabIds.contains(tab.id))
        .toList();

    String currentSelection = _defaultTabId ?? "";
    if (!availableStartupTabs.any((t) => t.id == currentSelection)) {
      if (availableStartupTabs.isNotEmpty) {
        currentSelection = availableStartupTabs.first.id;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- 1. STARTUP PAGE SECTION ---
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 4),
          child: Text(
            "STARTUP PAGE",
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ),

        GradientSettingsTile(
          icon: Icons.home_filled,
          title: "Open App To",
          subtitle: "Select your default home page",
          onTap: () {},
          trailing: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentSelection,
              icon: Icon(
                Icons.arrow_drop_down,
                color: theme.colorScheme.primary,
              ),
              dropdownColor: theme.cardColor,
              borderRadius: BorderRadius.circular(15),
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
              items: availableStartupTabs.map((tab) {
                return DropdownMenuItem<String>(
                  value: tab.id,
                  child: Text(
                    tab.id.toUpperCase(),
                    style: TextStyle(color: theme.colorScheme.onSurface),
                  ),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) _updateDefaultTab(newValue);
              },
            ),
          ),
        ),

        const SizedBox(height: 25),

        // --- 2. LAYOUT SECTION ---
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 4),
          child: Text(
            "NAVIGATION BAR LAYOUT",
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ),

        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: theme.cardColor.withOpacity(0.5),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 15),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Drag handle to reorder • Toggle to hide",
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),

              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                proxyDecorator: (child, index, animation) =>
                    Material(color: Colors.transparent, child: child),
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = _localOrderedTabs.removeAt(oldIndex);
                    _localOrderedTabs.insert(newIndex, item);
                  });
                  widget.onReorder(_localOrderedTabs);
                },
                children: _localOrderedTabs.asMap().entries.map((entry) {
                  final int index = entry.key;
                  final TabData tab = entry.value;
                  final bool isActive = _localActiveTabIds.contains(tab.id);

                  // NEW LOGIC: Use the property on the object, no hardcoded list!
                  final bool isBeta = tab.isBeta;

                  String displayTitle = tab.id.toUpperCase();
                  if (isBeta) displayTitle += " (BETA)";

                  String subtitleText = isActive ? "Visible" : "Hidden";
                  if (isBeta && isActive)
                    subtitleText = "Beta Feature • Visible";

                  return GradientSettingsTile(
                    key: ValueKey(tab.id),
                    icon: tab.icon,
                    title: displayTitle,
                    subtitle: subtitleText,
                    onTap: () {
                      bool newValue = !isActive;
                      if (!newValue && _localActiveTabIds.length <= 1) return;
                      setState(() {
                        newValue
                            ? _localActiveTabIds.add(tab.id)
                            : _localActiveTabIds.remove(tab.id);
                      });
                      widget.onToggle(tab.id, newValue);
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: isActive,
                          activeColor: theme.colorScheme.primary,
                          onChanged: (val) {
                            setState(() {
                              if (val) {
                                _localActiveTabIds.add(tab.id);
                              } else if (_localActiveTabIds.length > 1) {
                                _localActiveTabIds.remove(tab.id);
                              } else {
                                return;
                              }
                            });
                            widget.onToggle(tab.id, val);
                          },
                        ),
                        const SizedBox(width: 10),
                        ReorderableDragStartListener(
                          index: index,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            color: Colors.transparent,
                            child: const Icon(
                              Icons.drag_handle,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
