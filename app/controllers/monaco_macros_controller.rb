# ============================================================
# Monaco Editor 用 マクロ一覧エンドポイント
# ============================================================
# {{macro_list}} が内部で参照している
# Redmine::WikiFormatting::Macros.available_macros を読み、
# Monaco の補完候補に使える形（name / detail / documentation）の
# JSON 配列で返す。
#
# 設計方針:
#   - REST API(.json) 全体が無効化されている環境でも使えるよう、
#     プラグイン独自のトップレベルルート（/monaco_editor/macros）を
#     用意し、そこへ素のHTML系リクエストとして取りに行く。
#   - ログインユーザーのみ許可（require_login）。マクロ名と説明は
#     秘匿情報ではないが、不特定アクセスを避けるため認証を要求する。
#   - DBは触らない。available_macros はメモリ上のレジストリのため
#     高速で、副作用もない。
#
# 返却形式:
#   [
#     { "name": "toc",
#       "detail": "目次を表示する",            # descの1行目
#       "documentation": "目次を表示する\n\n使用例:\n  {{toc}} ..." # 全文(!{{ は {{ に正規化済み)
#     },
#     ...
#   ]
class MonacoMacrosController < ApplicationController
  # ログイン必須。匿名ユーザーには 403 ではなくログイン要求とする。
  before_action :require_login

  # ブラウザキャッシュ・ETag を素直に効かせたいだけなので
  # CSRF 検証は GET の読み取り専用アクションとして扱う。
  # （Redmine の ApplicationController は GET では verify を要求しない）

  def index
    macros = collect_macros
    respond_to do |format|
      format.json { render json: macros }
      # .json 拡張子が使えない環境向けに、拡張子なしGETでも
      # JSON を返せるよう any も JSON にフォールバックさせる。
      format.any  { render json: macros, content_type: 'application/json' }
    end
  end

  private

  # available_macros を Monaco 補完向けの配列へ整形する。
  def collect_macros
    available =
      begin
        Redmine::WikiFormatting::Macros.available_macros
      rescue => e
        Rails.logger.error "[redmine_monaco_editor] available_macros error: #{e.class}: #{e.message}"
        {}
      end

    # available_macros は { name => { desc: "..." } } 形式。
    # name は Symbol または String、値はHash（:desc キーを持つ）か、
    # 環境によっては説明文字列を直接持つこともあるため両対応する。
    available.map do |name, meta|
      raw_desc =
        if meta.is_a?(Hash)
          meta[:desc] || meta['desc'] || ''
        else
          meta.to_s
        end

      normalized = normalize_desc(raw_desc.to_s)
      first_line = normalized.lines.first.to_s.strip

      {
        name: name.to_s,
        detail: first_line,
        documentation: normalized
      }
    end.sort_by { |h| h[:name] }
  end

  # desc文字列の整形。
  #   - 使用例で使われる !{{ ... }} のエスケープ記法を {{ ... }} に戻す
  #     （Monaco の documentation 上ではそのまま記法として読ませたいため）
  #   - 行末の余分な空白を除去
  #   - 連続する空行を1行に圧縮（長文マクロの見栄え対策）
  def normalize_desc(text)
    text = text.gsub('!{{', '{{')
    lines = text.split("\n").map { |l| l.rstrip }
    # 連続空行の圧縮
    compacted = []
    prev_blank = false
    lines.each do |l|
      blank = l.empty?
      next if blank && prev_blank
      compacted << l
      prev_blank = blank
    end
    compacted.join("\n").strip
  end
end
