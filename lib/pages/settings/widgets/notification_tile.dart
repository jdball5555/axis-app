import 'package:flutter/material.dart';

class NotificationTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isEnabled;
  final TimeOfDay time;
  final VoidCallback onTimeTap;
  final ValueChanged<bool> onToggle;

  const NotificationTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isEnabled,
    required this.time,
    required this.onTimeTap,
    required this.onToggle,
  });

  String _formatTime(TimeOfDay t) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    String h = dt.hour > 12
        ? (dt.hour - 12).toString()
        : (dt.hour == 0 ? "12" : dt.hour.toString());
    String m = dt.minute.toString().padLeft(2, '0');
    String a = dt.hour >= 12 ? "PM" : "AM";
    return "$h:$m $a";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 16,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (isEnabled)
            GestureDetector(
              onTap: onTimeTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatTime(time),
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          Switch(
            value: isEnabled,
            activeColor: theme.colorScheme.primary,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }
}
