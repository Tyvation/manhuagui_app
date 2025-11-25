import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AdBlocker {
  String? _adblockerJS;
  String? _hideOtherAreaJS;

  Future<void> loadJsFiles() async {
    _adblockerJS = await rootBundle.loadString('lib/assets/adblocker.js');
    _hideOtherAreaJS =
        await rootBundle.loadString('lib/assets/hideOtherArea.js');
  }

  Future<void> injectAdBlockingCSS(WebViewController controller) async {
    await controller.runJavaScript('''
      (function() {
        if (!window.__adBlockPreHideApplied) {
          document.documentElement.classList.add('adblock-prehide');
          window.__adBlockPreHideApplied = true;
        }

        if (!window.__adBlockPreHideReleaseScheduled) {
          window.__adBlockPreHideReleaseScheduled = true;
          setTimeout(function() {
            document.documentElement.classList.remove('adblock-prehide');
            window.__adBlockPreHideApplied = false;
            window.__adBlockPreHideReleaseScheduled = false;
          }, 2000);
        }

        var baseCss = `
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

        var prehideCss = `
          html.adblock-prehide body {
            visibility: hidden !important;
          }
          html.adblock-prehide .manga-box,
          html.adblock-prehide .manga-box * {
            visibility: visible !important;
          }
        `;

        var styleEl = document.getElementById('__adblockStyle');
        if (!styleEl) {
          styleEl = document.createElement('style');
          styleEl.id = '__adblockStyle';
          styleEl.type = 'text/css';
          (document.head || document.documentElement).appendChild(styleEl);
        }

        styleEl.innerHTML = baseCss + prehideCss;
      })();
    ''');
  }

  Future<void> hideAds(WebViewController controller) async {
    if (_adblockerJS != null) {
      await controller.runJavaScript(_adblockerJS!);
    }
  }

  Future<void> showMangaBoxOnly(WebViewController controller) async {
    if (_hideOtherAreaJS != null) {
      await controller.runJavaScript(_hideOtherAreaJS!);
    }

    // Backup retry mechanism - check if manga-box is visible after a delay
    Future.delayed(const Duration(milliseconds: 1500), () async {
      try {
        var result = await controller.runJavaScriptReturningResult('''
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
          // print('⚠ Manga box not properly visible, retrying...');
          if (_hideOtherAreaJS != null) {
            await controller.runJavaScript(_hideOtherAreaJS!);
          }

          // Final retry after another delay
          Future.delayed(const Duration(milliseconds: 1000), () async {
            await controller.runJavaScript('''
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
        // print('Error checking manga box visibility: $e');
      }
    });
  }
}
