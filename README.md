# ReverseLang

Typed "akuo" when you meant "שלום"? Select it, press **Ctrl+Shift+E**, and the text flips to the right language. The keyboard layout switches too, so you can keep typing. Works with any keyboard language installed in Windows: Hebrew, English, Arabic, Russian, French, Spanish and more.

## Install
1. Download ReverseLang.zip from the Releases page or from https://cv.work-it.uk, and extract the folder somewhere permanent (not Downloads).
2. Double-click `ReverseLang.exe`. No AutoHotkey install needed.
3. `ReverseLang.exe` is the official AutoHotkey v2 executable, renamed. It loads `ReverseLang.ahk` from the same folder automatically, so keep all the files together.

## Usage
- **With a selection**: select text and press the shortcut.
- **Without a selection**: converts from the start of the line to the cursor (can be changed to the last word).
- **Auto-fix** (off by default, turn it on from the tray menu): after every space, checks the last word. It converts only if the word is not a real word in the language it was typed in, and the converted version is a real word in the other language (dictionaries of about 38,000 words per language). Words shorter than 3 letters are skipped.
- A word keeps getting converted by mistake? Add it to the exceptions list from the tray menu.

## Multiple languages
- ReverseLang reads the key mapping of every installed keyboard from Windows, so there are no hard-coded tables.
- The shortcut converts to the first language in the list (other than the one the text was typed in). Press it again right away to move to the next language. After the last one you get the original text back.
- In Settings, on the Languages tab: tick the languages to cycle through and set their order. "Add language..." opens the Windows language settings. After installing a language there, click "Refresh".
- "Refresh" reloads the list from Windows and removes unticked languages. "Show all" brings them back.
- When several languages share a script (English, French, Spanish), the source language is taken from the active keyboard layout.
- Auto-fix while typing works between Hebrew and English only.

## Settings
Double-click the tray icon to open Settings: shortcut, languages, auto-fix, exceptions and conversion history. You can still edit the file by hand:

## settings.ini
| Key | Meaning |
|---|---|
| Hotkey | Shortcut. `^`=Ctrl `!`=Alt `+`=Shift `#`=Win. Default `^+e` |
| AutoMode | 1/0 |
| AutoMinLength | Minimum word length for auto-fix |
| NoSelection | `line` or `word` |
| Languages | Active languages in cycle order (HKL codes). Set from Settings |
| HiddenLanguages | Languages removed from the list with Refresh |

After editing, choose "Reload" from the tray menu.

## Single EXE
If you have AutoHotkey v2 with Ahk2Exe installed, run:
`Ahk2Exe.exe /in ReverseLang.ahk /out ReverseLang.exe`
You still need to keep en.txt and he.txt next to the exe.

## License
[MIT](LICENSE). AutoHotkey is licensed separately, see `AutoHotkey-license.txt`.
