import 'package:flutter/material.dart';
import '../managers/favorites_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/network_constants.dart';

class FavoriteListItem extends StatefulWidget {
  final String favorite;
  final int index;
  final int? canDeleteIndex;
  final Function(int) onLongPress;
  final Function(String) onDelete;
  final Function(String, String, bool, String, int)? onTap;
  final String? cookies;
  final bool isRefreshing;
  final bool isBlocked;

  const FavoriteListItem({
    super.key,
    required this.favorite,
    required this.index,
    required this.canDeleteIndex,
    required this.onLongPress,
    required this.onDelete,
    required this.onTap,
    this.cookies,
    this.isRefreshing = false,
    this.isBlocked = false,
  });

  @override
  State<FavoriteListItem> createState() => _FavoriteListItemState();
}

class _FavoriteListItemState extends State<FavoriteListItem> {
  bool wasUpToDate = false;
  int remainingCount = 0;
  bool showRemaining = false;

  @override
  void initState() {
    super.initState();
    String comicId =
        RegExp(r'ID: (\w+)').firstMatch(widget.favorite)?.group(1) ?? '';
    if (comicId.isNotEmpty) {
      _checkWasUpToDate(comicId);
    }
  }

  Future<void> _checkWasUpToDate(String comicId) async {
    try {
      // Use FavoritesManager cache instead of SharedPreferences directly
      var chapterData = await FavoritesManager().getCachedChapterData(comicId);

      if (chapterData != null) {
        List<dynamic> chapters = chapterData['chapters'] ?? [];

        if (chapters.isNotEmpty) {
          // Get the latest chapter title (first in descending order list)
          String latestChapterTitle = chapters.first['title'] ?? '';

          // Get the favoriteChapter (what user last watched)
          String favoriteChapter = RegExp(r'Chapter: ([^,]+)')
                  .firstMatch(widget.favorite)
                  ?.group(1) ??
              '';

          // Exact comparison - if user's chapter exactly matches latest chapter, show gray border
          if (mounted &&
              favoriteChapter.isNotEmpty &&
              latestChapterTitle == favoriteChapter) {
            setState(() {
              wasUpToDate = true;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking if was up to date: $e');
    }
  }

  Future<int> _calculateRemainingChapters(
      String comicId, String favoriteChapter) async {
    try {
      var chapterData = await FavoritesManager().getCachedChapterData(comicId);

      if (chapterData != null) {
        List<dynamic> chapters = chapterData['chapters'] ?? [];

        if (chapters.isNotEmpty && favoriteChapter.isNotEmpty) {
          debugPrint('Checking remaining for $comicId. Favorite: "$favoriteChapter". Total Chapters: ${chapters.length}');

          // Find user's current chapter position in the list
          int userPosition = -1;
          for (int i = 0; i < chapters.length; i++) {
            String chapterTitle = chapters[i]['title'] ?? '';
            if (chapterTitle.contains(favoriteChapter) ||
                favoriteChapter.contains(chapterTitle)) {
              userPosition = i;
              debugPrint('Found match at index $i: "$chapterTitle"');
              break;
            }
          }

          // Calculate remaining chapters (chapters before user's position since list is descending)
          if (userPosition > 0) {
            debugPrint('Remaining count: $userPosition');
            return userPosition; // Number of chapters before current position
          } else if (userPosition == 0) {
            debugPrint('User is at the latest chapter.');
          } else {
            debugPrint('No match found for "$favoriteChapter" in chapter list.');
          }
        }
      }
    } catch (e) {
      debugPrint('Error calculating remaining chapters: $e');
    }
    return 0;
  }

  bool _calculationAttempted = false;

  @override
  Widget build(BuildContext context) {
    String favoriteName =
        RegExp(r'漫畫: ([^,]+)').firstMatch(widget.favorite)?.group(1) ??
            "Undefine";
    String favoriteChapter =
        RegExp(r'Chapter: ([^,]+)').firstMatch(widget.favorite)?.group(1) ??
            "Undefine";
    String favoritePage =
        RegExp(r'Page: ([^,]+)').firstMatch(widget.favorite)?.group(1) ??
            "Undefine";
    String favoriteCover = RegExp(r'Cover: (https?://[^\s]+)')
            .firstMatch(widget.favorite)
            ?.group(1) ??
        "Unknow";
    String comicId =
        RegExp(r'ID: (\w+)').firstMatch(widget.favorite)?.group(1) ?? '';

    bool hasNew = FavoritesManager().hasNewChapters(comicId);
    int newCount = FavoritesManager().getNewChapterCount(comicId);

    // Calculate remaining chapters if no new updates but not caught up
    if (!hasNew && !wasUpToDate && !showRemaining && !_calculationAttempted) {
      _calculationAttempted = true;
      _calculateRemainingChapters(comicId, favoriteChapter).then((count) {
        if (mounted) {
          if (count > 0) {
            setState(() {
              remainingCount = count;
              showRemaining = true;
            });
          }
        }
      });
    }

    debugPrint('Item: $favoriteName, ID: $comicId, HasNew: $hasNew, NewCount: $newCount, Remaining: $remainingCount, ShowRemaining: $showRemaining');

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              splashColor: Colors.blue[400],
              onTap: widget.isBlocked || widget.onTap == null
                  ? null
                  : () async {
                      // Get total chapters from cache if available
                      int totalChapters = 0;
                      var chapterData = await FavoritesManager()
                          .getCachedChapterData(comicId);
                      if (chapterData != null) {
                        List<dynamic> chapters = chapterData['chapters'] ?? [];
                        totalChapters = chapters.length;
                      }

                      await widget.onTap!(widget.favorite, comicId, hasNew,
                          favoriteChapter, totalChapters);
                    },
              onLongPress: () {
                widget.onLongPress(widget.index);
              },
              child: ListTile(
                contentPadding: const EdgeInsets.only(
                    left: 10, top: 5, bottom: 5, right: 0),
                visualDensity: const VisualDensity(horizontal: 0, vertical: 2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                        color: hasNew
                            ? Colors.orange
                            : (wasUpToDate ? Colors.grey : Colors.white),
                        width: hasNew ? 2.5 : 1.5)),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(favoriteName,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            height: 1,
                            color: Colors.white)),
                    Wrap(
                      children: [
                        const Text(
                          '上次看到 ',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70),
                        ),
                        Text(
                          '$favoriteChapter 第$favoritePage頁',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white54),
                        )
                      ],
                    ),
                  ],
                ),
                leading: favoriteCover != 'Unknow'
                    ? CachedNetworkImage(
                        imageUrl: favoriteCover,
                        fit: BoxFit.cover,
                        httpHeaders: NetworkConstants.defaultHeaders,
                        placeholder: (context, url) =>
                            const CircularProgressIndicator(strokeWidth: 2),
                        errorWidget: (context, url, error) =>
                            const Icon(Icons.error_outline),
                      )
                    : const Icon(Icons.error_outline),
                trailing: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: widget.canDeleteIndex == widget.index ? 1.0 : 0.0,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 200),
                    scale: widget.canDeleteIndex == widget.index ? 1.0 : 0.0,
                    child: Transform.translate(
                      offset: Offset(
                          0, wasUpToDate ? 0 : -10), // Move 8 pixels upward
                      child: IconButton(
                        icon: Icon(Icons.delete_forever,
                            color: Colors.red[400], size: 35),
                        onPressed: widget.canDeleteIndex == widget.index
                            ? () {
                                widget.onDelete(widget.favorite);
                              }
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (hasNew)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '+$newCount 話',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            if (!hasNew && showRemaining && remainingCount > 0)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$remainingCount ↓',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            if (widget.isBlocked)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    color: Colors.black
                        .withOpacity(widget.isRefreshing ? 0.6 : 0.4),
                    child: widget.isRefreshing
                        ? const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.orange),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
