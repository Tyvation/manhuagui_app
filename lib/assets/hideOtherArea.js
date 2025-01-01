// 顯示特定區域
document.querySelectorAll('body > *:not(.manga-box)').forEach(element => {
  element.style.display = "none"; // 隱藏非目標區域
});

var targetElement = document.querySelector('.manga-box'); // 替換為你想顯示的區域選擇器

if (targetElement) {
  document.body.style.display = 'flex';
  document.body.style.flexDirection = 'column';
  document.body.style.justifyContent = 'center'; // Space between top and bottom
  document.body.style.alignItems = 'center'; // Horizontally center
  document.body.style.minHeight = '100vh'; // Ensure the body spans the viewport height
  document.body.style.margin = '0'; // Remove default margin
  document.body.style.overflowY = 'auto'; // Enable scrolling for overflow content

// Adjust the child content to ensure it behaves properly
targetElement.style.paddingTop = '40px';
  targetElement.style.maxWidth = '100%'; // Prevent overflowing horizontally
  targetElement.style.boxSizing = 'border-box'; // Ensure proper box model behavior
}