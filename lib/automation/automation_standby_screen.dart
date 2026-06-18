import "package:flutter/material.dart";

import "../app_theme.dart";
import "../widgets/hydra_cam_app_bar.dart";
import "../widgets/hydracam_surface.dart";

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
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isShort = constraints.maxHeight < 360;
            final padding = isShort ? 16.0 : 24.0;
            final iconSize = isShort ? 56.0 : 72.0;

            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: EdgeInsets.all(padding),
                      child: HydraCamSurface(
                        tone: HydraCamSurfaceTone.dark,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.pause_circle_outline,
                              color: AppTheme.accent,
                              size: iconSize,
                            ),
                            SizedBox(height: isShort ? 12 : 20),
                            Text(
                              "Automation standby",
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: AppTheme.inverseText,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "Waiting for role assignment",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppTheme.inverseTextMuted,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const HydraCamStatusChip(
                              status: HydraCamStatusTone.active,
                              icon: Icons.settings_ethernet,
                              label: "Bridge ready",
                            ),
                            if (onOpenNormalApp != null) ...[
                              SizedBox(height: isShort ? 20 : 28),
                              HydraCamButton(
                                icon: Icons.play_arrow,
                                label: "Open HydraCam",
                                onPressed: onOpenNormalApp,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
