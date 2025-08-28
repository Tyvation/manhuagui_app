// ignore_for_file: avoid_print

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'dart:convert';
import 'dart:math' as math;

void main() { 
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewExample()
    );
  }
}

class AllowVerticalDragGestureRecognizer extends VerticalDragGestureRecognizer {
  @override
  void rejectGesture(int pointer) {
    acceptGesture(pointer);  //override rejectGesture here
  }
}

class AllowTapGestureRecognizer extends TapGestureRecognizer {
  @override
  void rejectGesture(int pointer) {
    acceptGesture(pointer);  //override rejectGesture here
  }
}

class WebViewExample extends StatefulWidget {
  const WebViewExample({super.key});
  @override
  WebViewExampleState createState() => WebViewExampleState();
}

class WebViewExampleState extends State<WebViewExample> {
  late final WebViewController _controller;
  late final String _adblockerJS;
  late final String _hideOtherAreaJS;
  final ScrollController  _pageSelectorController = ScrollController();
  bool _scrollingDown = false;
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
  Map<String, int> _newChapterCounts = {};
  String _selectedGenreFilter = "全部";
  List<String> _cachedFavorites = [];
  List<String> _cachedAvailableGenres = [];
  bool _favoritesLoaded = false;
  bool _isRefreshingGenres = false;

  // Genre translation map from Simplified to Traditional Chinese
  static const Map<String, String> genreTranslationMap = {
    '热血': '熱血',
    '冒险': '冒險',
    '魔幻': '魔幻',
    '神鬼': '神鬼',
    '搞笑': '搞笑',
    '萌系': '萌系',
    '爱情': '愛情',
    '科幻': '科幻',
    '魔法': '魔法',
    '格斗': '格鬥',
    '武侠': '武俠',
    '机战': '機戰',
    '战争': '戰爭',
    '竞技': '競技',
    '体育': '體育',
    '校园': '校園',
    '生活': '生活',
    '励志': '勵志',
    '历史': '歷史',
    '伪娘': '偽娘',
    '宅男': '宅男',
    '腐女': '腐女',
    '耽美': '耽美',
    '百合': '百合',
    '后宫': '後宮',
    '治愈': '治癒',
    '美食': '美食',
    '推理': '推理',
    '悬疑': '懸疑',
    '恐怖': '恐怖',
    '四格': '四格',
    '职场': '職場',
    '侦探': '偵探',
    '社会': '社會',
    '音乐': '音樂',
    '舞蹈': '舞蹈',
    '杂志': '雜誌',
    '黑道': '黑道',
  };

  Future<void> setJsFiles() async{
    _adblockerJS = await rootBundle.loadString('lib/assets/adblocker.js');
    _hideOtherAreaJS = await rootBundle.loadString('lib/assets/hideOtherArea.js');
  }
  
  Future<void> injectAdBlockingCSS() async {
    await _controller.runJavaScript('''
      (function() {
        // Create CSS rules to hide ads immediately
        var css = `
          iframe,
          [id*="ad"],
          [class*="gg"],
          [class*="HF"], 
          [class*="sitemaji"],
          [class*="ads"],
          [href*="ad"],
          [href*="click"],
          [src*="doubleclick.net"],
          [src*="ad"],
          [src*="adservice.google"],
          [src*="sitemaji.com"],
          .clickforceads {
            display: none !important;
            visibility: hidden !important;
            opacity: 0 !important;
            height: 0 !important;
            width: 0 !important;
            position: absolute !important;
            left: -9999px !important;
          }
        `;
        
        // Inject CSS immediately
        var style = document.createElement('style');
        style.type = 'text/css';
        style.innerHTML = css;
        (document.head || document.documentElement).appendChild(style);
        
        console.log('🛡️ Ad blocking CSS injected immediately');
      })();
    ''');
  }

  Future<void> hideAds() async{
    await _controller.runJavaScript(_adblockerJS);
  }

  Future<void> showMangaBoxOnly() async{
    await _controller.runJavaScript(_hideOtherAreaJS);
    
    // Backup retry mechanism - check if manga-box is visible after a delay
    Future.delayed(const Duration(milliseconds: 1500), () async {
      try {
        var result = await _controller.runJavaScriptReturningResult('''
          (function() {
            var mangaBox = document.querySelector('.manga-box');
            if (!mangaBox) return false;
            
            var style = window.getComputedStyle(mangaBox);
            var isVisible = style.display !== 'none' && style.visibility !== 'hidden';
            var hasContent = mangaBox.offsetHeight > 0;
            
            return isVisible && hasContent;
          })();
        ''');
        
        if (result.toString() == 'false') {
          print('⚠ Manga box not properly visible, retrying...');
          await _controller.runJavaScript(_hideOtherAreaJS);
          
          // Final retry after another delay
          Future.delayed(const Duration(milliseconds: 1000), () async {
            await _controller.runJavaScript('''
              // Emergency fallback - force show manga box
              var mangaBox = document.querySelector('.manga-box');
              if (mangaBox) {
                document.querySelectorAll('body > *:not(.manga-box)').forEach(el => el.style.display = 'none');
                mangaBox.style.display = 'block';
                mangaBox.style.visibility = 'visible';
                console.log('🔧 Emergency fallback applied');
              }
            ''');
          });
        } 
      } catch (e) {
        print('Error checking manga box visibility: $e');
      }
    });
  }

  Future<Map<String, dynamic>> fetchChapterListInBackground(String detailUrl) async {
    print("fetching: $detailUrl");
    
    // Check cache first
    String comicId = extractComicIdFromUrl(detailUrl);
    var cachedData = await getCachedChapterData(comicId);
    if (cachedData != null) {
      print("Using cached data for comic $comicId");
      return cachedData;
    }

    try {
      // HTTP request approach (much faster than WebView)
      final response = await http.get(
        Uri.parse(detailUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          'Accept-Encoding': 'gzip, deflate',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // Parse HTML to extract chapter data
        final document = html_parser.parse(response.body);
        final chapterList = document.querySelector('#chapterList > ul');
        
        var data = {
          'count': 0,
          'chapters': <Map<String, String>>[],
          'comicId': comicId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };

        if (chapterList != null) {
          final liElements = chapterList.querySelectorAll('li');
          data['count'] = liElements.length;
          
          for (var li in liElements) {
            var link = li.querySelector('a');
            if (link != null) {
              var href = link.attributes['href'] ?? '';
              var title = link.text.trim();
              
              if (href.isNotEmpty && title.isNotEmpty) {
                (data['chapters'] as List).add({
                  'title': title,
                  'url': href.startsWith('http') ? href : 'https://m.manhuagui.com$href'
                });
              }
            }
          }
          
          print("Chapter Count: ${data['count']}");
        } else {
          print("Chapter Count: 0 (no chapter list found)");
        }

        // Cache the result
        await cacheChapterData(comicId, data);
        return data;
      } else {
        print("Failed to fetch: ${response.statusCode}");
        return {'count': 0, 'chapters': [], 'comicId': comicId};
      }
    } catch (e) {
      print('Error in background fetch: $e');
      return {'count': 0, 'chapters': [], 'comicId': comicId};
    }
  }

  String extractComicIdFromUrl(String url) {
    var match = RegExp(r'/comic/(\d+)').firstMatch(url);
    return match?.group(1) ?? '';
  }

  Future<void> cacheChapterData(String comicId, Map<String, dynamic> data) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String dataJson = jsonEncode(data);
    await prefs.setString('chapters_$comicId', dataJson);
  }

  Future<Map<String, dynamic>?> getCachedChapterData(String comicId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? dataJson = prefs.getString('chapters_$comicId');
    
    if (dataJson != null) {
      var data = jsonDecode(dataJson) as Map<String, dynamic>;
      // Check if cache is still valid (24 hours)
      int timestamp = data['timestamp'] ?? 0;
      int now = DateTime.now().millisecondsSinceEpoch;
      int cacheAge = now - timestamp;
      
      if (cacheAge < 24 * 60 * 60 * 1000) { // 24 hours in milliseconds
        return data;
      }
    }
    
    return null;
  }

  Future<String> extractComicGenres(String detailUrl) async {
    try {
      print('🔍 Fetching genres from: $detailUrl');
      final response = await http.get(
        Uri.parse(detailUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        var genreList = <String>[];
        
        print('📄 Page loaded, searching for genres...');
        
        // Try multiple approaches to find genres
        // Approach 1: Look for all dl elements
        var dlElements = document.querySelectorAll('dl');
        print('🔎 Found ${dlElements.length} dl elements');
        
        for (var dl in dlElements) {
          var dtElements = dl.querySelectorAll('dt');
          for (var dt in dtElements) {
            print('📝 DT text: "${dt.text}"');
            if (dt.text.contains('类别') || dt.text.contains('類別')) {
              print('✅ Found genre section!');
              var dd = dt.nextElementSibling;
              if (dd != null && dd.localName == 'dd') {
                print('📋 DD content: ${dd.outerHtml}');
                var genreLinks = dd.querySelectorAll('a');
                print('🔗 Found ${genreLinks.length} genre links');
                for (var link in genreLinks) {
                  String genreName = link.attributes['title'] ?? link.text.trim();
                  print('🏷️ Genre found: "$genreName"');
                  if (genreName.isNotEmpty) {
                    // Translate to Traditional Chinese if available
                    String translatedGenre = genreTranslationMap[genreName] ?? genreName;
                    print('🌐 Translated to: "$translatedGenre"');
                    genreList.add(translatedGenre);
                  }
                }
              }
              break;
            }
          }
          if (genreList.isNotEmpty) break;
        }
        
        // Approach 2: Direct search for genre pattern
        if (genreList.isEmpty) {
          print('🔍 Trying direct search for genre pattern...');
          var genreText = response.body;
          var genreRegex = RegExp(r'类别[：:][^<]*<dd[^>]*>(.*?)</dd>', multiLine: true);
          var match = genreRegex.firstMatch(genreText);
          if (match != null) {
            print('📝 Found genre HTML: ${match.group(1)}');
            var linkRegex = RegExp(r'<a[^>]*title="([^"]+)"[^>]*>([^<]+)</a>');
            var linkMatches = linkRegex.allMatches(match.group(1) ?? '');
            for (var linkMatch in linkMatches) {
              String genreName = linkMatch.group(1) ?? linkMatch.group(2) ?? '';
              print('🏷️ Genre found via regex: "$genreName"');
              if (genreName.isNotEmpty) {
                // Translate to Traditional Chinese if available
                String translatedGenre = genreTranslationMap[genreName] ?? genreName;
                print('🌐 Translated to: "$translatedGenre"');
                genreList.add(translatedGenre);
              }
            }
          }
        }
        
        String result = genreList.join(',');
        print('🎯 Final genres: "$result"');
        return result;
      } else {
        print('❌ HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error extracting genres: $e');
    }
    
    return '';
  }

  Future<void> checkAllFavoritesForNewChapters() async {
    print("🔍 Checking favorites for new chapters...");
    
    List<String> favorites = await getFavorites();
    if (favorites.isEmpty) {
      print("No favorites to check");
      return;
    }

    List<Future<void>> checkTasks = [];
    
    for (String favorite in favorites) {
      String comicId = RegExp(r'ID: (\w+)').firstMatch(favorite)?.group(1) ?? '';
      if (comicId.isNotEmpty) {
        checkTasks.add(checkSingleComicForNewChapters(comicId, favorite));
      }
    }

    // Run all checks in parallel for better performance
    await Future.wait(checkTasks);
    
    // Update UI if new chapters found
    if (_newChapterCounts.isNotEmpty) {
      setState(() {}); // Trigger UI rebuild to show notifications
      int totalNewChapters = _newChapterCounts.values.fold(0, (sum, count) => sum + count);
      print("📚 Found $totalNewChapters new chapters across ${_newChapterCounts.length} comics!");
    } else {
      print("✅ All favorites are up to date");
    }
  }

  Future<void> checkSingleComicForNewChapters(String comicId, String favorite) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String detailUrl = 'https://m.manhuagui.com/comic/$comicId/';
      
      // Get the initial chapter count saved when user first favorited
      String? initialCountStr = prefs.getString('initial_count_$comicId');
      if (initialCountStr == null) {
        print("⚠️ No initial count found for comic $comicId, skipping...");
        return;
      }
      
      int initialCount = int.tryParse(initialCountStr) ?? 0;
      
      // Fetch current chapter count
      var currentData = await fetchChapterListInBackground(detailUrl);
      int currentCount = currentData['count'] ?? 0;
      
      if (currentCount > initialCount) {
        // There are new chapters since user favorited
        int newChapters = currentCount - initialCount;
        _newChapterCounts[comicId] = newChapters;
        
        String comicName = RegExp(r'漫畫: ([^,]+)').firstMatch(favorite)?.group(1) ?? 'Unknown';
        print("🆕 $comicName has $newChapters new chapters! ($initialCount → $currentCount)");
      } else {
        // No new chapters, remove from new list
        _newChapterCounts.remove(comicId);
      }
    } catch (e) {
      print('Error checking comic $comicId: $e');
    }
  }

  Future<Map<String, dynamic>> getStoredComicProgress(String comicId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? progressJson = prefs.getString('progress_$comicId');
    
    if (progressJson != null) {
      return jsonDecode(progressJson) as Map<String, dynamic>;
    }
    
    return {'totalChapters': 0, 'lastWatchedChapter': 0, 'hasNewChapters': false};
  }

  Future<void> updateComicProgress(String comicId, Map<String, dynamic> progress) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String progressJson = jsonEncode(progress);
    await prefs.setString('progress_$comicId', progressJson);
  }

  Future<void> markChapterAsWatched(String comicId, int chapterNumber) async {
    var progress = await getStoredComicProgress(comicId);
    progress['lastWatchedChapter'] = chapterNumber;
    progress['hasNewChapters'] = false; // Clear new chapter flag when user reads
    await updateComicProgress(comicId, progress);
    
    // Remove from new chapters count
    setState(() {
      _newChapterCounts.remove(comicId);
    });
  }

  bool hasNewChapters(String comicId) {
    return _newChapterCounts.containsKey(comicId);
  }

  int getNewChapterCount(String comicId) {
    return _newChapterCounts[comicId] ?? 0;
  }

  List<String> getAvailableGenres(List<String> favorites) {
    Set<String> allGenres = {'全部'};
    
    for (String favorite in favorites) {
      String genresStr = RegExp(r'Genres: ([^,]*(?:,[^,]*)*)').firstMatch(favorite)?.group(1) ?? '';
      if (genresStr.isNotEmpty) {
        List<String> genres = genresStr.split(',');
        for (String genre in genres) {
          String trimmedGenre = genre.trim();
          if (trimmedGenre.isNotEmpty) {
            // Apply translation to displayed genres
            String translatedGenre = genreTranslationMap[trimmedGenre] ?? trimmedGenre;
            allGenres.add(translatedGenre);
          }
        }
      }
    }
    
    List<String> genreList = allGenres.toList();
    genreList.remove('全部'); // Remove from current position
    genreList.sort(); // Sort remaining genres
    genreList.insert(0, '全部'); // Insert at beginning
    return genreList;
  }

  Future<void> updateFavoritesWithGenres() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> favorites = prefs.getStringList('favorites') ?? [];
    bool hasUpdates = false;
    
    for (int i = 0; i < favorites.length; i++) {
      String favorite = favorites[i];
      
      // Check if this favorite already has genres
      if (!favorite.contains('Genres:')) {
        String comicId = RegExp(r'ID: (\w+)').firstMatch(favorite)?.group(1) ?? '';
        if (comicId.isNotEmpty) {
          print("🔄 Adding genres to existing favorite: $comicId");
          
          String detailUrl = 'https://m.manhuagui.com/comic/$comicId/';
          String genres = await extractComicGenres(detailUrl);
          
          // Add genres to existing favorite
          favorites[i] = '$favorite, Genres: $genres';
          hasUpdates = true;
          
          // Small delay to avoid overwhelming the server
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    
    if (hasUpdates) {
      await prefs.setStringList('favorites', favorites);
      print("✅ Updated ${favorites.length} favorites with genres");
      setState(() {}); // Refresh UI
    }
  }

  List<String> filterFavoritesByGenre(List<String> favorites, String selectedGenre) {
    if (selectedGenre == "全部") {
      return favorites;
    }
    
    return favorites.where((favorite) {
      String genresStr = RegExp(r'Genres: ([^,]*(?:,[^,]*)*)').firstMatch(favorite)?.group(1) ?? '';
      if (genresStr.isEmpty) return false;
      
      // Check both original and translated versions
      List<String> genres = genresStr.split(',');
      for (String genre in genres) {
        String trimmedGenre = genre.trim();
        // Check original genre or its translation
        String translatedGenre = genreTranslationMap[trimmedGenre] ?? trimmedGenre;
        if (translatedGenre == selectedGenre) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  Future<void> _checkAndClearIfAtLastChapter(String comicId, String favoriteChapter) async {
    try {
      // Get cached chapter data
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? dataJson = prefs.getString('chapters_$comicId');
      
      if (dataJson != null) {
        var chapterData = jsonDecode(dataJson) as Map<String, dynamic>;
        List<dynamic> chapters = chapterData['chapters'] ?? [];
        
        if (chapters.isNotEmpty) {
          // Get the latest chapter title (first in descending order list)
          String latestChapterTitle = chapters.first['title'] ?? '';
          
          // Clean up both strings for comparison
          String cleanLatest = latestChapterTitle.trim().toLowerCase();
          String cleanFavorite = favoriteChapter.trim().toLowerCase();
          
          // If user is at the last chapter, clear the new chapter flag
          bool isAtLastChapter = cleanFavorite.isNotEmpty && 
              (cleanLatest.contains(cleanFavorite) || cleanFavorite.contains(cleanLatest) || cleanLatest == cleanFavorite);
          
          if (isAtLastChapter) {
            print('🏁 User is at last chapter for $comicId, clearing new chapter flag');
            
            // Update progress to mark as caught up
            var progress = await getStoredComicProgress(comicId);
            int totalChapters = progress['totalChapters'] ?? 0;
            await updateComicProgress(comicId, {
              'totalChapters': totalChapters,
              'lastWatchedChapter': totalChapters, // Mark as caught up
              'lastChecked': DateTime.now().millisecondsSinceEpoch,
              'hasNewChapters': false,
            });
            
            // Remove from new chapters count
            setState(() {
              _newChapterCounts.remove(comicId);
            });
          }
        }
      }
    } catch (e) {
      print('Error checking if at last chapter: $e');
    }
  }

  RegExp comicPattern = RegExp(r'https://m\.manhuagui\.com/comic/(\d+)/(\d+)\.html');
  RegExp comicPattern1 = RegExp(r'^https://m\.manhuagui\.com/comic/(\d+)/$');
  Future<void> addComicToFavorite() async{
    String? url = await _controller.currentUrl();
    
    if(url != null && (comicPattern.hasMatch(url) || comicPattern1.hasMatch(url))){
      String? title = await _controller.getTitle();
      String comicName;
      String comicChapter;
      String comicId;
      String finalUrl;
      String comicPage = "1";
      
      if(comicPattern1.hasMatch(url)) {
        // Comic detail page - get first chapter data and genres
        var match1 = comicPattern1.firstMatch(url);
        comicId = match1!.group(1)!;
        
        // Get chapter list to find first chapter
        var chapterData = await fetchChapterListInBackground(url);
        List<dynamic> chapters = chapterData['chapters'] ?? [];
        
        if(chapters.isNotEmpty) {
          // Get first chapter (last in descending list)
          var firstChapter = chapters.last;
          String firstChapterUrl = firstChapter['url'] ?? '';
          String firstChapterTitle = firstChapter['title'] ?? '';
          
          // Extract comic name from title (detail page format)
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
        // Comic page - existing logic
        var match = comicPattern.firstMatch(url);
        comicId = match!.group(1)!;
        finalUrl = url;
        
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
      
      // Extract genres from detail page
      String detailUrl = 'https://m.manhuagui.com/comic/$comicId/';
      String genres = await extractComicGenres(detailUrl);
      
      String bCover = "https://cf.mhgui.com/cpic/g/$comicId.jpg";
      String favoriteItem = '漫畫: $comicName, ID: $comicId, Cover: $bCover, URL: $finalUrl, Chapter: $comicChapter, Page: $comicPage, Genres: $genres';
      saveFavorite(favoriteItem);
    } else {
      print("當前不是漫畫頁面");
    }
  }

  Future<bool> checkComicInFavorite() async{
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> favorites = prefs.getStringList('favorites') ?? [];
    String? url = await _controller.currentUrl();
    if(url != null && (comicPattern.hasMatch(url) || comicPattern1.hasMatch(url))){
      String comicId;
      
      if(comicPattern1.hasMatch(url)) {
        // Detail page
        var match1 = comicPattern1.firstMatch(url);
        comicId = match1!.group(1)!;
      } else {
        // Comic page
        var match = comicPattern.firstMatch(url);
        comicId = match!.group(1)!;
      }
      
      int index = favorites.indexWhere((item) => RegExp(r'ID: (\w*)').firstMatch(item)?.group(1) == comicId);
      return index == -1 ? false : true;
    } else {
      return false;
    }
  }

  Future<void> saveFavorite(String favoriteItem) async{
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> favorites = prefs.getStringList('favorites') ?? [];
    int index = favorites.indexWhere(
      (item) => RegExp(r'ID: (\w*)').firstMatch(item)?.group(1) == RegExp(r'ID: (\w*)').firstMatch(favoriteItem)?.group(1)
    );

    if(index == -1){
      setState(() {
        favorites.add(favoriteItem);
        _addedToFavorite = true;
      });
      print("已加入收藏清單");
      await prefs.setStringList('favorites', favorites);
      _refreshFavoritesCache();
      
      // Save initial chapter count when adding to favorites
      String comicId = RegExp(r'ID: (\w*)').firstMatch(favoriteItem)?.group(1) ?? '';
      if (comicId.isNotEmpty) {
        // Get current chapter count and save it as baseline
        String detailUrl = 'https://m.manhuagui.com/comic/$comicId/';
        var chapterData = await fetchChapterListInBackground(detailUrl);
        int currentChapterCount = chapterData['count'] ?? 0;
        
        // Save the initial chapter count as baseline
        await prefs.setString('initial_count_$comicId', currentChapterCount.toString());
        print("💾 Saved initial chapter count for comic $comicId: $currentChapterCount");
        
        // Clear any existing new chapter flags
        setState(() {
          _newChapterCounts.remove(comicId);
        });
      }
    } 
    else {
      // Existing favorite - only update if from comic page (not detail page)
      String? currentUrl = await _controller.currentUrl();
      if (currentUrl != null && comicPattern.hasMatch(currentUrl)) {
        // From comic page - update reading progress
        updateFavorite(index, favoriteItem);
      } else {
        // From detail page - don't overwrite progress, just mark as favorited
        setState(() {
          _addedToFavorite = true;
        });
        print("Comic already in favorites, keeping existing progress");
      }
    }
  }

  Future<void> updateFavorite(int index, String favoriteItem) async{
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> favorites = prefs.getStringList('favorites') ?? [];
    setState(() {
      favorites[index] = favoriteItem;
    });
    await prefs.setStringList('favorites', favorites);
    _refreshFavoritesCache();
  }

  Future<void> removeFavorite(String favoriteItem) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> favorites = prefs.getStringList('favorites') ?? [];
    setState(() {
      favorites.remove(favoriteItem);
      _addedToFavorite = false;
    });
    await prefs.setStringList('favorites', favorites);
    _refreshFavoritesCache();
  }

  Future<List<String>> getFavorites() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('favorites') ?? [];
  }

  void loadingScreen(int loadingType,int delay){
    setState(() => _isLoadingChapter = loadingType);
    Future.delayed(Duration(milliseconds: delay), (){
      setState(() => _isLoadingChapter = 0);
      if(loadingType==2) _controller.clearCache();
    });
  }

  @override
  void initState() {
    super.initState();
    setJsFiles();
    
    // Load favorites cache and then check for new chapters
    _initializeFavoritesAndCheckChapters();
    _controller = WebViewController()
      ..canGoBack()..canGoForward()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..clearCache()
      ..setOnJavaScriptAlertDialog((request) async{
        print(request.message);
        if(request.message == "没有上一章了" || request.message == "没有下一章了"){
          setState((){
            _isLoadingChapter = 0;
            _showNoChapterDialog = true;
            _isLastChapter = request.message == "没有下一章了" ? true : false;
          });
          Future.delayed(const Duration(seconds: 2),(){setState(() => _showNoChapterDialog = false);});
        }
      })
      ..setNavigationDelegate(NavigationDelegate(
        onUrlChange: (change) async{
          String? url = await _controller.currentUrl();
          if (comicPattern.hasMatch(url!)) {
            // Get page info but don't call showMangaBoxOnly here - timing issues
            Object? page = await _controller.runJavaScriptReturningResult('''
              document.querySelector('.manga-page').textContent;
            '''); 
            setState(() {
              currentPage = page.toString().replaceAll(RegExp(r'["]'), '');
              if(currentPage != '' && currentPage.split('/').length>1) _totalPages = int.tryParse(currentPage.split('/')[1].replaceAll(RegExp(r'P'), '')) ?? 1;
            });
          }
          
          setState(() {
            currentUrl = url; 
          });
          //print('PageChanged ${change.url}');
        },
        onPageStarted: (url) {
          _isLoadingChapter = 0;
          
          // Inject CSS rules immediately to prevent ads from showing
          injectAdBlockingCSS();
          
          // Run JavaScript ad blocker immediately  
          hideAds();
        },
        onPageFinished: (url) async {
          //print('onPageFinished : $url');
          String? title = await _controller.getTitle(); 
          _addedToFavorite = await checkComicInFavorite();
          if(_addedToFavorite) addComicToFavorite();

          // Run follow-up ad cleanup to catch any ads that loaded after page start
          hideAds();
          
          // Add delayed cleanup for late-loading ads
          Future.delayed(const Duration(milliseconds: 1000), () {
            hideAds();
          });
          
          Future.delayed(const Duration(milliseconds: 3000), () {
            hideAds();
          });

          if (comicPattern.hasMatch(url)) {
            // Call showMangaBoxOnly after page is fully loaded
            showMangaBoxOnly();
            
            Object? page = await _controller.runJavaScriptReturningResult('''
              document.querySelector('.manga-page').textContent;
            '''); 
            
            setState(() {
              currentPage = page.toString().replaceAll(RegExp(r'["]'), '');
              if(currentPage != '' && currentPage.split('/').length>1) _totalPages = int.tryParse(currentPage.split('/')[1].replaceAll(RegExp(r'P'), '')) ?? 1;
            });
          } 
          setState((){
            if (title != null) {
              
              int mangaIndex = title.indexOf('漫画_');
              if (mangaIndex != -1) {
                // Main page format - remove "漫画_" and everything after it
                currentComic = title.substring(0, mangaIndex);
                currentComicChap = "";
              } else {
                // Chapter page format - split by last underscore
                int lastUnderscoreIndex = title.lastIndexOf('_');
                if (lastUnderscoreIndex != -1) {
                  currentComic = title.substring(0, lastUnderscoreIndex);
                  currentComicChap = title.substring(lastUnderscoreIndex + 1);
                  // Remove " - 看漫画手机版" from chapter if present
                  currentComicChap = currentComicChap.replaceAll(' - 看漫画手机版', '');
                } else {
                  // Fallback if no underscore found
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
      ..loadRequest(Uri.parse('https://manhuagui.com')
    );
  }

  Future<void> _loadFavoritesCache() async {
    final favorites = await getFavorites();
    if (mounted) {
      setState(() {
        _cachedFavorites = favorites;
        _cachedAvailableGenres = getAvailableGenres(favorites);
        _favoritesLoaded = true;
      });
    }
  }
  
  void _refreshFavoritesCache() {
    _loadFavoritesCache();
  }

  Future<void> _initializeFavoritesAndCheckChapters() async {
    // First load favorites cache
    await _loadFavoritesCache();
    
    // Then check for new chapters (with a small delay to let UI settle)
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _cachedFavorites.isNotEmpty) {
        checkAllFavoritesForNewChapters();
      }
    });
  }

  void _showTopNotification(String message) {
    OverlayState? overlayState = Overlay.of(context);
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => _AnimatedTopNotification(
        message: message,
        onComplete: () => overlayEntry.remove(),
      ),
    );

    overlayState?.insert(overlayEntry);
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
            const Icon(Icons.filter_alt_rounded, color: Colors.white70, size: 22),
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
                // Header
                
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
                // Grid
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: math.min(_cachedAvailableGenres.length, 4),
                      childAspectRatio: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _cachedAvailableGenres.length,
                    itemBuilder: (context, index) {
                      String genre = _cachedAvailableGenres[index];
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
                            color: isSelected ? Colors.orange.withOpacity(0.2) : Colors.grey[700],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? Colors.orange : Colors.grey[600]!,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(right: 0, left: 12),
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.orange : Colors.blue,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  genre,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isSelected ? Colors.orange : Colors.white,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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
      onPopInvokedWithResult: (didPop, result) async{
        if (await _controller.canGoBack()) {
          _controller.goBack(); // 返回上一頁
          return; // 攔截返回鍵事件
        }
        SystemNavigator.pop(); // 如果無法返回上一頁，允許返回鍵退出程式
      },
      child: Scaffold(
        backgroundColor: Colors.black45,
        onDrawerChanged: (isOpened) {
          if(!isOpened) {setState(() => _canDeleteIndex = null);}
          else { setState(() => _scrollingDown = false);}
        },
        drawer: Drawer(
          backgroundColor: Colors.blue[400],
          child: Builder(
            builder: (context) {
              return SafeArea(
                child: Column(
                  children: [
                    const SizedBox(
                      //height: 60,
                      child: Center(
                        child: Text(
                          '我的書櫃', 
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)
                        )
                      )
                    ),
                    Expanded(
                      child: SizedBox(
                        width: double.infinity,
                        child: favoriteListWidget(context),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: IconButton(
                        onPressed: () async{
                          _controller.loadRequest(Uri.parse('https://m.manhuagui.com'));
                          Scaffold.of(context).closeDrawer();
                        },
                        icon: const Icon(Icons.home, color: Colors.white, size: 35),
                      ),
                    ),
                  ],
                ),
              );
            }
          ),
        ),
        body: Stack(
          children: [
            SafeArea(
              child: WebViewWidget(
                controller: _controller,
                gestureRecognizers: Set()
                ..add(
                  Factory<AllowVerticalDragGestureRecognizer>(() => 
                    AllowVerticalDragGestureRecognizer()
                    ..onUpdate = (DragUpdateDetails details){
                      if(details.delta.dy > 0 && _scrollingDown==false && details.primaryDelta!>15){
                        //print("Scrolling Down : $_scrollingDown");
                        setState(() => _scrollingDown = true);
                      } else if(details.delta.dy < 0 && details.primaryDelta!<-15){
                        setState(() => _scrollingDown = false);
                      }
                    }
                  )
                )
                ..add(
                  Factory<AllowTapGestureRecognizer>(() =>
                    AllowTapGestureRecognizer()
                    ..onTap = () async{
                      if(comicPattern.hasMatch(currentUrl)){
                        int? pPage = int.tryParse(currentPage.split('/')[0]) ?? 1;
                        int? lPage = _totalPages;

                        Future.delayed(const Duration(milliseconds: 50), () async{
                          String? u = await _controller.currentUrl();
                          var p = RegExp(r"#p=(\d+)").firstMatch(u!)?.group(1) ?? 1;
                          int? cPage = int.tryParse(p.toString());
                          //print('Previous Page: $pPage, Current Page: $cPage, Last Page: $lPage');

                          if(cPage==1 && pPage==1){loadingScreen(1, 2000);} //! Previous Chapter
                          else if(pPage==lPage && cPage==pPage){loadingScreen(2, 2000);} //! Next Chapter
                        });
                      }
                      setState((){
                        _scrollingDown = false;
                        _listPageSelector = false;
                      });
                    }
                  )
                )
              ),
            ),
            //! AppBar
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              top: _scrollingDown ? 0 : -100, // 隱藏時移動到螢幕外
              left: 0,
              right: 0,
              child: Container(
                width: 1000,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(15), bottomRight: Radius.circular(15))
                ),
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                child: SafeArea(
                  child: Builder(
                    builder: (context){
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Stack(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.collections_bookmark_rounded, color: Colors.white, size: 30),
                                onPressed: () {
                                  Scaffold.of(context).openDrawer();
                                },
                              ),
                              if (_newChapterCounts.isNotEmpty)
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
                                      '${_newChapterCounts.length}',
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
                              onTap: (){
                                String? url = currentUrl.replaceFirst(RegExp(r'(?<=comic/\d+)/.*'), '');
                                _controller.loadRequest(Uri.parse(url));
                                //print(url);
                              },
                              child: FittedBox(
                                fit: BoxFit.fitHeight,
                                child: Text(
                                  "$currentComic $currentComicChap",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    overflow: TextOverflow.clip
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _addedToFavorite ? Icons.bookmark_added : Icons.bookmark_add_outlined, 
                              color: Colors.white, size: 30
                            ),
                            onPressed: () async{
                              if(_addedToFavorite){
                                String? url = currentUrl;
                                if(url != null){
                                  SharedPreferences prefs = await SharedPreferences.getInstance();
                                  List<String> favorites = prefs.getStringList('favorites') ?? [];
                                  String comicId;
                                  
                                  // Support both URL patterns
                                  if(comicPattern1.hasMatch(url)) {
                                    var match1 = comicPattern1.firstMatch(url);
                                    comicId = match1!.group(1)!;
                                  } else if(comicPattern.hasMatch(url)) {
                                    var match = comicPattern.firstMatch(url);
                                    comicId = match!.group(1)!;
                                  } else {
                                    print("URL doesn't match any pattern: $url");
                                    return;
                                  }
                                  
                                  var i = favorites.where((item) => RegExp(r'ID: (\w*)').firstMatch(item)?.group(1) == comicId);
                                  removeFavorite(i.toString().replaceAll(RegExp(r'[()]'), ''));
                                }
                              }else{
                                await addComicToFavorite();
                              }
                            },
                          )
                        ],
                      );
                    }
                  ),
                ),
              ),
            ),
            //! Alert Dialog
            AnimatedPositioned(
              top: _showNoChapterDialog ? 30 : -100,
              width: MediaQuery.of(context).size.width,
              duration: const Duration(milliseconds: 300),
              child: SafeArea(
                child: Container(
                  alignment: Alignment.center,
                  margin: EdgeInsets.symmetric(horizontal: _isLastChapter ? 110 : 120),
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: Colors.blue[400]
                  ),
                  child: Text(
                    _isLastChapter ? "已經是最後一章了" : "這才第一章而已", 
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white
                    ),
                  ),
                ),
              ), 
            
            ),
            //! PagePicker
            Positioned(
            bottom: 25, right: 0,
              child: AnimatedContainer(
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10))
                ),
                height: _listPageSelector ? 150 : 0, width: 60,
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
                          if (currentUrl.contains('#p=')) {url = currentUrl.replaceAll(RegExp(r"#p=(\d+)"), "#p=${index + 1}");}
                          else {url = "$currentUrl#p=${index + 1}";}
                          _controller.loadRequest(Uri.parse(url));
                          if(_pageSelectorController.hasClients){
                            _pageSelectorController.jumpTo(0);
                          }
                        },
                        splashColor: Colors.blue[200],
                        child: Container(
                          height: 30, 
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Text(
                              "第 ${index+1} 頁", 
                              style: const TextStyle(color: Colors.black),
                              textAlign: TextAlign.center,
                            ),
                          )
                        ),
                      ),
                    );
                  },
                ),
              )
            ),
            //! ChapterButton
            AnimatedPositioned(
              bottom: 10, right: _listPageSelector ? 80 : 8,
              duration: const Duration(milliseconds: 300),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _listPageSelector ? 1 : 0,
                child: Row(
                  children: [
                    SizedBox(
                      height: 30, width: 30,
                      child: IconButton(

                        padding: EdgeInsets.zero,
                        onPressed: (){
                          _listPageSelector = false;
                          _controller.runJavaScript('''
                          var button = document.querySelector('a[data-action="chapter.prev"]');
                          if (button) {button.click();}
                        ''');
                          loadingScreen(1, 2000);
                        }, 
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey[300]
                        ),
                        icon: const Icon(Icons.keyboard_double_arrow_left_rounded)
                      ),
                    ),
                    const SizedBox(width: 5),
                    SizedBox(
                      height: 30, width: 30,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        onPressed: (){
                          _listPageSelector = false;
                          _controller.runJavaScript('''
                            var button = document.querySelector('a[data-action="chapter.next"]');
                            if (button) {button.click();}
                          ''');
                          loadingScreen(2, 2000);
                        }, 
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey[300]
                        ),
                        icon: const Icon(Icons.keyboard_double_arrow_right_rounded)
                      ),
                    ),
                  ],
                ),
              )
            ),
            //! PageButton
            Positioned(
              bottom: 0, right: 0,
              child: comicPattern.hasMatch(currentUrl)
              ? InkWell(
                child: Container(
                  margin: const EdgeInsets.all(10),
                  height: 30, width: 60,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(10)
                  ),
                  child: FittedBox(
                    fit: BoxFit.contain, 
                    child: Text(currentPage)
                  ),
                ),
                onTap: () {
                  setState(() => _listPageSelector = !_listPageSelector);
                },
              )
              : const SizedBox.shrink()
            ),
            //! Loading Screen
            Positioned.fill(
              child: _isLoadingChapter == 0
              ? const SizedBox.shrink()
              : Container(
                alignment: Alignment.center,
                color: Colors.black.withOpacity(0.4),
                child: Text(
                  _isLoadingChapter==1 ? "正在載入上一章" : "正在載入下一章",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white
                  ),
                ),
              )
            )
          ],
        ),
      ),
    );
  }

  Widget favoriteListWidget(BuildContext context) {
    if (!_favoritesLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_cachedFavorites.isEmpty) {
      return const Center(child: Text("沒有收藏的漫畫😢", style: TextStyle(color: Colors.white)));
    }
    
    List<String> filteredFavorites = filterFavoritesByGenre(_cachedFavorites, _selectedGenreFilter);
    
    print('📊 Debug info:');
    print('  Total favorites: ${_cachedFavorites.length}');
    print('  Available genres: $_cachedAvailableGenres');
    print('  First favorite sample: ${_cachedFavorites.isNotEmpty ? _cachedFavorites.first : "none"}');
          
    return Stack(
      children: [
        Column(
          children: [
            // Genre filter dropdown with update button
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
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.category, color: Colors.orange, size: 22),
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
                        onTap: _isRefreshingGenres ? null : () async {
                          setState(() {
                            _isRefreshingGenres = true;
                          });
                          print('🔄 Refresh button pressed!');
                          try {
                            // Update genres and check for new chapters
                            await Future.wait([
                              updateFavoritesWithGenres(),
                              checkAllFavoritesForNewChapters(),
                            ]);
                            _refreshFavoritesCache();
                            
                            // Show success message as overlay
                            if (mounted) {
                              _showTopNotification(
                                _newChapterCounts.isNotEmpty 
                                  ? "已更新！發現 ${_newChapterCounts.length} 部漫畫有新章節"
                                  : "已更新！所有漫畫都是最新的"
                              );
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
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                              ),
                            )
                          : const Icon(Icons.refresh, color: Colors.orange, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              // Filtered favorites list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                  itemCount: filteredFavorites.length,
                  itemBuilder: (context, index) {
                    String comicId = RegExp(r'ID: (\w+)').firstMatch(filteredFavorites[index])?.group(1) ?? 'unknown_$index';
                    return FavoriteListItem(
                      key: ValueKey(comicId), // Unique key based on comic ID
                      favorite: filteredFavorites[index],
                      index: index,
                      canDeleteIndex: _canDeleteIndex,
                onLongPress: (idx) {
                  setState(() {
                    _canDeleteIndex = _canDeleteIndex == idx ? null : idx;
                  });
                },
                onDelete: (favorite) {
                  removeFavorite(favorite);
                  setState(() => _addedToFavorite = false);
                },
                onTap: (favorite, comicId, hasNew, favoriteChapter) async {
                  String url = RegExp(r'URL: (https?://[^,]+)').firstMatch(favorite)!.group(1)!;
                  _controller.loadRequest(Uri.parse(url));
                  Navigator.of(context).pop();
                  setState(() => _scrollingDown = false);
                  
                  // Clear hasNew flag when user taps into the comic
                  if (hasNew && comicId.isNotEmpty) {
                    setState(() {
                      _newChapterCounts.remove(comicId);
                    });
                  }
                },
                hasNewChapters: hasNewChapters,
                getNewChapterCount: getNewChapterCount,
                getStoredComicProgress: getStoredComicProgress,
                    );
                  },
                ),
              ),
            ],
          ),
          // Loading overlay when refreshing genres
          if (_isRefreshingGenres)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                    ),
                    SizedBox(height: 16),
                    Text(
                      "更新分類中...",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
  }
}

class _AnimatedTopNotification extends StatefulWidget {
  final String message;
  final VoidCallback onComplete;

  const _AnimatedTopNotification({
    required this.message,
    required this.onComplete,
  });

  @override
  State<_AnimatedTopNotification> createState() => _AnimatedTopNotificationState();
}

class _AnimatedTopNotificationState extends State<_AnimatedTopNotification>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.0), // Start above screen
      end: const Offset(0, 0), // End at normal position
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));

    // Start animation
    _controller.forward();

    // Auto-dismiss after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _controller.reverse().then((_) {
          widget.onComplete();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 0,
      right: 0,
      child: Center(
        child: SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _opacityAnimation,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IntrinsicWidth(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        widget.message,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FavoriteListItem extends StatefulWidget {
  final String favorite;
  final int index;
  final int? canDeleteIndex;
  final Function(int) onLongPress;
  final Function(String) onDelete;
  final Function(String, String, bool, String) onTap;
  final bool Function(String) hasNewChapters;
  final int Function(String) getNewChapterCount;
  final Future<Map<String, dynamic>> Function(String) getStoredComicProgress;

  const FavoriteListItem({
    super.key,
    required this.favorite,
    required this.index,
    required this.canDeleteIndex,
    required this.onLongPress,
    required this.onDelete,
    required this.onTap,
    required this.hasNewChapters,
    required this.getNewChapterCount,
    required this.getStoredComicProgress,
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
    String comicId = RegExp(r'ID: (\w+)').firstMatch(widget.favorite)?.group(1) ?? '';
    if (comicId.isNotEmpty) {
      _checkWasUpToDate(comicId);
    }
  }
  
  Future<void> _checkWasUpToDate(String comicId) async {
    try {
      // Get cached chapter data
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? dataJson = prefs.getString('chapters_$comicId');
      
      if (dataJson != null) {
        var chapterData = jsonDecode(dataJson) as Map<String, dynamic>;
        List<dynamic> chapters = chapterData['chapters'] ?? [];
        
        if (chapters.isNotEmpty) {
          // Get the latest chapter title (first in descending order list)
          String latestChapterTitle = chapters.first['title'] ?? '';
          
          // Get the favoriteChapter (what user last watched)
          String favoriteChapter = RegExp(r'Chapter: ([^,]+)').firstMatch(widget.favorite)?.group(1) ?? '';
          
          // Exact comparison - if user's chapter exactly matches latest chapter, show gray border
          if (mounted && favoriteChapter.isNotEmpty && latestChapterTitle == favoriteChapter) {
            setState(() {
              wasUpToDate = true;
            });
          }
        }
      }
    } catch (e) {
      print('Error checking if was up to date: $e');
    }
  }

  Future<int> _calculateRemainingChapters(String comicId, String favoriteChapter) async {
    try {
      // Get cached chapter data
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? dataJson = prefs.getString('chapters_$comicId');
      
      if (dataJson != null) {
        var chapterData = jsonDecode(dataJson) as Map<String, dynamic>;
        List<dynamic> chapters = chapterData['chapters'] ?? [];
        
        if (chapters.isNotEmpty && favoriteChapter.isNotEmpty) {
          // Find user's current chapter position in the list
          int userPosition = -1;
          for (int i = 0; i < chapters.length; i++) {
            String chapterTitle = chapters[i]['title'] ?? '';
            if (chapterTitle.contains(favoriteChapter)) {
              userPosition = i;
              break;
            }
          }
          
          // Calculate remaining chapters (chapters before user's position since list is descending)
          if (userPosition > 0) {
            return userPosition; // Number of chapters before current position
          }
        }
      }
    } catch (e) {
      print('Error calculating remaining chapters: $e');
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    String favoriteName = RegExp(r'漫畫: ([^,]+)').firstMatch(widget.favorite)?.group(1) ?? "Undefine";
    String favoriteChapter = RegExp(r'Chapter: ([^,]+)').firstMatch(widget.favorite)?.group(1) ?? "Undefine";
    String favoritePage = RegExp(r'Page: ([^,]+)').firstMatch(widget.favorite)?.group(1) ?? "Undefine";
    String favoriteCover = RegExp(r'Cover: (https?://[^\s]+)').firstMatch(widget.favorite)?.group(1) ?? "Unknow";
    String comicId = RegExp(r'ID: (\w+)').firstMatch(widget.favorite)?.group(1) ?? '';
    bool hasNew = widget.hasNewChapters(comicId);
    int newCount = widget.getNewChapterCount(comicId);
    
    // Calculate remaining chapters if no new updates but not caught up
    if (!hasNew && !wasUpToDate && !showRemaining) {
      _calculateRemainingChapters(comicId, favoriteChapter).then((count) {
        if (mounted && count > 0) {
          setState(() {
            remainingCount = count;
            showRemaining = true;
          });
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
              onTap: () async {
                await widget.onTap(widget.favorite, comicId, hasNew, favoriteChapter);
              },
              onLongPress: () {
                widget.onLongPress(widget.index);
              },
              child: ListTile(
                contentPadding: const EdgeInsets.only(left: 10, top: 5, bottom: 5, right: 0),
                visualDensity: const VisualDensity(horizontal: 0, vertical: 2),

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: hasNew ? Colors.orange : (wasUpToDate ? Colors.grey : Colors.white), 
                    width: hasNew ? 2.5 : 1.5
                  )
                ),

                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      favoriteName, 
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, height: 1, color: Colors.white)
                    ),
                    Wrap(
                      children: [
                        const Text(
                          '上次看到 ',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                        ),
                        Text(
                          '$favoriteChapter 第$favoritePage頁',
                          style: const TextStyle(fontSize: 11, color: Colors.white54),
                        )
                      ],
                    ),
                  ],
                ),

                leading: favoriteCover != 'Unknow'
                  ? Image.network(favoriteCover, fit: BoxFit.cover)
                  : const Icon(Icons.error_outline),
                
                trailing: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: widget.canDeleteIndex == widget.index ? 1.0 : 0.0,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 200),
                    scale: widget.canDeleteIndex == widget.index ? 1.0 : 0.0,
                    child: Transform.translate(
                      offset: Offset(0, wasUpToDate ? 0 : -10), // Move 8 pixels upward
                      child: IconButton(
                        icon: Icon(Icons.delete_forever, color: Colors.red[400], size: 35),
                        onPressed: widget.canDeleteIndex == widget.index ? () {
                          widget.onDelete(widget.favorite);
                        } : null,
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          ],
        ),
      ),
    );
  }
}

