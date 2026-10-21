import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/secrets.dart';
import '../core/theme.dart';
import '../services/ai_adapter.dart';
import '../services/coach_service.dart';
import '../services/store.dart';

const _uuid = Uuid();

enum _MsgSource { user, ai, local, pending, error }

class _ChatMsg {
  final String id;
  final String text;
  final _MsgSource source;
  final AiError? error;

  _ChatMsg({
    String? id,
    required this.text,
    required this.source,
    this.error,
  }) : id = id ?? _uuid.v4();
}

/// Coach de vida saludable: chat donde el usuario pregunta y la IA responde
/// usando su perfil y datos reales. Si no hay IA, usa respuestas locales.
class CoachTab extends StatefulWidget {
  const CoachTab({super.key});

  @override
  State<CoachTab> createState() => _CoachTabState();
}

class _CoachTabState extends State<CoachTab> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  late final CoachService _coach;
  final List<_ChatMsg> _msgs = [];
  bool _typing = false;
  bool _disclaimerShown = false;
  String? _pendingQuestion;

  static const _suggestions = [
    '¿Qué como hoy?',
    '¿Qué suplemento me sirve?',
    '¿Cuánta proteína necesito?',
    '¿Qué rutina hago hoy?',
    'No tengo ganas de entrenar',
  ];

  @override
  void initState() {
    super.initState();
    final adapter = kUseGeminiAI
        ? GeminiAdapter()
        : MockAiAdapter(injectError: AiError.noConfig);
    _coach = CoachService(adapter);
    _msgs.add(_ChatMsg(
      text: '¡Hola! 💪 Soy tu coach. Pregúntame lo que quieras sobre '
          'entrenamiento, comida, suplementos o hábitos.',
      source: _MsgSource.local,
    ));
  }

  @override
  void dispose() {
    _coach.dispose();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final q = text.trim();
    if (q.isEmpty || _typing) return;

    _ctrl.clear();
    setState(() {
      _msgs.add(_ChatMsg(text: q, source: _MsgSource.user));
      _msgs.add(_ChatMsg(text: 'pensando…', source: _MsgSource.pending));
      _typing = true;
      _pendingQuestion = q;
    });
    _scrollDown();

    final resp = await _coach.send(q);
    if (!mounted) return;

    setState(() {
      _typing = false;
      _pendingQuestion = null;
      // Reemplaza la burbuja "pensando"
      _msgs.removeLast();

      if (resp.text.isEmpty) return;

      final src = resp.error != null && !resp.fromAi
          ? _MsgSource.local
          : (resp.fromAi ? _MsgSource.ai : _MsgSource.local);

      _msgs.add(_ChatMsg(
        text: resp.text,
        source: src,
        error: resp.error,
      ));
    });
    _scrollDown();
  }

  Future<void> _retry() async {
    final q = _pendingQuestion;
    if (q == null || _typing) return;
    // Remove error bubble and retry
    setState(() {
      if (_msgs.isNotEmpty && _msgs.last.source == _MsgSource.error) {
        _msgs.removeLast();
      }
    });
    await _send(q);
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStore.instance,
      builder: (context, _) => _body(context),
    );
  }

  Widget _body(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _header(),
          if (!_disclaimerShown) _disclaimerBanner(),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: _msgs.length,
              itemBuilder: (_, i) => _bubble(_msgs[i]),
            ),
          ),
          _chips(),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.brand, AppColors.brandDark]),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Coach IA',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
              Text('Tu asistente de vida saludable',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _disclaimerBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.brandDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Este coach ofrece orientación general sobre entrenamiento y alimentación. '
              'No reemplaza a un profesional de la salud.',
              style: TextStyle(fontSize: 12, color: AppColors.brandDark, height: 1.3),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _disclaimerShown = true),
            child: const Icon(Icons.close_rounded, size: 18, color: AppColors.brandDark),
          ),
        ],
      ),
    );
  }

  Widget _chips() {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: _suggestions
            .map((s) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(s, style: TextStyle(fontSize: 12, color: AppColors.ink)),
                    backgroundColor: AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: AppColors.line),
                    ),
                    onPressed: _typing ? null : () => _send(s),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _bubble(_ChatMsg m) {
    if (m.source == _MsgSource.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: AppColors.brand,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(m.text, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35)),
        ),
      );
    }

    if (m.source == _MsgSource.pending) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand),
              ),
              const SizedBox(width: 10),
              Text('pensando…', style: TextStyle(fontSize: 13, color: AppColors.muted)),
            ],
          ),
        ),
      );
    }

    // AI / local / error bubble
    final isError = m.source == _MsgSource.error;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: isError ? AppColors.warn : AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.error != null && m.source == _MsgSource.local && m.text.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.wifi_off_rounded, size: 13, color: AppColors.muted),
                  const SizedBox(width: 4),
                  Text('Respuesta local', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                ],
              ),
              const SizedBox(height: 4),
            ],
            Text(m.text, style: TextStyle(color: AppColors.ink, fontSize: 14, height: 1.35)),
            if (m.error != null && _canRetry(m.error!)) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _retry,
                child: Text('Reintentar',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.brand,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _canRetry(AiError e) => e == AiError.timeout || e == AiError.invalidResponse;

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      color: AppColors.bg,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              decoration: InputDecoration(
                hintText: 'Pregúntale a tu coach…',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: BorderSide(color: AppColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: BorderSide(color: AppColors.line),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 24,
            backgroundColor: _typing ? AppColors.faint : AppColors.brand,
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white),
              onPressed: _typing ? null : () => _send(_ctrl.text),
            ),
          ),
        ],
      ),
    );
  }
}
