// phase-06
// AI settings: model status + import/delete + test roast, RAM tier
// suggestion, preload ("brain warm rakhna") toggle, persona picker
// with pin, learned-regex approval rows, and the telemetry
// transparency card. Everything on this screen is honest about
// absence — no model ever pretends to be loaded.
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/udao_spacing.dart';
import '../../core/ui/section_header.dart';
import '../../core/ui/udao_button.dart';
import '../../core/ui/udao_card.dart';
import '../../l10n/app_localizations.dart';
import '../ai/ai_providers.dart' as ai;
import '../ai/model/model_manager.dart';
import '../ai/model/model_tier.dart';
import '../ai/parser_fallback/learned_pattern.dart';
import '../ai/persona/persona.dart';
import '../ai/persona/persona_router.dart';
import '../ai/roast/roast_engine.dart' as roast;
import '../ai/telemetry/ai_telemetry.dart';

class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  bool _importing = false;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    // Discovery + (model present ⇒ capped) pending-format drain —
    // both cheap, both honest failures.
    final ModelManager manager = ref.read(ai.modelManagerProvider);
    unawaited(manager.discover());
  }

  Future<void> _import() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _importing = true);
    try {
      // FileType.custom + allowedExtensions crashes/throws on several
      // OEM file managers (seen live on MIUI: "Import failed: picker").
      // Safe to relax: importFromFile() re-validates the .task
      // extension (and size + sha256) after picking.
      final FilePickerResult? picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );
      final String? path = picked?.files.single.path;
      if (path == null) {
        setState(() => _importing = false);
        return;
      }
      final ModelManager manager = ref.read(ai.modelManagerProvider);
      final result = await manager.importFromFile(path);
      if (!mounted) {
        return;
      }
      setState(() => _importing = false);
      if (result.isErr) {
        _snack(l10n.aiSettingsImportFailed(result.failureOrNull!.message));
      } else {
        _snack(l10n.aiSettingsImportDone);
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        // Real reason, not just "picker" — the live MIUI failure was
        // undebuggable without it.
        final String raw = e.toString();
        _snack(l10n.aiSettingsImportFailed(
          'picker: ${raw.length > 90 ? raw.substring(0, 90) : raw}',
        ));
      }
    }
  }

  Future<void> _delete() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    await ref.read(ai.modelManagerProvider).deleteModel();
    if (mounted) {
      _snack(l10n.aiSettingsDeleteDone);
    }
  }

  Future<void> _load() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ModelManager manager = ref.read(ai.modelManagerProvider);
    final result = await manager.load();
    await ref
        .read(ai.aiTelemetryProvider)
        .recordModelLoad(ok: result.isOk);
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      _snack(l10n.aiSettingsModelLoadFailed(result.failureOrNull!.message));
    } else {
      _snack(l10n.aiSettingsModelLoaded);
    }
  }

  Future<void> _testRoast() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final Stopwatch watch = Stopwatch()..start();
    final roast.RoastOutcome outcome =
        await ref.read(ai.roastEngineProvider).generate(
              const roast.RoastRequestShape(),
            );
    final int ms = watch.elapsedMilliseconds;
    final AiTelemetrySnapshot telemetry =
        await ref.read(ai.aiTelemetryProvider).snapshot();
    if (!mounted) {
      return;
    }
    setState(() {
      _testing = false;
      _testResult = l10n.aiSettingsTestRoastDone(
        ms,
        telemetry.estimatedTokens,
      );
    });
    _snack(outcome.text);
  }

  void _snack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ModelManager manager = ref.watch(ai.modelManagerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiSettingsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(UdaoSpacing.md),
          children: <Widget>[
            const SectionHeader(number: '01', label: 'AI / DIMAAG'),
            _ModelCard(
              manager: manager,
              importing: _importing,
              onImport: _import,
              onDelete: _delete,
              onLoad: _load,
            ),
            const SizedBox(height: UdaoSpacing.md),
            _TierCard(manager: manager),
            const SizedBox(height: UdaoSpacing.md),
            _PersonaCard(ref: ref),
            const SizedBox(height: UdaoSpacing.md),
            _PreloadCard(manager: manager),
            const SizedBox(height: UdaoSpacing.md),
            _TestRoastCard(
              testing: _testing,
              result: _testResult,
              onTest: _testRoast,
            ),
            const SizedBox(height: UdaoSpacing.md),
            _LearnedPatternsCard(ref: ref),
            const SizedBox(height: UdaoSpacing.md),
            _TelemetryCard(ref: ref),
            const SizedBox(height: UdaoSpacing.lg),
          ],
        ),
      ),
    );
  }
}

// ── model card ────────────────────────────────────────────────────

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.manager,
    required this.importing,
    required this.onImport,
    required this.onDelete,
    required this.onLoad,
  });

  final ModelManager manager;
  final bool importing;
  final Future<void> Function() onImport;
  final Future<void> Function() onDelete;
  final Future<void> Function() onLoad;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ModelManagerState state = manager.state;

    return UdaoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.aiSettingsModelTitle, style: text.titleMedium),
          const SizedBox(height: UdaoSpacing.sm),
          if (state.candidate == null) ...<Widget>[
            Text(
              l10n.aiSettingsModelAbsent,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: UdaoSpacing.md),
            Text(
              l10n.aiSettingsTemplateOnlyBody,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: UdaoSpacing.md),
            UdaoButton(
              label: l10n.aiSettingsImportCta,
              loading: importing,
              onTap: importing ? null : () => onImport(),
            ),
          ] else ...<Widget>[
            _kv(text, l10n.aiSettingsFileLabel, state.candidate!.fileName),
            _kv(
              text,
              l10n.aiSettingsSizeLabel,
              '${(state.candidate!.sizeBytes / (1024 * 1024)).round()} MB',
            ),
            _kv(
              text,
              l10n.aiSettingsShaLabel,
              state.candidate!.sha256.substring(
                0,
                state.candidate!.sha256.length.clamp(0, 12),
              ),
            ),
            if (state.phase == ModelPhase.loaded)
              _kv(text, l10n.aiSettingsStatusLabel, l10n.aiSettingsStatusLoaded)
            else if (state.phase == ModelPhase.loading)
              _kv(text, l10n.aiSettingsStatusLabel, l10n.aiSettingsStatusLoading)
            else
              _kv(text, l10n.aiSettingsStatusLabel, l10n.aiSettingsStatusReady),
            const SizedBox(height: UdaoSpacing.md),
            Wrap(
              spacing: UdaoSpacing.sm,
              runSpacing: UdaoSpacing.sm,
              children: <Widget>[
                if (state.phase != ModelPhase.loaded)
                  UdaoButton(
                    label: l10n.aiSettingsLoadCta,
                    onTap: () => onLoad(),
                  ),
                UdaoButton(
                  label: l10n.aiSettingsImportCta,
                  variant: UdaoButtonVariant.glass,
                  loading: importing,
                  onTap: importing ? null : () => onImport(),
                ),
                UdaoButton(
                  label: l10n.aiSettingsDeleteCta,
                  variant: UdaoButtonVariant.glass,
                  onTap: () => onDelete(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static Widget _kv(TextTheme text, String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text('$k: $v', style: text.bodySmall),
      );
}

// ── tier card ─────────────────────────────────────────────────────

class _TierCard extends StatelessWidget {
  const _TierCard({required this.manager});

  final ModelManager manager;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return UdaoCard(
      child: FutureBuilder<ModelTier>(
        future: manager.suggestedTier(),
        builder: (BuildContext context, AsyncSnapshot<ModelTier> snap) {
          final ModelTier tier = snap.data ?? ModelTier.small;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l10n.aiSettingsTierTitle, style: text.titleMedium),
              const SizedBox(height: UdaoSpacing.sm),
              Text(l10n.aiSettingsTierBody(tier.label, tier.suggestedFile)),
            ],
          );
        },
      ),
    );
  }
}

// ── persona picker ────────────────────────────────────────────────

class _PersonaCard extends StatefulWidget {
  const _PersonaCard({required this.ref});

  final WidgetRef ref;

  @override
  State<_PersonaCard> createState() => _PersonaCardState();
}

class _PersonaCardState extends State<_PersonaCard> {
  String? _activePersonaId;

  @override
  void initState() {
    super.initState();
    // Base persona (pinned or not) — shown selected in the picker.
    unawaited(
      widget.ref.read(ai.personaRouterProvider).resolve().then(
            (ResolvedPersona resolved) => setState(
              () => _activePersonaId = resolved.persona.id,
            ),
          ),
    );
  }

  void _pick(BuildContext context, String id) {
    final PersonaRouter router = widget.ref.read(ai.personaRouterProvider);
    // Picking from settings is an explicit act — pin it (stress
    // auto-switch will not override a pinned choice).
    unawaited(router.setPersona(id, pinned: true));
    setState(() => _activePersonaId = id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).aiSettingsPersonaSaved),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return UdaoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.aiSettingsPersonaTitle, style: text.titleMedium),
          const SizedBox(height: UdaoSpacing.sm),
          Wrap(
            spacing: UdaoSpacing.sm,
            runSpacing: UdaoSpacing.sm,
            children: <Widget>[
              for (final Persona p in Personas.all)
                ChoiceChip(
                  label: Text(p.id.toUpperCase()),
                  selected: _activePersonaId == p.id,
                  onSelected: (_) => _pick(context, p.id),
                ),
            ],
          ),
          const SizedBox(height: UdaoSpacing.sm),
          Text(
            l10n.aiSettingsPersonaPinBody,
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ── preload toggle ────────────────────────────────────────────────

class _PreloadCard extends StatefulWidget {
  const _PreloadCard({required this.manager});

  final ModelManager manager;

  @override
  State<_PreloadCard> createState() => _PreloadCardState();
}

class _PreloadCardState extends State<_PreloadCard> {
  bool? _preload;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.manager.preloadEnabled().then((bool v) {
        if (mounted) {
          setState(() => _preload = v);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return UdaoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.aiSettingsPreloadTitle, style: text.titleMedium),
          const SizedBox(height: UdaoSpacing.sm),
          Text(l10n.aiSettingsPreloadBody, style: text.bodySmall),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _preload ?? false,
            onChanged: (bool v) {
              setState(() => _preload = v);
              unawaited(widget.manager.setPreload(v));
            },
            title: Text(l10n.aiSettingsPreloadToggle),
          ),
        ],
      ),
    );
  }
}

// ── test roast ────────────────────────────────────────────────────

class _TestRoastCard extends StatelessWidget {
  const _TestRoastCard({
    required this.testing,
    required this.result,
    required this.onTest,
  });

  final bool testing;
  final String? result;
  final Future<void> Function() onTest;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return UdaoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.aiSettingsTestRoastTitle, style: text.titleMedium),
          const SizedBox(height: UdaoSpacing.sm),
          Text(l10n.aiSettingsTestRoastBody, style: text.bodySmall),
          const SizedBox(height: UdaoSpacing.md),
          UdaoButton(
            label: l10n.aiSettingsTestRoastCta,
            loading: testing,
            onTap: testing ? null : () => onTest(),
          ),
          if (result != null) ...<Widget>[
            const SizedBox(height: UdaoSpacing.sm),
            Text(result!, style: text.bodySmall),
          ],
        ],
      ),
    );
  }
}

// ── learned patterns approval ─────────────────────────────────────

class _LearnedPatternsCard extends StatefulWidget {
  const _LearnedPatternsCard({required this.ref});

  final WidgetRef ref;

  @override
  State<_LearnedPatternsCard> createState() => _LearnedPatternsCardState();
}

class _LearnedPatternsCardState extends State<_LearnedPatternsCard> {
  List<LearnedPatternEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final store = widget.ref.read(ai.learnedPatternStoreProvider);
    final result = await store.all();
    if (mounted) {
      setState(() => _entries = result.valueOrNull ?? <LearnedPatternEntry>[]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final List<LearnedPatternEntry> entries =
        _entries ?? <LearnedPatternEntry>[];
    return UdaoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.aiSettingsLearnedTitle, style: text.titleMedium),
          const SizedBox(height: UdaoSpacing.sm),
          if (entries.isEmpty)
            Text(l10n.aiSettingsLearnedEmpty, style: text.bodySmall)
          else
            for (final LearnedPatternEntry e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: UdaoSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.aiSettingsLearnedRow(e.pattern),
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.aiSettingsLearnedSample(e.sample),
                      style: text.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Text(
                          LearnedPattern.testPattern(e.pattern, e.sample)
                              ? l10n.aiSettingsLearnedTestOk
                              : l10n.aiSettingsLearnedTestFail,
                          style: text.bodySmall,
                        ),
                        const Spacer(),
                        if (!e.approved) ...<Widget>[
                          TextButton(
                            onPressed: () => _act(e, true),
                            child: Text(l10n.aiSettingsLearnedApprove),
                          ),
                          TextButton(
                            onPressed: () => _act(e, false),
                            child: Text(l10n.aiSettingsLearnedDismiss),
                          ),
                        ] else
                          Icon(
                            PhosphorIconsBold.checkCircle,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _act(LearnedPatternEntry e, bool approve) async {
    final store = widget.ref.read(ai.learnedPatternStoreProvider);
    if (approve) {
      await store.approve(e.id);
    } else {
      await store.dismiss(e.id);
    }
    await _reload();
  }
}

// ── telemetry ─────────────────────────────────────────────────────

class _TelemetryCard extends StatefulWidget {
  const _TelemetryCard({required this.ref});

  final WidgetRef ref;

  @override
  State<_TelemetryCard> createState() => _TelemetryCardState();
}

class _TelemetryCardState extends State<_TelemetryCard> {
  AiTelemetrySnapshot _snap = AiTelemetrySnapshot.empty;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.ref.read(ai.aiTelemetryProvider).snapshot().then(
            (AiTelemetrySnapshot s) => mounted ? setState(() => _snap = s) : null,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return UdaoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.aiSettingsTelemetryTitle, style: text.titleMedium),
          const SizedBox(height: UdaoSpacing.sm),
          Text(
            l10n.aiSettingsTelemetryBody(
              _snap.estimatedTokens,
              _snap.avgLatencyMs,
              _snap.toolCallsOk,
              _snap.toolCallsFailed,
              _snap.guardrailBlocks,
            ),
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}
