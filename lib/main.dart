// ignore_for_file: avoid_print

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'package:manhuagui_app/managers/ad_blocker.dart';
import 'package:manhuagui_app/managers/chapter_fetcher.dart';
import 'package:manhuagui_app/managers/favorites_manager.dart';
import 'package:manhuagui_app/models/favorite_comic.dart';
import 'package:manhuagui_app/widgets/animated_top_notification.dart';
import 'package:manhuagui_app/widgets/favorite_list_item.dart';
import 'package:manhuagui_app/constants/network_constants.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
        debugShowCheckedModeBanner: false, home: WebViewExample());
  }
}

class AllowVerticalDragGestureRecognizer extends VerticalDragGestureRecognizer {
  @override
  void rejectGesture(int pointer) {
    acceptGesture(pointer);
  }
}

class AllowTapGestureRecognizer extends TapGestureRecognizer {
  @override
  void rejectGesture(int pointer) {
    acceptGesture(pointer);
  }
}

class AllowHorizontalDragGestureRecognizer
    extends HorizontalDragGestureRecognizer {
  int? _primaryPointer;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_primaryPointer == null) {
      _primaryPointer = event.pointer;
      super.addAllowedPointer(event);
    } else {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    if (_primaryPointer == pointer) {
      _primaryPointer = null;
    }
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  void rejectGesture(int pointer) {
    if (_primaryPointer == pointer) {
      _primaryPointer = null;
    }
    acceptGesture(pointer);
  }
}

class WebViewExample extends StatefulWidget {
  const WebViewExample({super.key});
  @override
  WebViewExampleState createState() => WebViewExampleState();
}

class WebViewExampleState extends State<WebViewExample> {
  late final WebViewController _controller;
  final ScrollController _pageSelectorController = ScrollController();
  final AdBlocker _adBlocker = AdBlocker();
  final FavoritesManager _favoritesManager = FavoritesManager();

  String? _cookies;
  bool _isAppBarVisible = true;
  int? _canDeleteIndex;
  bool _addedToFavorite = false;
  int _isLoadingChapter = 0;
  bool _showNoChapterDialog = false;
  bool _isLastChapter = true;
  bool _listPageSelector = false;
  int _totalPages = 1;
  String currentUrl = '';
  String currentComic = '';
  String currentComicChap = '';
  String currentPage = '';
  String _selectedGenreFilter = "全部";
  bool _favoritesLoaded = false;
  bool _isRefreshingGenres = false;
  bool _isRefreshingChapters = false;
  final Set<String> _refreshingComicIds = {};
  final Set<String> _checkedComicIds = {};
  double _horizontalDragOffset = 0;
  bool _isHorizontalDragActive = false;
  bool _isSwipeNavigating = false;
  static const double _horizontalSwipeThreshold = 70.0;

  void _handleHorizontalDragStart(DragStartDetails details) {
    _isHorizontalDragActive = true;
    _horizontalDragOffset = 0;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isHorizontalDragActive) {
      return;
    }
    _horizontalDragOffset += details.delta.dx;
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (!_isHorizontalDragActive) {
      return;
    }
    _isHorizontalDragActive = false;
    final double delta = _horizontalDragOffset;
    _horizontalDragOffset = 0;

    if (delta.abs() < _horizontalSwipeThreshold) {
      return;
    }

    final String url = currentUrl;
    if (url.isEmpty ||
        (!comicPattern.hasMatch(url) && !comicPattern1.hasMatch(url))) {
      return;
    }

    final bool toNext = delta < 0;
    _triggerSwipeNavigation(toNext: toNext);
  }

  void _handleHorizontalDragCancel() {
    _isHorizontalDragActive = false;
    _horizontalDragOffset = 0;
  }

  Future<void> _triggerSwipeNavigation({required bool toNext}) async {
    if (_isSwipeNavigating) {
      return;
    }
    final String url = currentUrl;
    if (url.isEmpty ||
        (!comicPattern.hasMatch(url) && !comicPattern1.hasMatch(url))) {
      return;
    }

    _isSwipeNavigating = true;
    final String direction = toNext ? 'next' : 'prev';
    final String textHint = toNext ? '下' : '上';

    int currentPageNumber = 1;
    int totalPages = _totalPages;
    final parts = currentPage.split('/');
    if (parts.isNotEmpty) {
      currentPageNumber = int.tryParse(parts[0]) ?? 1;
      if (parts.length > 1) {
        totalPages = int.tryParse(parts[1].replaceAll(RegExp(r'[^0-9]'), '')) ??
            totalPages;
      }
    }

    bool shouldShowChapterLoading =
        toNext ? currentPageNumber >= totalPages : currentPageNumber <= 1;

    final String script = '''
      (function() {
        var selectors = ['#$direction', '.manga-panel-$direction', '.manga-panel-$direction.manga-panel-on', 'a[rel="$direction"]'];
        for (var i = 0; i < selectors.length; i++) {
          var el = document.querySelector(selectors[i]);
          if (el) {
            el.click();
            return true;
          }
        }
        var hint = /$textHint/;
        var links = document.querySelectorAll('.manga-box a');
        for (var j = 0; j < links.length; j++) {
          var node = links[j];
          if (!node) continue;
          var text = node.textContent || '';
          if (hint.test(text)) {
            node.click();
            return true;
          }
        }
        return false;
      })();
    ''';

    try {
      final result = await _controller.runJavaScriptReturningResult(script);
      if (result.toString() == 'true') {
        if (shouldShowChapterLoading) {
          loadingScreen(toNext ? 2 : 1, 2000);
        }
      } else {
        print('Swipe navigation target not found for direction: $direction');
      }
    } catch (e) {
      print('Swipe navigation error: $e');
    } finally {
      Future.delayed(const Duration(milliseconds: 400), () {
        _isSwipeNavigating = false;
      });
    }
  }

  RegExp comicPattern =
      RegExp(r'https://m\.manhuagui\.com/comic/(\d+)/(\d+)\.html');
  RegExp comicPattern1 = RegExp(r'^https://m\.manhuagui\.com/comic/(\d+)/$');

  Future<void> addComicToFavorite() async {
    String? url = await _controller.currentUrl();

    if (url != null &&
        (comicPattern.hasMatch(url) || comicPattern1.hasMatch(url))) {
      // Extract cookies
      String? cookies;
      try {
        final result =
            await _controller.runJavaScriptReturningResult('document.cookie');
        cookies = result.toString();
        if (cookies.startsWith('"') && cookies.endsWith('"')) {
          cookies = cookies.substring(1, cookies.length - 1);
        }
      } catch (e) {
        debugPrint('Error getting cookies: $e');
      }

      String? title = await _controller.getTitle();
      String comicName;
      String comicChapter;
      String comicId;
      String finalUrl;
      String comicPage = "1";

      if (comicPattern1.hasMatch(url)) {
        var match1 = comicPattern1.firstMatch(url);
        comicId = match1!.group(1)!;

        var chapterData =
            await ChapterFetcher.fetchChapterList(url, cookies: cookies);
        List<dynamic> chapters = chapterData['chapters'] ?? [];

        // Initialize lastTotalChapters to avoid showing all chapters as new
        // if (chapters.isNotEmpty) {
        //   await _favoritesManager.setLastTotalChapters(
        //       comicId, chapters.length);
        // }

        if (chapters.isNotEmpty) {
          var firstChapter = chapters.last;
          String firstChapterUrl = firstChapter['url'] ?? '';
          String firstChapterTitle = firstChapter['title'] ?? '';

          int mangaIndex = title!.indexOf('漫画_');
          if (mangaIndex != -1) {
            comicName = title.substring(0, mangaIndex);
          } else {
            comicName = title;
          }

          comicChapter = firstChapterTitle;
          finalUrl = firstChapterUrl;
        } else {
          print("無法獲取章節列表");
          return;
        }
      } else {
        var match = comicPattern.firstMatch(url);
        comicId = match!.group(1)!;
        finalUrl = url;

        // Fetch and cache chapter data using detail URL
        // String detailUrl = 'https://m.manhuagui.com/comic/$comicId/';
        // var chapterData =
        //     await ChapterFetcher.fetchChapterList(detailUrl, cookies: cookies);
        // Initialize lastTotalChapters to avoid showing all chapters as new
        // List<dynamic> chapters = chapterData['chapters'] ?? [];
        // if (chapters.isNotEmpty) {
        //   await _favoritesManager.setLastTotalChapters(
        //       comicId, chapters.length);
        // }

        int mangaIndex = title!.indexOf('漫画_');
        if (mangaIndex != -1) {
          comicName = title.substring(0, mangaIndex);
          comicChapter = "";
        } else {
          int lastUnderscoreIndex = title.lastIndexOf('_');
          if (lastUnderscoreIndex != -1) {
            comicName = title.substring(0, lastUnderscoreIndex);
            comicChapter = title.substring(lastUnderscoreIndex + 1);
            comicChapter = comicChapter.replaceAll(' - 看漫画手机版', '');
          } else {
            comicName = title;
            comicChapter = "";
          }
        }
        comicPage = url.contains('=') ? url.split('=')[1] : "1";
      }

      String detailUrl = 'https://m.manhuagui.com/comic/$comicId/';
      String genres =
          await ChapterFetcher.extractComicGenres(detailUrl, cookies: cookies);

      String bCover = "https://cf.mhgui.com/cpic/g/$comicId.jpg";

      await _favoritesManager.addComicToFavorite(
          comicId, comicName, finalUrl, bCover, comicChapter, comicPage,
          genres: genres);

      setState(() {
        _addedToFavorite = true;
      });
      print("已加入收藏清單");
    } else {
      print("當前不是漫畫頁面");
    }
  }

  Future<bool> checkComicInFavorite() async {
    String? url = await _controller.currentUrl();
    if (url != null &&
        (comicPattern.hasMatch(url) || comicPattern1.hasMatch(url))) {
      String comicId;

      if (comicPattern1.hasMatch(url)) {
        var match1 = comicPattern1.firstMatch(url);
        comicId = match1!.group(1)!;
      } else {
        var match = comicPattern.firstMatch(url);
        comicId = match!.group(1)!;
      }

      return _favoritesManager.isFavorite(comicId);
    } else {
      return false;
    }
  }

  Future<void> updateFavorite(FavoriteComic comic) async {
    await _favoritesManager.updateFavorite(comic);
    setState(() {});
  }

  Future<void> removeFavorite(String comicId) async {
    await _favoritesManager.removeFavorite(comicId);
    setState(() {
      _addedToFavorite = false;
    });
  }

  Future<List<FavoriteComic>> getFavorites() async {
    return _favoritesManager.cachedFavorites;
  }

  void loadingScreen(int loadingType, int delay) {
    setState(() => _isLoadingChapter = loadingType);
    if (loadingType == 2) _controller.clearCache();
    // Future.delayed(Duration(milliseconds: delay), () {
    //   setState(() => _isLoadingChapter = 0);
    //   if (loadingType == 2) _controller.clearCache();
    // });
  }

  @override
  void initState() {
    super.initState();
    _adBlocker.loadJsFiles();
    _favoritesManager.loadFavorites().then((_) {
      if (mounted) {
        setState(() {
          _favoritesLoaded = true;
        });
        _favoritesManager.checkAllFavoritesForNewChapters().then((_) {
          if (mounted) setState(() {});
        });
      }
    });
    _controller = WebViewController()
      ..canGoBack()
      ..canGoForward()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(NetworkConstants.userAgent)
      ..clearCache()
      ..setOnJavaScriptAlertDialog((request) async {
        print(request.message);
        if (request.message == "没有上一章了" || request.message == "没有下一章了") {
          setState(() {
            _isLoadingChapter = 0;
            _showNoChapterDialog = true;
            _isLastChapter = request.message == "没有下一章了" ? true : false;
          });
          Future.delayed(const Duration(seconds: 2), () {
            setState(() => _showNoChapterDialog = false);
          });
        }
      })
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (WebResourceError error) {
          print(
              'WebView Error: ${error.description} (Code: ${error.errorCode})');
          // Ignore ERR_NAME_NOT_RESOLVED (-2) as it often happens with ads or tracking scripts
          // or invalid next-page links at the end of chapters
          if (error.errorCode == -2) return;

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text('無法載入網頁: ${error.description} (${error.errorCode})'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: '重試',
                  textColor: Colors.white,
                  onPressed: () => _controller.reload(),
                ),
              ),
            );
          }
        },
        onUrlChange: (change) async {
          String? url = await _controller.currentUrl();
          if (url != null && comicPattern.hasMatch(url)) {
            // Turn off loading screen when URL changes (new chapter loaded)
            if (_isLoadingChapter != 0) {
              setState(() => _isLoadingChapter = 0);
            }

            try {
              Object? page = await _controller.runJavaScriptReturningResult('''
                document.querySelector('.manga-page').textContent;
              ''');
              setState(() {
                currentPage = page.toString().replaceAll(RegExp(r'["]'), '');
                if (currentPage != '' && currentPage.split('/').length > 1) {
                  _totalPages = int.tryParse(currentPage
                          .split('/')[1]
                          .replaceAll(RegExp(r'P'), '')) ??
                      1;
                }
              });

              // Update favorite progress
              if (_addedToFavorite) {
                var match = comicPattern.firstMatch(url);
                String comicId = match!.group(1)!;
                String pageNum = currentPage.split('/').first;
                await _favoritesManager.updateFavoriteProgressData(
                    comicId, currentComicChap, pageNum, url);
              }
            } catch (e) {
              debugPrint('Error in onUrlChange: $e');
            }
          }

          // Apply centering inline immediately when URL changes
          if (url != null && comicPattern.hasMatch(url)) {
            try {
              await _controller.runJavaScript('''
                if (document.body) {
                  document.body.style.cssText += '; display: flex !important; flex-direction: column !important; justify-content: center !important; align-items: center !important; min-height: 100vh !important; margin: 0 !important; overflow-y: auto !important;';
                }
              ''');
            } catch (e) {
              debugPrint('Error applying centering in onUrlChange: $e');
            }
          }

          setState(() {
            currentUrl = url ?? '';
          });
        },
        onPageStarted: (url) {
          _isLoadingChapter = 0;
          _adBlocker.injectAdBlockingCSS(_controller);
          _adBlocker.hideAds(_controller);
          if (comicPattern.hasMatch(url)) _adBlocker.showMangaBoxOnly(_controller);
        },
        onPageFinished: (url) async {
          String? title = await _controller.getTitle();
          _addedToFavorite = await checkComicInFavorite();

          // Update cookies
          try {
            final result = await _controller
                .runJavaScriptReturningResult('document.cookie');
            String cookies = result.toString();
            if (cookies.startsWith('"') && cookies.endsWith('"')) {
              cookies = cookies.substring(1, cookies.length - 1);
            }
            _cookies = cookies;
          } catch (e) {
            debugPrint('Error updating cookies: $e');
          }

          if (_addedToFavorite) {
            // Update progress on page load if it's a comic page
            if (comicPattern.hasMatch(url)) {
              var match = comicPattern.firstMatch(url);
              String comicId = match!.group(1)!;
              try {
                Object? page =
                    await _controller.runJavaScriptReturningResult('''
                  document.querySelector('.manga-page').textContent;
                ''');
                String p = page.toString().replaceAll(RegExp(r'["]'), '');
                String pageNum = p.split('/').first;

                // Always extract chapter from title
                String chap = currentComicChap;
                if (title != null) {
                  int lastUnderscoreIndex = title.lastIndexOf('_');
                  if (lastUnderscoreIndex != -1) {
                    chap = title.substring(lastUnderscoreIndex + 1);
                    chap = chap.replaceAll(' - 看漫画手机版', '');
                  }
                }

                await _favoritesManager.updateFavoriteProgressData(
                    comicId, chap, pageNum, url);
                if (mounted) setState(() {});
              } catch (e) {
                debugPrint('Error updating progress: $e');
              }
            } else {
              // Just add if not exists (handled by addComicToFavorite check inside)
              addComicToFavorite();
            }
          }

          _adBlocker.hideAds(_controller);

          Future.delayed(const Duration(milliseconds: 1000), () {
            _adBlocker.hideAds(_controller);
          });

          Future.delayed(const Duration(milliseconds: 3000), () {
            _adBlocker.hideAds(_controller);
          });

          if (comicPattern.hasMatch(url)) {
            try {
              Object? page = await _controller.runJavaScriptReturningResult('''
                document.querySelector('.manga-page').textContent;
              ''');

              setState(() {
                currentPage = page.toString().replaceAll(RegExp(r'["]'), '');
                if (currentPage != '' && currentPage.split('/').length > 1) {
                  _totalPages = int.tryParse(currentPage
                          .split('/')[1]
                          .replaceAll(RegExp(r'P'), '')) ??
                      1;
                }
              });
            } catch (e) {
              debugPrint('Error getting page info: $e');
            }
          }
          setState(() {
            if (title != null) {
              int mangaIndex = title.indexOf('漫画_');
              if (mangaIndex != -1) {
                currentComic = title.substring(0, mangaIndex);
                currentComicChap = "";
              } else {
                int lastUnderscoreIndex = title.lastIndexOf('_');
                if (lastUnderscoreIndex != -1) {
                  currentComic = title.substring(0, lastUnderscoreIndex);
                  currentComicChap = title.substring(lastUnderscoreIndex + 1);
                  currentComicChap =
                      currentComicChap.replaceAll(' - 看漫画手机版', '');
                } else {
                  currentComic = title;
                  currentComicChap = "";
                }
              }
            } else {
              currentComic = "Undefine";
              currentComicChap = "";
            }
          });
          print(title);
        },
      ))
      ..loadRequest(Uri.parse('https://manhuagui.com'));
  }

  void _showTopNotification(String message) {
    OverlayState? overlayState = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => AnimatedTopNotification(
        message: message,
        onComplete: () => overlayEntry.remove(),
      ),
    );

    overlayState.insert(overlayEntry);
  }

  Future<void> _simulateNewChapter() async {
    if (_favoritesManager.cachedFavorites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No favorites to test with!')),
      );
      return;
    }

    FavoriteComic target = _favoritesManager.cachedFavorites.first;
    // Remove the last chapter to simulate a new one appearing
    List<String> reducedTitles = List.from(target.chapterTitles);
    if (reducedTitles.isNotEmpty) {
      reducedTitles.removeAt(0); // Remove the newest chapter
    }

    FavoriteComic modified = target.copyWith(
      chapterTitles: reducedTitles,
      chapterCount: reducedTitles.length,
    );

    // Update DB with "old" data
    await _favoritesManager.updateFavorite(modified);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Simulated old state for ${target.title}. Checking for updates...')),
    );

    // Trigger check
    await _favoritesManager.checkAllFavoritesForNewChapters(
      cookies: _cookies,
      onComicRefreshStateChange: (id, refreshing) {
        if (mounted) setState(() {});
      },
    );

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Check complete. Should see new chapter badge for ${target.title}')),
      );
    }
  }

  Widget _buildCategorySelector() {
    return GestureDetector(
      onTap: () => _showCategoryPopup(),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[700],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[600]!),
        ),
        child: Row(
          children: [
            Container(
              margin: const EdgeInsets.only(right: 6),
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Text(
                _selectedGenreFilter,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.filter_alt_rounded,
                color: Colors.white70, size: 22),
          ],
        ),
      ),
    );
  }

  void _showCategoryPopup() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 800),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[850],
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "選擇分類",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: math.min(
                          _favoritesManager.cachedAvailableGenres.length, 4),
                      childAspectRatio: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _favoritesManager.cachedAvailableGenres.length,
                    itemBuilder: (context, index) {
                      String genre =
                          _favoritesManager.cachedAvailableGenres[index];
                      bool isSelected = genre == _selectedGenreFilter;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedGenreFilter = genre;
                          });
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.orange.withOpacity(0.2)
                                : Colors.grey[700],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.orange
                                  : Colors.grey[600]!,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                margin:
                                    const EdgeInsets.only(right: 0, left: 12),
                                decoration: BoxDecoration(
                                  color:
                                      isSelected ? Colors.orange : Colors.blue,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  genre,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isSelected
                                        ? Colors.orange
                                        : Colors.white,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (await _controller.canGoBack()) {
          _controller.goBack();
          return;
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black45,
        onDrawerChanged: (isOpened) {
          if (!isOpened) {
            setState(() => _canDeleteIndex = null);
          } else {
            setState(() => _isAppBarVisible = false);
          }
        },
        drawer: Drawer(
          backgroundColor: Colors.blue[400],
          child: Builder(builder: (context) {
            return SafeArea(
              child: Column(
                children: [
                  const SizedBox(
                      child: Center(
                          child: Text('我的書櫃',
                              style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)))),
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: favoriteListWidget(context),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () async {
                          _controller.loadRequest(
                              Uri.parse('https://m.manhuagui.com'));
                          Scaffold.of(context).closeDrawer();
                        },
                        icon: const Icon(Icons.home,
                            color: Colors.white, size: 35),
                      ),
                      (kDebugMode)
                          ? IconButton(
                              onPressed: () async {
                                await _simulateNewChapter();
                              },
                              icon: const Icon(Icons.bug_report,
                                  color: Colors.red, size: 35),
                            )
                          : const SizedBox(),
                    ],
                  ),
                ],
              ),
            );
          }),
        ),
        body: Stack(
          children: [
            SafeArea(
              child: Stack(
                children: [
                  WebViewWidget(
                      controller: _controller,
                      gestureRecognizers: Set()
                        ..add(Factory<AllowVerticalDragGestureRecognizer>(
                            () => AllowVerticalDragGestureRecognizer()
                              ..onUpdate = (DragUpdateDetails details) {
                                // Swipe Down (dy > 0) -> Show AppBar
                                if (details.delta.dy > 0 &&
                                    !_isAppBarVisible &&
                                    details.primaryDelta! > 5) {
                                  setState(() => _isAppBarVisible = true);
                                }
                                // Swipe Up (dy < 0) -> Hide AppBar
                                else if (details.delta.dy < 0 &&
                                    _isAppBarVisible &&
                                    details.primaryDelta! < -5) {
                                  setState(() => _isAppBarVisible = false);
                                }
                              }))
                        ..add(Factory<AllowHorizontalDragGestureRecognizer>(() {
                          final recognizer =
                              AllowHorizontalDragGestureRecognizer();
                          recognizer.onStart = _handleHorizontalDragStart;
                          recognizer.onUpdate = _handleHorizontalDragUpdate;
                          recognizer.onEnd = _handleHorizontalDragEnd;
                          recognizer.onCancel = _handleHorizontalDragCancel;
                          recognizer.minFlingDistance =
                              _horizontalSwipeThreshold;
                          return recognizer;
                        }))
                        ..add(Factory<AllowTapGestureRecognizer>(
                            () => AllowTapGestureRecognizer()
                              ..onTap = () async {
                                if (comicPattern.hasMatch(currentUrl)) {
                                  int? pPage =
                                      int.tryParse(currentPage.split('/')[0]) ??
                                          1;
                                  int? lPage = _totalPages;

                                  Future.delayed(
                                      const Duration(milliseconds: 50),
                                      () async {
                                    String? u = await _controller.currentUrl();
                                    var p = RegExp(r"#p=(\d+)")
                                            .firstMatch(u!)
                                            ?.group(1) ??
                                        1;
                                    int? cPage = int.tryParse(p.toString());

                                    if (cPage == null) {
                                      return;
                                    }

                                    if (cPage == 1 && pPage == 1) {
                                      await _triggerSwipeNavigation(
                                          toNext: false);
                                    } else if (pPage == lPage &&
                                        cPage == pPage) {
                                      await _triggerSwipeNavigation(
                                          toNext: true);
                                    }
                                  });
                                }
                                setState(() {
                                  _isAppBarVisible = false;
                                  _listPageSelector = false;
                                });
                              }))),
                  if (_isLoadingChapter != 0)
                    Positioned.fill(
                        child: GestureDetector(
                            onVerticalDragUpdate: (details) {
                              // Swipe Down (dy > 0) -> Show AppBar
                              if (details.delta.dy > 0 &&
                                  !_isAppBarVisible &&
                                  details.primaryDelta! > 5) {
                                setState(() => _isAppBarVisible = true);
                              }
                              // Swipe Up (dy < 0) -> Hide AppBar
                              else if (details.delta.dy < 0 &&
                                  _isAppBarVisible &&
                                  details.primaryDelta! < -5) {
                                setState(() => _isAppBarVisible = false);
                              }
                            },
                            child: Container(
                                alignment: Alignment.center,
                                color: Colors.black.withOpacity(0.4),
                                child: Text(
                                  _isLoadingChapter == 1
                                      ? "正在載入上一章"
                                      : "正在載入下一章",
                                  style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                )))),
                ],
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              top: _isAppBarVisible ? 0 : -100,
              left: 0,
              right: 0,
              child: Container(
                width: 1000,
                decoration: const BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(15),
                        bottomRight: Radius.circular(15))),
                padding:
                    const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                child: SafeArea(
                  child: Builder(builder: (context) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Stack(
                          children: [
                            IconButton(
                              icon: const Icon(
                                  Icons.collections_bookmark_rounded,
                                  color: Colors.white,
                                  size: 30),
                              onPressed: () {
                                Scaffold.of(context).openDrawer();
                              },
                            ),
                            if (_favoritesManager.newChapterCounts.isNotEmpty)
                              Positioned(
                                right: 2,
                                top: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Colors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '${_favoritesManager.newChapterCounts.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Flexible(
                          child: InkWell(
                            onTap: () {
                              String? url = currentUrl.replaceFirst(
                                  RegExp(r'(?<=comic/\d+)/.*'), '');
                              _controller.loadRequest(Uri.parse(url));
                            },
                            child: FittedBox(
                              fit: BoxFit.fitHeight,
                              child: Text(
                                "$currentComic $currentComicChap",
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    overflow: TextOverflow.clip),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                              _addedToFavorite
                                  ? Icons.bookmark_added
                                  : Icons.bookmark_add_outlined,
                              color: Colors.white,
                              size: 30),
                          onPressed: () async {
                            if (_addedToFavorite) {
                              String? url = currentUrl;
                              SharedPreferences prefs =
                                  await SharedPreferences.getInstance();
                              List<String> favorites =
                                  prefs.getStringList('favorites') ?? [];
                              String comicId;

                              if (comicPattern1.hasMatch(url)) {
                                var match1 = comicPattern1.firstMatch(url);
                                comicId = match1!.group(1)!;
                              } else if (comicPattern.hasMatch(url)) {
                                var match = comicPattern.firstMatch(url);
                                comicId = match!.group(1)!;
                              } else {
                                print("URL doesn't match any pattern: $url");
                                return;
                              }

                              var i = favorites.where((item) =>
                                  RegExp(r'ID: (\w*)')
                                      .firstMatch(item)
                                      ?.group(1) ==
                                  comicId);
                              removeFavorite(
                                  i.toString().replaceAll(RegExp(r'[()]'), ''));
                            } else {
                              await addComicToFavorite();
                            }
                          },
                        )
                      ],
                    );
                  }),
                ),
              ),
            ),
            AnimatedPositioned(
              top: _showNoChapterDialog ? 30 : -100,
              width: MediaQuery.of(context).size.width,
              duration: const Duration(milliseconds: 300),
              child: SafeArea(
                child: Container(
                  alignment: Alignment.center,
                  margin: EdgeInsets.symmetric(
                      horizontal: _isLastChapter ? 110 : 120),
                  height: 30,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      color: Colors.blue[400]),
                  child: Text(
                    _isLastChapter ? "已經是最後一章了" : "這才第一章而已",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
            Positioned(
                bottom: 25,
                right: 0,
                child: AnimatedContainer(
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(10),
                          topRight: Radius.circular(10))),
                  height: _listPageSelector ? 150 : 0,
                  width: 60,
                  duration: const Duration(milliseconds: 400),
                  margin: const EdgeInsets.all(10),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 10),
                    controller: _pageSelectorController,
                    itemCount: _totalPages,
                    itemBuilder: (context, index) {
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            setState(() => _listPageSelector = false);
                            String url;
                            if (currentUrl.contains('#p=')) {
                              url = currentUrl.replaceAll(
                                  RegExp(r"#p=(\d+)"), "#p=${index + 1}");
                            } else {
                              url = "$currentUrl#p=${index + 1}";
                            }
                            _controller.loadRequest(Uri.parse(url));
                            if (_pageSelectorController.hasClients) {
                              _pageSelectorController.jumpTo(0);
                            }
                          },
                          splashColor: Colors.blue[200],
                          child: Container(
                              height: 30,
                              alignment: Alignment.center,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 5),
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: Text(
                                  "第 ${index + 1} 頁",
                                  style: const TextStyle(color: Colors.black),
                                  textAlign: TextAlign.center,
                                ),
                              )),
                        ),
                      );
                    },
                  ),
                )),
            AnimatedPositioned(
                bottom: 10,
                right: _listPageSelector ? 80 : 8,
                duration: const Duration(milliseconds: 300),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _listPageSelector ? 1 : 0,
                  child: Row(
                    children: [
                      SizedBox(
                        height: 30,
                        width: 30,
                        child: IconButton(
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              _listPageSelector = false;
                              _controller.runJavaScript('''
                          var button = document.querySelector('a[data-action="chapter.prev"]');
                          if (button) {button.click();}
                        ''');
                              loadingScreen(1, 2000);
                            },
                            style: IconButton.styleFrom(
                                backgroundColor: Colors.grey[300]),
                            icon: const Icon(
                                Icons.keyboard_double_arrow_left_rounded)),
                      ),
                      const SizedBox(width: 5),
                      SizedBox(
                        height: 30,
                        width: 30,
                        child: IconButton(
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              _listPageSelector = false;
                              _controller.runJavaScript('''
                            var button = document.querySelector('a[data-action="chapter.next"]');
                            if (button) {button.click();}
                          ''');
                              loadingScreen(2, 2000);
                            },
                            style: IconButton.styleFrom(
                                backgroundColor: Colors.grey[300]),
                            icon: const Icon(
                                Icons.keyboard_double_arrow_right_rounded)),
                      ),
                    ],
                  ),
                )),
            Positioned(
                bottom: 0,
                right: 0,
                child: comicPattern.hasMatch(currentUrl)
                    ? InkWell(
                        child: Container(
                          margin: const EdgeInsets.all(10),
                          height: 30,
                          width: 60,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: Colors.grey[400],
                              borderRadius: BorderRadius.circular(10)),
                          child: FittedBox(
                              fit: BoxFit.contain, child: Text(currentPage)),
                        ),
                        onTap: () {
                          setState(
                              () => _listPageSelector = !_listPageSelector);
                        },
                      )
                    : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }

  Widget favoriteListWidget(BuildContext context) {
    if (!_favoritesLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_favoritesManager.cachedFavorites.isEmpty) {
      return const Center(
          child: Text("沒有收藏的漫畫😢", style: TextStyle(color: Colors.white)));
    }

    List<FavoriteComic> filteredFavorites =
        _favoritesManager.filterFavoritesByGenre(
            _favoritesManager.cachedFavorites, _selectedGenreFilter);

    return Stack(
      children: [
        Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.grey[850]!, Colors.grey[800]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _isRefreshingGenres
                          ? null
                          : () async {
                              setState(() {
                                _isRefreshingGenres = true;
                                _checkedComicIds.clear();
                              });
                              try {
                                String? cookies;
                                try {
                                  final result = await _controller
                                      .runJavaScriptReturningResult(
                                          'document.cookie');
                                  cookies = result.toString();
                                  if (cookies.startsWith('"') &&
                                      cookies.endsWith('"')) {
                                    cookies = cookies.substring(
                                        1, cookies.length - 1);
                                  }
                                } catch (e) {
                                  debugPrint('Error getting cookies: $e');
                                }

                                await _favoritesManager
                                    .updateFavoritesWithGenres(
                                        cookies: cookies,
                                        onComicRefreshStateChange:
                                            (comicId, isRefreshing) {
                                          if (mounted) {
                                            setState(() {
                                              if (isRefreshing) {
                                                _refreshingComicIds
                                                    .add(comicId);
                                              } else {
                                                _refreshingComicIds
                                                    .remove(comicId);
                                                _checkedComicIds.add(comicId);
                                              }
                                            });
                                          }
                                        });
                                if (mounted) {
                                  _showTopNotification("已更新分類資訊");
                                  setState(() {});
                                }
                              } finally {
                                setState(() {
                                  _isRefreshingGenres = false;
                                });
                              }
                            },
                      child: _isRefreshingGenres
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.orange),
                              ),
                            )
                          : const Icon(Icons.category_rounded,
                              color: Colors.orange, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCategorySelector(),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _isRefreshingChapters
                          ? null
                          : () async {
                              setState(() {
                                _isRefreshingChapters = true;
                                _checkedComicIds.clear();
                              });
                              try {
                                String? cookies;
                                try {
                                  final result = await _controller
                                      .runJavaScriptReturningResult(
                                          'document.cookie');
                                  cookies = result.toString();
                                  if (cookies.startsWith('"') &&
                                      cookies.endsWith('"')) {
                                    cookies = cookies.substring(
                                        1, cookies.length - 1);
                                  }
                                } catch (e) {
                                  debugPrint('Error getting cookies: $e');
                                }

                                await _favoritesManager
                                    .checkAllFavoritesForNewChapters(
                                        cookies: cookies,
                                        onComicRefreshStateChange:
                                            (comicId, isRefreshing) {
                                          if (mounted) {
                                            setState(() {
                                              if (isRefreshing) {
                                                _refreshingComicIds
                                                    .add(comicId);
                                              } else {
                                                _refreshingComicIds
                                                    .remove(comicId);
                                                _checkedComicIds.add(comicId);
                                              }
                                            });
                                          }
                                        });

                                if (mounted) {
                                  int newCount =
                                      _favoritesManager.newChapterCounts.length;
                                  _showTopNotification(newCount > 0
                                      ? "已更新！發現 $newCount 部漫畫有新章節"
                                      : "已更新！所有漫畫都是最新的");
                                  setState(() {});
                                }
                              } finally {
                                setState(() {
                                  _isRefreshingChapters = false;
                                });
                              }
                            },
                      child: _isRefreshingChapters
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.orange),
                              ),
                            )
                          : const Icon(Icons.refresh,
                              color: Colors.orange, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                itemCount: filteredFavorites.length,
                itemBuilder: (context, index) {
                  FavoriteComic comic = filteredFavorites[index];
                  String comicId = comic.id;

                  bool isRefreshing = _refreshingComicIds.contains(comicId);
                  bool isBlocked =
                      (_isRefreshingChapters || _isRefreshingGenres) &&
                          !_checkedComicIds.contains(comicId);

                  return FavoriteListItem(
                    key: ValueKey(comicId),
                    favorite: comic,
                    index: index,
                    canDeleteIndex: _canDeleteIndex,
                    cookies: _cookies,
                    isRefreshing: isRefreshing,
                    isBlocked: isBlocked,
                    onLongPress: (idx) {
                      setState(() {
                        _canDeleteIndex = _canDeleteIndex == idx ? null : idx;
                      });
                    },
                    onDelete: (favorite) {
                      removeFavorite(favorite.id);
                      setState(() => _addedToFavorite = false);
                    },
                    onTap: (favorite, hasNew, totalChapters) async {
                      final navigator = Navigator.of(context);
                      if (favorite.id.isNotEmpty) {
                        await _favoritesManager
                            .recordFavoriteVisit(favorite.id);
                      }
                      if (!mounted) {
                        return;
                      }

                      String url = favorite.url;

                      if (hasNew && favorite.id.isNotEmpty) {
                        if (totalChapters > 0) {
                          await _favoritesManager.setLastTotalChapters(
                              favorite.id, totalChapters);
                        }

                        setState(() {
                          _favoritesManager.clearNewChapterCount(favorite.id);
                        });
                      } else {
                        if (totalChapters > 0) {
                          await _favoritesManager.setLastTotalChapters(
                              favorite.id, totalChapters);
                        }
                      }

                      _controller.loadRequest(Uri.parse(url));
                      navigator.pop();
                      setState(() => _isAppBarVisible = false);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
