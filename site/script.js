'use strict';
const messages = {
  "zh": {
    "skip": "跳到正文",
    "nav": "主导航",
    "featuresLink": "功能",
    "downloadLink": "下载",
    "title": "macOS 剪贴板历史工具",
    "intro": "记录复制过的文字、图片和文件。\n搜索、查看结果，再粘贴回原来的应用。",
    "downloadButton": "下载 TinyCopy",
    "requirements": "macOS 14 及以上 · Apple 芯片与 Intel",
    "carouselLabel": "功能示例",
    "zoomHeroocr": "放大图片识别示例",
    "altHeroocr": "图片识别示例",
    "slide0": "从图片提取文字，原图和结果同时保留。",
    "zoomHerojson": "放大JSON示例",
    "altHerojson": "JSON示例",
    "slide1": "查看格式化结果，选择后即可复制或粘贴。",
    "zoomHerotranslation": "放大翻译示例",
    "altHerotranslation": "翻译示例",
    "slide2": "原文与译文一起显示，按左右键选择使用哪份内容。",
    "slidesLabel": "选择示例",
    "tab0": "图片识别",
    "tab1": "JSON",
    "tab2": "翻译",
    "shortcut": "打开，↑↓ 选记录，←→ 选内容，↩ 粘贴。",
    "featureHeading": "主要功能",
    "historyTitle": "历史、搜索和收藏",
    "historyDescription": "文字、富文本、图片和文件都可记录。重复复制的内容移到顶部，历史在重启后保留。",
    "historyNote": "按类型筛选，也能搜索识别文字、译文和解码结果。常用内容可收藏，单独筛选。",
    "zoomFeaturehistory": "放大历史、搜索和收藏界面",
    "altFeaturehistory": "历史、搜索和收藏界面",
    "jsonTitle": "JSON、解码和时间转换",
    "jsonDescription": "格式化或压缩 JSON，解码 JWT、Base64 和 URL 编码文本，将 Unix 时间戳转成日期。",
    "jsonNote": "原始内容和结果同时显示，只有选中并确认后才会使用处理结果。",
    "zoomFeaturejson": "放大JSON、解码和时间转换界面",
    "altFeaturejson": "JSON、解码和时间转换界面",
    "translationTitle": "系统翻译",
    "translationDescription": "选中外语正文即可查看原文与译文，再选择复制或粘贴。",
    "translationNote": "使用 macOS 系统翻译。需要 macOS 15 及以上，首次使用某种语言时可能需下载语言包。",
    "zoomFeaturetranslation": "放大系统翻译界面",
    "altFeaturetranslation": "系统翻译界面",
    "ocrTitle": "图片文字识别",
    "ocrDescription": "从截图、会议通知等图片中提取文字，识别结果可搜索、复制或粘贴。",
    "ocrNote": "识别在本机完成，原始图片保留。",
    "zoomFeatureocr": "放大图片文字识别界面",
    "altFeatureocr": "图片文字识别界面",
    "qrTitle": "二维码",
    "qrDescription": "提取图片中的二维码内容，或将网址生成二维码图片。",
    "qrNote": "识别结果不会自动打开；生成的二维码可直接复制或粘贴。",
    "zoomFeatureqr": "放大二维码界面",
    "altFeatureqr": "二维码界面",
    "getTitle": "下载 TinyCopy",
    "getDescription": "macOS 14 及以上，支持 Apple 芯片与 Intel Mac。",
    "getDownload": "下载最新版（DMG）",
    "viewProject": "查看项目 ↗",
    "install": "打开 DMG，将 TinyCopy 拖入“应用程序”文件夹即可。应用已签名并通过 Apple 公证。",
    "permission": "自动粘贴需要辅助功能权限；未授权时仍可复制，再自行按 ⌘V。历史仅保存在本机，默认不记录被标记为保密或临时的内容。",
    "zoomDialog": "截图大图",
    "close": "关闭 ×",
    "languageSwitch": "切换为 English",
    "themeSystem": "外观：跟随系统，点击切换为浅色",
    "themeLight": "外观：浅色，点击切换为深色",
    "themeDark": "外观：深色，点击跟随系统",
    "pause": "暂停自动切换",
    "play": "继续自动切换"
  },
  "en": {
    "skip": "Skip to content",
    "nav": "Navigation",
    "featuresLink": "Features",
    "downloadLink": "Download",
    "title": "Clipboard history for macOS",
    "intro": "Keep copied text, images and files.\nSearch your history, preview the results, and paste them back.",
    "downloadButton": "Download TinyCopy",
    "requirements": "macOS 14 or later · Apple silicon and Intel",
    "carouselLabel": "Feature examples",
    "zoomHeroocr": "Enlarge Text recognition example",
    "altHeroocr": "Text recognition example",
    "slide0": "Extract text from an image while keeping the original.",
    "zoomHerojson": "Enlarge JSON example",
    "altHerojson": "JSON example",
    "slide1": "Preview formatted JSON, then copy or paste it.",
    "zoomHerotranslation": "Enlarge Translation example",
    "altHerotranslation": "Translation example",
    "slide2": "See the original and translation together, then choose which to use.",
    "slidesLabel": "Choose an example",
    "tab0": "Text recognition",
    "tab1": "JSON",
    "tab2": "Translation",
    "shortcut": "to open, ↑↓ to choose a record, ←→ to choose content, ↩ to paste.",
    "featureHeading": "Features",
    "historyTitle": "History, search and favorites",
    "historyDescription": "Keep text, rich text, images and files across restarts. Repeated copies move to the top.",
    "historyNote": "Filter by type or search recognized text, translations and decoded content. Save frequently used records as favorites.",
    "zoomFeaturehistory": "Enlarge History, search and favorites screenshot",
    "altFeaturehistory": "History, search and favorites screenshot",
    "jsonTitle": "JSON, decoding and timestamps",
    "jsonDescription": "Format or minify JSON, decode JWT, Base64 and URL-encoded text, and turn Unix timestamps into dates.",
    "jsonNote": "The original and result stay visible together. A result is used only when you select and confirm it.",
    "zoomFeaturejson": "Enlarge JSON, decoding and timestamps screenshot",
    "altFeaturejson": "JSON, decoding and timestamps screenshot",
    "translationTitle": "Apple translation",
    "translationDescription": "See the original and translation together, then choose which to copy or paste.",
    "translationNote": "Uses Apple translation on macOS 15 or later. A language pack may need to be downloaded on first use.",
    "zoomFeaturetranslation": "Enlarge Apple translation screenshot",
    "altFeaturetranslation": "Apple translation screenshot",
    "ocrTitle": "Text recognition",
    "ocrDescription": "Extract text from screenshots, meeting notices and other images. Search, copy or paste the recognized text.",
    "ocrNote": "Recognition runs on this Mac and keeps the original image.",
    "zoomFeatureocr": "Enlarge Text recognition screenshot",
    "altFeatureocr": "Text recognition screenshot",
    "qrTitle": "QR codes",
    "qrDescription": "Extract QR content from images, or generate a QR image from a URL.",
    "qrNote": "Detected links are not opened automatically. Generated QR images can be copied or pasted.",
    "zoomFeatureqr": "Enlarge QR codes screenshot",
    "altFeatureqr": "QR codes screenshot",
    "getTitle": "Get TinyCopy",
    "getDescription": "For macOS 14 or later, on Apple silicon and Intel Macs.",
    "getDownload": "Download the latest DMG",
    "viewProject": "View on GitHub ↗",
    "install": "Open the DMG and drag TinyCopy into Applications. The app is signed and notarized by Apple.",
    "permission": "Automatic pasting requires Accessibility permission. Without it, content is copied and you press ⌘V yourself. History stays on this Mac; concealed and transient content is ignored by default.",
    "zoomDialog": "Screenshot preview",
    "close": "Close ×",
    "languageSwitch": "切换为中文",
    "themeSystem": "Appearance: system. Switch to light.",
    "themeLight": "Appearance: light. Switch to dark.",
    "themeDark": "Appearance: dark. Follow system.",
    "pause": "Pause slideshow",
    "play": "Resume slideshow"
  }
};
const root = document.documentElement;
const languageButton = document.getElementById('language');
const themeButton = document.getElementById('theme');
const tabs = [...document.querySelectorAll('[data-slide]')];
const slides = [...document.querySelectorAll('.hero-slide')];
const caption = document.querySelector('.slide-caption');
const showcase = document.getElementById('showcase');
const stage = document.querySelector('.carousel-stage');
const autoplayButton = document.getElementById('autoplay');
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
let languageMode = 'auto';
try { languageMode = localStorage.getItem('tinycopy-language') || 'auto'; } catch (_) {}
let currentLanguage = 'zh';
let currentSlide = 0;
let autoplay = !reducedMotion.matches;
let timer, inView = false, hovered = false, focused = false;
function strings() { return messages[currentLanguage]; }
function updateControls() {
  languageButton.title = languageButton.ariaLabel = strings().languageSwitch;
  const theme = root.dataset.theme || 'system';
  themeButton.title = themeButton.ariaLabel = strings()['theme' + theme[0].toUpperCase() + theme.slice(1)];
  document.querySelectorAll('[data-theme-icon]').forEach(icon => { icon.hidden = icon.dataset.themeIcon !== theme; });
  autoplayButton.title = autoplayButton.ariaLabel = strings()[autoplay ? 'pause' : 'play'];
  autoplayButton.setAttribute('aria-pressed', String(!autoplay));
  autoplayButton.querySelector('.pause-icon').hidden = !autoplay;
  autoplayButton.querySelector('.play-icon').hidden = autoplay;
}
function applyLanguage() {
  currentLanguage = ['zh','en'].includes(languageMode) ? languageMode : (/^zh/i.test(navigator.languages?.[0] || navigator.language || 'en') ? 'zh' : 'en');
  root.lang = currentLanguage === 'zh' ? 'zh-CN' : 'en';
  document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = strings()[el.dataset.i18n]; });
  document.querySelectorAll('[data-i18n-aria]').forEach(el => { el.setAttribute('aria-label',strings()[el.dataset.i18nAria]); });
  document.querySelectorAll('[data-i18n-alt]').forEach(el => { el.alt = strings()[el.dataset.i18nAlt]; });
  document.title = currentLanguage === 'zh' ? 'TinyCopy — macOS 剪贴板历史工具' : 'TinyCopy — Clipboard history for macOS';
  updateControls();
}
languageButton.addEventListener('click', () => {
  languageMode = currentLanguage === 'zh' ? 'en' : 'zh';
  try { localStorage.setItem('tinycopy-language', languageMode); } catch (_) {}
  applyLanguage();
});
window.addEventListener('languagechange', () => { if (!['zh','en'].includes(languageMode)) applyLanguage(); });
themeButton.addEventListener('click', () => {
  const themes = ['system','light','dark'];
  const next = themes[(themes.indexOf(root.dataset.theme || 'system') + 1) % 3];
  if (next === 'system') delete root.dataset.theme; else root.dataset.theme = next;
  try { localStorage.setItem('tinycopy-theme', next); } catch (_) {}
  updateControls();
});
function schedule() {
  clearTimeout(timer);
  if (autoplay && inView && !hovered && !focused && !document.hidden && !zoom.open) timer = setTimeout(() => { showSlide(currentSlide + 1); }, 6000);
}
function showSlide(index, manual = false) {
  currentSlide = (index + slides.length) % slides.length;
  if (manual) autoplay = false;
  slides.forEach((slide,i) => { slide.hidden = i !== currentSlide; });
  tabs.forEach((tab,i) => { tab.setAttribute('aria-selected',String(i === currentSlide)); tab.tabIndex = i === currentSlide ? 0 : -1; });
  caption.dataset.i18n = 'slide' + currentSlide;
  caption.textContent = strings()[caption.dataset.i18n];
  updateControls(); schedule();
}
tabs.forEach((tab,i) => {
  tab.addEventListener('click', () => showSlide(i,true));
  tab.addEventListener('keydown', event => {
    let index;
    if (event.key === 'ArrowRight') index = (i+1)%tabs.length;
    else if (event.key === 'ArrowLeft') index = (i+tabs.length-1)%tabs.length;
    else if (event.key === 'Home') index = 0;
    else if (event.key === 'End') index = tabs.length-1;
    else return;
    event.preventDefault(); showSlide(index,true); tabs[index].focus();
  });
});
stage.addEventListener('keydown', event => {
  if (event.key === 'ArrowRight' || event.key === 'ArrowLeft') { event.preventDefault(); showSlide(currentSlide + (event.key === 'ArrowRight' ? 1 : -1),true); }
});
autoplayButton.addEventListener('click', () => { autoplay = !autoplay; updateControls(); schedule(); });
showcase.addEventListener('mouseenter', () => { hovered = true; schedule(); });
showcase.addEventListener('mouseleave', () => { hovered = false; schedule(); });
showcase.addEventListener('focusin', () => { focused = true; schedule(); });
showcase.addEventListener('focusout', event => { focused = showcase.contains(event.relatedTarget); schedule(); });
document.addEventListener('visibilitychange', schedule);
reducedMotion.addEventListener('change', () => { if (reducedMotion.matches) { autoplay = false; updateControls(); schedule(); } });
if ('IntersectionObserver' in window) new IntersectionObserver(entries => { inView = entries[0].isIntersecting; schedule(); },{threshold:0.15}).observe(showcase);
const zoom = document.getElementById('zoom');
let previousFocus;
document.querySelectorAll('[data-zoom]').forEach(button => {
  button.addEventListener('click', () => {
    const image = [...button.querySelectorAll('img')].find(img => getComputedStyle(img).display !== 'none');
    if (!image) return;
    previousFocus = button;
    zoom.querySelector('img').src = image.src; zoom.querySelector('img').alt = image.alt;
    zoom.showModal(); schedule();
  });
});
zoom.querySelector('.zoom-close').addEventListener('click', () => zoom.close());
zoom.addEventListener('click', event => { if (event.target === zoom) zoom.close(); });
zoom.addEventListener('close', () => { previousFocus?.focus({preventScroll:true}); schedule(); });
applyLanguage();
