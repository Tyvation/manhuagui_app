// Enhanced script to reliably show manga box only
(function() {
  'use strict';
  
  var maxRetries = 50; // Maximum number of retry attempts
  var retryDelay = 100; // Delay between retries in milliseconds
  var maxWaitTime = 10000; // Maximum total wait time (10 seconds)
  var startTime = Date.now();
  
  // Function to apply manga-only styling
  function applyMangaOnlyStyle(targetElement) {
    try {
      // Hide all other elements except manga-box
      document.querySelectorAll('body > *:not(.manga-box)').forEach(element => {
        element.style.display = "none";
      });

      // Style the body
      document.body.style.display = 'flex';
      document.body.style.flexDirection = 'column';
      document.body.style.justifyContent = 'center';
      document.body.style.alignItems = 'center';
      document.body.style.minHeight = '100vh';
      document.body.style.margin = '0';
      document.body.style.overflowY = 'auto';

      // Style the manga box
      targetElement.style.paddingTop = '40px';
      targetElement.style.maxWidth = '100%';
      targetElement.style.boxSizing = 'border-box';
      targetElement.style.display = 'block';
      targetElement.style.visibility = 'visible';
      
      console.log('✓ Manga-only mode applied successfully');
      return true;
    } catch (error) {
      console.warn('Error applying manga-only style:', error);
      return false;
    }
  }
  
  // Function to wait for manga-box element
  function waitForMangaBox(attempt = 0) {
    var targetElement = document.querySelector('.manga-box');
    
    // Check if we've exceeded maximum wait time
    if (Date.now() - startTime > maxWaitTime) {
      console.warn('⚠ Timeout: manga-box element not found within', maxWaitTime, 'ms');
      return;
    }
    
    if (targetElement && targetElement.offsetHeight > 0) {
      // Element found and has dimensions, apply styling
      if (applyMangaOnlyStyle(targetElement)) {
        return; // Success, exit
      }
    }
    
    // Element not found or styling failed, retry
    if (attempt < maxRetries) {
      setTimeout(() => waitForMangaBox(attempt + 1), retryDelay);
    } else {
      console.warn('⚠ Max retries exceeded, manga-box element not found');
    }
  }
  
  // Function to handle new manga-box elements (for dynamic loading)
  function handleMutations(mutations) {
    mutations.forEach(mutation => {
      mutation.addedNodes.forEach(node => {
        if (node.nodeType === 1) { // Element node
          // Check if the added node is manga-box or contains manga-box
          if (node.classList && node.classList.contains('manga-box')) {
            console.log('✓ Manga-box detected via mutation observer');
            applyMangaOnlyStyle(node);
          } else if (node.querySelector) {
            var mangaBox = node.querySelector('.manga-box');
            if (mangaBox) {
              console.log('✓ Manga-box found in added content');
              applyMangaOnlyStyle(mangaBox);
            }
          }
        }
      });
    });
  }
  
  // Set up mutation observer to watch for dynamically added manga-box
  var observer = new MutationObserver(handleMutations);
  observer.observe(document.body, { 
    childList: true, 
    subtree: true 
  });
  
  // Start the waiting process
  console.log('🔍 Starting manga-box search...');
  
  // Try immediate execution first
  var immediateTarget = document.querySelector('.manga-box');
  if (immediateTarget && immediateTarget.offsetHeight > 0) {
    console.log('✓ Manga-box found immediately');
    applyMangaOnlyStyle(immediateTarget);
  } else {
    // If not found immediately, start waiting
    if (document.readyState === 'loading') {
      // DOM still loading, wait for DOMContentLoaded
      document.addEventListener('DOMContentLoaded', () => {
        setTimeout(() => waitForMangaBox(), 100);
      });
    } else {
      // DOM already loaded, start waiting immediately
      waitForMangaBox();
    }
  }
  
  // Also try after a longer delay as final fallback
  setTimeout(() => {
    var finalTarget = document.querySelector('.manga-box');
    if (finalTarget && finalTarget.style.display !== 'block') {
      console.log('✓ Final fallback: manga-box found');
      applyMangaOnlyStyle(finalTarget);
    }
  }, 3000);
  
})();