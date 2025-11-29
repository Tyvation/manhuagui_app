import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chapter_fetcher.dart';
import '../constants/network_constants.dart';
import '../database/database_helper.dart';
import '../models/favorite_comic.dart';

class FavoritesManager {
  static final FavoritesManager _instance = FavoritesManager._internal();
  factory FavoritesManager() => _instance;
  FavoritesManager._internal();

  List<FavoriteComic> _cachedFavorites = [];
  List<String> _cachedAvailableGenres = [];
  final Map<String, int> _newChapterCounts = {};
  static final DateTime _defaultLastRead = DateTime(2004, 7, 13);

  List<FavoriteComic> get cachedFavorites => _cachedFavorites;
  List<String> get cachedAvailableGenres => _cachedAvailableGenres;
  Map<String, int> get newChapterCounts => _newChapterCounts;

  Future<void> loadFavorites() async {
    final dbHelper = DatabaseHelper();
    _cachedFavorites = await dbHelper.getFavorites();

    // Migration Logic: If DB is empty, check SharedPreferences
    if (_cachedFavorites.isEmpty) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> oldFavorites = prefs.getStringList('favorites') ?? [];

      if (oldFavorites.isNotEmpty) {
        debugPrint('Migrating favorites from SharedPreferences to SQLite...');
        for (String favStr in oldFavorites) {
          try {
            FavoriteComic comic = FavoriteComic.fromString(favStr);

            // Try to migrate chapter cache if available
            String? chapterJson = prefs.getString('chapters_${comic.id}');
            List<String> titles = [];
            if (chapterJson != null) {
              try {
                var data = jsonDecode(chapterJson);
                if (data['chapters'] != null) {
                  for (var ch in data['chapters']) {
                    titles.add(ch['title'] ?? '');
                  }
                }
              } catch (e) {
                debugPrint('Error parsing cached chapters for migration: $e');
              }
            }

            FavoriteComic newComic = comic.copyWith(
              chapterTitles: titles,
              chapterCount: titles.length,
            );
            await dbHelper.insertFavorite(newComic);
          } catch (e) {
            debugPrint('Error migrating favorite: $favStr, error: $e');
          }
        }
        // Reload from DB after migration
        _cachedFavorites = await dbHelper.getFavorites();
      }
    }

    _sortFavorites();
    _updateAvailableGenresFromCache();
  }

  void _sortFavorites() {
    _cachedFavorites.sort((a, b) {
      // Helper to check if a comic is "fully completed" (Finished AND Read to the end)
      bool isCompleted(FavoriteComic c) {
        if (!c.isFinished) return false;
        if (c.chapterTitles.isEmpty) return false;
        // Assuming chapterTitles[0] is the latest chapter
        return c.latestChapter == c.chapterTitles.first;
      }

      bool aCompleted = isCompleted(a);
      bool bCompleted = isCompleted(b);

      // Primary sort: Active (not completed) first, Completed last
      if (aCompleted != bCompleted) {
        return aCompleted ? 1 : -1;
      }

      // Secondary sort: lastRead (Descending)
      DateTime timeA = _parseLastReadValue(a.lastRead);
      DateTime timeB = _parseLastReadValue(b.lastRead);
      return timeB.compareTo(timeA);
    });
  }

  void _updateAvailableGenresFromCache() {
    Set<String> genreSet = {};
    for (var comic in _cachedFavorites) {
      if (comic.genres.isNotEmpty) {
        genreSet.addAll(comic.genres.split(',').where((g) => g.isNotEmpty));
      }
    }
    List<String> sortedGenres = genreSet.toList()..sort();
    if (!sortedGenres.contains("全部")) {
      sortedGenres.insert(0, "全部");
    }
    _cachedAvailableGenres = sortedGenres;
  }

  Future<void> addComicToFavorite(String comicId, String title, String url,
      String cover, String latestChapter, String page,
      {String? genres}) async {
    // Check if already exists
    if (_cachedFavorites.any((item) => item.id == comicId)) {
      return;
    }

    String finalGenres = genres ?? await ChapterFetcher.extractComicGenres(url);
    String lastRead = _formatLastRead(DateTime.now());

    // Fetch chapter list to store titles
    List<String> titles = [];
    bool isFinished = false;
    try {
      String detailUrl = 'https://m.manhuagui.com/comic/$comicId/';
      Map<String, dynamic> data =
          await ChapterFetcher.fetchChapterList(detailUrl);
      if (data['chapters'] != null) {
        for (var ch in data['chapters']) {
          titles.add(ch['title'] ?? '');
        }
      }
      if (data['is_finished'] == true) {
        isFinished = true;
      }
    } catch (e) {
      debugPrint('Error fetching chapters for new favorite: $e');
    }

    FavoriteComic newComic = FavoriteComic(
      id: comicId,
      title: title,
      cover: cover,
      url: url,
      latestChapter: latestChapter,
      page: page,
      lastRead: lastRead,
      genres: finalGenres,
      chapterTitles: titles,
      chapterCount: titles.length,
      isFinished: isFinished,
    );

    await DatabaseHelper().insertFavorite(newComic);
    _cachedFavorites.add(newComic);
    _sortFavorites();
    _updateAvailableGenresFromCache();
  }

  Future<void> removeFavorite(String comicId) async {
    await DatabaseHelper().deleteFavorite(comicId);
    _cachedFavorites.removeWhere((item) => item.id == comicId);
    _newChapterCounts.remove(comicId);
    _updateAvailableGenresFromCache();
  }

  Future<void> updateFavoritesWithGenres(
      {String? cookies,
      Function(String comicId, bool isRefreshing)?
          onComicRefreshStateChange}) async {
    List<FavoriteComic> updatedFavorites = [];
    bool changed = false;

    for (var comic in _cachedFavorites) {
      if (comic.genres.isNotEmpty) {
        updatedFavorites.add(comic);
        if (onComicRefreshStateChange != null) {
          onComicRefreshStateChange(comic.id, false);
        }
        continue;
      }

      if (comic.url.isNotEmpty) {
        if (onComicRefreshStateChange != null) {
          onComicRefreshStateChange(comic.id, true);
        }

        String genres = await ChapterFetcher.extractComicGenres(comic.url,
            cookies: cookies);

        if (genres.isNotEmpty) {
          FavoriteComic updatedComic = comic.copyWith(genres: genres);
          await DatabaseHelper().updateFavorite(updatedComic);
          updatedFavorites.add(updatedComic);
          changed = true;
        } else {
          updatedFavorites.add(comic);
        }

        if (onComicRefreshStateChange != null) {
          onComicRefreshStateChange(comic.id, false);
        }
        await Future.delayed(NetworkConstants.crawlDelay);
      } else {
        updatedFavorites.add(comic);
        if (onComicRefreshStateChange != null) {
          onComicRefreshStateChange(comic.id, false);
        }
      }
    }

    if (changed) {
      _cachedFavorites = updatedFavorites;
      _sortFavorites();
      _updateAvailableGenresFromCache();
    }
  }

  Future<void> checkAllFavoritesForNewChapters({
    String? cookies,
    Function(String comicId, bool isRefreshing)? onComicRefreshStateChange,
  }) async {
    _newChapterCounts.clear();
    for (var favorite in _cachedFavorites) {
      if (favorite.id.isNotEmpty && !favorite.isFinished) {
        if (onComicRefreshStateChange != null) {
          onComicRefreshStateChange(favorite.id, true);
        }
        await _checkSingleComicForNewChapters(favorite, cookies: cookies);
        if (onComicRefreshStateChange != null) {
          onComicRefreshStateChange(favorite.id, false);
        }
        await Future.delayed(NetworkConstants.crawlDelay);
      }
    }
  }

  Future<void> _checkSingleComicForNewChapters(FavoriteComic favorite,
      {String? cookies}) async {
    String detailUrl = 'https://m.manhuagui.com/comic/${favorite.id}/';
    Map<String, dynamic> data =
        await ChapterFetcher.fetchChapterList(detailUrl, cookies: cookies);

    List<dynamic> chapters = data['chapters'] ?? [];
    if (chapters.isEmpty) return;

    List<String> newTitles = [];
    for (var ch in chapters) {
      newTitles.add(ch['title'] ?? '');
    }

    // Update the stored chapter titles in DB
    FavoriteComic updatedComic = favorite.copyWith(
      chapterTitles: newTitles,
      chapterCount: newTitles.length,
      isFinished: data['is_finished'] == true,
    );
    await updateFavorite(updatedComic);

    // Calculate new chapters count
    // We compare the length of the new list with the old list?
    // Or we can just use the length difference if we assume chapters are only added.
    // The previous logic used `last_total_chapters` from SharedPreferences.
    // We can now just compare with `favorite.chapterTitles.length`.

    int lastTotal = favorite.chapterTitles.length;
    int currentTotal = newTitles.length;

    if (lastTotal == 0 && currentTotal > 0) {
      // First time fetching or no previous chapters, don't mark all as new?
      // Or maybe we do? Let's stick to previous behavior: just update.
      return;
    }

    int newCount = currentTotal - lastTotal;
    if (newCount > 0) {
      _newChapterCounts[favorite.id] = newCount;
    }
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
    return _cachedFavorites.any((item) => item.id == comicId);
  }

  Future<void> updateFavorite(FavoriteComic comic) async {
    await DatabaseHelper().updateFavorite(comic);
    int index = _cachedFavorites.indexWhere((c) => c.id == comic.id);
    if (index != -1) {
      _cachedFavorites[index] = comic;
      _sortFavorites();
    }
  }

  List<FavoriteComic> filterFavoritesByGenre(
      List<FavoriteComic> favorites, String genre) {
    if (genre == "全部") return favorites;
    return favorites.where((item) {
      return item.genres.split(',').contains(genre);
    }).toList();
  }

  // Helper methods
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

  Future<void> recordFavoriteVisit(String comicId,
      {DateTime? timestamp}) async {
    if (comicId.isEmpty) return;

    int index = _cachedFavorites.indexWhere((c) => c.id == comicId);
    if (index != -1) {
      FavoriteComic comic = _cachedFavorites[index];
      String newLastRead = _formatLastRead(timestamp ?? DateTime.now());
      FavoriteComic updatedComic = comic.copyWith(lastRead: newLastRead);

      await updateFavorite(updatedComic);
    }
  }

  Future<void> updateFavoriteProgressData(
      String comicId, String chapter, String page, String url) async {
    if (comicId.isEmpty) return;

    int index = _cachedFavorites.indexWhere((c) => c.id == comicId);
    if (index != -1) {
      FavoriteComic comic = _cachedFavorites[index];
      FavoriteComic updatedComic = comic.copyWith(
        latestChapter: chapter.isNotEmpty ? chapter : null,
        page: page.isNotEmpty ? page : null,
        url: url.isNotEmpty ? url : null,
        lastRead: _formatLastRead(DateTime.now()),
      );

      await updateFavorite(updatedComic);
    }
  }

  Future<void> setLastTotalChapters(String comicId, int count) async {
    // This is now implicitly handled by the chapterTitles length in the DB.
    // But main.dart might still call this.
    // We can either update the DB with a dummy list of that length (bad idea)
    // or just ignore it if we trust checkAllFavoritesForNewChapters to handle it.
    // However, main.dart calls this when a user clicks a comic to reset the count.
    // Actually, main.dart calls `clearNewChapterCount` when clicking.
    // `setLastTotalChapters` is called in main.dart to update the count when entering a comic.
    // Since we now store the actual titles, we don't need to manually set the count integer anymore.
    // The count is derived from `chapterTitles.length`.
    // So this method can be empty or removed.
    // I'll keep it empty to avoid breaking main.dart for now, or better, remove it and fix main.dart.
    // I'll remove it and fix main.dart.
  }
}
