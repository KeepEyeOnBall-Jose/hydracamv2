import "package:flutter/material.dart";

import "../widgets/hydra_cam_app_bar.dart";

class AutomationStandbyScreen extends StatelessWidget {
  const AutomationStandbyScreen({
    super.key,
    this.onOpenNormalApp,
  });

  final VoidCallback? onOpenNormalApp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: HydraCamAppBar(
        title: "HydraCam",
        onBack: onOpenNormalApp ?? () {},
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.pause_circle_outline,
                  color: theme.colorScheme.primary,
                  size: 72,
                ),
                const SizedBox(height: 20),
                Text(
                  "Automation standby",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  "Waiting for role assignment",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                if (onOpenNormalApp != null) ...[
                  const SizedBox(height: 28),
                  ElevatedButton.icon(
                    onPressed: onOpenNormalApp,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text("Open HydraCam"),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
