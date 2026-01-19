import 'package:flutter/material.dart';

class HomeTileConfig {
  final String id;
  final String title;
  final IconData icon;

  // 1 = Small (Half Width), 2 = Wide (Full Width)
  int span;
  bool isVisible;

  HomeTileConfig({
    required this.id,
    required this.title,
    required this.icon,
    this.span = 1, // Default to small
    this.isVisible = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'span': span,
    'isVisible': isVisible,
  };

  factory HomeTileConfig.fromJson(
    Map<String, dynamic> json,
    String title,
    IconData icon,
  ) {
    return HomeTileConfig(
      id: json['id'],
      title: title,
      icon: icon,
      span: json['span'] ?? 1,
      isVisible: json['isVisible'] ?? true,
    );
  }
}
