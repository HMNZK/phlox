// DesignSystemIOS — iOS 向けデザインシステム層。
//
// 共有 DesignSystem（クロスプラットフォームのコアトークン DSColor/DSSpacing/DSRadius/DSFont/
// DSShadow と状態語彙 StatusBadge）を再エクスポートし、import DesignSystemIOS だけで
// コアトークン + iOS 固有トークン（DSTouch/DSMotion/DSIcon）+ Atoms/Molecules に到達できるようにする。
//
// iOS 固有の追加は本ターゲットに閉じ、共有 DesignSystem（Mac と共用）は汚さない（一方向依存）。
@_exported import DesignSystem
