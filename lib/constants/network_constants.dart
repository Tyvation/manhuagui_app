class NetworkConstants {
  static const String userAgent = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36';

  static const String referer = 'https://m.manhuagui.com/';

  static const Duration crawlDelay = Duration(seconds: 4);

  static const Map<String, String> defaultHeaders = {
    'User-Agent': userAgent,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Accept-Encoding': 'gzip, deflate',
    'Referer': referer,
  };
}
