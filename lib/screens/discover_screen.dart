import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

final _api = ApiService();

final recommendProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return _api.getRecommendations();
});


const _palette = [
  Color(0xFF4ECDC4), Color(0xFF7B68EE), Color(0xFFFF6B6B),
  Color(0xFF95E1D3), Color(0xFFF38181), Color(0xFFAA96DA),
  Color(0xFFFCBF49), Color(0xFF2D6A4F), Color(0xFFE84393), Color(0xFF3A86FF),
];

class DiscoverScreen extends ConsumerStatefulWidget {
  final ValueNotifier<int>? tapNotifier;
  const DiscoverScreen({super.key, this.tapNotifier});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _searchCtrl = TextEditingController();
  final _focus = FocusNode();
  List<Map<String, dynamic>> _suggestions = [];
  bool _searching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() { _suggestions = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      try {
        final results = await _api.searchDiscover(q.trim());
        if (mounted) setState(() { _suggestions = results; _searching = false; });
      } catch (_) {
        if (mounted) setState(() { _suggestions = []; _searching = false; });
      }
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _focus.unfocus();
    setState(() { _suggestions = []; _searching = false; });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(recommendProvider);
    final topPad = MediaQuery.of(context).padding.top;
    final showDropdown = _searching || _suggestions.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Content
          GestureDetector(
            onTap: _clearSearch,
            child: Padding(
              padding: EdgeInsets.only(top: topPad + 52),
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text('Could not load', style: TextStyle(color: Colors.grey[600])),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(recommendProvider),
                      child: const Text('Retry'),
                    ),
                  ]),
                ),
                data: (recs) => recs.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('Could not load recommendations'),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => ref.invalidate(recommendProvider),
                          child: const Text('Retry'),
                        ),
                      ]))
                    : RefreshIndicator(
                        onRefresh: () async => ref.invalidate(recommendProvider),
                        child: _DiscoverGrid(recs: recs),
                      ),
              ),
            ),
          ),
          // Search island
          Positioned(
            top: topPad + 8,
            left: 32,
            right: 32,
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _focus,
                      onChanged: _onSearch,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Discover',
                        hintStyle: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A),
                            fontSize: 14),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_searchCtrl.text.isNotEmpty)
                    GestureDetector(
                      onTap: _clearSearch,
                      child: const Icon(Icons.close, size: 16, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ),
          // Dropdown results
          if (showDropdown)
            Positioned(
              top: topPad + 8 + 36 + 6,
              left: 32,
              right: 32,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _searching
                      ? const SizedBox(
                          height: 56,
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _suggestions.length,
                          itemBuilder: (_, i) {
                            final m = _suggestions[i];
                            final cover = m['cover_url'] as String?;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: cover != null
                                    ? Image.network(cover, width: 36, height: 50, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(width: 36, height: 50, color: Colors.grey[200]))
                                    : Container(width: 36, height: 50, color: Colors.grey[200]),
                              ),
                              title: Text(m['title'] ?? '',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: m['status'] != null
                                  ? Text('${m['status']}', style: TextStyle(fontSize: 11, color: Colors.grey[500]))
                                  : null,
                              onTap: () {
                                _clearSearch();
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.white,
                                  shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                                  builder: (_) => _DetailSheet(rec: m),
                                );
                              },
                            );
                          },
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Grid: 5 rows × 10 cards ───────────────────────────────────────────────────

class _DiscoverGrid extends StatefulWidget {
  final List<Map<String, dynamic>> recs;
  const _DiscoverGrid({required this.recs});

  @override
  State<_DiscoverGrid> createState() => _DiscoverGridState();
}

class _DiscoverGridState extends State<_DiscoverGrid> {
  static const _rowCount = 5;
  static const _perRow = 10;
  static const _speed = 25.0; // px/sec

  final List<ScrollController> _ctrls =
      List.generate(_rowCount, (_) => ScrollController());
  final List<bool> _paused = List.filled(_rowCount, false);
  final List<bool> _dragging = List.filled(_rowCount, false);
  // Prevents our own jumpTo calls from re-triggering the notification handler
  final List<bool> _cancelling = List.filled(_rowCount, false);

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < _rowCount; i++) {
      final goRight = i.isEven;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_ctrls[i].hasClients) return;
        if (!goRight) _ctrls[i].jumpTo(_ctrls[i].position.maxScrollExtent);
        _scroll(i, goRight);
      });
    }
  }

  void _scroll(int row, bool goRight) {
    if (!mounted || _paused[row] || !_ctrls[row].hasClients) return;
    final ctrl = _ctrls[row];
    final max = ctrl.position.maxScrollExtent;
    if (max <= 0) return;
    final target = goRight ? max : 0.0;
    final dist = (target - ctrl.position.pixels).abs();
    if (dist < 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _paused[row] || !_ctrls[row].hasClients) return;
        _cancelling[row] = true;
        _ctrls[row].jumpTo(goRight ? 0 : max);
        _cancelling[row] = false;
        _scroll(row, goRight);
      });
      return;
    }
    final ms = (dist / _speed * 1000).round();
    ctrl
        .animateTo(target, duration: Duration(milliseconds: ms), curve: Curves.linear)
        .then((_) { if (mounted && !_paused[row]) _scroll(row, goRight); });
  }

  // Called on first pointer-down (before gesture arena) to kill the animation
  // so the tap gesture can resolve cleanly.
  void _cancelAnimation(int row) {
    if (!_ctrls[row].hasClients) return;
    _cancelling[row] = true;
    _ctrls[row].jumpTo(_ctrls[row].position.pixels);
    _cancelling[row] = false;
    _paused[row] = true;
  }

  void _resume(int row) {
    if (!mounted || !_paused[row]) return;
    _paused[row] = false;
    Future.microtask(() => _scroll(row, row.isEven));
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  void _showDetail(Map<String, dynamic> rec) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _DetailSheet(rec: rec),
    );
  }

  @override
  Widget build(BuildContext context) {
    const cardW = 147.0;
    const cardH = cardW * 1.5;

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 100),
      itemCount: _rowCount,
      itemBuilder: (_, rowIdx) {
        final start = rowIdx * _perRow;
        final end = (start + _perRow).clamp(0, widget.recs.length);
        if (start >= widget.recs.length) return const SizedBox.shrink();
        final row = widget.recs.sublist(start, end);

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: SizedBox(
            height: cardH + 4,
            child: Listener(
              onPointerDown: (_) => _cancelAnimation(rowIdx),
              onPointerUp: (_) {
                if (!_dragging[rowIdx]) {
                  Future.delayed(const Duration(milliseconds: 400), () => _resume(rowIdx));
                }
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (_cancelling[rowIdx]) return false;
                  if (n is ScrollStartNotification && n.dragDetails != null) {
                    _dragging[rowIdx] = true;
                  } else if (n is ScrollEndNotification && _dragging[rowIdx]) {
                    _dragging[rowIdx] = false;
                    Future.delayed(const Duration(milliseconds: 800), () => _resume(rowIdx));
                  }
                  return false;
                },
                child: ListView.builder(
                  controller: _ctrls[rowIdx],
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: row.length,
                  itemBuilder: (_, i) {
                    final rec = row[i];
                    final cover = rec['cover_url'] as String?;
                    final color = _palette[(rowIdx * _perRow + i) % _palette.length];
                    return GestureDetector(
                      onTap: () => _showDetail(rec),
                      child: Container(
                        width: cardW,
                        height: cardH,
                        margin: const EdgeInsets.only(right: 4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: cover != null
                              ? Image.network(cover, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(color: color))
                              : Container(color: color),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool isOngoing, isCompleted;
  const _StatusBadge({required this.status, required this.isOngoing, required this.isCompleted});

  @override
  Widget build(BuildContext context) {
    final isHiatus = status.toLowerCase() == 'hiatus';
    final color = isOngoing ? Colors.green : isCompleted ? Colors.blue : isHiatus ? Colors.orange : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color[700])),
    );
  }
}

class _GenreChip extends StatelessWidget {
  final String label;
  const _GenreChip({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
  );
}

// ── Detail sheet ──────────────────────────────────────────────────────────────

class _DetailSheet extends StatefulWidget {
  final Map<String, dynamic> rec;
  const _DetailSheet({required this.rec});

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  bool _adding = false, _added = false, _checkingLibrary = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkIfAlreadyAdded();
  }

  Future<void> _checkIfAlreadyAdded() async {
    try {
      final library = await _api.getManga();
      final titleLower = '${widget.rec['title'] ?? ''}'.toLowerCase().trim();
      final alreadyIn = library.any((m) => m.title.toLowerCase().trim() == titleLower);
      if (mounted) setState(() { _added = alreadyIn; _checkingLibrary = false; });
    } catch (_) {
      if (mounted) setState(() { _checkingLibrary = false; });
    }
  }

  Future<void> _addToLibrary() async {
    setState(() { _adding = true; _error = null; });
    try {
      await _api.addManga('${widget.rec['title'] ?? ''}');
      setState(() { _added = true; _adding = false; });
    } catch (_) {
      setState(() { _error = 'Failed to add. Try again.'; _adding = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title    = '${widget.rec['title'] ?? ''}';
    final genre    = '${widget.rec['genre'] ?? ''}';
    final reason   = '${widget.rec['reason'] ?? ''}';
    final status   = '${widget.rec['manga_status'] ?? ''}';
    final chapters = widget.rec['total_chapters'];
    final cover    = widget.rec['cover_url'] as String?;
    final isOngoing   = status.toLowerCase() == 'ongoing';
    final isCompleted = status.toLowerCase() == 'completed';

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          if (cover != null)
            Center(child: ClipRRect(borderRadius: BorderRadius.circular(16),
                child: Image.network(cover, height: 180, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()))),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
          const SizedBox(height: 8),
          Row(children: [
            if (status.isNotEmpty) _StatusBadge(status: status, isOngoing: isOngoing, isCompleted: isCompleted),
            if (status.isNotEmpty && chapters != null) const SizedBox(width: 8),
            if (chapters != null) Text('$chapters chapters', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 4,
              children: genre.split(',').map((g) => g.trim()).where((g) => g.isNotEmpty)
                  .map((g) => _GenreChip(label: g)).toList()),
          const SizedBox(height: 14),
          Text(reason, style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.5)),
          const SizedBox(height: 24),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              onPressed: (_added || _adding || _checkingLibrary) ? null : _addToLibrary,
              style: ElevatedButton.styleFrom(
                backgroundColor: _added ? Colors.grey[300] : const Color(0xFF1A1A1A),
                foregroundColor: _added ? Colors.grey[600] : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _adding || _checkingLibrary
                  ? SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: _checkingLibrary ? Colors.grey : Colors.white, strokeWidth: 2))
                  : Text(_added ? 'Already in Shelf ✓' : 'Add to Library',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
