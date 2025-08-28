import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

class ChapterFetcher {
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

  static String extractComicIdFromUrl(String url) {
    var match = RegExp(r'/comic/(\d+)').firstMatch(url);
    return match?.group(1) ?? '';
  }

  static Future<Map<String, dynamic>> fetchChapterList(String detailUrl) async {
    print("fetching: $detailUrl");
    String comicId = extractComicIdFromUrl(detailUrl);

    try {
      final response = await http.get(
        Uri.parse(detailUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          'Accept-Encoding': 'gzip, deflate',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
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
                  'url': href.startsWith('http')
                      ? href
                      : 'https://m.manhuagui.com$href'
                });
              }
            }
          }

          print("Chapter Count: ${data['count']}");
        } else {
          print("Chapter Count: 0 (no chapter list found)");
        }

        return data;
      } else {
        print("Failed to fetch: ${response.statusCode}");
        return {
          'count': 0,
          'chapters': <Map<String, String>>[],
          'comicId': comicId
        };
      }
    } catch (e) {
      print('Error in background fetch: $e');
      return {
        'count': 0,
        'chapters': <Map<String, String>>[],
        'comicId': comicId
      };
    }
  }

  static Future<String> extractComicGenres(String detailUrl) async {
    try {
      print('🔍 Fetching genres from: $detailUrl');
      final response = await http.get(
        Uri.parse(detailUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        var genreList = <String>[];

        print('📄 Page loaded, searching for genres...');

        // Approach 1: Look for all dl elements
        var dlElements = document.querySelectorAll('dl');

        for (var dl in dlElements) {
          var dtElements = dl.querySelectorAll('dt');
          for (var dt in dtElements) {
            if (dt.text.contains('类别') || dt.text.contains('類別')) {
              var dd = dt.nextElementSibling;
              if (dd != null && dd.localName == 'dd') {
                var genreLinks = dd.querySelectorAll('a');
                for (var link in genreLinks) {
                  String genreName =
                      link.attributes['title'] ?? link.text.trim();
                  if (genreName.isNotEmpty) {
                    String translatedGenre =
                        genreTranslationMap[genreName] ?? genreName;
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
          var genreText = response.body;
          var genreRegex =
              RegExp(r'类别[：:][^<]*<dd[^>]*>(.*?)</dd>', multiLine: true);
          var match = genreRegex.firstMatch(genreText);
          if (match != null) {
            var linkRegex = RegExp(r'<a[^>]*title="([^"]+)"[^>]*>([^<]+)</a>');
            var linkMatches = linkRegex.allMatches(match.group(1) ?? '');
            for (var linkMatch in linkMatches) {
              String genreName = linkMatch.group(1) ?? linkMatch.group(2) ?? '';
              if (genreName.isNotEmpty) {
                String translatedGenre =
                    genreTranslationMap[genreName] ?? genreName;
                genreList.add(translatedGenre);
              }
            }
          }
        }

        return genreList.join(',');
      }
    } catch (e) {
      print('❌ Error extracting genres: $e');
    }

    return '';
  }
}
