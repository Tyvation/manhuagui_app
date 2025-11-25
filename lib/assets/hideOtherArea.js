// Enhanced script to reliably show only the manga reader area and hide navigation panels.
(function () {
  'use strict';

  var maxRetries = 50;
  var retryDelay = 100;
  var maxWaitTime = 10000;
  var startTime = Date.now();

  var extraPanelSelectors = [
    '.manga-panel-prev',
    '.manga-panel-next',
    '.manga-panel-prev.manga-panel-on',
    '.manga-panel-next.manga-panel-on',
    '#prev',
    '#next'
  ];

  (function injectPanelHidingCss() {
    if (document.getElementById('__mangaPanelHideStyle')) {
      return;
    }
    var css = extraPanelSelectors.join(', ') + `{
      opacity: 0 !important;
      background: transparent !important;
      color: transparent !important;
      border: none !important;
    }`;
    var style = document.createElement('style');
    style.id = '__mangaPanelHideStyle';
    style.type = 'text/css';
    style.textContent = css;
    (document.head || document.documentElement).appendChild(style);
  })();

  function hideExtraPanels() {
    extraPanelSelectors.forEach(function (selector) {
      document.querySelectorAll(selector).forEach(function (element) {
        element.style.opacity = '0';
        element.style.background = 'transparent';
        element.style.color = 'transparent';
        element.style.border = 'none';
        element.style.visibility = 'visible';
        element.style.pointerEvents = 'auto';
      });
    });
  }

  function applyMangaOnlyStyle(targetElement) {
    try {
      document.querySelectorAll('body > *:not(.manga-box)').forEach(function (element) {
        element.style.display = 'none';
      });

      document.body.style.display = 'flex';
      document.body.style.flexDirection = 'column';
      document.body.style.justifyContent = 'center';
      document.body.style.alignItems = 'center';
      document.body.style.minHeight = '100vh';
      document.body.style.margin = '0';
      document.body.style.overflowY = 'auto';

      targetElement.style.paddingTop = '40px';
      targetElement.style.maxWidth = '100%';
      targetElement.style.boxSizing = 'border-box';
      targetElement.style.display = 'block';
      targetElement.style.visibility = 'visible';

      hideExtraPanels();

      console.log('✅ Manga-only mode applied successfully');
      return true;
    } catch (error) {
      console.warn('Error applying manga-only style:', error);
      return false;
    }
  }

  function hideIndicatorsInNode(node) {
    if (!node || node.nodeType !== 1) {
      return;
    }

    if (node.matches) {
      extraPanelSelectors.forEach(function (selector) {
        if (node.matches(selector)) {
          node.style.opacity = '0';
          node.style.background = 'transparent';
          node.style.color = 'transparent';
          node.style.border = 'none';
          node.style.visibility = 'visible';
          node.style.pointerEvents = 'auto';
        }
      });
    }

    if (node.querySelectorAll) {
      extraPanelSelectors.forEach(function (selector) {
        node.querySelectorAll(selector).forEach(function (element) {
          element.style.opacity = '0';
          element.style.background = 'transparent';
          element.style.color = 'transparent';
          element.style.border = 'none';
          element.style.visibility = 'visible';
          element.style.pointerEvents = 'auto';
        });
      });
    }
  }

  function waitForMangaBox(attempt) {
    attempt = attempt || 0;
    var targetElement = document.querySelector('.manga-box');

    if (Date.now() - startTime > maxWaitTime) {
      console.warn('⏳ Timeout: manga-box element not found within', maxWaitTime, 'ms');
      return;
    }

    if (targetElement && targetElement.offsetHeight > 0) {
      if (applyMangaOnlyStyle(targetElement)) {
        return;
      }
    }

    if (attempt < maxRetries) {
      setTimeout(function () {
        waitForMangaBox(attempt + 1);
      }, retryDelay);
    } else {
      console.warn('⚠️ Max retries exceeded, manga-box element not found');
    }
  }

  function handleMutations(mutations) {
    mutations.forEach(function (mutation) {
      mutation.addedNodes.forEach(function (node) {
        if (node.nodeType !== 1) {
          return;
        }

        if (node.classList && node.classList.contains('manga-box')) {
          console.log('📦 Manga-box detected via mutation observer');
          applyMangaOnlyStyle(node);
        } else if (node.querySelector) {
          var mangaBox = node.querySelector('.manga-box');
          if (mangaBox) {
            console.log('🔍 Manga-box found inside added content');
            applyMangaOnlyStyle(mangaBox);
          }
        }

        hideIndicatorsInNode(node);
      });
    });
  }

  var observer = new MutationObserver(handleMutations);
  observer.observe(document.body, {
    childList: true,
    subtree: true
  });

  console.log('🔎 Starting manga-box search...');

  var immediateTarget = document.querySelector('.manga-box');
  if (immediateTarget && immediateTarget.offsetHeight > 0) {
    console.log('✅ Manga-box found immediately');
    applyMangaOnlyStyle(immediateTarget);
  } else {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', function () {
        setTimeout(function () {
          waitForMangaBox();
        }, 100);
      });
    } else {
      waitForMangaBox();
    }
  }

  setTimeout(function () {
    var finalTarget = document.querySelector('.manga-box');
    if (finalTarget && finalTarget.style.display !== 'block') {
      console.log('🛠️ Final fallback: manga-box found');
      applyMangaOnlyStyle(finalTarget);
    }
    hideExtraPanels();
  }, 3000);

  setInterval(hideExtraPanels, 500);
})();
