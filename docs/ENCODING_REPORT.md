# Encoding report

## Scan result

Scanned the tracked text files in the repository (86 files with source, documentation, configuration, markup, or SQL extensions) using UTF-8 decoding. Checked for the reported mojibake markers (`Ø`, `Ù`, `Ã`, `ï¿½`), common garbled punctuation sequences, replacement characters, and runs of three or more question marks.

**Files with confirmed garbled text: none.** The Arabic text in `README.md`, Dart source/comments, and SQL files is valid UTF-8 and readable when decoded as UTF-8. Therefore no reverse-code-page conversion was appropriate, and no source/comment/SQL files required encoding repair. No lines containing confirmed irrecoverable question-mark substitutions were found.

The garbled Arabic visible in some PowerShell `Get-Content` output was caused by that command's legacy default decoding for files without a BOM. Reading the same files explicitly as UTF-8 displays readable Arabic; the source bytes were not mojibake.

## Files changed

- `README.md` was reorganized and rewritten in English as requested. The original Arabic app name, `على الطريق`, was preserved because it is valid UTF-8.
- `.editorconfig` sets UTF-8, LF line endings, and final newlines for future edits.

No manual text recovery is required based on this scan.
