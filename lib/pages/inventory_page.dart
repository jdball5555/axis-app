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

  // --- CSV EXPORT LOGIC ---
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
      backgroundColor: const Color(0xFF222222),
      builder: (ctx) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.table_chart, color: Color(0xFF00C897)),
            title: const Text(
              "Export Inventory List",
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(ctx);
              _exportInventoryCSV();
            },
          ),
          ListTile(
            leading: const Icon(Icons.history, color: Colors.orangeAccent),
            title: const Text(
              "Export Activity Log",
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              "Full history with Rooms & Changes",
              style: TextStyle(color: Colors.white38),
            ),
            onTap: () {
              Navigator.pop(ctx);
              _exportActivityLogCSV();
            },
          ),
        ],
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
          backgroundColor: const Color(0xFF222222),
          title: const Text("Use Item?", style: TextStyle(color: Colors.white)),
          content: Text(
            "Did you use 1 '${item.name}'?",
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(ctx),
            ),
            TextButton(
              child: const Text(
                "Yes, I used one",
                style: TextStyle(color: Color(0xFF00C897)),
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
          backgroundColor: const Color(0xFF222222),
          title: const Text("Delete?", style: TextStyle(color: Colors.white)),
          content: Text(
            isRoom
                ? "WARNING: Deleting '${item.name}' will also delete ALL items in this room."
                : "Are you sure you want to delete '${item.name}'?",
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
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

  // --- UPDATED: RESTOCK DIALOG (No Purple + Counter Style) ---
  void _showQuantityDialog(InventoryItem item) {
    int tempQuantity = item.quantity == 0 ? 1 : item.quantity;
    const Color themeTeal = Color(0xFF00C897);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Apply Theme to remove default purple
            return Theme(
              data: ThemeData.dark().copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: themeTeal,
                  onSurface: Colors.white,
                ),
              ),
              child: AlertDialog(
                backgroundColor: const Color(0xFF222222),
                title: Text(
                  item.name,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Adjust Quantity",
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Minus Button
                        IconButton(
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            color: Colors.white70,
                            size: 32,
                          ),
                          onPressed: () {
                            if (tempQuantity > 0) {
                              setDialogState(() => tempQuantity--);
                            }
                          },
                        ),

                        // Counter Number
                        Container(
                          constraints: const BoxConstraints(minWidth: 60),
                          alignment: Alignment.center,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            "$tempQuantity",
                            style: const TextStyle(
                              color: themeTeal,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        // Plus Button
                        IconButton(
                          icon: const Icon(
                            Icons.add_circle_outline,
                            color: Colors.white70,
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
                    child: const Text(
                      "Cancel",
                      style: TextStyle(color: Colors.white54),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  TextButton(
                    child: const Text(
                      "Update",
                      style: TextStyle(
                        color: themeTeal,
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
        return AlertDialog(
          backgroundColor: const Color(0xFF111111),
          title: const Text(
            "Add to Inventory",
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.meeting_room,
                  color: Color(0xFF00C897),
                ),
                title: const Text(
                  "Add Room",
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showNameInputDialog(isRoom: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.category, color: Color(0xFF00C897)),
                title: const Text(
                  "Add Item",
                  style: TextStyle(color: Colors.white),
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

  // --- UPDATED: ADD DIALOG (No Purple) ---
  void _showNameInputDialog({required bool isRoom}) {
    TextEditingController nameController = TextEditingController();
    String? selectedRoom;
    List<String> rooms = getRoomNames();
    const Color themeTeal = Color(0xFF00C897);

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
            return Theme(
              data: ThemeData.dark().copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: themeTeal,
                  onSurface: themeTeal,
                ),
                textSelectionTheme: const TextSelectionThemeData(
                  cursorColor: themeTeal,
                  selectionColor: themeTeal,
                  selectionHandleColor: themeTeal,
                ),
              ),
              child: AlertDialog(
                backgroundColor: const Color(0xFF222222),
                title: Text(
                  isRoom ? "New Room" : "New Item",
                  style: const TextStyle(color: Colors.white),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: themeTeal,
                      // REMOVED 'const' HERE:
                      decoration: InputDecoration(
                        hintText: isRoom
                            ? "Enter Room Name"
                            : "Enter Item Name",
                        hintStyle: const TextStyle(color: Colors.white38),
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: themeTeal),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: themeTeal, width: 2.0),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (!isRoom) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Select Room:",
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ),
                      DropdownButton<String>(
                        value: selectedRoom,
                        dropdownColor: const Color(0xFF333333),
                        isExpanded: true,
                        underline: Container(height: 1, color: Colors.white30),
                        style: const TextStyle(color: Colors.white),
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
                    child: const Text(
                      "Cancel",
                      style: TextStyle(color: Colors.white54),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  TextButton(
                    child: const Text(
                      "Save",
                      style: TextStyle(
                        color: themeTeal,
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
    const Color themeTeal = Color(0xFF00C897);
    final roomList = inventoryList
        .where((element) => element.type == "Room")
        .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: themeTeal,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 140, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "My Inventory",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.history, color: Colors.white54),
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
                      onPressed: _showExportMenu,
                      tooltip: "Export Options",
                      icon: const Icon(Icons.download, color: themeTeal),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 5),
            const Text(
              "Track your items",
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: inventoryList.isEmpty
                  ? const Center(
                      child: Text(
                        "Click + to add",
                        style: TextStyle(color: Colors.white30),
                      ),
                    )
                  : ListView.builder(
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
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.meeting_room,
                                      color: themeTeal,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      room.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (roomItems.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(left: 20, bottom: 10),
                                child: Text(
                                  "No items yet.",
                                  style: TextStyle(
                                    color: Colors.white24,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ...roomItems.map((item) {
                              return GestureDetector(
                                onLongPress: () => _confirmDelete(item),
                                child: Container(
                                  margin: const EdgeInsets.only(
                                    bottom: 8,
                                    left: 15,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black26,
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: ListTile(
                                    leading: Container(
                                      width: 40,
                                      height: 40,
                                      alignment: Alignment.center,
                                      decoration: const BoxDecoration(
                                        color: Colors.white10,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        "${item.quantity}",
                                        style: const TextStyle(
                                          color: themeTeal,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        const Icon(
                                          Icons.category,
                                          size: 16,
                                          color: Colors.white54,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            item.name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle,
                                            color: Colors.white54,
                                          ),
                                          onPressed: () => _confirmUseOne(item),
                                          tooltip: "Use One",
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.add,
                                            color: Colors.white54,
                                          ),
                                          onPressed: () =>
                                              _showQuantityDialog(item),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ],
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
