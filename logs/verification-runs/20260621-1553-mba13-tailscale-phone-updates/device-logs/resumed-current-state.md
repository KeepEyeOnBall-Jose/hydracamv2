# Resumed Current State

- Resumed on 2026-06-22 after the user clarified the MBA host as `joss-macbook-air.tail6ce139.ts.net`.
- MBA13 SSH over Tailscale was reachable again.
- Remote deploy checkout: `/Users/jose/src/work/hydracamv2-mba13-deploy`.
- MBA13 Android debug build remained available, and the matching local-debug-key APK remained transferred as `build/app/outputs/flutter-apk/app-debug-local-signed.apk`.
- Final MBA13 ADB inventory showed two attached Android devices, `9885e6503930304946` and `RF8M90QE7LX`, both `unauthorized` after `adb kill-server` / `adb start-server`; Android installs require accepting the USB debugging prompt on each phone.
- MBA13 CoreDevice inventory showed `José Ramón’s iPhone` available and paired: `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A`.
- MBA13 native iOS Profile build reached signing, but the machine had zero valid code-signing identities and zero local provisioning profiles, and Xcode could not authenticate `javier@keepeyeonball.com` to create/find a `com.keepeyeonball` development profile.
- Workaround used for the connected iPhone: build a fresh local `com.keepeyeonball` Profile app with team `4RRY2QT7H8`, verify its embedded provisioning profile includes `00008101-000A68811E43001E`, transfer the signed app to MBA13, install with `devicectl`, and launch it.
- Launch/process proof: `devicectl` reported `Launched application with com.keepeyeonball bundle identifier`; installed app metadata showed `HydraCam` version `1.4.0`, build `18`; `device info processes` showed PID `2427` running `/private/var/containers/Bundle/Application/8160D96A-B593-4E5F-8477-8F704D659CC9/Runner.app/Runner`.
