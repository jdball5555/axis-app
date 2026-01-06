class InventoryItem {
  final String name;
  final String type; // 'Item' or 'Room'
  final String? roomLocation; // Null if type is 'Room' (it IS the room)
  final int quantity;
  final String?
  defaultSource; // NEW: The room ID/Name this item is usually taken from

  InventoryItem({
    required this.name,
    required this.type,
    this.roomLocation,
    required this.quantity,
    this.defaultSource,
  });

  // Convert to JSON for Firestore
  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'roomLocation': roomLocation,
    'quantity': quantity,
    'defaultSource': defaultSource,
  };

  // Create from JSON
  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      name: json['name'] ?? '',
      type: json['type'] ?? 'Item',
      roomLocation: json['roomLocation'],
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      defaultSource: json['defaultSource'],
    );
  }
}
