// Common ad selectors to hide
var adSelectors = [
  'iframe',                // Ad iframes
  '[id*="ad"]',            // IDs containing 'ad'
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
  '.clickforceads',
];

// Whitelisted selectors (e.g., manga images)
var whitelistSelectors = [
  '.manga-loading',          // Example class for manga images
  '[src*="webp"]',        // Example pattern for manga images
];

// Track if the first `.book-intro.book-intro-more + div` is removed
var firstDivRemoved = false;

// Function to remove initial ads and the first div
function initialAdCleanup() {
  adSelectors.forEach(selector => {
    document.querySelectorAll(selector).forEach(element => {
      if (!isWhitelisted(element)) {
        element.remove();
      }
    });
  });

  if (!firstDivRemoved) {
    const t = document.querySelector('.book-intro.book-intro-more + div');
    if (t) {
      t.remove();
      firstDivRemoved = true;
    }
  }
}

// Function to check if an element matches whitelisted selectors
function isWhitelisted(element) {
  return whitelistSelectors.some(whitelistSelector => element.matches(whitelistSelector));
}

// Function to handle mutations (dynamic ads)
function handleMutations(mutations) {
  mutations.forEach(mutation => {
    mutation.addedNodes.forEach(node => {
      if (node.nodeType === 1){
        if (adSelectors.some(selector => node.matches(selector)) && !isWhitelisted(node)) {node.remove();}
        if (document.body.contains(document.querySelector('.manga-box'))){
          document.querySelectorAll('body > *:not(.manga-box)').forEach(element => {
            element.style.display = "none"; // 隱藏非目標區域
          });
        }
      }
    });
  });
}

// Run the initial cleanup for static ads
initialAdCleanup();

// Create and set up the MutationObserver
var observer = new MutationObserver(handleMutations);
observer.observe(document.body, { childList: true, subtree: true });
