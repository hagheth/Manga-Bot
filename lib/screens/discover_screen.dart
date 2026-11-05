import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

final _api = ApiService();

final recommendProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return _api.getRecommendations();
});

class DiscoverScreen extends ConsumerWidget {
  final ValueNotifier<int>? tapNotifier;
  const DiscoverScreen({super.key, this.tapNotifier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recommendProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'Discover',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Get new suggestions',
            onPressed: () => ref.invalidate(recommendProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text('Could not load recommendations', style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(recommendProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (recs) {
          if (recs.isEmpty) {
            return const Center(child: Text('No recommendations yet. Add more manga to your library!'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: recs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _RecommendCard(
              rec: recs[i],
              onTap: () => _showDetail(context, ref, recs[i]),
            ),
          );
        },
      ),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref, Map<String, dynamic> rec) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DetailSheet(rec: rec, ref: ref),
    );
  }
}

class _RecommendCard extends StatelessWidget {
  final Map<String, dynamic> rec;
  final VoidCallback onTap;
  const _RecommendCard({required this.rec, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = '${rec['title'] ?? ''}';
    final genre = '${rec['genre'] ?? ''}';
    final reason = '${rec['reason'] ?? ''}';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: genre
                  .split(',')
                  .map((g) => g.trim())
                  .where((g) => g.isNotEmpty)
                  .map((g) => _GenreChip(label: g))
                  .toList(),
            ),
            const SizedBox(height: 10),
            Text(
              reason,
              style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  final String label;
  const _GenreChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
    );
  }
}

class _DetailSheet extends StatefulWidget {
  final Map<String, dynamic> rec;
  final WidgetRef ref;
  const _DetailSheet({required this.rec, required this.ref});

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  bool _adding = false;
  bool _added = false;
  String? _error;

  Future<void> _addToLibrary() async {
    setState(() { _adding = true; _error = null; });
    try {
      await _api.addManga(widget.rec['title']);
      setState(() { _added = true; _adding = false; });
    } catch (e) {
      setState(() { _error = 'Failed to add. Try again.'; _adding = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = '${widget.rec['title'] ?? ''}';
    final genre = '${widget.rec['genre'] ?? ''}';
    final reason = '${widget.rec['reason'] ?? ''}';

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: genre
                .split(',')
                .map((g) => g.trim())
                .where((g) => g.isNotEmpty)
                .map((g) => _GenreChip(label: g))
                .toList(),
          ),
          const SizedBox(height: 16),
          Text(
            reason,
            style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.5),
          ),
          const SizedBox(height: 28),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _added || _adding ? null : _addToLibrary,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _adding
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(
                      _added ? 'Added to Library ✓' : 'Add to Library',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
