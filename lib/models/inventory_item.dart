class InventoryItem {
  String name;
  String type; // "Item" or "Room"
  String? roomLocation; // Nullable if type is "Room"
  int quantity;

  // NEW: Usage Rate (Items per day)
  double usageRate;

  InventoryItem({
    required this.name,
    required this.type,
    this.roomLocation,
    required this.quantity,
    this.usageRate = 0.0, // Default to 0
  });

  // Convert to JSON
  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'roomLocation': roomLocation,
    'quantity': quantity,
    'usageRate': usageRate,
  };

  // Create from JSON
  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      name: json['name'],
      type: json['type'],
      roomLocation: json['roomLocation'],
      quantity: json['quantity'],
      // Load rate, default to 0.0 if missing
      usageRate: (json['usageRate'] ?? 0.0).toDouble(),
    );
  }
}
