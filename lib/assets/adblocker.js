// Aggressive ad blocking script injected into the WebView.
(function () {
  var adSelectors = [
    'iframe',
    '[id*="ad"]',
    '[class*="gg"]',
    '[class*="HF"]',
    '[class*="sitemaji"]',
    '[class*="ads"]',
    '[href*="ad"]',
    '[href*="click"]',
    '[src*="doubleclick.net"]',
    '[src*="ad"]',
    '[src*="adservice.google"]',
    '[src*="sitemaji.com"]',
    '.clickforceads'
  ];

  var whitelistSelectors = [
    '.manga-loading',
    '[src*="webp"]'
  ];

  var firstIntroDivRemoved = false;

  function releasePrehide() {
    if (document.documentElement && document.documentElement.classList.contains('adblock-prehide')) {
      document.documentElement.classList.remove('adblock-prehide');
    }
  }

  function isWhitelisted(element) {
    return whitelistSelectors.some(function (selector) {
      try {
        return element.matches(selector);
      } catch (err) {
        return false;
      }
    });
  }

  function removeAdsInNode(root) {
    adSelectors.forEach(function (selector) {
      root.querySelectorAll(selector).forEach(function (element) {
        if (!isWhitelisted(element)) {
          element.remove();
        }
      });
    });

    if (!firstIntroDivRemoved) {
      var introDiv = root.querySelector('.book-intro.book-intro-more + div');
      if (introDiv) {
        introDiv.remove();
        firstIntroDivRemoved = true;
      }
    }
  }

  function initialAdCleanup() {
    if (!document.body) {
      return;
    }

    removeAdsInNode(document);

    var mangaBox = document.querySelector('.manga-box');
    if (mangaBox) {
      document.querySelectorAll('body > *:not(.manga-box)').forEach(function (element) {
        element.style.display = 'none';
      });
    }

    releasePrehide();
  }

  function handleMutations(mutations) {
    mutations.forEach(function (mutation) {
      mutation.addedNodes.forEach(function (node) {
        if (node.nodeType !== 1) {
          return;
        }

        if (!isWhitelisted(node)) {
          removeAdsInNode(node);
        }

        var mangaBox = document.querySelector('.manga-box');
        if (mangaBox && document.body.contains(mangaBox)) {
          document.querySelectorAll('body > *:not(.manga-box)').forEach(function (element) {
            element.style.display = 'none';
          });
        }

        releasePrehide();
      });
    });
  }

  function rapidCleanup(iterations) {
    if (iterations <= 0) {
      return;
    }

    initialAdCleanup();
    requestAnimationFrame(function () {
      rapidCleanup(iterations - 1);
    });
  }

  function startObserver() {
    if (!document.body) {
      requestAnimationFrame(startObserver);
      return;
    }

    initialAdCleanup();
    rapidCleanup(5);

    var observer = new MutationObserver(handleMutations);
    observer.observe(document.body, { childList: true, subtree: true });
  }

  startObserver();

  window.addEventListener('load', function () {
    rapidCleanup(2);
    releasePrehide();
  });
})();
