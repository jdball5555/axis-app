import 'package:flutter/material.dart';

void showAxisAboutDialog(BuildContext context, String appVersion) {
  final theme = Theme.of(context);
  final isLandscape =
      MediaQuery.of(context).orientation == Orientation.landscape;

  Widget identitySection = Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
        width: 80,
        height: 80,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black,
          shape: BoxShape.circle,
          border: Border.all(
            color: theme.colorScheme.primary.withOpacity(0.5),
            width: 2,
          ),
        ),
        child: ClipOval(
          child: Image.asset(
            'assets/icon.png',
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) =>
                Icon(Icons.hub, size: 40, color: theme.colorScheme.primary),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        "Axis",
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 26,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
      Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: theme.dividerColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          "v$appVersion",
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ),
    ],
  );

  Widget infoSection = Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildFeature(theme, Icons.cloud_queue, "Cloud"),
          _buildFeature(theme, Icons.group, "Shared"),
          _buildFeature(theme, Icons.settings_suggest, "Rework"),
        ],
      ),
      const SizedBox(height: 20),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(
              "What's New",
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "• Cloud-Powered Alerts\n• Customizable Home Page\n• Redesigned Settings\n• Unified Inventory Logic",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      contentPadding: const EdgeInsets.all(24),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            "Close",
            style: TextStyle(color: theme.colorScheme.primary),
          ),
        ),
      ],
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: isLandscape ? 300 : 500,
        ),
        child: SingleChildScrollView(
          child: isLandscape
              ? Row(
                  children: [
                    Expanded(flex: 2, child: identitySection),
                    const SizedBox(width: 24),
                    Container(width: 1, height: 150, color: theme.dividerColor),
                    const SizedBox(width: 24),
                    Expanded(flex: 3, child: infoSection),
                  ],
                )
              : Column(
                  children: [
                    identitySection,
                    const SizedBox(height: 30),
                    infoSection,
                  ],
                ),
        ),
      ),
    ),
  );
}

Widget _buildFeature(ThemeData theme, IconData icon, String label) => Column(
  children: [
    Icon(icon, color: theme.colorScheme.primary, size: 24),
    const SizedBox(height: 6),
    Text(
      label,
      style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 10),
    ),
  ],
);
