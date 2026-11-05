import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../models/manga.dart';

final _api = ApiService();

class _Message {
  final String text;
  final bool isUser;
  final Map<String, dynamic>? action;
  _Message({required this.text, required this.isUser, this.action});
}

class _Suggestion {
  final String label;
  final IconData icon;
  const _Suggestion(this.label, this.icon);
}

const _suggestions = [
  _Suggestion('What should I read next?', Icons.auto_awesome_outlined),
  _Suggestion('Show my stats',            Icons.bar_chart_outlined),
  _Suggestion('Top rated manga',          Icons.star_outline),
  _Suggestion('What am I reading?',       Icons.menu_book_outlined),
];

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  final _msgs   = <_Message>[];
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _ctrl.text).trim();
    if (text.isEmpty || _loading) return;
    _ctrl.clear();

    setState(() => _msgs.add(_Message(text: text, isUser: true)));
    _scrollDown();
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _loading = true);
    _scrollDown();

    try {
      final res    = await _api.chat(text);
      final intent = res['intent'] as String?;
      String reply = (res['reply'] as String? ?? '').trim();

      // For data intents, build a readable reply from the returned data
      if (intent == 'stats') {
        final d = res['data'] as Map<String, dynamic>? ?? {};
        final total = d['total'] ?? 0;
        if (total == 0) {
          reply = 'No manga in your list yet!';
        } else {
          final reading   = d['reading']   ?? 0;
          final completed = d['completed'] ?? 0;
          final dropped   = d['dropped']   ?? 0;
          final totalCh   = d['total_chapters'] ?? 0;
          final avgCh     = d['avg_chapters']   ?? 0;
          final mostRead  = (d['most_read']  as Map?)?['title'] ?? '—';
          final topRated  = (d['top_rated']  as Map?)?['title'];
          reply = '📚 You have $total manga total\n'
              '• Reading: $reading  ✅ Completed: $completed  💀 Dropped: $dropped\n'
              '• Total chapters read: $totalCh (avg $avgCh / manga)\n'
              '• Most read: $mostRead'
              '${topRated != null ? '\n• Top rated: $topRated' : ''}';
        }
      } else if (intent == 'list') {
        final data = (res['data'] as List?) ?? [];
        if (data.isEmpty) {
          reply = 'Nothing in that list yet!';
        } else {
          final lines = data.map((m) {
            final ch = m['chapter'] ?? 0;
            return '• ${m['title']} — ch.$ch';
          }).join('\n');
          reply = '${data.length} manga:\n$lines';
        }
      } else if (intent == 'search') {
        final data = (res['data'] as List?) ?? [];
        if (data.isEmpty) {
          reply = 'Nothing found for that search.';
        } else {
          final lines = data.map((m) => '• ${m['title']}').join('\n');
          reply = 'Found ${data.length}:\n$lines';
        }
      }

      if (reply.isEmpty) reply = '...';

      const writeIntents = {'add', 'update', 'update_chapter', 'update_status', 'delete'};
      setState(() {
        _msgs.add(_Message(
          text: reply,
          isUser: false,
          action: (intent != null && writeIntents.contains(intent)) ? res : null,
        ));
      });
    } catch (_) {
      setState(() {
        _msgs.add(_Message(
            text: 'Something went wrong. Check your connection.', isUser: false));
      });
    } finally {
      setState(() => _loading = false);
      _scrollDown();
    }
  }

  Future<void> _confirmAction(Map<String, dynamic> action, int idx) async {
    final intent = action['intent'] as String?;
    final data   = (action['parsed'] as Map<String, dynamic>?) ?? action;
    try {
      if (intent == 'add') {
        await _api.addManga(data['title'] ?? '', url: data['url'], chapter: data['chapter'] ?? 0);
        _showResult('Added!', idx);
      } else if (intent == 'update' || intent == 'update_chapter' || intent == 'update_status') {
        final mangas = await _api.getManga();
        final title  = (data['title'] as String? ?? '').toLowerCase();
        final match  = mangas.firstWhere(
          (m) => m.title.toLowerCase().contains(title),
          orElse: () => Manga(id: -1, title: '', chapter: 0, status: 'reading', updatedAt: ''),
        );
        if (match.id == -1) { _showResult('Manga not found.', idx); return; }
        await _api.updateManga(match.id, chapter: data['chapter'], status: data['status']);
        _showResult('Updated!', idx);
      } else if (intent == 'delete') {
        final mangas = await _api.getManga();
        final title  = (data['title'] as String? ?? '').toLowerCase();
        final match  = mangas.firstWhere(
          (m) => m.title.toLowerCase().contains(title),
          orElse: () => Manga(id: -1, title: '', chapter: 0, status: 'reading', updatedAt: ''),
        );
        if (match.id == -1) { _showResult('Manga not found.', idx); return; }
        await _api.deleteManga(match.id);
        _showResult('Deleted!', idx);
      }
    } catch (e) {
      _showResult('Error: $e', idx);
    }
  }

  void _showResult(String msg, int idx) {
    setState(() {
      final old = _msgs[idx];
      _msgs[idx] = _Message(text: '${old.text}\n\n✅ $msg', isUser: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('Chat', style: TextStyle(color: Color(0xFF111111), fontWeight: FontWeight.w600, fontSize: 20)),
        actions: [
          if (_msgs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Color(0xFF888888)),
              tooltip: 'Clear',
              onPressed: () => setState(() => _msgs.clear()),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              itemCount: 1 + _msgs.length,
              itemBuilder: (ctx, i) {
                if (i == 0) return _EmptyState(onSuggestion: _send);
                final mi = i - 1;
                return _Bubble(
                  msg: _msgs[mi],
                  onConfirm: _msgs[mi].action != null ? () => _confirmAction(_msgs[mi].action!, mi) : null,
                  onDismiss: _msgs[mi].action != null
                      ? () => setState(() {
                            final old = _msgs[mi];
                            _msgs[mi] = _Message(text: '${old.text}\n\nCancelled.', isUser: false);
                          })
                      : null,
                );
              },
            ),
          ),
          if (_loading) const _TypingBubble(),
          _InputBar(ctrl: _ctrl, onSend: () => _send()),
        ],
      ),
    );
  }
}

// ── Empty / welcome state ─────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final void Function(String) onSuggestion;
  const _EmptyState({required this.onSuggestion});

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 16),
          _LuffyOrb(size: sw * 0.72),
          const SizedBox(height: 12),
          const Text(
            'Konnichiwa Harith!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF7B7FE8),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'How can I help U today?',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: Color(0xFF555555),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: _suggestions.map((s) => _SuggestionChip(
                label: s.label,
                icon: s.icon,
                onTap: () => onSuggestion(s.label),
              )).toList(),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _LuffyOrb extends StatelessWidget {
  final double size;
  const _LuffyOrb({this.size = 240});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/luffy_fat.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _SuggestionChip({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD0D0D8)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: const Color(0xFF7B7FE8)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF333333), fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ── Chat bubble ───────────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  final _Message msg;
  final VoidCallback? onConfirm;
  final VoidCallback? onDismiss;
  const _Bubble({required this.msg, this.onConfirm, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF111111) : const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.only(
            topLeft:     const Radius.circular(18),
            topRight:    const Radius.circular(18),
            bottomLeft:  Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4  : 18),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.text,
              style: TextStyle(
                color: isUser ? Colors.white : const Color(0xFF111111),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (msg.action != null && onConfirm != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF111111),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 0,
                    ),
                    onPressed: onConfirm,
                    child: const Text('Confirm', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF888888)),
                    onPressed: onDismiss,
                    child: const Text('Cancel', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Typing indicator ─────────────────────────────────────────────────────────

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 0, 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) => _Dot(controller: _ctrl, index: i)),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final AnimationController controller;
  final int index;
  const _Dot({required this.controller, required this.index});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        // Each dot is offset by 1/3 of the cycle
        final offset = (controller.value - index / 3.0) % 1.0;
        // Jump: goes up during first half, comes back down second half
        final dy = -math.sin(offset * math.pi).clamp(0.0, 1.0) * 6.0;
        return Transform.translate(
          offset: Offset(0, dy),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF999999),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

// ── Input bar ─────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController ctrl;
  final VoidCallback onSend;
  const _InputBar({required this.ctrl, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    final bottomPad = keyboardH > 0 ? 10.0 : 84.0;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, bottomPad),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(fontSize: 15, color: Color(0xFF111111)),
              decoration: InputDecoration(
                hintText: 'Ask me anything...',
                hintStyle: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 15),
                filled: true,
                fillColor: const Color(0xFFF5F5F7),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFF111111),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
