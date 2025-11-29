import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chapter_fetcher.dart';
import '../constants/network_constants.dart';

class FavoritesManager {
  static final FavoritesManager _instance = FavoritesManager._internal();
  factory FavoritesManager() => _instance;
  FavoritesManager._internal();

  List<String> _cachedFavorites = [];
  List<String> _cachedAvailableGenres = [];
  final Map<String, int> _newChapterCounts = {};
  final Map<String, Map<String, dynamic>> _chapterCache = {};
  static final DateTime _defaultLastRead = DateTime(2004, 7, 13);

  List<String> get cachedFavorites => _cachedFavorites;
  List<String> get cachedAvailableGenres => _cachedAvailableGenres;
  Map<String, int> get newChapterCounts => _newChapterCounts;

  Future<void> loadFavorites() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _cachedFavorites = prefs.getStringList('favorites') ?? [];
    _cachedAvailableGenres = prefs.getStringList('available_genres') ?? [];

    // Pre-load chapter cache for favorites
    for (var favorite in _cachedFavorites) {
      String comicId =
          RegExp(r'ID: (\w+)').firstMatch(favorite)?.group(1) ?? '';
      if (comicId.isNotEmpty) {
        String? dataJson = prefs.getString('chapters_$comicId');
        if (dataJson != null) {
          try {
            _chapterCache[comicId] =
                jsonDecode(dataJson) as Map<String, dynamic>;
          } catch (e) {
            debugPrint('Error decoding cache for $comicId: $e');
          }
        }
      }
    }
  }

  Future<void> addComicToFavorite(String comicId, String title, String url,
      String cover, String latestChapter, String page) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> favorites = prefs.getStringList('favorites') ?? [];

    // Check if already exists
    if (favorites.any((item) => item.contains('ID: $comicId'))) {
      return;
    }

    String genres = await ChapterFetcher.extractComicGenres(url);
    String favoriteString =
        "ID: $comicId, 漫畫: $title, URL: $url, Cover: $cover, Chapter: $latestChapter, Page: $page, Genres: $genres";

    favorites.add(favoriteString);
    await prefs.setStringList('favorites', favorites);
    _cachedFavorites = favorites;

    // Update available genres
    await _updateAvailableGenres(genres);
  }

  Future<void> removeFavorite(String favorite) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> favorites = prefs.getStringList('favorites') ?? [];
    favorites.remove(favorite);
    await prefs.setStringList('favorites', favorites);
    _cachedFavorites = favorites;

    String comicId = RegExp(r'ID: (\w+)').firstMatch(favorite)?.group(1) ?? '';
    if (comicId.isNotEmpty) {
      _newChapterCounts.remove(comicId);
    }
  }

  Future<void> _updateAvailableGenres(String newGenres) async {
    if (newGenres.isEmpty) return;

    Set<String> genreSet = Set.from(_cachedAvailableGenres);
    List<String> genres = newGenres.split(',');
    genreSet.addAll(genres.where((g) => g.isNotEmpty));

    List<String> sortedGenres = genreSet.toList()..sort();

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('available_genres', sortedGenres);
    _cachedAvailableGenres = sortedGenres;
  }

  Future<void> updateFavoritesWithGenres({String? cookies}) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> favorites = prefs.getStringList('favorites') ?? [];
    List<String> updatedFavorites = [];
    Set<String> allGenres = {};

    for (String favorite in favorites) {
      if (favorite.contains('Genres:')) {
        String genres =
            RegExp(r'Genres: ([^,]*)').firstMatch(favorite)?.group(1) ?? '';
        if (genres.isNotEmpty) {
          allGenres.addAll(genres.split(',').where((g) => g.isNotEmpty));
        }
        updatedFavorites.add(favorite);
        continue;
      }

      String url =
          RegExp(r'URL: (https?://[^,]+)').firstMatch(favorite)?.group(1) ?? '';
      if (url.isNotEmpty) {
        String genres =
            await ChapterFetcher.extractComicGenres(url, cookies: cookies);
        if (genres.isNotEmpty) {
          allGenres.addAll(genres.split(',').where((g) => g.isNotEmpty));
          updatedFavorites.add('$favorite, Genres: $genres');
        } else {
          updatedFavorites.add(favorite);
        }
        // Add delay to prevent IP blocking (rate limiting)
        await Future.delayed(NetworkConstants.crawlDelay);
      } else {
        updatedFavorites.add(favorite);
      }
    }

    await prefs.setStringList('favorites', updatedFavorites);
    _cachedFavorites = updatedFavorites;

    List<String> sortedGenres = allGenres.toList()..sort();
    await prefs.setStringList('available_genres', sortedGenres);
    _cachedAvailableGenres = sortedGenres;
  }

  Future<Map<String, dynamic>?> getCachedChapterData(String comicId) async {
    if (_chapterCache.containsKey(comicId)) {
      var data = _chapterCache[comicId]!;
      int timestamp = data['timestamp'] ?? 0;
      int now = DateTime.now().millisecondsSinceEpoch;
      if (now - timestamp < 24 * 60 * 60 * 1000) {
        return data;
      }
    }

    // Fallback to disk if not in memory (though loadFavorites puts it in memory)
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? dataJson = prefs.getString('chapters_$comicId');
    if (dataJson != null) {
      var data = jsonDecode(dataJson) as Map<String, dynamic>;
      _chapterCache[comicId] = data;
      return data;
    }
    return null;
  }

  Future<void> cacheChapterData(
      String comicId, Map<String, dynamic> data) async {
    _chapterCache[comicId] = data;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('chapters_$comicId', jsonEncode(data));
  }

  Future<void> checkAllFavoritesForNewChapters({String? cookies}) async {
    _newChapterCounts.clear();
    for (String favorite in _cachedFavorites) {
      String comicId =
          RegExp(r'ID: (\w+)').firstMatch(favorite)?.group(1) ?? '';
      if (comicId.isNotEmpty) {
        await _checkSingleComicForNewChapters(comicId, favorite,
            cookies: cookies);
        // Add delay to prevent IP blocking (rate limiting)
        await Future.delayed(NetworkConstants.crawlDelay);
      }
    }
  }

  Future<void> _checkSingleComicForNewChapters(String comicId, String favorite,
      {String? cookies}) async {
    // Construct detail URL using comicId to ensure we fetch from the correct page
    String detailUrl = 'https://m.manhuagui.com/comic/$comicId/';

    // Force refresh to get latest data
    Map<String, dynamic> data =
        await ChapterFetcher.fetchChapterList(detailUrl, cookies: cookies);
    await cacheChapterData(comicId, data);

    List<dynamic> chapters = data['chapters'] ?? [];
    if (chapters.isEmpty) return;

    SharedPreferences prefs = await SharedPreferences.getInstance();
    int lastTotal = prefs.getInt('last_total_chapters_$comicId') ?? 0;
    int currentTotal = chapters.length;

    if (lastTotal == 0) {
      await setLastTotalChapters(comicId, currentTotal);
      return;
    }

    int newCount = currentTotal - lastTotal;

    if (newCount > 0) {
      _newChapterCounts[comicId] = newCount;
    }
  }

  Future<void> setLastTotalChapters(String comicId, int count) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_total_chapters_$comicId', count);
  }

  bool hasNewChapters(String comicId) {
    return _newChapterCounts.containsKey(comicId);
  }

  int getNewChapterCount(String comicId) {
    return _newChapterCounts[comicId] ?? 0;
  }

  void clearNewChapterCount(String comicId) {
    _newChapterCounts.remove(comicId);
  }

  bool isFavorite(String comicId) {
    return _cachedFavorites.any((item) => item.contains('ID: $comicId'));
  }

  Future<void> updateFavorite(int index, String favoriteItem) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> favorites = prefs.getStringList('favorites') ?? [];
    if (index >= 0 && index < favorites.length) {
      favorites[index] = favoriteItem;
      await prefs.setStringList('favorites', favorites);
      await _normalizeAndPersistFavorites(favorites, prefs);
    }
  }

  Future<Map<String, dynamic>> getStoredComicProgress(String comicId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString('comic_progress_$comicId');
    if (jsonStr != null) {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    }
    return {};
  }

  Future<void> addFavorite(String favoriteItem) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> favorites = prefs.getStringList('favorites') ?? [];
    // Check for duplicates based on ID
    String comicId =
        RegExp(r'ID: (\w+)').firstMatch(favoriteItem)?.group(1) ?? '';

    if (comicId.isNotEmpty) {
      bool exists = favorites.any(
          (item) => RegExp(r'ID: (\w+)').firstMatch(item)?.group(1) == comicId);
      if (exists) return;
    }

    favorites.add(favoriteItem);
    await prefs.setStringList('favorites', favorites);
    await _normalizeAndPersistFavorites(favorites, prefs);
  }

  List<String> filterFavoritesByGenre(List<String> favorites, String genre) {
    if (genre == "全部") return favorites;
    return favorites.where((item) {
      String itemGenres =
          RegExp(r'Genres: ([^,]*)').firstMatch(item)?.group(1) ?? '';
      return itemGenres.split(',').contains(genre);
    }).toList();
  }

  Future<void> updateComicProgress(
      String comicId, Map<String, dynamic> progress) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('comic_progress_$comicId', jsonEncode(progress));
  }

  // LastRead Helper Methods

  String _formatLastRead(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}.${time.month}.${time.day} ${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  DateTime _parseLastReadValue(String? value) {
    if (value == null || value.trim().isEmpty) {
      return _defaultLastRead;
    }

    try {
      List<String> parts = value.split(' ');
      List<String> dateParts = parts.first.split('.');
      int year = int.parse(dateParts[0]);
      int month = dateParts.length > 1 ? int.parse(dateParts[1]) : 1;
      int day = dateParts.length > 2 ? int.parse(dateParts[2]) : 1;

      int hour = 0;
      int minute = 0;
      int second = 0;

      if (parts.length > 1) {
        List<String> timeParts = parts[1].split(':');
        if (timeParts.isNotEmpty) {
          hour = int.parse(timeParts[0]);
        }
        if (timeParts.length > 1) {
          minute = int.parse(timeParts[1]);
        }
        if (timeParts.length > 2) {
          second = int.parse(timeParts[2]);
        }
      }

      return DateTime(year, month, day, hour, minute, second);
    } catch (e) {
      debugPrint('Error parsing LastRead value "$value": $e');
      return _defaultLastRead;
    }
  }

  String _ensureFavoriteHasLastRead(String favorite) {
    final regex = RegExp(r'LastRead: ([^,]+)');
    final match = regex.firstMatch(favorite);

    if (match == null) {
      final defaultString = _formatLastRead(_defaultLastRead);
      if (favorite.contains(', Genres:')) {
        return favorite.replaceFirst(
            ', Genres:', ', LastRead: $defaultString, Genres:');
      }
      return '$favorite, LastRead: $defaultString';
    }

    final normalized = _formatLastRead(_parseLastReadValue(match.group(1)));
    return favorite.replaceFirst(regex, 'LastRead: $normalized');
  }

  String _setFavoriteLastRead(String favorite, DateTime timestamp) {
    final formatted = _formatLastRead(timestamp);
    final regex = RegExp(r'LastRead: ([^,]+)');
    if (regex.hasMatch(favorite)) {
      return favorite.replaceFirst(regex, 'LastRead: $formatted');
    }
    if (favorite.contains(', Genres:')) {
      return favorite.replaceFirst(
          ', Genres:', ', LastRead: $formatted, Genres:');
    }
    return '$favorite, LastRead: $formatted';
  }

  DateTime _extractLastRead(String favorite) {
    final match = RegExp(r'LastRead: ([^,]+)').firstMatch(favorite);
    return _parseLastReadValue(match?.group(1));
  }

  Future<List<String>> _normalizeAndPersistFavorites(
      List<String> favorites, SharedPreferences prefs) async {
    bool needsPersist = false;
    final entries = <MapEntry<DateTime, String>>[];

    for (final favorite in favorites) {
      final normalized = _ensureFavoriteHasLastRead(favorite);
      if (normalized != favorite) {
        needsPersist = true;
      }
      entries.add(MapEntry(_extractLastRead(normalized), normalized));
    }

    entries.sort((a, b) => b.key.compareTo(a.key));
    final sortedFavorites = entries.map((entry) => entry.value).toList();

    if (!listEquals(sortedFavorites, favorites)) {
      needsPersist = true;
    }

    if (needsPersist) {
      await prefs.setStringList('favorites', sortedFavorites);
      _cachedFavorites = sortedFavorites;
    } else {
      _cachedFavorites = favorites;
    }

    return sortedFavorites;
  }

  Future<void> recordFavoriteVisit(String comicId,
      {DateTime? timestamp}) async {
    if (comicId.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList('favorites') ?? [];
    bool updated = false;
    final visitTime = timestamp ?? DateTime.now();

    for (int i = 0; i < favorites.length; i++) {
      final currentId =
          RegExp(r'ID: (\w+)').firstMatch(favorites[i])?.group(1) ?? '';
      if (currentId == comicId) {
        favorites[i] = _setFavoriteLastRead(favorites[i], visitTime);
        updated = true;
        break;
      }
    }

    if (updated) {
      await _normalizeAndPersistFavorites(favorites, prefs);
    }
  }

  Future<void> updateFavoriteProgress(
      String comicId, String chapter, String page, String url) async {
    if (comicId.isEmpty) return;

    SharedPreferences prefs = await SharedPreferences.getInstance();
    // Use cached favorites as the source of truth
    List<String> favorites = List.from(_cachedFavorites);
    bool updated = false;
    DateTime now = DateTime.now();

    for (int i = 0; i < favorites.length; i++) {
      String currentId =
          RegExp(r'ID: (\w+)').firstMatch(favorites[i])?.group(1) ?? '';
      if (currentId == comicId) {
        String favorite = favorites[i];

        // Update Chapter
        if (chapter.isNotEmpty) {
          favorite = favorite.replaceAll(
              RegExp(r'Chapter: [^,]*'), "Chapter: $chapter");
        }

        // Update Page
        if (page.isNotEmpty) {
          favorite = favorite.replaceAll(RegExp(r'Page: [^,]*'), "Page: $page");
        }

        // Update URL
        if (url.isNotEmpty) {
          favorite = favorite.replaceAll(RegExp(r'URL: [^,]*'), "URL: $url");
        }

        // Update LastRead
        favorite = _setFavoriteLastRead(favorite, now);

        debugPrint('📝 Updating progress for $comicId:');
        debugPrint('   Chapter: $chapter, Page: $page');
        debugPrint('   URL: $url');
        debugPrint(
            '   Updated entry: ${favorite.length > 100 ? favorite.substring(0, 100) + "..." : favorite}');

        favorites[i] = favorite;
        updated = true;
        break;
      }
    }

    if (updated) {
      // Force persist to SharedPreferences
      await prefs.setStringList('favorites', favorites);
      // Normalize and update cache
      await _normalizeAndPersistFavorites(favorites, prefs);
    }
  }
}
