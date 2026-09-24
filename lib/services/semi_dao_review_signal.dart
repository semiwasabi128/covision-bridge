// lib/services/semi_dao_review_signal.dart
//
// [教練 Agent 2026-08-05] 從 `semi_dao_review_store.dart` 拆出
//
// SemiDAO 預審 / 社群評審 共用的信號 enum。
// 之前藏在 store 內，現在獨立出來讓：
// - `SemiDaoReviewStore`（社群評審資料層）引用
// - `CompanionCertificationGuard`（合規檢查）引用
// - `companion_*` wizard UI 引用
//
// 沒有循環依賴（兩個引用方都只是 enum consumer）。

/// 審核信號：通過（綠）/ 觀察中（黃）/ 阻擋（紅）
enum SemiDaoReviewSignal { approved, watching, blocked }