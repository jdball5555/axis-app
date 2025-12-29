class InventoryItem {
  final String name;
  final String type; // "Item" or "Room"
  final String? roomLocation;
  int quantity;

  InventoryItem({
    required this.name,
    required this.type,
    this.roomLocation,
    required this.quantity,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'roomLocation': roomLocation,
    'quantity': quantity,
  };

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      name: json['name'] ?? '',
      type: json['type'] ?? 'Item',
      roomLocation: json['roomLocation'],
      // Handles both int and double to prevent crashes
      quantity: (json['quantity'] is int)
          ? json['quantity']
          : (json['quantity'] as double?)?.toInt() ?? 0,
    );
  }
}
