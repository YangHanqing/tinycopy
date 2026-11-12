# TinyCopy Clipboard History

[简体中文](README.md) | **English**

TinyCopy is a **native macOS clipboard history tool**. It keeps the text, rich text, images and files you copy, finds them again with one shortcut, and pastes them back into the app you were in.

Press `⇧⌘V` to open it and type to search. Up and Down pick a record, Left and Right pick the original or a converted version, and Return pastes. A copied file or folder can be pasted as its path; JSON, encoded text, foreign languages and the text in screenshots can be converted before you paste.

For a quick look, see the [introduction page](https://yanghanqing.github.io/tinycopy/?lang=en), with screenshots of the main features.

![TinyCopy overview](assets/screenshots/hero-ocr-light.png)

## Features

The screenshots use sample content. The interface is in Chinese for now.

| Feature | Description | Screenshot |
| --- | --- | --- |
| History, search and favorites | Text, rich text, images and files are kept, through restarts too; copying something again moves it to the top. Filter by text, images or files; search also covers recognized text, translations and decoded content. Press `⌘P` to keep a record as a favorite, which is never dropped. | <img src="assets/screenshots/history.png" alt="Clipboard history and filters" width="360"> |
| Files and paths | Copy files or folders in Finder, then paste just the path — one path per line when you copied several. The contents show too: images, PDFs and videos show a picture, text and code show their text. Paste an image file as an image, or read the text or QR code in it; paste a text file as its contents. Files that were moved or deleted are marked. | <img src="assets/screenshots/file-preview-light.png" alt="Copied files and their paths" width="560"> |
| JSON, decoding and timestamps | Format or minify JSON, keeping key order and numbers as written; decode JWT, Base64 and URL-encoded text; turn Unix timestamps into dates. The original and the result stay side by side, and a result is used only when you pick it. | <img src="assets/screenshots/hero-json-light.png" alt="Original and formatted JSON" width="560"> |
| Apple translation | See the original and its translation together, then copy or paste either. Requires macOS 15 or later; a language pack may need to be downloaded on first use. | <img src="assets/screenshots/hero-translation-light.png" alt="Original text and translation" width="560"> |
| Text recognition | Extract the text from screenshots, meeting notices and other pictures, then search, copy or paste it. Recognition runs on your Mac and keeps the original image. | <img src="assets/screenshots/hero-ocr-light.png" alt="An image and its recognized text" width="560"> |
| QR codes | Read the QR code in a picture, or turn a URL into a QR image. Links that are read are never opened automatically. | <img src="assets/screenshots/qrcode.png" alt="A QR image generated from a URL" width="560"> |
| Appearance and window | Light, dark or following the system; the window keeps its place and size. The menu bar icon can be hidden, and TinyCopy can start at login. |  |

## Using it

| Action | Keys |
| --- | --- |
| Open / close | `⇧⌘V` (change it in Settings) |
| Pick a record / a version | `↑` `↓` / `←` `→` |
| Paste | `↩`, or double-click a record to paste the original |
| Copy without pasting | `⌘↩` |
| Favorite | `⌘P` |
| Close the preview or the panel | `Esc` |

Pasting for you needs Accessibility permission. With it, Return pastes straight into the previous app; without it, the content goes to the clipboard and you press `⌘V` yourself. When the focus is in a file list or on the desktop in Finder or another file manager, TinyCopy only copies and does not paste, so the paste does not become a new file. If macOS asks about clipboard access, choose Always Allow so the history can be recorded.

If another app (a screenshot or clipboard tool) also uses `⇧⌘V`, both respond and the panel may close at once; choose another shortcut in Settings.

## Download and install

Download the latest version from [Releases](https://github.com/YangHanqing/tinycopy/releases/latest) (or from the [introduction page](https://yanghanqing.github.io/tinycopy/?lang=en#download)), open the DMG and drag TinyCopy into Applications.

- Requires macOS 14 or later, on Apple silicon or Intel.
- Apple translation requires macOS 15.
- The app is signed with a Developer ID and notarized by Apple, so it opens normally.

## Privacy and network

TinyCopy collects no data. The history stays on this Mac, with no account and no cloud sync. Content that password managers and other apps mark as concealed or transient is skipped by default. Text recognition, QR codes and conversions run on your Mac; Apple translation runs on your Mac too, with language packs downloaded by macOS.

TinyCopy goes online only to check for updates: once every 30 days it asks GitHub for the latest version number, sending no identifiers. A newer version is mentioned at the bottom of the panel and in the menu; it only opens the release page and never downloads or installs anything. Turn it off in Settings ▸ General.

## Building from source

Install Xcode 27 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen), run `xcodegen generate` in the repository root, then open `TinyCopy.xcodeproj` and run the **TinyCopy** scheme.

## License

GNU General Public License v3 (GPL v3).
