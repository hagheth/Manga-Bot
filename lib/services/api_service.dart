import 'package:dio/dio.dart';
import '../models/manga.dart';

class ApiService {
  static const String baseUrl = 'https://manga-bot-k4yd.onrender.com';
  final Dio _dio = Dio(BaseOptions(baseUrl: baseUrl));

  // ── Manga ──────────────────────────────────────────────────────────────

  Future<List<Manga>> getManga({String? status}) async {
    final res = await _dio.get('/manga', queryParameters: status != null ? {'status': status} : null);
    return (res.data as List).map((e) => Manga.fromJson(e)).toList();
  }

  Future<Manga> addManga(String title, {String? url, int chapter = 0}) async {
    final res = await _dio.post('/manga', data: {'title': title, 'url': url, 'chapter': chapter});
    return Manga.fromJson(res.data);
  }

  Future<Manga> addMangaFromUrl(String url, {int chapter = 0}) async {
    final res = await _dio.post('/manga/from-url', data: {'url': url, 'chapter': chapter});
    return Manga.fromJson(res.data);
  }

  Future<Manga> updateManga(int id, {int? chapter, String? status, int? rating, String? note, String? url, String? title}) async {
    final data = <String, dynamic>{};
    if (chapter != null) data['chapter'] = chapter;
    if (status != null) data['status'] = status;
    if (rating != null) data['rating'] = rating;
    if (note != null) data['note'] = note;
    if (url != null) data['url'] = url;
    if (title != null) data['title'] = title;
    final res = await _dio.patch('/manga/$id', data: data);
    return Manga.fromJson(res.data);
  }

  Future<void> deleteManga(int id) async {
    await _dio.delete('/manga/$id');
  }

  Future<List<Manga>> searchManga(String query) async {
    final res = await _dio.get('/manga/search', queryParameters: {'q': query});
    return (res.data as List).map((e) => Manga.fromJson(e)).toList();
  }

  Future<Map<String, dynamic>> getStats() async {
    final res = await _dio.get('/manga/stats');
    return res.data;
  }

  // ── MangaDex ───────────────────────────────────────────────────────────

  Future<String?> suggestLink(int id) async {
    try {
      final res = await _dio.get('/manga/$id/suggest-link');
      return res.data['url'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getMangaInfo(String title) async {
    try {
      final res = await _dio.get('/mangainfo', queryParameters: {'title': title});
      return res.data;
    } catch (_) {
      return null;
    }
  }

  // ── Discover ───────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getRecommendations() async {
    final res = await _dio.get('/manga/recommend');
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  // ── Chat ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> chat(String message) async {
    final res = await _dio.post('/chat', data: {'message': message});
    return res.data;
  }
}
