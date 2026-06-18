import "package:flutter/material.dart";
import "../app_theme.dart";
import "../master/master_screen.dart";
import "../slave/slave_screen.dart";
import "../widgets/hydracam_surface.dart";

/// RoleSelectionScreen - Initial screen to select the role of the device (Master or Slave).
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent app from closing on pressing "back"
      child: Scaffold(
        appBar: AppBar(
          title: const Text("HydraCam"),
          automaticallyImplyLeading: false, // Disable the "back" button
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const HydraCamSurface(
                      tone: HydraCamSurfaceTone.dark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.videocam_outlined,
                            color: AppTheme.accent,
                            size: 36,
                          ),
                          SizedBox(height: 12),
                          Text(
                            "HydraCam Capture",
                            style: TextStyle(
                              color: AppTheme.inverseText,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            "Select this device's court role before capture.",
                            style: TextStyle(
                              color: AppTheme.inverseTextMuted,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const HydraCamToolbar(
                      children: [
                        HydraCamStatusChip(
                          status: HydraCamStatusTone.neutral,
                          icon: Icons.radio_button_unchecked,
                          label: "No active session",
                        ),
                        HydraCamStatusChip(
                          status: HydraCamStatusTone.warning,
                          icon: Icons.wifi,
                          label: "Local network required",
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    HydraCamSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: 56,
                            child: HydraCamButton(
                              icon: Icons.settings_remote,
                              label: "Master",
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const MasterScreen(),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 56,
                            child: HydraCamButton(
                              icon: Icons.link,
                              label: "Slave",
                              variant: HydraCamButtonVariant.neutral,
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const SlaveScreen(),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
