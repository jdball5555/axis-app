import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/inventory_item.dart';
import 'activity_log_page.dart';

class AxisInventoryTab extends StatefulWidget {
  const AxisInventoryTab({super.key});

  @override
  State<AxisInventoryTab> createState() => _AxisInventoryTabState();
}

class _AxisInventoryTabState extends State<AxisInventoryTab> {
  List<InventoryItem> inventoryList = [];
  List<String> activityLog = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ... (Data Loading/Saving/Log/Export/Share Logic - same as before) ...
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final String? data = prefs.getString('axis_inventory');
    if (data != null) {
      final List<dynamic> jsonList = jsonDecode(data);
      setState(() {
        inventoryList = jsonList.map((e) => InventoryItem.fromJson(e)).toList();
      });
    } else {
      setState(() {
        inventoryList = [];
      });
    }
    final List<String>? logData = prefs.getStringList('axis_activity_log');
    if (logData != null) {
      setState(() {
        activityLog = logData;
      });
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final String data = jsonEncode(
      inventoryList.map((e) => e.toJson()).toList(),
    );
    await prefs.setString('axis_inventory', data);
  }

  Future<void> _logActivity(
    String action,
    String itemName,
    String roomName,
    int? change,
    int? total,
  ) async {
    final DateTime now = DateTime.now();
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final String timestamp =
        "${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)} ${twoDigits(now.hour)}:${twoDigits(now.minute)}:${twoDigits(now.second)}";
    final String safeItem = itemName.replaceAll('|', '');
    final String safeRoom = roomName.replaceAll('|', '');
    final String changeStr = change?.toString() ?? "-";
    final String totalStr = total?.toString() ?? "-";
    final String logEntry =
        "$timestamp|$action|$safeItem|$safeRoom|$changeStr|$totalStr|";
    activityLog.add(logEntry);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('axis_activity_log', activityLog);
  }

  Future<void> _exportInventoryCSV() async {
    if (inventoryList.isEmpty) return;
    String csvData = "Name,Type,Room Location,Quantity\n";
    for (var item in inventoryList) {
      String safeName = item.name.replaceAll(',', '');
      String safeRoom = (item.roomLocation ?? "").replaceAll(',', '');
      csvData += "$safeName,${item.type},$safeRoom,${item.quantity}\n";
    }
    await _shareFile(csvData, "axis_inventory.csv");
  }

  Future<void> _exportActivityLogCSV() async {
    if (activityLog.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Log is empty!")));
      return;
    }
    String csvData = "Timestamp,Action,Item Name,Room,Change,Total,Note\n";
    for (var entry in activityLog) {
      csvData += entry.replaceAll('|', ',') + "\n";
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (ctx) => Theme(
        data: Theme.of(context),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.download_rounded,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Export Data",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildExportOption(
                ctx,
                title: "Inventory List",
                subtitle: "Current stock levels & rooms",
                icon: Icons.table_view_rounded,
                onTap: () {
                  Navigator.pop(ctx);
                  _exportInventoryCSV();
                },
              ),
              const SizedBox(height: 12),
              _buildExportOption(
                ctx,
                title: "Activity Log",
                subtitle: "Full history of changes",
                icon: Icons.history_edu_rounded,
                onTap: () {
                  Navigator.pop(ctx);
                  _exportActivityLogCSV();
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExportOption(
    BuildContext ctx, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).dividerColor.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: Theme.of(context).primaryColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  // --- ITEM MANAGEMENT ---
  void _addItem(String name, String type, String? room) {
    setState(() {
      inventoryList.add(
        InventoryItem(name: name, type: type, roomLocation: room, quantity: 0),
      );
    });
    _saveData();
    if (type == 'Item') {
      _logActivity("CREATED ITEM", name, room ?? "Unknown", 0, 0);
    } else {
      _logActivity("CREATED ROOM", name, "N/A", 0, 0);
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
                setState(() {
                  item.quantity -= 1;
                });
                _saveData();
                _logActivity(
                  "USED ONE",
                  item.name,
                  item.roomLocation ?? "Unknown",
                  -1,
                  item.quantity,
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
                setState(() {
                  if (isRoom) {
                    final itemsInRoom = inventoryList
                        .where(
                          (e) =>
                              e.type == "Item" && e.roomLocation == item.name,
                        )
                        .toList();
                    for (var i in itemsInRoom) {
                      _logActivity(
                        "DELETED (Room Clear)",
                        i.name,
                        item.name,
                        -i.quantity,
                        0,
                      );
                    }
                    inventoryList.removeWhere(
                      (e) =>
                          (e.type == "Room" && e.name == item.name) ||
                          (e.type == "Item" && e.roomLocation == item.name),
                    );
                    _logActivity("ROOM DELETED", item.name, "N/A", null, null);
                  } else {
                    _logActivity(
                      "DELETED",
                      item.name,
                      item.roomLocation ?? "Unknown",
                      -item.quantity,
                      0,
                    );
                    inventoryList.remove(item);
                  }
                });
                _saveData();
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    );
  }

  void _showQuantityDialog(InventoryItem item) {
    int tempQuantity = item.quantity == 0 ? 1 : item.quantity;
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
                            if (tempQuantity > 0) {
                              setDialogState(() => tempQuantity--);
                            }
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
                      setState(() {
                        item.quantity = tempQuantity;
                      });
                      _saveData();
                      _logActivity(
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

  List<String> getRoomNames() {
    return inventoryList
        .where((e) => e.type == "Room")
        .map((e) => e.name)
        .toList();
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: Text(
            "Add to Inventory",
            style: TextStyle(color: theme.colorScheme.onSurface),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  Icons.meeting_room,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  "Add Room",
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showNameInputDialog(isRoom: true);
                },
              ),
              ListTile(
                leading: Icon(Icons.category, color: theme.colorScheme.primary),
                title: Text(
                  "Add Item",
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showNameInputDialog(isRoom: false);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showNameInputDialog({required bool isRoom}) {
    TextEditingController nameController = TextEditingController();
    String? selectedRoom;
    List<String> rooms = getRoomNames();
    if (!isRoom && rooms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please create a Room first!")),
      );
      return;
    }
    if (!isRoom) selectedRoom = rooms.first;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final theme = Theme.of(context);
            return Theme(
              data: theme,
              child: AlertDialog(
                backgroundColor: theme.cardColor,
                title: Text(
                  isRoom ? "New Room" : "New Item",
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      cursorColor: theme.colorScheme.primary,
                      decoration: InputDecoration(
                        hintText: isRoom
                            ? "Enter Room Name"
                            : "Enter Item Name",
                        hintStyle: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: theme.colorScheme.primary,
                            width: 2.0,
                          ),
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
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      DropdownButton<String>(
                        value: selectedRoom,
                        dropdownColor: theme.cardColor,
                        isExpanded: true,
                        underline: Container(
                          height: 1,
                          color: theme.dividerColor,
                        ),
                        style: TextStyle(color: theme.colorScheme.onSurface),
                        focusColor: Colors.transparent,
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
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  TextButton(
                    child: Text(
                      "Save",
                      style: TextStyle(
                        color: theme.colorScheme.primary,
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
    final theme = Theme.of(context);
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final double topPadding = isLandscape ? 20.0 : 140.0;

    final roomList = inventoryList
        .where((element) => element.type == "Room")
        .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(),
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
                      icon: Icon(Icons.history, color: theme.iconTheme.color),
                      tooltip: "View Logs",
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ActivityLogPage(),
                          ),
                        );
                        _loadData();
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
                        int crossAxisCount = constraints.maxWidth > 600 ? 2 : 1;
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
                                      borderRadius: BorderRadius.circular(8),
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
                                            color: theme.colorScheme.onSurface,
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
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
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
                                        onLongPress: () => _confirmDelete(item),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: theme.cardColor,
                                            borderRadius: BorderRadius.circular(
                                              15,
                                            ),
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
                                                  color:
                                                      theme.colorScheme.primary,
                                                  fontWeight: FontWeight.bold,
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
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
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
                                                      _showQuantityDialog(item),
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
  }
}
