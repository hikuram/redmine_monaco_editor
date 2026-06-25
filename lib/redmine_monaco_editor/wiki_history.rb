module RedmineMonacoEditor
  # ============================================================
  # Wikiページ本文の変更履歴を収集し、フロントへ渡す。
  # ============================================================
  # 用途:
  #   チケット説明欄(DescriptionHistory)と同じ「変更履歴ドロップダウン」
  #   「左右diff」「Blameヒント」を、Wikiページの本文編集画面でも使えるように
  #   するためのデータを組み立てる。フロントは window.MONACO_EDITOR_DIFF として
  #   受け取り、選択された2版を左右の Monaco エディタへ読み取り専用で展開する。
  #
  # 設計:
  #   - 出力するJSONの形は DescriptionHistory.build と完全に同一にする。
  #     これにより JS 側(ドロップダウン/diffモード/Blame)を一切変更せずに
  #     Wikiでも同じ機能が動く。owner_selector だけ Wiki 用に差し替える。
  #   - WebAPI(XHR/fetch)は使わない。view hook で一度に埋め込む。
  #   - 履歴は直近 MAX_VERSIONS 件まで。古い版は捨てる。
  #
  # Redmine のデータ構造(チケットとの違い):
  #   チケット説明欄は「説明を変更した journal」だけが差分(old/new)を持つが、
  #   Wikiは WikiContentVersion が版ごとに本文全体(text)を丸ごと保持する。
  #   そのため snapshot を old_value/value から復元する必要がなく、各版の
  #   text をそのまま使えるぶん構造はシンプルになる。
  #     - page.content                : 現在の WikiContent(最新版)
  #     - page.content.versions       : 全 WikiContentVersion(版ごとの本文)
  #     - WikiContentVersion#version  : 版番号(1始まり。0版は存在しない)
  #     - WikiContentVersion#text     : その版の本文(gzip圧縮は解凍済みで返る)
  #     - WikiContentVersion#author   : その版を保存したユーザー
  #     - WikiContentVersion#updated_on : その版の保存日時
  #
  # index について:
  #   DescriptionHistory では index==0 を「作成時(Creation)」として扱うが、
  #   Wiki には 0版が無く version 1 が最初の保存版なので、index には Wiki の
  #   version 番号をそのまま入れる。結果フロントでは全版が "#1, #2, ..." と
  #   表示され、0 特別扱い(Creation ラベル)には入らない。これは Wiki の
  #   履歴画面(#1, #2, ...)の見え方とも一致する。
  #
  # 生成するデータ(window.MONACO_EDITOR_DIFF) — DescriptionHistory と同形:
  #   {
  #     "wiki_page_id":  45,
  #     "owner_selector": "#content_text",
  #     "current":       "現在の保存版の本文全文",
  #     "current_meta":  { "journal_id": nil, "index": 7, "author": ..., "created_on": ... },
  #     "truncated":     false,
  #     "versions": [                      # 古い順(最新版は含めない)
  #       {
  #         "journal_id": nil,             # Wiki に journal は無いので常に nil
  #         "index":      1,               # Wiki の version 番号
  #         "author":     "落合 卓",
  #         "created_on": "2026-06-15T08:57:00Z",
  #         "text":       "その版の本文全文"
  #       },
  #       ...
  #     ]
  #   }
  #
  # versions が空 → 版が1つ(=作成のみで一度も更新されていない)。
  module WikiHistory
    module_function

    MAX_VERSIONS = 20

    # このdiffデータの「持ち主」となるtextareaを指すCSSセレクタ。
    # Wiki編集フォームの本文は Redmine 標準で text_area_tag 'content[text]'
    # により生成され、id は "content_text" になる(Rails の sanitize_to_id 仕様)。
    # フロントはこのセレクタに一致するエディタにのみ履歴/Blameを有効化する。
    OWNER_SELECTOR = '#content_text'

    # page: WikiPage
    def build(page)
      return nil if page.nil? || page.new_record?

      content = page.content
      return nil if content.nil?

      # 全版を version 昇順(古い→新しい)で取得。author は N+1 を避けて includes。
      all_versions = content.versions.reorder(version: :asc).includes(:author).to_a
      return nil if all_versions.empty?

      current_ver = all_versions.last
      current_text = current_ver.text.to_s

      # 最新版を除いた過去版を古い順に versions[] へ。各版は本文全文を持つ。
      past = all_versions[0...-1]

      versions = past.map do |v|
        {
          'journal_id' => nil,
          'index'      => v.version,
          'author'     => author_name(v.author),
          'created_on' => v.updated_on&.utc&.iso8601,
          'text'       => v.text.to_s
        }
      end

      # 直近 MAX_VERSIONS 件に制限(古い方から切る)。
      truncated = false
      if versions.length > MAX_VERSIONS
        truncated = true
        versions = versions.last(MAX_VERSIONS)
      end

      {
        'wiki_page_id'   => page.id,
        'owner_selector' => OWNER_SELECTOR,
        'current'        => current_text,
        'current_meta'   => {
          'journal_id' => nil,
          'index'      => current_ver.version,
          'author'     => author_name(current_ver.author),
          'created_on' => current_ver.updated_on&.utc&.iso8601
        },
        'truncated'      => truncated,
        'versions'       => versions
      }
    end

    def author_name(user)
      return nil if user.nil?
      user.respond_to?(:name) ? user.name.to_s : user.to_s
    end
  end
end
