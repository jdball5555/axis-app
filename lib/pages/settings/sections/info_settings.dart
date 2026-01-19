import 'package:flutter/material.dart';
import '../widgets/settings_widgets.dart';
import '../dialogs/about_dialog.dart';

class InfoSettings extends StatelessWidget {
  final String appVersion;

  const InfoSettings({super.key, required this.appVersion});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GradientSettingsTile(
          icon: Icons.info_outline,
          title: "About Axis",
          subtitle: "View licenses and app info",
          onTap: () => showAxisAboutDialog(context, appVersion),
        ),
        GradientSettingsTile(
          icon: Icons.developer_mode,
          title: "App Version",
          subtitle: "v$appVersion",
          onTap:
              () {}, // Keep empty for ripple, or set null to disable completely
          trailing: const SizedBox.shrink(), // This hides the arrow
        ),
      ],
    );
  }
}
