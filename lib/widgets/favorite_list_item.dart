import 'package:flutter/material.dart';
import '../managers/favorites_manager.dart';
import '../models/favorite_comic.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/network_constants.dart';

class FavoriteListItem extends StatefulWidget {
  final FavoriteComic favorite;
  final int index;
  final int? canDeleteIndex;
  final Function(int) onLongPress;
  final Function(FavoriteComic) onDelete;
  final Function(FavoriteComic, bool, int)? onTap;
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
    if (widget.favorite.id.isNotEmpty) {
      _checkWasUpToDate(widget.favorite.id);
    }
  }

  Future<void> _checkWasUpToDate(String comicId) async {
    try {
      List<String> titles = widget.favorite.chapterTitles;

      if (titles.isNotEmpty) {
        String latestChapterTitle = titles.first;
        String favoriteChapter = widget.favorite.latestChapter;

        if (mounted &&
            favoriteChapter.isNotEmpty &&
            latestChapterTitle == favoriteChapter) {
          setState(() {
            wasUpToDate = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking if was up to date: $e');
    }
  }

  Future<int> _calculateRemainingChapters(
      String comicId, String favoriteChapter) async {
    try {
      List<String> titles = widget.favorite.chapterTitles;
      if (titles.isEmpty) return 0;

      // Find the index of the favorite chapter
      int userPosition = -1;
      for (int i = 0; i < titles.length; i++) {
        String chapterTitle = titles[i];
        if (chapterTitle.contains(favoriteChapter) ||
            favoriteChapter.contains(chapterTitle)) {
          userPosition = i;
          break;
        }
      }

      if (userPosition != -1) {
        return userPosition;
      }
    } catch (e) {
      debugPrint('Error calculating remaining chapters: $e');
    }
    return 0;
  }

  bool _calculationAttempted = false;

  @override
  Widget build(BuildContext context) {
    String favoriteName = widget.favorite.title;
    String favoriteChapter = widget.favorite.latestChapter;
    String favoritePage = widget.favorite.page;
    String favoriteCover = widget.favorite.cover;
    String comicId = widget.favorite.id;

    bool hasNew = FavoritesManager().hasNewChapters(comicId);
    int newCount = FavoritesManager().getNewChapterCount(comicId);

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
                      int totalChapters = widget.favorite.chapterTitles.length;
                      await widget.onTap!(
                          widget.favorite, hasNew, totalChapters);
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
                leading: SizedBox(
                  width: 43,
                  height: 80,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: favoriteCover.isNotEmpty &&
                                favoriteCover != 'Unknow'
                            ? CachedNetworkImage(
                                imageUrl: favoriteCover,
                                fit: BoxFit.fitHeight,
                                httpHeaders: NetworkConstants.defaultHeaders,
                                placeholder: (context, url) =>
                                    const CircularProgressIndicator(
                                        strokeWidth: 2),
                                errorWidget: (context, url, error) =>
                                    const Icon(Icons.error_outline),
                              )
                            : const Icon(Icons.error_outline),
                      ),
                      if (widget.favorite.isFinished)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          left: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 2, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.8),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(4),
                              ),
                            ),
                            child: const Text(
                              '完結',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.normal,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                trailing: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: widget.canDeleteIndex == widget.index ? 1.0 : 0.0,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 200),
                    scale: widget.canDeleteIndex == widget.index ? 1.0 : 0.0,
                    child: Transform.translate(
                      offset: Offset(0, wasUpToDate ? 0 : -10),
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
