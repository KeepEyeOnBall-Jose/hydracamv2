import "package:flutter/material.dart";

import "../widgets/hydra_cam_app_bar.dart";

class AutomationStandbyScreen extends StatelessWidget {
  const AutomationStandbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HydraCamAppBar(
        title: "HydraCam",
        onBack: () {},
      ),
      body: const SizedBox.expand(),
    );
  }
}
