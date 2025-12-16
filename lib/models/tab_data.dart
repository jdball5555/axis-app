import 'package:flutter/material.dart';

class TabData {
  String id;
  IconData icon;

  TabData({required this.id, required this.icon});

  Map<String, dynamic> toJson() => {'id': id, 'codePoint': icon.codePoint};

  factory TabData.fromJson(Map<String, dynamic> json) {
    return TabData(
      id: json['id'],
      icon: IconData(json['codePoint'], fontFamily: 'MaterialIcons'),
    );
  }
}
