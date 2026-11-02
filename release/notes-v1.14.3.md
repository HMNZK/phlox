# Phlox 1.14.3

## Fixed

- Reduced synchronization overhead in long conversations by transferring only changed history and logs. History is preserved, and more of the synchronization work runs separately from interface operations.
- The new synchronization takes effect after the background service next starts. After updating, save your work and restart your Mac to enable it; updating the app alone keeps existing sessions running on the current service.

## 修正

- 長い会話では履歴とログの変更分だけを同期し、処理の負担を減らしました。履歴はそのまま保持し、同期処理のうち画面操作と競合する仕事も減らしています。
- 新しい同期方式は常駐処理の次回起動後に有効になります。更新後、作業を保存してMacを再起動すると有効になります。アプリの更新だけでは、実行中のセッションは現在の常駐処理で続きます。
