import 'package:flutter/material.dart';

Future<void> showSmartTextInputDialog({
  required BuildContext context,
  required String title,
  required String label,
  required String buttonText,
  String? initialValue,
  required Function(String) onSubmit,
}) async {
  final controller = TextEditingController(text: initialValue);

  await showDialog(
    context: context,
    builder: (ctx) {
      // 1. Get dimensions
      final mediaQuery = MediaQuery.of(ctx);
      final isLandscape = mediaQuery.orientation == Orientation.landscape;
      final keyboardHeight = mediaQuery.viewInsets.bottom;
      final screenHeight = mediaQuery.size.height;

      // 2. Determine "Compact Mode" (Strip Mode)
      // Only trigger if:
      // - We are in Landscape
      // - The Keyboard is Open
      // - The available vertical space is SMALL (less than 400px total height)
      // This keeps the title on tablets/large screens but hides it on phones.
      final isCompactMode =
          isLandscape && keyboardHeight > 0 && screenHeight < 450;

      return AlertDialog(
        scrollable: true,
        backgroundColor: Theme.of(context).cardColor,

        // 3. Dynamic Padding
        // WIDER in Landscape to use space, narrower in Portrait
        insetPadding: EdgeInsets.symmetric(
          horizontal: isLandscape ? 10.0 : 40.0,
          vertical: 24.0,
        ),

        // 4. Conditionally Hide Title
        title: isCompactMode
            ? null
            : Text(
                title,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),

        // 5. Content
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                textCapitalization: TextCapitalization.words,
                autofocus: true,
                // Ensure field scrolls above keyboard
                scrollPadding: EdgeInsets.only(bottom: keyboardHeight + 20),
                decoration: InputDecoration(
                  labelText: label,
                  labelStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  // "Check" button appears nicely inside the field
                  suffixIcon: IconButton(
                    icon: Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: () {
                      if (controller.text.trim().isNotEmpty) {
                        onSubmit(controller.text.trim());
                        Navigator.pop(ctx);
                      }
                    },
                  ),
                ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) {
                    onSubmit(val.trim());
                    Navigator.pop(ctx);
                  }
                },
              ),
            ],
          ),
        ),

        // 6. Conditionally Hide Bottom Buttons
        actions: isCompactMode
            ? []
            : [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () {
                    if (controller.text.trim().isNotEmpty) {
                      onSubmit(controller.text.trim());
                      Navigator.pop(ctx);
                    }
                  },
                  child: Text(buttonText),
                ),
              ],
      );
    },
  );
}
