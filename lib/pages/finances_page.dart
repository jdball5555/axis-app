import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class FinancesTab extends StatefulWidget {
  const FinancesTab({super.key});

  @override
  State<FinancesTab> createState() => _FinancesTabState();
}

class _FinancesTabState extends State<FinancesTab> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? "";
  Map<String, List<String>> _userCategories = {};

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  Future<void> _fetchCategories() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('settings')
          .doc('finances')
          .get();
      if (doc.exists &&
          doc.data() != null &&
          doc.data()!.containsKey('categories')) {
        Map<String, dynamic> rawCat = doc.data()!['categories'];
        Map<String, List<String>> parsed = {};
        rawCat.forEach((key, value) {
          parsed[key] = List<String>.from(value);
        });
        setState(() => _userCategories = parsed);
      } else {
        setState(() {
          _userCategories = {};
        });
      }
    } catch (e) {
      debugPrint("Error fetching categories: $e");
    }
  }

  Future<void> _saveCategoriesToFirebase() async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('settings')
        .doc('finances')
        .set({'categories': _userCategories}, SetOptions(merge: true));
  }

  void _openCategoryManager() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Manage Categories",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 15),

                  if (_userCategories.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          "No categories yet. Add one below!",
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView(
                        children: _userCategories.keys.map((cat) {
                          return ExpansionTile(
                            iconColor: const Color(0xFF00C897),
                            collapsedIconColor: Colors.white54,
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    cat,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    setModalState(
                                      () => _userCategories.remove(cat),
                                    );
                                    _saveCategoriesToFirebase();
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                            children: [
                              Wrap(
                                spacing: 8,
                                children: _userCategories[cat]!.map((sub) {
                                  return Chip(
                                    label: Text(
                                      sub,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                    backgroundColor: Colors.white10,
                                    deleteIcon: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.white54,
                                    ),
                                    onDeleted: () {
                                      setModalState(
                                        () => _userCategories[cat]!.remove(sub),
                                      );
                                      _saveCategoriesToFirebase();
                                      setState(() {});
                                    },
                                  );
                                }).toList(),
                              ),
                              TextButton.icon(
                                onPressed: () =>
                                    _addSubcategory(cat, setModalState),
                                icon: const Icon(
                                  Icons.add,
                                  color: Color(0xFF00C897),
                                  size: 18,
                                ),
                                label: const Text(
                                  "Add Subcategory",
                                  style: TextStyle(color: Color(0xFF00C897)),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C897),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => _addCategory(setModalState),
                      child: const Text("Add New Category"),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _addCategory(Function setModalState) {
    TextEditingController ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          "New Category",
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                setModalState(
                  () => _userCategories[ctrl.text.trim()] = ["General"],
                );
                _saveCategoriesToFirebase();
                setState(() {});
              }
              Navigator.pop(c);
            },
            child: const Text(
              "Add",
              style: TextStyle(color: Color(0xFF00C897)),
            ),
          ),
        ],
      ),
    );
  }

  void _addSubcategory(String category, Function setModalState) {
    TextEditingController ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          "New Subcategory for $category",
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                setModalState(
                  () => _userCategories[category]!.add(ctrl.text.trim()),
                );
                _saveCategoriesToFirebase();
                setState(() {});
              }
              Navigator.pop(c);
            },
            child: const Text(
              "Add",
              style: TextStyle(color: Color(0xFF00C897)),
            ),
          ),
        ],
      ),
    );
  }

  void _openAddReceiptModal() async {
    try {
      List<String>? pictures = await CunningDocumentScanner.getPictures();
      if (pictures == null || pictures.isEmpty) return;

      if (mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: const Color(0xFF1E1E1E),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          builder: (context) => _LogReceiptForm(
            imagePath: pictures.first,
            uid: _uid,
            categories: _userCategories,
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unable to open document scanner.")),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: 24.0,
                right: 24.0,
                top: 20,
                bottom: 10,
              ),
              child: Text(
                "Finances",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 10,
              ),
              child: GestureDetector(
                onTap: _openCategoryManager,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Categories",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            color: _userCategories.isEmpty
                                ? Colors.transparent
                                : Colors.white38,
                            size: 16,
                          ),
                        ],
                      ),
                      if (_userCategories.isEmpty)
                        const Positioned(
                          right: -5,
                          top: -5,
                          child: Icon(
                            Icons.add_circle,
                            color: Color(0xFF00C897),
                            size: 22,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(_uid)
                    .collection('finances')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData)
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00C897),
                      ),
                    );
                  if (snapshot.data!.docs.isEmpty)
                    return const Center(
                      child: Text(
                        "No receipts logged yet.",
                        style: TextStyle(color: Colors.white54, fontSize: 16),
                      ),
                    );

                  var docs = snapshot.data!.docs.toList();
                  docs.sort((a, b) {
                    var dataA = a.data() as Map<String, dynamic>;
                    var dataB = b.data() as Map<String, dynamic>;
                    DateTime dateA = _parseReceiptDate(dataA['date']);
                    DateTime dateB = _parseReceiptDate(dataB['date']);
                    return dateB.compareTo(dateA);
                  });

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      var data = docs[index].data() as Map<String, dynamic>;
                      return _ReceiptTile(data: data);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'finances_fab',
        onPressed: _openAddReceiptModal,
        backgroundColor: const Color(0xFF00C897),
        icon: const Icon(Icons.document_scanner, color: Colors.black),
        label: const Text(
          "Scan Receipt",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  DateTime _parseReceiptDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return DateTime(1970);
    try {
      List<String> parts = dateStr.split('/');
      if (parts.length == 3) {
        return DateTime(
          int.parse(parts[2]),
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
      }
    } catch (e) {}
    return DateTime.now();
  }
}

// =========================================================
// CUSTOM EXPANDABLE RECEIPT TILE
// =========================================================
class _ReceiptTile extends StatefulWidget {
  final Map<String, dynamic> data;

  const _ReceiptTile({required this.data});

  @override
  State<_ReceiptTile> createState() => _ReceiptTileState();
}

class _ReceiptTileState extends State<_ReceiptTile> {
  bool _isExpanded = false;

  String _formatTimestamp(String? isoString) {
    if (isoString == null) return "";
    try {
      DateTime dt = DateTime.parse(isoString);
      int h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      String amPm = dt.hour >= 12 ? "PM" : "AM";
      return "${dt.month}/${dt.day}/${dt.year} at $h:${dt.minute.toString().padLeft(2, '0')} $amPm";
    } catch (e) {
      return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    List<dynamic> itemsList = widget.data['items'] is List
        ? widget.data['items']
        : [];

    return GestureDetector(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.data['store'] ?? "Unknown Store",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "\$${(widget.data['total'] ?? 0.0).toStringAsFixed(2)}",
                      style: const TextStyle(
                        color: Color(0xFF00C897),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_isExpanded) ...[
                      const SizedBox(height: 4),
                      Text(
                        "Tax: \$${(widget.data['tax'] ?? 0.0).toStringAsFixed(2)}",
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        "Subtotal: \$${(widget.data['subtotal'] ?? 0.0).toStringAsFixed(2)}",
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (itemsList.isEmpty)
              const Text(
                "No items detailed",
                style: TextStyle(
                  color: Colors.white38,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              ...itemsList.map((item) {
                String name = item['name'] ?? 'Item';
                String cat = item['category'] ?? '';
                String sub = item['subcategory'] ?? '';
                String badge = sub.isNotEmpty ? "$cat > $sub" : cat;
                double price =
                    double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;

                if (_isExpanded) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                "• $name",
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              "\$${price.toStringAsFixed(2)}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (badge.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 12.0,
                              top: 4.0,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF00C897,
                                ).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                badge,
                                style: const TextStyle(
                                  color: Color(0xFF00C897),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                } else {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "• $name",
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (badge.isNotEmpty)
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF00C897,
                                  ).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  badge,
                                  style: const TextStyle(
                                    color: Color(0xFF00C897),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }
              }),

            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Receipt: ${widget.data['date']}",
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                if (_isExpanded)
                  Text(
                    "Scanned: ${_formatTimestamp(widget.data['timestamp'])}",
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================
// ADD RECEIPT MODAL FORM (ITEMIZED AI)
// =========================================================
class _LogReceiptForm extends StatefulWidget {
  final String imagePath;
  final String uid;
  final Map<String, List<String>> categories;

  const _LogReceiptForm({
    required this.imagePath,
    required this.uid,
    required this.categories,
  });

  @override
  State<_LogReceiptForm> createState() => _LogReceiptFormState();
}

class _LogReceiptFormState extends State<_LogReceiptForm> {
  final TextEditingController _storeController = TextEditingController();
  final TextEditingController _subtotalController = TextEditingController();
  final TextEditingController _taxController = TextEditingController();
  final TextEditingController _totalController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();

  List<Map<String, dynamic>> _parsedItems = [];
  bool _isScanningAI = false;
  bool _isDuplicate = false; // Tracks if this exact receipt already exists

  @override
  void initState() {
    super.initState();
    _scanReceiptWithAI();
  }

  Future<void> _scanReceiptWithAI() async {
    setState(() => _isScanningAI = true);

    try {
      final String apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
      if (apiKey.isEmpty) throw Exception("API Key not found in .env");

      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
      final imageBytes = await File(widget.imagePath).readAsBytes();

      String categoryRules = jsonEncode(widget.categories);

      final prompt = TextPart('''
        Analyze this receipt and extract the information into strict JSON format. 
        You must itemize the purchases, including their exact price. 
        Extract the subtotal (pre-tax) and the tax amount as well.
        
        Here are the user's custom Categories and Subcategories:
        $categoryRules
        
        For each item you find, do your absolute best to guess which Category and Subcategory it belongs to based on that list. 
        If you are completely unsure, use "Other" and "Misc".

        Format exactly like this, returning ONLY raw JSON:
        {
          "store": "Name of the store",
          "subtotal": 14.00,
          "tax": 1.99,
          "total": 15.99,
          "date": "MM/DD/YYYY",
          "time": "h:mm AM/PM",
          "items": [
            {
              "name": "Item Name",
              "price": 5.99,
              "category": "Food",
              "subcategory": "Groceries"
            }
          ]
        }
      ''');

      final imagePart = DataPart('image/jpeg', imageBytes);
      final response = await model.generateContent([
        Content.multi([prompt, imagePart]),
      ]);

      if (response.text != null) {
        String cleanJson = response.text!
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        final data = json.decode(cleanJson);

        if (mounted) {
          setState(() {
            _storeController.text = data['store']?.toString() ?? "";
            _subtotalController.text = data['subtotal']?.toString() ?? "";
            _taxController.text = data['tax']?.toString() ?? "";
            _totalController.text = data['total']?.toString() ?? "";

            if (data['date'] != null && data['date'].toString().isNotEmpty)
              _dateController.text = data['date'];
            else
              _setDateFallback();

            if (data['time'] != null && data['time'].toString().isNotEmpty)
              _timeController.text = data['time'];
            else
              _setTimeFallback();

            if (data['items'] != null) {
              _parsedItems = List<Map<String, dynamic>>.from(data['items']);
            }
          });

          // --- DUPLICATE CHECK LOGIC ---
          await _checkForDuplicateReceipt(
            _storeController.text.trim(),
            _dateController.text.trim(),
            _totalController.text.trim(),
          );
        }
      }
    } catch (e) {
      debugPrint("AI Scanning Failed: $e");
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Axis AI is unable to extract the data right now."),
            backgroundColor: Colors.redAccent,
          ),
        );
      _setDateFallback();
      _setTimeFallback();
    }
    if (mounted) setState(() => _isScanningAI = false);
  }

  Future<void> _checkForDuplicateReceipt(
    String store,
    String date,
    String totalStr,
  ) async {
    if (store.isEmpty || date.isEmpty) return;
    double scannedTotal = double.tryParse(totalStr.replaceAll('\$', '')) ?? 0.0;

    // Ask Firebase if a receipt from this store exists
    final query = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('finances')
        .where('store', isEqualTo: store)
        .get();

    bool foundDuplicate = false;

    // Check if the Date and Total match exactly
    for (var doc in query.docs) {
      var existingData = doc.data();
      double existingTotal = (existingData['total'] ?? 0.0) * 1.0;
      String existingDate = existingData['date'] ?? "";

      if (existingTotal == scannedTotal && existingDate == date) {
        foundDuplicate = true;
        break;
      }
    }

    if (mounted) {
      setState(() {
        _isDuplicate = foundDuplicate;
      });
    }
  }

  void _setDateFallback() {
    final now = DateTime.now();
    _dateController.text = "${now.month}/${now.day}/${now.year}";
  }

  void _setTimeFallback() {
    final now = DateTime.now();
    int h = now.hour == 0 ? 12 : (now.hour > 12 ? now.hour - 12 : now.hour);
    String amPm = now.hour >= 12 ? "PM" : "AM";
    _timeController.text = "$h:${now.minute.toString().padLeft(2, '0')} $amPm";
  }

  void _applyCategoryToAll(String category, String subcategory) {
    setState(() {
      for (var item in _parsedItems) {
        item['category'] = category;
        item['subcategory'] = subcategory;
      }
    });
  }

  void _showFullImage() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(widget.imagePath)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveReceipt() async {
    double subtotal =
        double.tryParse(_subtotalController.text.replaceAll('\$', '')) ?? 0.0;
    double tax =
        double.tryParse(_taxController.text.replaceAll('\$', '')) ?? 0.0;
    double total =
        double.tryParse(_totalController.text.replaceAll('\$', '')) ?? 0.0;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('finances')
        .add({
          'store': _storeController.text.trim(),
          'subtotal': subtotal,
          'tax': tax,
          'total': total,
          'date': _dateController.text.trim(),
          'time': _timeController.text.trim(),
          'items': _parsedItems,
          'timestamp': DateTime.now().toIso8601String(),
        });

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    List<String> masterCategories = widget.categories.keys.toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Verify Receipt",
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: _showFullImage,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            height: 100,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              image: DecorationImage(
                                image: FileImage(File(widget.imagePath)),
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                colorFilter: _isScanningAI
                                    ? ColorFilter.mode(
                                        Colors.black.withOpacity(0.6),
                                        BlendMode.darken,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          if (_isScanningAI)
                            const Column(
                              children: [
                                CircularProgressIndicator(
                                  color: Color(0xFF00C897),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  "Axis AI is extracting the data.",
                                  style: TextStyle(
                                    color: Color(0xFF00C897),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            )
                          else
                            const Positioned(
                              bottom: 8,
                              right: 8,
                              child: Icon(
                                Icons.zoom_out_map,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField("Date", _dateController),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: _buildTextField("Time", _timeController),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    _buildTextField("Store", _storeController),
                    const SizedBox(height: 15),

                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            "Subtotal",
                            _subtotalController,
                            isNumber: true,
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: _buildTextField(
                            "Tax",
                            _taxController,
                            isNumber: true,
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: _buildTextField(
                            "Total",
                            _totalController,
                            isNumber: true,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 25),
                    const Text(
                      "Itemized Breakdown",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (_parsedItems.isEmpty && !_isScanningAI)
                      const Text(
                        "No items detected.",
                        style: TextStyle(color: Colors.white54),
                      )
                    else
                      ...List.generate(_parsedItems.length, (index) {
                        var item = _parsedItems[index];
                        String cat = masterCategories.contains(item['category'])
                            ? item['category']
                            : (masterCategories.isNotEmpty
                                  ? masterCategories.first
                                  : '');
                        List<String> subList = widget.categories[cat] ?? [];
                        String sub = subList.contains(item['subcategory'])
                            ? item['subcategory']
                            : (subList.isNotEmpty ? subList.first : '');

                        TextEditingController nameCtrl = TextEditingController(
                          text: item['name'],
                        );
                        TextEditingController priceCtrl = TextEditingController(
                          text: item['price']?.toString() ?? '0.00',
                        );

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: nameCtrl,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: InputBorder.none,
                                        hintText: "Item Name",
                                        hintStyle: TextStyle(
                                          color: Colors.white24,
                                        ),
                                      ),
                                      onChanged: (val) => item['name'] = val,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    flex: 1,
                                    child: TextField(
                                      controller: priceCtrl,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      style: const TextStyle(
                                        color: Color(0xFF00C897),
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.right,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: InputBorder.none,
                                        prefixText: "\$ ",
                                        prefixStyle: TextStyle(
                                          color: Color(0xFF00C897),
                                        ),
                                      ),
                                      onChanged: (val) => item['price'] =
                                          double.tryParse(val) ?? 0.0,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _parsedItems.removeAt(index);
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const Divider(color: Colors.white10),

                              Row(
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        isExpanded: true,
                                        dropdownColor: const Color(0xFF1E1E1E),
                                        value: cat.isEmpty ? null : cat,
                                        hint: const Text(
                                          "Category",
                                          style: TextStyle(
                                            color: Colors.white38,
                                            fontSize: 14,
                                          ),
                                        ),
                                        items: masterCategories
                                            .map(
                                              (c) => DropdownMenuItem(
                                                value: c,
                                                child: Text(
                                                  c,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (val) {
                                          setState(() {
                                            item['category'] = val!;
                                            item['subcategory'] =
                                                widget
                                                    .categories[val]!
                                                    .isNotEmpty
                                                ? widget.categories[val]!.first
                                                : '';
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 4,
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        isExpanded: true,
                                        dropdownColor: const Color(0xFF1E1E1E),
                                        value: sub.isEmpty ? null : sub,
                                        hint: const Text(
                                          "Subcategory",
                                          style: TextStyle(
                                            color: Colors.white38,
                                            fontSize: 14,
                                          ),
                                        ),
                                        items: subList
                                            .map(
                                              (s) => DropdownMenuItem(
                                                value: s,
                                                child: Text(
                                                  s,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (val) => setState(
                                          () => item['subcategory'] = val!,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    flex: 3,
                                    child: InkWell(
                                      onTap: () =>
                                          _applyCategoryToAll(cat, sub),
                                      borderRadius: BorderRadius.circular(4),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 8.0,
                                        ),
                                        child: Text(
                                          "Apply this\ncategory to all",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Color(0xFF00C897),
                                            fontSize: 12,
                                            height: 1.1,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),

                    TextButton.icon(
                      onPressed: () => setState(
                        () => _parsedItems.add({
                          "name": "",
                          "category": masterCategories.isNotEmpty
                              ? masterCategories.first
                              : "",
                          "subcategory": "",
                          "price": 0.0,
                        }),
                      ),
                      icon: const Icon(Icons.add, color: Color(0xFF00C897)),
                      label: const Text(
                        "Add Missing Item",
                        style: TextStyle(color: Color(0xFF00C897)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 15),

            // --- DUPLICATE WARNING BANNER ---
            if (_isDuplicate)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "This looks like a duplicate. You already have a receipt logged for this store on this date with this total.",
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C897),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isScanningAI ? null : _saveReceipt,
                child: Text(
                  _isScanningAI ? "Scanning..." : "Save to Finances",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String labelStr,
    TextEditingController controller, {
    bool isNumber = false,
  }) {
    const Color exactMatchColor = Color(0xFF292929);

    return TextField(
      controller: controller,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        isDense: true,
        label: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: exactMatchColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            labelStr,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        filled: true,
        fillColor: exactMatchColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00C897)),
        ),
      ),
    );
  }
}
