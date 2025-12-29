import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/inventory_item.dart';
import '../services/firestore_service.dart';
import 'activity_log_page.dart';

class AxisInventoryTab extends StatefulWidget {
  const AxisInventoryTab({super.key});

  @override
  State<AxisInventoryTab> createState() => _AxisInventoryTabState();
}

class _AxisInventoryTabState extends State<AxisInventoryTab>
    with AutomaticKeepAliveClientMixin {
  final FirestoreService _db = FirestoreService();

  // 1. Create a variable to hold the open connection
  late Stream<List<InventoryItem>> _inventoryStream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 2. Open the connection ONCE here
    _inventoryStream = _db.getInventoryStream();
  }

  // --- ACTIONS ---

  void _addItem(String name, String type, String? room) {
    _db.addItem(
      InventoryItem(name: name, type: type, roomLocation: room, quantity: 0),
    );

    if (type == 'Item') {
      _db.logActivity("CREATED ITEM", name, room ?? "Unknown", 0, 0);
    } else {
      _db.logActivity("CREATED ROOM", name, "N/A", 0, 0);
    }
  }

  void _confirmUseOne(InventoryItem item) {
    if (item.quantity <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("None left to use!")));
      return;
    }
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            "Use Item?",
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: Text(
            "Did you use 1 '${item.name}'?",
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                "Cancel",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
            TextButton(
              child: Text(
                "Yes, I used one",
                style: TextStyle(color: Theme.of(context).primaryColor),
              ),
              onPressed: () {
                _db.updateQuantity(item.name, item.quantity - 1);
                _db.logActivity(
                  "USED ONE",
                  item.name,
                  item.roomLocation ?? "Unknown",
                  -1,
                  item.quantity - 1,
                );
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    );
  }

  void _confirmDelete(InventoryItem item) {
    final isRoom = item.type == "Room";
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            "Delete?",
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: Text(
            isRoom
                ? "WARNING: Deleting '${item.name}' will also delete ALL items in this room."
                : "Are you sure you want to delete '${item.name}'?",
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                "Cancel",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
            TextButton(
              child: const Text(
                "Delete",
                style: TextStyle(color: Colors.redAccent),
              ),
              onPressed: () {
                if (isRoom) {
                  _db.deleteRoom(item.name);
                  _db.logActivity("ROOM DELETED", item.name, "N/A", 0, 0);
                } else {
                  _db.deleteItem(item.name);
                  _db.logActivity(
                    "DELETED",
                    item.name,
                    item.roomLocation ?? "Unknown",
                    -item.quantity,
                    0,
                  );
                }
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    );
  }

  void _showQuantityDialog(InventoryItem item) {
    int tempQuantity = item.quantity;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Theme(
              data: Theme.of(context),
              child: AlertDialog(
                backgroundColor: Theme.of(context).cardColor,
                title: Text(
                  item.name,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Adjust Quantity",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.remove_circle_outline,
                            color: Theme.of(context).iconTheme.color,
                            size: 32,
                          ),
                          onPressed: () {
                            if (tempQuantity > 0)
                              setDialogState(() => tempQuantity--);
                          },
                        ),
                        Container(
                          constraints: const BoxConstraints(minWidth: 60),
                          alignment: Alignment.center,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            "$tempQuantity",
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.add_circle_outline,
                            color: Theme.of(context).iconTheme.color,
                            size: 32,
                          ),
                          onPressed: () {
                            setDialogState(() => tempQuantity++);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    child: Text(
                      "Cancel",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  TextButton(
                    child: Text(
                      "Update",
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      int diff = tempQuantity - item.quantity;
                      _db.updateQuantity(item.name, tempQuantity);
                      _db.logActivity(
                        "RESTOCKED",
                        item.name,
                        item.roomLocation ?? "Unknown",
                        diff,
                        tempQuantity,
                      );
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _exportInventoryCSV() async {
    final snapshot = await _db.inventoryCollection.get();
    if (snapshot.docs.isEmpty) return;
    String csvData = "Name,Type,Room Location,Quantity\n";
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      String safeName = (data['name'] ?? "").toString().replaceAll(',', '');
      String safeRoom = (data['roomLocation'] ?? "").toString().replaceAll(
        ',',
        '',
      );
      String type = data['type'] ?? "Item";
      String qty = (data['quantity'] ?? 0).toString();
      csvData += "$safeName,$type,$safeRoom,$qty\n";
    }
    await _shareFile(csvData, "axis_inventory.csv");
  }

  Future<void> _exportActivityLogCSV() async {
    final snapshot = await _db.logCollection
        .orderBy('timestamp', descending: true)
        .get();
    if (snapshot.docs.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Log is empty!")));
      return;
    }
    String csvData = "Timestamp,Action,Item Name,Room,Change,Total\n";
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      csvData +=
          "${data['timestamp']},${data['action']},${data['item']},${data['room']},${data['change']},${data['total']}\n";
    }
    await _shareFile(csvData, "axis_activity_log.csv");
  }

  Future<void> _shareFile(String content, String fileName) async {
    if (!mounted) return;
    final directory = await getTemporaryDirectory();
    final path = "${directory.path}/$fileName";
    final file = File(path);
    await file.writeAsString(content);
    await Share.shareXFiles([XFile(path)], text: 'Exported from Axis');
  }

  void _showExportMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      builder: (ctx) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.table_view),
            title: const Text("Export Inventory"),
            onTap: () {
              Navigator.pop(ctx);
              _exportInventoryCSV();
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text("Export Logs"),
            onTap: () {
              Navigator.pop(ctx);
              _exportActivityLogCSV();
            },
          ),
        ],
      ),
    );
  }

  void _showAddDialog(List<String> rooms) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            "Add to Inventory",
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  Icons.meeting_room,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  "Add Room",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showNameInputDialog(isRoom: true, rooms: rooms);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.category,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  "Add Item",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showNameInputDialog(isRoom: false, rooms: rooms);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showNameInputDialog({
    required bool isRoom,
    required List<String> rooms,
  }) {
    TextEditingController nameController = TextEditingController();
    String? selectedRoom = (!isRoom && rooms.isNotEmpty) ? rooms.first : null;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Theme(
              data: Theme.of(context),
              child: AlertDialog(
                backgroundColor: Theme.of(context).cardColor,
                title: Text(
                  isRoom ? "New Room" : "New Item",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: isRoom
                            ? "Enter Room Name"
                            : "Enter Item Name",
                        hintStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (!isRoom) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Select Room:",
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      DropdownButton<String>(
                        value: selectedRoom,
                        dropdownColor: Theme.of(context).cardColor,
                        isExpanded: true,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        items: rooms
                            .map(
                              (String room) => DropdownMenuItem<String>(
                                value: room,
                                child: Text(room),
                              ),
                            )
                            .toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            selectedRoom = newValue;
                          });
                        },
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    child: Text(
                      "Cancel",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  TextButton(
                    child: Text(
                      "Save",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      if (nameController.text.isNotEmpty) {
                        _addItem(
                          nameController.text,
                          isRoom ? "Room" : "Item",
                          selectedRoom,
                        );
                        Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final topPadding =
        MediaQuery.of(context).orientation == Orientation.landscape
        ? 20.0
        : 140.0;

    return StreamBuilder<List<InventoryItem>>(
      // 3. Use the persistent variable
      stream: _inventoryStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final inventoryList = snapshot.data ?? [];
        final roomList = inventoryList
            .where((element) => element.type == "Room")
            .toList();
        final roomNames = roomList.map((e) => e.name).toList();

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddDialog(roomNames),
            backgroundColor: theme.colorScheme.primary,
            child: const Icon(Icons.add, color: Colors.white),
          ),
          body: Padding(
            padding: EdgeInsets.fromLTRB(20, topPadding, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "My Inventory",
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.history,
                            color: theme.iconTheme.color,
                          ),
                          tooltip: "View Logs",
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ActivityLogPage(),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          onPressed: () => _showExportMenu(),
                          tooltip: "Export Options",
                          icon: Icon(
                            Icons.download,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  "Track your items",
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: inventoryList.isEmpty
                      ? Center(
                          child: Text(
                            "Click + to add",
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            int crossAxisCount = constraints.maxWidth > 600
                                ? 2
                                : 1;
                            return ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: roomList.length,
                              itemBuilder: (context, index) {
                                final room = roomList[index];
                                final roomItems = inventoryList
                                    .where(
                                      (item) =>
                                          item.type == "Item" &&
                                          item.roomLocation == room.name,
                                    )
                                    .toList();
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    GestureDetector(
                                      onLongPress: () => _confirmDelete(room),
                                      child: Container(
                                        margin: const EdgeInsets.only(
                                          top: 15,
                                          bottom: 5,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme.dividerColor.withOpacity(
                                            0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: theme.dividerColor,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.meeting_room,
                                              color: theme.colorScheme.primary,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              room.name,
                                              style: TextStyle(
                                                color:
                                                    theme.colorScheme.onSurface,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (roomItems.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 20,
                                          bottom: 10,
                                        ),
                                        child: Text(
                                          "No items yet.",
                                          style: TextStyle(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                            fontStyle: FontStyle.italic,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: roomItems.map((item) {
                                        double cardWidth = crossAxisCount == 1
                                            ? double.infinity
                                            : (constraints.maxWidth - 10) / 2;
                                        return SizedBox(
                                          width: cardWidth,
                                          child: GestureDetector(
                                            onLongPress: () =>
                                                _confirmDelete(item),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: theme.cardColor,
                                                borderRadius:
                                                    BorderRadius.circular(15),
                                                border: Border.all(
                                                  color: theme.dividerColor,
                                                ),
                                              ),
                                              child: ListTile(
                                                leading: Container(
                                                  width: 40,
                                                  height: 40,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color: theme.dividerColor
                                                        .withOpacity(0.2),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Text(
                                                    "${item.quantity}",
                                                    style: TextStyle(
                                                      color: theme
                                                          .colorScheme
                                                          .primary,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                ),
                                                title: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.category,
                                                      size: 16,
                                                      color: theme
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        item.name,
                                                        style: TextStyle(
                                                          color: theme
                                                              .colorScheme
                                                              .onSurface,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                trailing: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: Icon(
                                                        Icons.remove_circle,
                                                        color: theme
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                      onPressed: () =>
                                                          _confirmUseOne(item),
                                                      tooltip: "Use One",
                                                    ),
                                                    IconButton(
                                                      icon: Icon(
                                                        Icons.add,
                                                        color: theme
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                      onPressed: () =>
                                                          _showQuantityDialog(
                                                            item,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
