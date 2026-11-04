class Manga {
  final int id;
  final String title;
  final String? url;
  final String? coverUrl;
  final int chapter;
  final String status;
  final String? notes;
  final int? rating;
  final String updatedAt;

  Manga({
    required this.id,
    required this.title,
    this.url,
    this.coverUrl,
    required this.chapter,
    required this.status,
    this.notes,
    this.rating,
    required this.updatedAt,
  });

  factory Manga.fromJson(Map<String, dynamic> j) => Manga(
        id: j['id'],
        title: j['title'],
        url: j['url'],
        coverUrl: j['cover_url'],
        chapter: j['chapter'] ?? 0,
        status: j['status'] ?? 'reading',
        notes: j['notes'],
        rating: j['rating'],
        updatedAt: j['updated_at'] ?? '',
      );

  Manga copyWith({
    int? chapter,
    String? status,
    int? rating,
    String? notes,
    String? url,
    String? coverUrl,
    String? title,
  }) =>
      Manga(
        id: id,
        title: title ?? this.title,
        url: url ?? this.url,
        coverUrl: coverUrl ?? this.coverUrl,
        chapter: chapter ?? this.chapter,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        rating: rating ?? this.rating,
        updatedAt: updatedAt,
      );
}
