import 'package:flutter/material.dart';

// --- 1. GRADIENT SETTINGS TILE ---
// The colorful button with the gradient background (0.1 -> 0.4 opacity)
class GradientSettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const GradientSettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 70,
        margin: const EdgeInsets.only(bottom: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              theme.colorScheme.primary.withOpacity(0.1),
              theme.colorScheme.primary.withOpacity(0.4),
            ],
            stops: const [0.0, 1.0],
          ),
          border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              // Leading Icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: theme.colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 20),

              // Text Content
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // Trailing Logic
              if (trailing != null)
                // Force any trailing widget (like Drag Handle) to be Black
                IconTheme(
                  data: const IconThemeData(color: Colors.black, size: 20),
                  child: trailing!,
                )
              else if (onTap != null)
                // Default Arrow is Black
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.black,
                  size: 16,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- 2. RESPONSIVE SETTINGS GRID ---
// Automatically switches between a Column (Portrait) and 2-Column Grid (Landscape)
class ResponsiveSettingsGrid extends StatelessWidget {
  final List<Widget> children;

  const ResponsiveSettingsGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    if (!isLandscape) {
      return Column(children: children);
    }

    // Landscape Logic: Group items into pairs
    List<Widget> rows = [];
    for (int i = 0; i < children.length; i += 2) {
      Widget item1 = children[i];
      Widget? item2 = (i + 1 < children.length) ? children[i + 1] : null;

      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: item1),
            const SizedBox(width: 15),
            Expanded(child: item2 ?? const SizedBox()),
          ],
        ),
      );
    }
    return Column(children: rows);
  }
}

// --- 3. SETTINGS SECTION ---
// Your existing wrapper for grouping standard list tiles
class SettingsSection extends StatelessWidget {
  final List<Widget> children;

  const SettingsSection({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(children: children),
    );
  }
}
