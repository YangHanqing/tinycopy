 'use strict';
const messages = {
  "zh": {
    "langAuto": "自动",
    "themeLabel": "页面外观",
    "themeSystem": "跟随系统",
    "themeLight": "浅色",
    "themeDark": "深色",
    "intro": "保存复制过的文字、图片和文件。\n用快捷键查找，再粘贴回原来的应用。",
    "metaOS": "macOS 14 及以上",
    "metaArch": "Apple 芯片与 Intel",
    "download": "下载 macOS 版 ↗",
    "seeFeatures": "查看功能 ↓",
    "keyRecords": "选记录",
    "keyContent": "选处理",
    "keyUse": "使用",
    "installEyebrow": "下载与安装",
    "installTitle": "TinyCopy 0.2.0",
    "installRequirements": "需要 macOS 14 或更高版本，支持 Apple 芯片和 Intel Mac。",
    "signed": "Developer ID 签名，已通过 Apple 公证。",
    "installStep1": "下载并打开 DMG 文件。",
    "installStep2": "将 TinyCopy 拖到“应用程序”文件夹。",
    "installStep3": "打开应用，按 ⇧⌘V 查看剪贴板历史。",
    "skip": "跳到正文",
    "navFeatures": "功能",
    "navScreenshots": "截图",
    "navInstall": "安装",
    "title": "macOS 剪贴板历史工具",
    "heroCaption": "主界面 · 示例内容",
    "featuresTitle": "功能一览",
    "featuresIntro": "默认打开历史列表。浏览记录时展开预览，原始内容与处理结果同时显示。",
    "tableDescription": "说明",
    "historyName": "历史与搜索",
    "historyDescription": "记录文本、富文本、图片和文件，重启后保留。重复复制的内容移到顶部；搜索也能找到识别文字、译文和解码结果。",
    "favoritesName": "分类与收藏",
    "favoritesDescription": "按全部、文本、图片、文件筛选。星标可只看收藏，与分类和搜索叠加；收藏记录不受普通历史条数限制。",
    "toolsName": "智能转换",
    "toolsDescription": "JSON 格式化与压缩，JWT、Base64 和 URL 解码，Unix 时间戳转换。低频编码工具放在“更多”中。",
    "translationName": "翻译",
    "translationDescription": "同时查看原文和译文，选择后复制或粘贴。使用系统翻译，支持按需或自动后台翻译；需要 macOS 15 及以上。",
    "ocrName": "图片文字",
    "ocrDescription": "预览完整图片，提取文字用于搜索、复制和粘贴。文字识别在本机完成，不替换原图。",
    "qrName": "二维码",
    "qrDescription": "从图片中提取二维码内容，也可把网址生成二维码图片。不会自动打开识别出的链接。",
    "windowName": "窗口与外观",
    "windowDescription": "拖动、缩放并记住位置；支持浅色、深色和跟随系统。托盘菜单可重置窗口和清空历史。",
    "menuName": "菜单栏入口",
    "menuDescription": "可在设置中关闭菜单栏图标。关闭后，从应用启动器、Spotlight 或“应用程序”打开 TinyCopy 进入设置；历史快捷键仍可用。",
    "galleryEyebrow": "实际界面",
    "galleryTitle": "预览与处理",
    "galleryDescription": "每次换记录都选中原始内容。左右键只改变回车要使用的内容，不会自动改动剪贴板。",
    "jsonCaption": "JSON 格式化",
    "jsonNote": "保留键顺序和数字写法。",
    "translateCaption": "系统翻译",
    "translateNote": "译文可复制，也可直接粘贴。",
    "ocrCaption": "图片文字识别",
    "ocrNote": "原图和文字都保留。",
    "qrNote": "提取内容，或从网址生成图片。",
    "usageEyebrow": "操作",
    "usageTitle": "快捷键与鼠标",
    "keyHeading": "按键",
    "actionHeading": "作用",
    "keyMove": "切换记录并展开预览",
    "keySelect": "选择原始内容或处理结果",
    "keyPaste": "粘贴 / 只复制",
    "keyFavorite": "收藏或取消收藏",
    "keyEscape": "先收起预览，再关闭窗口",
    "mouse": "鼠标单击预览，双击粘贴原始内容。搜索文字编辑时，左右键仍用于移动光标。",
    "permissionTitle": "自动粘贴需要授权",
    "permissionDescription": "辅助功能权限用于模拟 ⌘V。已授权时，回车直接粘贴到之前的应用；未授权时，内容只放回剪贴板，需自行按 ⌘V。",
    "clipboardPermission": "若系统询问剪贴板访问权限，请选择“始终允许”，以便记录历史。",
    "privacyTitle": "历史记录保存在本机",
    "privacyDescription": "没有账户，不收集遥测数据。默认忽略应用标记的保密或临时内容。",
    "frameworks": "识别与转换使用系统框架；翻译首次使用某种语言时，可能需要系统下载语言包。",
    "close": "关闭 ×",
    "openBefore": "按",
    "openAfter": "打开，直接输入关键词搜索。快捷键可在设置中修改。",
    "navLabel": "主导航",
    "zoomHero": "放大主界面截图",
    "zoomJSON": "放大 JSON 转换截图",
    "zoomTranslation": "放大翻译截图",
    "zoomOCR": "放大图片文字识别截图",
    "zoomQR": "放大二维码截图",
    "zoomDialog": "截图大图",
    "closeZoom": "关闭大图",
    "alt0": "TinyCopy 浅色主界面，左侧为历史记录，右侧预览彩色海滨图片",
    "alt1": "TinyCopy 深色主界面与彩色图片预览",
    "alt2": "JSON 原文和格式化结果",
    "alt3": "英文原文与中文译文同时显示",
    "alt4": "图片及识别出的文字",
    "alt5": "根据网址生成的正方形二维码"
  },
  "en": {
    "langAuto": "Auto",
    "themeLabel": "Appearance",
    "themeSystem": "System",
    "themeLight": "Light",
    "themeDark": "Dark",
    "intro": "Keep copied text, images and files.\nFind them with a shortcut and paste them back into your app.",
    "metaOS": "macOS 14 or later",
    "metaArch": "Apple silicon and Intel",
    "download": "Download for macOS ↗",
    "seeFeatures": "Explore features ↓",
    "keyRecords": "Choose a record",
    "keyContent": "Choose content",
    "keyUse": "Use",
    "installEyebrow": "Download & install",
    "installTitle": "TinyCopy 0.2.0",
    "installRequirements": "Requires macOS 14 or later. Supports Apple silicon and Intel Macs.",
    "signed": "Developer ID signed and notarized by Apple.",
    "installStep1": "Download and open the DMG file.",
    "installStep2": "Drag TinyCopy into Applications.",
    "installStep3": "Open the app, then press ⇧⌘V to see your clipboard history.",
    "skip": "Skip to content",
    "navFeatures": "Features",
    "navScreenshots": "Screenshots",
    "navInstall": "Download",
    "title": "Clipboard history for macOS",
    "heroCaption": "App screenshot · Sample content",
    "featuresTitle": "Features",
    "featuresIntro": "Start with the history list. Browse a record to see the original content and its results together.",
    "tableDescription": "Description",
    "historyName": "History & search",
    "historyDescription": "Keep text, rich text, images and files across restarts. Repeated copies move to the top. Search includes recognized text, translations and decoded content.",
    "favoritesName": "Filters & favorites",
    "favoritesDescription": "Filter by all, text, images or files. Combine the favorites filter with type filters and search. Favorites are excluded from the regular history limit.",
    "toolsName": "Text tools",
    "toolsDescription": "Format or minify JSON, decode JWT, Base64 and URL-encoded text, and convert Unix timestamps. Occasional encoding tools stay under More.",
    "translationName": "Translation",
    "translationDescription": "See the original and translation together, then choose which to copy or paste. Uses Apple translation, on demand or in the background. Requires macOS 15 or later.",
    "ocrName": "Text in images",
    "ocrDescription": "Preview the full image and extract text for search, copying or pasting. Recognition runs on this Mac and keeps the original image.",
    "qrName": "QR codes",
    "qrDescription": "Extract QR content from images, or turn a URL into a QR image. Detected links are never opened automatically.",
    "windowName": "Windows & appearance",
    "windowDescription": "Move and resize the window; its position is remembered. Choose light, dark or system appearance. Reset the window or clear history from the menu bar.",
    "menuName": "Menu bar icon",
    "menuDescription": "Hide the menu bar icon in Settings. Reopen TinyCopy from the app launcher, Spotlight or Applications to access Settings. The history shortcut still works.",
    "galleryEyebrow": "In the app",
    "galleryTitle": "Preview and choose",
    "galleryDescription": "Each record starts with the original selected. Left and Right choose what Enter will use; previews do not change the clipboard.",
    "jsonCaption": "JSON formatting",
    "jsonNote": "Keep key order and number formatting.",
    "translateCaption": "Apple translation",
    "translateNote": "Copy the translation or paste it directly.",
    "ocrCaption": "Text recognition",
    "ocrNote": "Keep the image and the recognized text.",
    "qrNote": "Read QR content or create an image from a URL.",
    "usageEyebrow": "Using TinyCopy",
    "usageTitle": "Keyboard and mouse",
    "keyHeading": "Key",
    "actionHeading": "Action",
    "keyMove": "Choose a record and reveal its preview",
    "keySelect": "Choose the original or a result",
    "keyPaste": "Paste / Copy only",
    "keyFavorite": "Add or remove a favorite",
    "keyEscape": "Collapse the preview, then close the window",
    "mouse": "Click a record to preview it; double-click to paste the original. While editing a search, Left and Right still move the text cursor.",
    "permissionTitle": "Permission for automatic pasting",
    "permissionDescription": "Accessibility permission lets TinyCopy send ⌘V. With permission, Enter pastes into your previous app. Without it, content is copied and you press ⌘V yourself.",
    "clipboardPermission": "If macOS asks about clipboard access, choose Always Allow so your history can be recorded.",
    "privacyTitle": "History stays on this Mac",
    "privacyDescription": "No account or telemetry. Clipboard content marked as concealed or transient is ignored by default.",
    "frameworks": "Recognition and conversions use system frameworks. Apple translation may need to download a language pack on first use.",
    "close": "Close ×",
    "openBefore": "Press",
    "openAfter": "to open and type to search. You can change the shortcut in Settings.",
    "navLabel": "Main navigation",
    "zoomHero": "Enlarge app screenshot",
    "zoomJSON": "Enlarge JSON screenshot",
    "zoomTranslation": "Enlarge translation screenshot",
    "zoomOCR": "Enlarge text recognition screenshot",
    "zoomQR": "Enlarge QR screenshot",
    "zoomDialog": "Screenshot preview",
    "closeZoom": "Close screenshot",
    "alt0": "TinyCopy in light mode, with clipboard history and a colorful coastal photo",
    "alt1": "TinyCopy in dark mode with a colorful photo preview",
    "alt2": "Original JSON and its formatted result",
    "alt3": "English original and Chinese translation shown together",
    "alt4": "An image and its recognized text",
    "alt5": "A square QR code generated from a URL"
  }
};
const root = document.documentElement;
const language = document.getElementById('language');
const theme = document.getElementById('theme');
function browserLanguage() { return /^zh/i.test(navigator.languages?.[0] || navigator.language || 'en') ? 'zh' : 'en'; }
function applyLanguage(mode) {
  const lang = mode === 'zh' || mode === 'en' ? mode : browserLanguage();
  const strings = messages[lang];
  root.lang = lang === 'zh' ? 'zh-CN' : 'en';
  document.querySelectorAll('[data-i18n]').forEach(el => { if (strings[el.dataset.i18n]) el.textContent = strings[el.dataset.i18n]; });
  document.querySelectorAll('[data-i18n-aria]').forEach(el => { el.setAttribute('aria-label', strings[el.dataset.i18nAria]); });
  document.querySelectorAll('[data-i18n-alt]').forEach(el => { el.alt = strings[el.dataset.i18nAlt]; });
  document.title = lang === 'zh' ? 'TinyCopy — macOS 剪贴板历史工具' : 'TinyCopy — Clipboard history for macOS';
}
let languageMode = 'auto';
try { languageMode = localStorage.getItem('tinycopy-language') || 'auto'; } catch (_) {}
language.value = ['zh','en'].includes(languageMode) ? languageMode : 'auto';
applyLanguage(language.value);
language.addEventListener('change', () => { applyLanguage(language.value); try { localStorage.setItem('tinycopy-language', language.value); } catch (_) {} });
window.addEventListener('languagechange', () => { if (language.value === 'auto') applyLanguage('auto'); });
theme.value = root.dataset.theme || 'system';
theme.addEventListener('change', () => { if (theme.value === 'system') delete root.dataset.theme; else root.dataset.theme = theme.value; try { localStorage.setItem('tinycopy-theme',theme.value); } catch (_) {} });
const repository = document.querySelector('meta[name="github-repository"]').content.trim();
if (/^[\w.-]+\/[\w.-]+$/.test(repository)) {
  const source = `https://github.com/${repository}`;
  document.querySelectorAll('[data-repository-link]').forEach(link => { link.href = source; link.hidden = false; });
  document.querySelectorAll('[data-releases-link]').forEach(link => { link.href = `${source}/releases/latest`; link.hidden = false; });
}
const zoom = document.getElementById('zoom');
let previousFocus;
document.querySelectorAll('[data-zoom]').forEach(button => {
  button.addEventListener('click', () => {
    const image = Array.from(button.querySelectorAll('img')).find(img => getComputedStyle(img).display !== 'none');
    if (!image) return;
    if (typeof zoom.showModal !== 'function') { window.open(image.src, '_blank', 'noopener'); return; }
    zoom.querySelector('img').src = image.src;
    zoom.querySelector('img').alt = image.alt;
    previousFocus = button;
    zoom.showModal();
  });
});
zoom.querySelector('.zoom-close').addEventListener('click', () => zoom.close());
zoom.addEventListener('click', event => { if (event.target === zoom) zoom.close(); });
zoom.addEventListener('close', () => previousFocus?.focus({ preventScroll: true }));
