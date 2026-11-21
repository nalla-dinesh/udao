// phase-05
// The OEM survival matrix — typed guide data for all 11 [OemId]s.
//
// HONESTY RULES baked into this file:
//   * Every deep link is UNDOCUMENTED OEM territory: each one is
//     try/catch'd at launch time (SurvivalBridge.openOemScreen) and
//     EVERY guide also carries full manual steps — a dead link must
//     never be a dead end.
//   * Copy never promises "guaranteed fix"; OEMs change these paths
//     between OS versions (MIUI→HyperOS, One UI majors, ColorOS 13+).
//   * dontkillmyapp.com stays linked as the community source of
//     truth for what each maker's updater broke this quarter.
import 'package:flutter/foundation.dart';

import 'oem_detector.dart';

/// A single try-launch OEM settings screen.
@immutable
class OemDeepLink {
  const OemDeepLink({required this.label, required this.component});

  /// Button label ("Autostart screen kholo").
  final String label;

  /// ComponentName flat string: "package/class".
  final String component;
}

/// One numbered setup step.
@immutable
class OemGuideStep {
  const OemGuideStep({
    required this.title,
    required this.detail,
    this.deepLink,
  });

  final String title;
  final String detail;
  final OemDeepLink? deepLink;
}

/// The full guide for one maker.
@immutable
class OemSetupGuide {
  const OemSetupGuide({
    required this.oem,
    required this.summary,
    required this.steps,
    required this.manualTitle,
    required this.manualSteps,
    required this.notes,
  });

  final OemId oem;

  /// One-line "why this phone needs this" (honest, no fear-mongering).
  final String summary;

  /// Ordered steps; at least one, each with manual-equivalent detail.
  final List<OemGuideStep> steps;

  /// Fallback path in words, ALWAYS present even when deep links work.
  final String manualTitle;
  final List<String> manualSteps;

  /// Version caveats and post-update checks.
  final List<String> notes;
}

/// Static registry — no async, no assets, testable invariants.
@immutable
class OemGuideData {
  const OemGuideData._();

  static const Map<OemId, OemSetupGuide> all = <OemId, OemSetupGuide>{
    OemId.xiaomi: OemSetupGuide(
      oem: OemId.xiaomi,
      summary:
          'MIUI/HyperOS background apps ko aggressively band karta hai — '
          'autostart + battery "No restrictions" dono chahiye.',
      steps: <OemGuideStep>[
        OemGuideStep(
          title: 'Autostart ON karo',
          detail:
              'Settings → Apps → Manage apps → UDAO → Autostart ON. '
              'Isse reboot ke baad listener wapas judta hai.',
          deepLink: OemDeepLink(
            label: 'Autostart screen kholo',
            component:
                'com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity',
          ),
        ),
        OemGuideStep(
          title: 'Battery saver → No restrictions',
          detail:
              'Manage apps → UDAO → Battery saver → "No restrictions". '
              '"Battery saver" ya "Smart" rakhne par MIUI capture rok deta hai.',
          deepLink: OemDeepLink(
            label: 'Battery settings kholo',
            component:
                'com.miui.powerkeeper/com.miui.powerkeeper.ui.HiddenAppsConfigActivity',
          ),
        ),
        OemGuideStep(
          title: 'Recents mein lock karo',
          detail:
              'Recent apps screen mein UDAO ka card pakdo → neeche "Lock" 🔒 '
              'icon dabao. Locked apps MIUI clean-up se bache rehte hain.',
        ),
      ],
      manualTitle: 'Deep link kaam na kare toh (manual path)',
      manualSteps: <String>[
        'Settings app kholo → "Apps" → "Manage apps"',
        'UDAO dhoondo → "Autostart" toggle ON karo',
        'Wahi screen par "Battery saver" → "No restrictions" chuno',
        'Recent apps mein UDAO card ko lock (🔒) karo',
      ],
      notes: <String>[
        'MIUI/HyperOS ke bade updates ye settings reset kar dete hain — '
            'update ke baad ek baar check kar lena.',
        'Kuch HyperOS builds mein path thoda alag hai — manual steps follow karo.',
      ],
    ),
    OemId.samsung: OemSetupGuide(
      oem: OemId.samsung,
      summary:
          'One UI "sleeping apps" background capture band kar deta hai — '
          'UDAO ko "Never sleeping apps" mein rakhna hai.',
      steps: <OemGuideStep>[
        OemGuideStep(
          title: 'Battery → Background usage limits',
          detail:
              'Settings → Battery and device care → Battery → Background '
              'usage limits. Yahan se UDAO ko remove/never-sleeping karo.',
          deepLink: OemDeepLink(
            label: 'Battery settings kholo',
            component:
                'com.samsung.android.lool/com.samsung.android.sm.battery.ui.BatteryActivity',
          ),
        ),
        OemGuideStep(
          title: 'UDAO ko "Never sleeping apps" mein add karo',
          detail:
              'Background usage limits → Never sleeping apps → + → UDAO. '
              '"Deep sleeping apps" mein kabhi na jaane do.',
        ),
        OemGuideStep(
          title: 'Battery optimization exempt',
          detail:
              'App info → Battery → Unrestricted. Samsung ka adaptive '
              'battery warna doze mein capture slow kar deta hai.',
        ),
      ],
      manualTitle: 'Deep link kaam na kare toh (manual path)',
      manualSteps: <String>[
        'Settings → "Battery and device care"',
        '"Battery" → "Background usage limits"',
        '"Never sleeping apps" → "+" → UDAO select karo',
        'UDAO app info → Battery → "Unrestricted" chuno',
      ],
      notes: <String>[
        'One UI ke software updates ke baad "device care" kabhi kabhi '
            ' sleeping list rebuild kar deta hai — monthly ek check accha hai.',
      ],
    ),
    OemId.oppo: OemSetupGuide(
      oem: OemId.oppo,
      summary:
          'ColorOS ka security center background apps ko freeze karta hai — '
          'autostart + manual battery management dono chahiye.',
      steps: <OemGuideStep>[
        OemGuideStep(
          title: 'Autostart allow karo',
          detail:
              'Security/Phone Manager → Privacy → Startup manager → UDAO ON. '
              'Reboot ke baad listener khud judta hai.',
          deepLink: OemDeepLink(
            label: 'Startup manager kholo',
            component:
                'com.coloros.safecenter/com.coloros.safecenter.permission.startup.StartupAppListActivity',
          ),
        ),
        OemGuideStep(
          title: 'Battery optimization exempt',
          detail:
              'Settings → Battery → App battery management → UDAO → '
              '"Allow background" / "Don\'t optimize".',
        ),
      ],
      manualTitle: 'Deep link kaam na kare toh (manual path)',
      manualSteps: <String>[
        'Settings → "Battery" → "App battery management"',
        'UDAO dhoondo → "Allow background" chuno',
        'Phone Manager / Security app → "Startup manager" → UDAO ON karo',
      ],
      notes: <String>[
        'ColorOS 13+ par paths "Privacy" ke andar shift hue hain — '
            'settings search mein "startup" likhke dhoondo.',
      ],
    ),
    OemId.realme: OemSetupGuide(
      oem: OemId.realme,
      summary:
          'Realme UI (ColorOS-based) bhi background freeze karta hai — '
          'autostart + battery allow chahiye.',
      steps: <OemGuideStep>[
        OemGuideStep(
          title: 'Autostart allow karo',
          detail:
              'Phone Manager / Security → Privacy → Startup manager → '
              'UDAO ON.',
          deepLink: OemDeepLink(
            label: 'Startup manager kholo',
            component:
                'com.coloros.safecenter/com.coloros.safecenter.permission.startup.StartupAppListActivity',
          ),
        ),
        OemGuideStep(
          title: 'Battery optimization exempt',
          detail:
              'Settings → Battery → App battery management → UDAO → '
              'background allow.',
        ),
      ],
      manualTitle: 'Deep link kaam na kare toh (manual path)',
      manualSteps: <String>[
        'Settings → "Battery" → "App battery management" → UDAO → allow',
        'Phone Manager → "Startup manager" ya "Auto-start management" → UDAO ON',
        'Recent apps mein UDAO card lock karo (agar lock option hai)',
      ],
      notes: <String>[
        'Realme UI versions mein app names thode-alag hote hain '
            '("Phone Manager" vs "Security") — dono check karo.',
      ],
    ),
    OemId.vivo: OemSetupGuide(
      oem: OemId.vivo,
      summary:
          'Funtouch/OriginOS background power management sabse aggressive '
          'mein se hai — autostart + high-power whitelist dono chahiye.',
      steps: <OemGuideStep>[
        OemGuideStep(
          title: 'Background power consumption allow',
          detail:
              'Settings → Battery → Background power consumption '
              'management → UDAO ko allow karo.',
          deepLink: OemDeepLink(
            label: 'Power manager kholo',
            component:
                'com.vivo.permissionmanager/com.vivo.permissionmanager.activity.BgStartUpManagerActivity',
          ),
        ),
        OemGuideStep(
          title: 'Autostart ON',
          detail:
              'Settings → Apps → UDAO → Autostart ON (Funtouch OS 12+ '
              'mein "Background pop-up"/autostart app info ke andar hai).',
        ),
      ],
      manualTitle: 'Deep link kaam na kare toh (manual path)',
      manualSteps: <String>[
        'Settings → "Battery" → "Background power consumption management"',
        'UDAO dhoondo → allow / "High background power consumption" OFF',
        'Settings → "Apps" → UDAO → "Autostart" ON karo',
      ],
      notes: <String>[
        'Vivo ke security updates ke baad whitelist reset ho sakti hai — '
            'capture band dikhe toh yahan wapas check karo.',
      ],
    ),
    OemId.iqoo: OemSetupGuide(
      oem: OemId.iqoo,
      summary:
          'iQOO (vivo ka sub-brand) Funtouch-style power manager use '
          'karta hai — autostart + power whitelist chahiye.',
      steps: <OemGuideStep>[
        OemGuideStep(
          title: 'Background power management',
          detail:
              'Phone Manager / i Manager → Power Manager → Background '
              'power consumption → UDAO allow.',
          deepLink: OemDeepLink(
            label: 'i Manager power screen kholo',
            component:
                'com.iqoo.secure/com.iqoo.secure.safeguard.PurviewTabActivity',
          ),
        ),
        OemGuideStep(
          title: 'Autostart ON',
          detail:
              'i Manager → App manager → Autostart manager → UDAO ON.',
          deepLink: OemDeepLink(
            label: 'Autostart screen kholo',
            component:
                'com.iqoo.secure/com.iqoo.secure.ui.phoneoptimize.BgStartUpManager',
          ),
        ),
      ],
      manualTitle: 'Deep link kaam na kare toh (manual path)',
      manualSteps: <String>[
        'i Manager app kholo → "Power Manager"',
        '"Background power consumption" mein UDAO allow karo',
        'i Manager → "App manager" → "Autostart manager" → UDAO ON',
      ],
      notes: <String>[
        'iQOO builds mein i Manager ka naam kabhi "Phone Manager" hota '
            'hai — wahi app hai.',
      ],
    ),
    OemId.huawei: OemSetupGuide(
      oem: OemId.huawei,
      summary:
          'EMUI ka "App launch" system strictest mein se hai — manual '
          'manage + protected apps teen setting chahiye.',
      steps: <OemGuideStep>[
        OemGuideStep(
          title: 'App launch → Manage manually',
          detail:
              'Settings → Battery → App launch → UDAO → "Manage manually" '
              'ON: Auto-launch, Secondary launch, Run in background — teeno.',
          deepLink: OemDeepLink(
            label: 'App launch screen kholo',
            component:
                'com.huawei.systemmanager/com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity',
          ),
        ),
        OemGuideStep(
          title: 'Protected apps',
          detail:
              'Phone Manager → Battery → Protected apps → UDAO ON '
              '(EMUI 5–9 mein alag list hai).',
          deepLink: OemDeepLink(
            label: 'Protected apps kholo',
            component:
                'com.huawei.systemmanager/com.huawei.systemmanager.optimize.process.ProtectActivity',
          ),
        ),
      ],
      manualTitle: 'Deep link kaam na kare toh (manual path)',
      manualSteps: <String>[
        'Settings → "Battery" → "App launch"',
        'UDAO → "Manage manually" ON karo (teeno toggles)',
        'Phone Manager → "Battery" → "Protected apps" → UDAO ON',
      ],
      notes: <String>[
        'EMUI update ke baad "App launch" list reset ho jaati hai — '
            'restart ke baad ek baar confirm karo.',
      ],
    ),
    OemId.honor: OemSetupGuide(
      oem: OemId.honor,
      summary:
          'Honor (MagicOS) post-split paths badal-chuki hain — deep '
          'links hit-or-miss, manual path pakka hai.',
      steps: <OemGuideStep>[
        OemGuideStep(
          title: 'App launch settings',
          detail:
              'Settings → Battery → App launch → UDAO → Manage manually '
              '(Auto-launch + Secondary launch + Run in background).',
          deepLink: OemDeepLink(
            label: 'App launch screen kholo',
            component:
                'com.hihonor.systemmanager/com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity',
          ),
        ),
        OemGuideStep(
          title: 'Battery optimization exempt',
          detail:
              'App info → Battery → Unrestricted / "Don\'t optimize".',
        ),
      ],
      manualTitle: 'Deep link kaam na kare toh (manual path)',
      manualSteps: <String>[
        'Settings → "Battery" → "App launch" (ya "Startup management")',
        'UDAO → "Manage manually" ON',
        'App info → Battery → optimization exempt karo',
      ],
      notes: <String>[
        'Purane Honor (Huawei-era) builds par Huawei wala path use hota '
            'hai — dono try kar sakte ho.',
        'MagicOS versions mein naam kaafi vary karte hain — settings '
            'search mein "launch" likho.',
      ],
    ),
    OemId.oneplus: OemSetupGuide(
      oem: OemId.oneplus,
      summary:
          'OxygenOS (ab OPlus/ColorOS base) auto-launch control karta '
          'hai — autostart + battery exempt chahiye.',
      steps: <OemGuideStep>[
        OemGuideStep(
          title: 'Auto-launch allow',
          detail:
              'Settings → Apps → UDAO → Battery usage → "Allow '
              'background activity" + auto-launch.',
          deepLink: OemDeepLink(
            label: 'Auto-launch screen kholo',
            component:
                'com.oneplus.security/com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity',
          ),
        ),
        OemGuideStep(
          title: 'Battery optimization exempt',
          detail:
              'App info → Battery → "Don\'t optimize" / Unrestricted.',
        ),
      ],
      manualTitle: 'Deep link kaam na kare toh (manual path)',
      manualSteps: <String>[
        'Settings → "Battery" → "Battery optimization" / "App battery management"',
        'UDAO → "Don\'t optimize" chuno',
        'Settings → "Apps" → UDAO → "Battery usage" → background allow',
      ],
      notes: <String>[
        'OxygenOS 13+ par ColorOS-style "Smart control" bhi hai — '
            'nahi samajh aaye toh battery screen mein "manual" chuno.',
      ],
    ),
    OemId.nokia: OemSetupGuide(
      oem: OemId.nokia,
      summary:
          'Nokia mostly near-stock Android hai — khaas setup nahi, '
          'bas battery optimization exempt kar do.',
      steps: <OemGuideStep>[
        OemGuideStep(
          title: 'Battery optimization exempt',
          detail:
              'App info → Battery → Unrestricted. Bas itna hi chahiye '
              '(stock doze watchdog khud sambhal lega).',
        ),
      ],
      manualTitle: 'Deep link kaam na kare toh (manual path)',
      manualSteps: <String>[
        'Settings → "Apps" → UDAO → "Battery"',
        '"Unrestricted" / "Don\'t optimize" chuno',
      ],
      notes: <String>[
        'Kuch purane Nokia builds (HMD) par "Battery Manager" naam se '
            'extra list thi — mille toh UDAO allow karo.',
      ],
    ),
    OemId.stock: OemSetupGuide(
      oem: OemId.stock,
      summary:
          'Stock Android (Pixel, Motorola, Nothing, …) — capture ke '
          'liye sirf doze-jod do settings chahiye.',
      steps: <OemGuideStep>[
        OemGuideStep(
          title: 'Battery optimization exempt',
          detail:
              'Settings → Apps → UDAO → Battery → Unrestricted. Doze '
              'ke idle windows mein bhi listener bound rahega.',
        ),
      ],
      manualTitle: 'Deep link kaam na kare toh (manual path)',
      manualSteps: <String>[
        'Settings → "Apps" → UDAO → "Battery" → "Unrestricted"',
        'Notification access ON hai ye ek baar confirm karo',
      ],
      notes: <String>[
        'App standby bucket "rare/active" system khud manage karta hai — '
            'UDAO ka watchdog sambhal lega.',
      ],
    ),
  };

  static OemSetupGuide forId(OemId id) =>
      all[id] ?? all[OemId.stock]!;
}
