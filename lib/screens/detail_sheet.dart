import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/manga.dart';
import '../services/api_service.dart';

final _api = ApiService();

Future<void> showDetailSheet(BuildContext context, Manga manga, VoidCallback onChanged) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _DetailSheet(manga: manga, onChanged: onChanged),
  );
}

class _DetailSheet extends StatefulWidget {
  final Manga manga;
  final VoidCallback onChanged;

  const _DetailSheet({required this.manga, required this.onChanged});

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  late int _chapter;
  late String _status;
  late int? _rating;
  late TextEditingController _urlCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _chapter = widget.manga.chapter;
    _status = widget.manga.status;
    _rating = widget.manga.rating;
    _urlCtrl = TextEditingController(text: widget.manga.url ?? '');
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final url = _urlCtrl.text.trim();
      await _api.updateManga(
        widget.manga.id,
        chapter: _chapter,
        status: _status,
        rating: _rating,
        url: url.isEmpty ? null : url,
      );
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Remove "${widget.manga.title}" from your list?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _api.deleteManga(widget.manga.id);
    widget.onChanged();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.9,
      builder: (_, ctrl) => ListView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title + delete
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.manga.title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: _delete,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            decoration: InputDecoration(
              labelText: 'Website Link',
              hintText: 'https://...',
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    tooltip: 'Paste',
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) setState(() => _urlCtrl.text = data!.text!);
                    },
                  ),
                  if (_urlCtrl.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _urlCtrl.clear()),
                    ),
                ],
              ),
            ),
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
          ),
          if (_urlCtrl.text.isEmpty) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Suggest link from MangaDex'),
              onPressed: () async {
                final url = await _api.suggestLink(widget.manga.id);
                if (url != null) {
                  setState(() => _urlCtrl.text = url);
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No link found on MangaDex')),
                  );
                }
              },
            ),
          ],
          const SizedBox(height: 16),

          // Chapter
          Text('Chapter', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.outlined(
                icon: const Icon(Icons.remove),
                onPressed: _chapter > 0 ? () => setState(() => _chapter--) : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  controller: TextEditingController(text: '$_chapter'),
                  onChanged: (v) => _chapter = int.tryParse(v) ?? _chapter,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                icon: const Icon(Icons.add),
                onPressed: () => setState(() => _chapter++),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Status
          Text('Status', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'reading', label: Text('Reading'), icon: Icon(Icons.auto_stories, size: 16)),
              ButtonSegment(value: 'completed', label: Text('Done'), icon: Icon(Icons.check, size: 16)),
              ButtonSegment(value: 'dropped', label: Text('Dropped'), icon: Icon(Icons.cancel, size: 16)),
            ],
            selected: {_status},
            onSelectionChanged: (s) => setState(() => _status = s.first),
          ),
          const SizedBox(height: 20),

          // Rating
          Row(
            children: [
              Text('Rating', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              const Spacer(),
              if (_rating != null)
                GestureDetector(
                  onTap: () => setState(() => _rating = null),
                  child: Text('Clear', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                _rating != null ? '$_rating / 10' : 'No rating',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _rating != null ? Theme.of(context).colorScheme.primary : Colors.grey[600],
                ),
              ),
            ],
          ),
          Slider(
            value: (_rating ?? 0).toDouble(),
            min: 0,
            max: 10,
            divisions: 10,
            label: _rating != null ? '$_rating' : 'None',
            onChanged: (v) => setState(() => _rating = v == 0 ? null : v.toInt()),
          ),
          const SizedBox(height: 28),

          // Save button
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}
