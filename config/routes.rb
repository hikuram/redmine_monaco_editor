# ============================================================
# Redmine Monaco Editor — ルーティング
# ============================================================
# プラグイン独自のトップレベルルート。
#   GET /monaco_editor/macros        → JSON でマクロ一覧
#   GET /monaco_editor/macros.json   → 同上（拡張子つき）
#
# Redmine 本体や他プラグインのルートと衝突しないよう、
# /monaco_editor/ 名前空間配下にまとめる。
RedmineApp::Application.routes.draw do
  get 'monaco_editor/macros', to: 'monaco_macros#index', as: 'monaco_editor_macros'
end
