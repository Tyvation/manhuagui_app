import 'dart:convert';

class FavoriteComic {
  final String id;
  final String title;
  final String cover;
  final String url;
  final String latestChapter;
  final String page;
  final String lastRead;
  final String genres;
  final List<String> chapterTitles;
  final int chapterCount;
  final bool isFinished;

  FavoriteComic({
    required this.id,
    required this.title,
    required this.cover,
    required this.url,
    required this.latestChapter,
    required this.page,
    required this.lastRead,
    required this.genres,
    this.chapterTitles = const [],
    this.chapterCount = 0,
    this.isFinished = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'cover': cover,
      'url': url,
      'latest_chapter': latestChapter,
      'page': page,
      'last_read': lastRead,
      'genres': genres,
      'chapter_titles': jsonEncode(chapterTitles),
      'chapter_count': chapterCount,
      'is_finished': isFinished ? 1 : 0,
    };
  }

  factory FavoriteComic.fromMap(Map<String, dynamic> map) {
    List<String> titles = [];
    if (map['chapter_titles'] != null) {
      try {
        titles = List<String>.from(jsonDecode(map['chapter_titles']));
      } catch (e) {
        // Handle legacy or invalid data
      }
    }

    return FavoriteComic(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      cover: map['cover'] ?? '',
      url: map['url'] ?? '',
      latestChapter: map['latest_chapter'] ?? '',
      page: map['page'] ?? '1',
      lastRead: map['last_read'] ?? '',
      genres: map['genres'] ?? '',
      chapterTitles: titles,
      chapterCount: map['chapter_count'] ?? titles.length,
      isFinished: (map['is_finished'] ?? 0) == 1,
    );
  }

  // Helper to parse from the old string format
  factory FavoriteComic.fromString(String favoriteString) {
    String id = RegExp(r'ID: (\w+)').firstMatch(favoriteString)?.group(1) ?? '';
    String title =
        RegExp(r'漫畫: ([^,]+)').firstMatch(favoriteString)?.group(1) ?? '';
    String cover = RegExp(r'Cover: (https?://[^\s,]+)')
            .firstMatch(favoriteString)
            ?.group(1) ??
        '';
    String url =
        RegExp(r'URL: (https?://[^,]+)').firstMatch(favoriteString)?.group(1) ??
            '';
    String chapter =
        RegExp(r'Chapter: ([^,]+)').firstMatch(favoriteString)?.group(1) ?? '';
    String page =
        RegExp(r'Page: ([^,]+)').firstMatch(favoriteString)?.group(1) ?? '1';
    String lastRead =
        RegExp(r'LastRead: ([^,]+)').firstMatch(favoriteString)?.group(1) ?? '';
    String genres =
        RegExp(r'Genres: (.*)').firstMatch(favoriteString)?.group(1) ?? '';

    return FavoriteComic(
      id: id,
      title: title,
      cover: cover,
      url: url,
      latestChapter: chapter,
      page: page,
      lastRead: lastRead,
      genres: genres,
      chapterTitles: [],
      chapterCount: 0,
      isFinished: false,
    );
  }

  FavoriteComic copyWith({
    String? id,
    String? title,
    String? cover,
    String? url,
    String? latestChapter,
    String? page,
    String? lastRead,
    String? genres,
    List<String>? chapterTitles,
    int? chapterCount,
    bool? isFinished,
  }) {
    return FavoriteComic(
      id: id ?? this.id,
      title: title ?? this.title,
      cover: cover ?? this.cover,
      url: url ?? this.url,
      latestChapter: latestChapter ?? this.latestChapter,
      page: page ?? this.page,
      lastRead: lastRead ?? this.lastRead,
      genres: genres ?? this.genres,
      chapterTitles: chapterTitles ?? this.chapterTitles,
      chapterCount: chapterCount ?? this.chapterCount,
      isFinished: isFinished ?? this.isFinished,
    );
  }
}
