class InventoryItem {
  String name;
  String type; // "Room" or "Item"
  String? roomLocation; // Only for items
  int quantity;

  InventoryItem({
    required this.name,
    required this.type,
    this.roomLocation,
    this.quantity = 0,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'roomLocation': roomLocation,
    'quantity': quantity,
  };

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      name: json['name'],
      type: json['type'],
      roomLocation: json['roomLocation'],
      quantity: json['quantity'] ?? 0,
    );
  }
}
