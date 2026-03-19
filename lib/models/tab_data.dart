import 'package:flutter/material.dart';

class TabData {
  final String id;
  final int iconCodePoint;
  final bool isBeta;

  TabData({required this.id, required this.iconCodePoint, this.isBeta = false});

  IconData get icon => IconData(iconCodePoint, fontFamily: 'MaterialIcons');

  static List<TabData> get allTabs => [
    TabData(id: 'home', iconCodePoint: Icons.home_filled.codePoint),
    TabData(id: 'inventory', iconCodePoint: Icons.inventory_2.codePoint),
    TabData(id: 'stats', iconCodePoint: Icons.bar_chart.codePoint),
    TabData(
      id: 'night',
      iconCodePoint: Icons.nights_stay.codePoint,
      isBeta: true,
    ),
    // TabData(
    //   id: 'ai',
    //   iconCodePoint: Icons.auto_awesome.codePoint,
    //   isBeta: true,
    // ),
    TabData(id: 'finances', iconCodePoint: Icons.attach_money.codePoint),
  ];

  Map<String, dynamic> toJson() => {
    'id': id,
    'iconCodePoint': iconCodePoint,
    'isBeta': isBeta,
  };

  factory TabData.fromJson(Map<String, dynamic> json) {
    int? code = json['iconCodePoint'];

    if (code == null) {
      try {
        final defaultTab = allTabs.firstWhere((t) => t.id == json['id']);
        code = defaultTab.iconCodePoint;
      } catch (e) {
        code = Icons.help_outline.codePoint;
      }
    }

    return TabData(
      id: json['id'],
      iconCodePoint: code,
      isBeta: json['isBeta'] ?? false,
    );
  }
}
