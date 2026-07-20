# APEX ORACLE Supabase移行設計

## 最優先原則
- 既存IndexedDB/localStorageは移行完了まで削除・上書きしない。
- 最初はローカル→Supabaseの一方向コピーのみ。
- コピー後に件数、ID、content_hashを照合する。
- 不一致が1件でもあれば正本を切り替えない。
- Realtimeと自動取得は検証完了後に有効化する。
- 削除は物理削除せず、当面はdeleted_atによる論理削除にする。

## データ単位
- scrims: 現在の1スクリムセット＝1行を維持。payloadに現行構造を保持。
- fight_matches: apexStatsMatchesV6を解析し、1試合＝1行へコピー。
- final_zones: 最終安置1記録＝1行。
- ring_console: Split×MAP×POI×前後半を1行。
- master_data: teams/maps/legends/regions/blocks/splits等をcategoryで管理。
- 画像: DatabaseへBase64保存せず、将来Supabase Storageへ分離。

## 移行順
1. SQLで新規テーブルのみ作成。
2. workspaceと管理者メンバーを登録。
3. IndexedDB/localStorageの完全JSONバックアップを保存。
4. scrimsを一方向コピー（upsert禁止、まずinsertのみ）。
5. source_count/destination_countと全IDを照合。
6. content_hashを照合。
7. apexStatsMatchesV6を読取専用解析しfight_matchesへコピー。
8. 最終安置・リング・マスターを順番にコピー。
9. 二重保存を開始（ローカル正本のまま）。
10. 一定期間の一致確認後、Supabaseを正本へ切替。
11. Realtimeを有効化。
12. 手動クラウドボタンを削除。
13. 古いCloudSafetyバックアップは別JSON保管後に整理。

## 競合ルール
- 同一IDの比較はupdated_atだけでなくcontent_hashも使用。
- 初期移行中はクラウドからローカルを自動上書きしない。
- 競合時は自動削除・自動上書きをせず、競合ログへ記録。
- 削除はdeleted_atを同期し、十分な保持期間後にのみ物理削除。

## 切替条件
- 全カテゴリで件数一致
- 全ID一致
- 全content_hash一致
- 主要画面の回帰テストPASS
- 旧方式へ戻せるバックアップ確認
