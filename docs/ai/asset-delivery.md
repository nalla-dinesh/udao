# Play Asset Delivery setup for the Gemma pack (human checklist)

> Why PAD: a 2 GB model cannot ship inside the APK (Play's 200 MB
> base limit), and UDAO has no download code by law (ADR-0001).
> PAD's **on-demand** pack is the Play-sanctioned way to move big
> assets without the app owning a downloader.

## What the app already does

- Discovery checks the staging directory
  `<appDocuments>/models/pad/gemma-3n-e2b-it-int4.task` FIRST
  (see `ModelManager.discover` + `ModelPaths`).
- Everything else (validation, SHA-256, tiering, load) treats a
  PAD-delivered file exactly like an imported one.

## What you (the human) set up in Play Console

1. **Android App Bundle** is mandatory for PAD — build with
   `flutter build appbundle --flavor play`.
2. Create an **on-demand** asset pack named exactly:
   ```
   gemma3n_e2b
   ```
3. Inside the pack, the asset must be named exactly:
   ```
   gemma-3n-e2b-it-int4.task
   ```
   (pack name + file name are pinned by `ModelPaths` and this doc).
4. Pack size tier: Google Play handles up to 2 GB per on-demand
   pack — E2B fits; E4B may need a second pack (`gemma3n_e4b`,
   file `gemma-3n-e4b-it-int4.task` — extend `ModelPaths` if you
   ship it).

## What the app needs later (NOT in this phase)

Retrieving an on-demand pack requires the Play Core library
(`com.google.android.play:asset-delivery`) — a NETWORK-capable
component, so wiring it is a deliberate, reviewed decision:

- add the Gradle dep + a small Kotlin fetch wrapper behind
  `udao/ai` (`fetchAssetPack` method returning progress events);
- Dart side: a progress card in AI settings that calls it once the
  user opts in ("Play se laao (2 GB)");
- delivery lands the file in `models/pad/` and discovery picks it
  up on next app start.

Until that is built, the practical paths are **manual import** and
the **adb sideload** documented in
[models.md](models.md) §3 — both fully wired today.

## License note

Shipping Gemma model files via PAD still requires accepting the
Gemma Terms of Use for the app listing (Play Console shows the
Gemma license flow). FunctionGemma-class models may be Apache-2.0 —
check each model card before adding it to a pack.
