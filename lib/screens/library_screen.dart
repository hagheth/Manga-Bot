import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/manga.dart';
import '../services/api_service.dart';
import 'detail_sheet.dart';

final _api = ApiService();

final mangaProvider = FutureProvider.family<List<Manga>, String?>((ref, status) async {
  return _api.getManga(status: status);
});

String _coverUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (kIsWeb) return '${ApiService.baseUrl}/proxy/image?url=${Uri.encodeComponent(url)}';
  return url;
}

enum _SortBy { updated, titleAZ, chapterDesc, chapterAsc, ratingDesc, ratingAsc }

const _sortLabels = {
  _SortBy.updated:     'Recently Updated',
  _SortBy.titleAZ:     'Title A→Z',
  _SortBy.chapterDesc: 'Chapter (High→Low)',
  _SortBy.chapterAsc:  'Chapter (Low→High)',
  _SortBy.ratingDesc:  'Rating (High→Low)',
  _SortBy.ratingAsc:   'Rating (Low→High)',
};

class LibraryScreen extends ConsumerStatefulWidget {
  final ValueNotifier<int>? tapNotifier;
  const LibraryScreen({super.key, this.tapNotifier});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _search = '';
  _SortBy _sort = _SortBy.updated;
  final _searchCtrl = TextEditingController();
  final _scrollControllers = <String, ScrollController>{};
  final _mainScroll = ScrollController();

  ScrollController _ctrl(String key) =>
      _scrollControllers.putIfAbsent(key, () => ScrollController());

  void _handleTap() {
    if (_mainScroll.hasClients && _mainScroll.offset > 10) {
      _mainScroll.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    } else {
      ref.invalidate(mangaProvider);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.tapNotifier?.addListener(_handleTap);
  }

  @override
  void dispose() {
    widget.tapNotifier?.removeListener(_handleTap);
    _searchCtrl.dispose();
    _mainScroll.dispose();
    for (final c in _scrollControllers.values) c.dispose();
    super.dispose();
  }

  List<Manga> _sorted(List<Manga> list) {
    final l = [...list];
    switch (_sort) {
      case _SortBy.updated:     break;
      case _SortBy.titleAZ:     l.sort((a, b) => a.title.compareTo(b.title));
      case _SortBy.chapterDesc: l.sort((a, b) => b.chapter.compareTo(a.chapter));
      case _SortBy.chapterAsc:  l.sort((a, b) => a.chapter.compareTo(b.chapter));
      case _SortBy.ratingDesc:  l.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
      case _SortBy.ratingAsc:   l.sort((a, b) => (a.rating ?? 0).compareTo(b.rating ?? 0));
    }
    return l;
  }

  void _scroll(String key, double delta) {
    final c = _ctrl(key);
    c.animateTo(
      (c.offset + delta).clamp(0.0, c.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _showSortSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Sort by', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ..._sortLabels.entries.map((e) => ListTile(
            title: Text(e.value),
            leading: _sort == e.key
                ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                : const SizedBox(width: 24),
            onTap: () { setState(() => _sort = e.key); Navigator.pop(context); },
          )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(mangaProvider(null));
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(
        children: [
          allAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (all) {
              final filtered = _search.isEmpty
                  ? all
                  : all.where((m) => m.title.toLowerCase().contains(_search)).toList();

              final reading   = _sorted(filtered.where((m) => m.status == 'reading').toList());
              final completed = _sorted(filtered.where((m) => m.status == 'completed').toList());
              final dropped   = _sorted(filtered.where((m) => m.status == 'dropped').toList());

              return CustomScrollView(
                controller: _mainScroll,
                slivers: [
                  // Space for floating islands
                  SliverToBoxAdapter(child: SizedBox(height: topPad + 60)),

                  // ── Header ───────────────────────────────────────────────────
                  SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'MANGA',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        'Bookmarks',
                        style: TextStyle(
                          fontSize: 13,
                          letterSpacing: 1.5,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Sections ─────────────────────────────────────────────────
              if (reading.isNotEmpty)
                _SectionSliver(
                  label: 'Reading',
                  mangas: reading,
                  accentColor: const Color(0xFF4A90D9),
                  scrollKey: 'reading',
                  onScroll: _scroll,
                  scrollCtrl: _ctrl('reading'),
                  onChanged: () => ref.invalidate(mangaProvider),
                ),
              if (completed.isNotEmpty)
                _SectionSliver(
                  label: 'Completed',
                  mangas: completed,
                  accentColor: const Color(0xFF5AAF7A),
                  scrollKey: 'completed',
                  onScroll: _scroll,
                  scrollCtrl: _ctrl('completed'),
                  onChanged: () => ref.invalidate(mangaProvider),
                ),
              if (dropped.isNotEmpty)
                _SectionSliver(
                  label: 'Dropped',
                  mangas: dropped,
                  accentColor: const Color(0xFFE05C5C),
                  scrollKey: 'dropped',
                  onScroll: _scroll,
                  scrollCtrl: _ctrl('dropped'),
                  onChanged: () => ref.invalidate(mangaProvider),
                ),
              if (filtered.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: Text('No manga found.')),
                ),

              // ── Add Manga button inside scroll ───────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 110),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add Manga', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _showAddOptions(context),
                  ),
                ),
              ),
            ],
          );
        },
      ),

          // ── Floating islands ─────────────────────────────────────────
          Positioned(
            top: topPad + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                // Add button island
                GestureDetector(
                  onTap: () => _showAddOptions(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 2))],
                    ),
                    child: const Icon(Icons.add, size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                // Search field island
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 2))],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.search, size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (v) => setState(() => _search = v.toLowerCase()),
                            style: const TextStyle(fontSize: 14),
                            decoration: const InputDecoration(
                              hintText: 'Search shelf...',
                              hintStyle: TextStyle(fontSize: 14, color: Colors.grey),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        if (_search.isNotEmpty)
                          GestureDetector(
                            onTap: () { _searchCtrl.clear(); setState(() => _search = ''); },
                            child: const Icon(Icons.close, size: 16, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Sort button island
                GestureDetector(
                  onTap: () => _showSortSheet(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 2))],
                    ),
                    child: const Icon(Icons.sort, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Add Manga', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.title),
              title: const Text('Add by title'),
              subtitle: const Text('Search by manga name'),
              onTap: () { Navigator.pop(context); _showAddDialog(context); },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Add by link'),
              subtitle: const Text('Paste a reading site URL — title & cover auto-detected'),
              onTap: () { Navigator.pop(context); _showAddByLinkDialog(context); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final chapterCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Manga'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(hintText: 'Title'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: chapterCtrl,
              decoration: const InputDecoration(
                hintText: 'Chapter (e.g. 42)',
                labelText: 'Current Chapter',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (titleCtrl.text.trim().isEmpty) return;
              final chapter = int.tryParse(chapterCtrl.text) ?? 0;
              await _api.addManga(titleCtrl.text.trim(), chapter: chapter);
              if (ctx.mounted) Navigator.pop(ctx);
              ref.invalidate(mangaProvider);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showAddByLinkDialog(BuildContext context) {
    final urlCtrl = TextEditingController();
    final chapterCtrl = TextEditingController();
    bool loading = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add by Link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatefulBuilder(
                builder: (ctx, setFieldState) => TextField(
                  controller: urlCtrl,
                  decoration: InputDecoration(
                    hintText: 'https://mangafire.to/manga/...',
                    labelText: 'Reading Site URL',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste_rounded, size: 18),
                      tooltip: 'Paste',
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) setFieldState(() => urlCtrl.text = data!.text!);
                      },
                    ),
                  ),
                  keyboardType: TextInputType.url,
                  autofocus: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: chapterCtrl,
                decoration: const InputDecoration(
                  hintText: 'Chapter (e.g. 42)',
                  labelText: 'Current Chapter',
                ),
                keyboardType: TextInputType.number,
              ),
              if (loading) ...[
                const SizedBox(height: 16),
                const Row(children: [
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Text('Detecting title & cover...'),
                ]),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: loading ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: loading ? null : () async {
                final url = urlCtrl.text.trim();
                if (url.isEmpty) return;
                setDialogState(() => loading = true);
                try {
                  final chapter = int.tryParse(chapterCtrl.text) ?? 0;
                  await _api.addMangaFromUrl(url, chapter: chapter);
                  if (ctx.mounted) Navigator.pop(ctx);
                  ref.invalidate(mangaProvider);
                } catch (e) {
                  setDialogState(() => loading = false);
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed: $e')));
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section widget ────────────────────────────────────────────────────────────

class _SectionSliver extends StatelessWidget {
  final String label;
  final List<Manga> mangas;
  final Color accentColor;
  final String scrollKey;
  final void Function(String, double) onScroll;
  final ScrollController scrollCtrl;
  final VoidCallback onChanged;

  const _SectionSliver({
    required this.label,
    required this.mangas,
    required this.accentColor,
    required this.scrollKey,
    required this.onScroll,
    required this.scrollCtrl,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${mangas.length} manga',
                    style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                  ),
                  const Spacer(),
                  _NavArrow(
                    icon: Icons.chevron_left,
                    onTap: () => onScroll(scrollKey, -260),
                  ),
                  const SizedBox(width: 4),
                  _NavArrow(
                    icon: Icons.chevron_right,
                    onTap: () => onScroll(scrollKey, 260),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Horizontal scroll
            SizedBox(
              height: 273,
              child: ListView.builder(
                controller: scrollCtrl,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: mangas.length,
                itemBuilder: (context, i) => _MangaCover(
                  manga: mangas[i],
                  accentColor: accentColor,
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, size: 22, color: Colors.black),
    );
  }
}

// ── Manga cover card ──────────────────────────────────────────────────────────

class _MangaCover extends StatelessWidget {
  final Manga manga;
  final Color accentColor;
  final VoidCallback onChanged;

  const _MangaCover({required this.manga, required this.accentColor, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final coverUrl = _coverUrl(manga.coverUrl);

    return GestureDetector(
      onTap: () async {
        // Tap cover → open manga link
        final rawUrl = manga.url?.isNotEmpty == true
            ? manga.url!
            : 'https://mangadex.org/search?q=${Uri.encodeComponent(manga.title)}';
        final uri = Uri.parse(rawUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        width: 150,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: coverUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: coverUrl,
                          width: 150,
                          height: 213,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _placeholder(),
                          errorWidget: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                ),
                // Edit button overlay
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: () => showDetailSheet(context, manga, onChanged),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.edit, size: 14, color: Colors.white),
                    ),
                  ),
                ),
                // Rating badge
                if (manga.rating != null)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, size: 10, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text('${manga.rating}', style: const TextStyle(fontSize: 10, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Title
            Text(
              manga.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.3),
            ),
            const SizedBox(height: 2),
            Text(
              'Ch. ${manga.chapter}',
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 150,
        height: 213,
        decoration: BoxDecoration(
          color: Colors.grey[850],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.menu_book, color: Colors.grey[700], size: 36),
      );
}
