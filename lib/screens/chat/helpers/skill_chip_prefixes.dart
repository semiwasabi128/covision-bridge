// [S17 收尾] Skill chip 指令 → 前綴文字對照表。
// 從 chat_screen.dart _selectSkillChip 抽出。

/// Skill 指令對應的輸入框前綴文字。
const Map<String, String> skillChipPrefixes = {
  '/grill-me': '我想釐清一下我的想法：',
  '/to-prd': '幫我把剛剛的討論整理成規格文件：',
  '/to-issues': '幫我把這個需求拆成具體任務：',
  '/tdd': '我們用測試驅動的方式來開發這個功能：',
  '/diagnose': '我遇到了一個 bug，需要系統化排查：',
  '/prototype': '我想快速驗證一個想法：',
  '/zoom-out': '幫我從更高層次看看這個問題：',
};
