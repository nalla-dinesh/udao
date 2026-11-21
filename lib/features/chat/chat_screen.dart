// phase-06
// The real Chat tab: streaming bubbles (bub-ai / bub-user surfaces),
// inline tool-call chips, persona indicator, honest template-only
// banner, suggested Hinglish prompts, stop button, voice + receipt
// attachment. History persists (clear-all in the app bar, DPDP).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/result/result.dart';
import '../../core/theme/udao_spacing.dart';
import '../../core/ui/udao_card.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../data/db/dao/txn_dao.dart';
import '../../data/repos/providers.dart' show budgetRepoProvider;
import '../../l10n/app_localizations.dart';
import '../ai/ai_providers.dart' as ai;
import '../ai/persona/stress_detector.dart';
import '../capture/capture_providers.dart' show dbProvider, kvDaoProvider;
import '../capture/ports/capture_ports_providers.dart' show voiceInputProvider;
import '../capture/receipt/receipt_capture_sheet.dart';
import 'chat_controller.dart';
import 'chat_history_store.dart';
import 'chat_models.dart';

final Provider<ChatHistoryStore> chatHistoryStoreProvider =
    Provider<ChatHistoryStore>(
  (Ref ref) => ChatHistoryStore(kv: ref.watch(kvDaoProvider)),
);

final Provider<StressInputGatherer> stressGathererProvider =
    Provider<StressInputGatherer>(
  (Ref ref) => StressInputGatherer(
    txns: TxnDao(ref.watch(dbProvider).db),
    budgets: ref.watch(budgetRepoProvider),
    kv: ref.watch(kvDaoProvider),
  ),
);

/// The chat state provider — UI-facing seam (widget tests override
/// this one and never touch the DB or channels).
final StateNotifierProvider<ChatController, ChatState> chatControllerProvider =
    StateNotifierProvider<ChatController, ChatState>(
  (Ref ref) => ChatController(
    agentLoop: ref.watch(ai.agentLoopProvider),
    roastEngine: ref.watch(ai.roastEngineProvider),
    personaRouter: ref.watch(ai.personaRouterProvider),
    guardrail: ref.watch(ai.guardrailProvider),
    history: ref.watch(chatHistoryStoreProvider),
    templateOnly: !ref.watch(ai.modelManagerProvider).isLoaded,
    stressGatherer: ref.watch(stressGathererProvider),
    stressDetector: const StressDetector(),
  ),
);

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  bool _listening = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final String text = _input.text;
    if (text.trim().isEmpty) {
      return;
    }
    _input.clear();
    unawaited(ref.read(chatControllerProvider.notifier).send(text));
  }

  Future<void> _listen() async {
    setState(() => _listening = true);
    final Result<String> heard =
        await ref.read(voiceInputProvider).listenOnce(localeId: 'en-IN');
    if (!mounted) {
      return;
    }
    setState(() => _listening = false);
    final String? text = heard.valueOrNull;
    if (text != null && text.trim().isNotEmpty) {
      _input.text = text;
    }
  }

  Future<void> _confirmClearAll() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.chatClearAll),
        content: Text(l10n.chatClearAllBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.chatClearCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.chatClearConfirm),
          ),
        ],
      ),
    );
    if (yes == true) {
      unawaited(ref.read(chatControllerProvider.notifier).clearHistory());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ChatState state = ref.watch(chatControllerProvider);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.chatTitle),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.chatClearAll,
            onPressed: () => unawaited(_confirmClearAll()),
            icon: const Icon(PhosphorIconsBold.trash),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _HeaderStrip(state: state),
            Expanded(
              child: state.messages.isEmpty && !state.streaming
                  ? _EmptyChat(l10n: l10n, onPick: _onSuggested)
                  : const _MessageList(),
            ),
            _InputBar(
              controller: _input,
              listening: _listening,
              streaming: state.streaming,
              onSend: _send,
              onStop: () => unawaited(
                ref.read(chatControllerProvider.notifier).stop(),
              ),
              onListen: _listen,
              onAttach: () => unawaited(showReceiptCaptureSheet(context)),
            ),
          ],
        ),
      ),
    );
  }

  void _onSuggested(String prompt) {
    unawaited(ref.read(chatControllerProvider.notifier).send(prompt));
  }
}

// ── header: persona + banners ─────────────────────────────────────

class _HeaderStrip extends ConsumerWidget {
  const _HeaderStrip({required this.state});

  final ChatState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        if (state.stressNotice)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              UdaoSpacing.md, UdaoSpacing.sm, UdaoSpacing.md, 0,
            ),
            child: UdaoCard(
              accent: UdaoCardAccent.lime,
              child: Row(
                children: <Widget>[
                  Icon(PhosphorIconsBold.flowerLotus, color: scheme.primary),
                  const SizedBox(width: UdaoSpacing.md),
                  Expanded(child: Text(l10n.personaStressNotice)),
                  TextButton(
                    onPressed: () => unawaited(
                      ref.read(chatControllerProvider.notifier).exitStressMode(),
                    ),
                    child: Text(l10n.personaStressExit),
                  ),
                ],
              ),
            ),
          ),
        if (state.templateOnly)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              UdaoSpacing.md, UdaoSpacing.sm, UdaoSpacing.md, 0,
            ),
            child: UdaoCard(
              child: Row(
                children: <Widget>[
                  Icon(PhosphorIconsBold.info, color: scheme.tertiary),
                  const SizedBox(width: UdaoSpacing.md),
                  Expanded(child: Text(l10n.chatTemplateOnlyBanner)),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: UdaoSpacing.md),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.chatPersonaTag(state.persona.id),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── message list + bubbles ────────────────────────────────────────

class _MessageList extends ConsumerWidget {
  const _MessageList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ChatState state = ref.watch(chatControllerProvider);
    return ListView.builder(
      padding: const EdgeInsets.all(UdaoSpacing.md),
      itemCount: state.messages.length + (state.streaming ? 1 : 0),
      itemBuilder: (BuildContext context, int index) {
        if (index == state.messages.length) {
          return _StreamingBubble(state: state);
        }
        return _MessageBubble(message: state.messages[index]);
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isUser = message.role == ChatRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: UdaoSpacing.md),
        padding: const EdgeInsets.all(UdaoSpacing.md),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: isUser ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (message.toolCalls.isNotEmpty) ...<Widget>[
              for (final ToolCallTrace tool in message.toolCalls)
                _ToolChip(tool: tool, onSurface: isUser ? Colors.white : scheme.onSurface),
              const SizedBox(height: UdaoSpacing.sm),
            ],
            Text(
              message.text,
              style: text.bodyMedium?.copyWith(
                color: isUser ? Colors.white : scheme.onSurface,
              ),
            ),
            if (message.guarded)
              Padding(
                padding: const EdgeInsets.only(top: UdaoSpacing.xs),
                child: Text(
                  l10n.chatGuardedChip,
                  style: text.labelSmall?.copyWith(
                    color: isUser ? Colors.white70 : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (message.capped)
              Padding(
                padding: const EdgeInsets.only(top: UdaoSpacing.xs),
                child: Text(
                  l10n.chatCappedChip,
                  style: text.labelSmall?.copyWith(
                    color: isUser ? Colors.white70 : scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.tool, required this.onSurface});

  final ToolCallTrace tool;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: UdaoSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: UdaoSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: onSurface.withValues(alpha: 0.4)),
      ),
      child: Text(
        l10n.chatToolChip(
          tool.name,
          tool.argsPreview.isEmpty ? tool.argsPreview : ' (${tool.argsPreview})',
          tool.elapsedMs,
        ) +
            (tool.ok ? ' ✓' : ' ✗'),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: onSurface,
              fontFamily: 'SpaceGrotesk',
            ),
      ),
    );
  }
}

class _StreamingBubble extends StatelessWidget {
  const _StreamingBubble({required this.state});

  final ChatState state;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<ToolCallTrace> chips = state.pendingToolChips;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: UdaoSpacing.md),
        padding: const EdgeInsets.all(UdaoSpacing.md),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final ToolCallTrace tool in chips)
              _ToolChip(tool: tool, onSurface: scheme.onSurface),
            Text(
              state.streamingText.isEmpty ? '…' : state.streamingText,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

// ── empty state with suggested prompts ────────────────────────────

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.l10n, required this.onPick});

  final AppLocalizations l10n;
  final void Function(String prompt) onPick;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(UdaoSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(l10n.chatEmptyTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: UdaoSpacing.sm),
            Text(
              l10n.chatEmptyBody,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: UdaoSpacing.lg),
            Wrap(
              spacing: UdaoSpacing.sm,
              runSpacing: UdaoSpacing.sm,
              alignment: WrapAlignment.center,
              children: <Widget>[
                for (final String prompt in <String>[
                  l10n.chatSuggested1,
                  l10n.chatSuggested2,
                  l10n.chatSuggested3,
                ])
                  ActionChip(
                    label: Text(prompt),
                    onPressed: () => onPick(prompt),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── input bar ─────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.listening,
    required this.streaming,
    required this.onSend,
    required this.onStop,
    required this.onListen,
    required this.onAttach,
  });

  final TextEditingController controller;
  final bool listening;
  final bool streaming;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final Future<void> Function() onListen;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(UdaoSpacing.md),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: l10n.chatAttachTooltip,
            onPressed: onAttach,
            icon: const Icon(PhosphorIconsBold.receipt),
          ),
          IconButton(
            tooltip: l10n.chatVoiceTooltip,
            onPressed: listening ? null : () => onListen(),
            icon: Icon(
              listening ? PhosphorIconsBold.microphone : PhosphorIconsBold.microphoneSlash,
              color: listening ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !streaming,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: l10n.chatPlaceholder,
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: UdaoSpacing.md,
                  vertical: UdaoSpacing.sm,
                ),
              ),
            ),
          ),
          const SizedBox(width: UdaoSpacing.sm),
          streaming
              ? IconButton(
                  tooltip: l10n.chatStopTooltip,
                  onPressed: onStop,
                  icon: Icon(PhosphorIconsBold.stopCircle, color: scheme.error),
                )
              : IconButton(
                  tooltip: l10n.chatSendTooltip,
                  onPressed: onSend,
                  icon: Icon(PhosphorIconsBold.paperPlaneRight, color: scheme.primary),
                ),
        ],
      ),
    );
  }
}
