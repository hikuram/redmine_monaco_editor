module RedmineMonacoEditor
  # ============================================================
  # チケット「説明欄」の変更履歴を収集し、フロントへ渡す。
  # ============================================================
  # 用途:
  #   ツールバーの「変更履歴」ドロップダウンで、過去版同士の diff を
  #   表示するために使う。フロントは window.MONACO_EDITOR_DIFF として
  #   履歴データを受け取り、選択された2版を左右の Monaco エディタへ
  #   読み取り専用で展開する。
  #
  # 設計:
  #   - WebAPI(XHR/fetch)は使わない。データは view hook で
  #     window.MONACO_EDITOR_DIFF として一度に埋め込む。
  #   - 履歴は直近 MAX_VERSIONS 件まで。古い版は捨てる。
  #   - 各版は「全文(text)+メタ情報(著者・日付・注記番号)」を持つ。
  #   - 現在の保存版(current)は別フィールドで持ち、versions には含めない。
  #
  # Redmine のデータ構造:
  #   説明変更は journal_details に property='attr', prop_key='description'
  #   で old_value(変更前全文)/value(変更後全文)が記録される。
  #   説明を変更した journal だけがこの detail を持つ。
  #
  # 生成するデータ(window.MONACO_EDITOR_DIFF):
  #   {
  #     "issue_id": 123,
  #     "current": "現在の保存版の説明全文",
  #     "current_meta": { "author": ..., "created_on": ... }, # 最終更新者
  #     "truncated": false,                                    # 上限超で古い版を切ったか
  #     "versions": [                                          # 古い順
  #       {
  #         "journal_id": 10,
  #         "index": 3,                  # 注記番号(#note-3)。0=作成時
  #         "author": "落合 卓",
  #         "created_on": "2026-06-15T08:57:00Z",
  #         "text": "その版の説明全文"
  #       },
  #       ...
  #     ]
  #   }
  #
  # versions が空 → 新規 or 説明が一度も変更されていない。
  module DescriptionHistory
    module_function

    MAX_VERSIONS = 20

    # このdiffデータの「持ち主」となるtextareaを指すCSSセレクタ。
    # 説明欄の変更履歴は Redmine 標準の説明欄textarea(#issue_description)
    # だけが持つ機能なので、フロントはこのセレクタに一致するエディタにのみ
    # 「変更履歴ドロップダウン」「Blameヒント」を有効化する。
    # コメント欄(#issue_notes)等は一致しないため、それらの機能は出ない。
    #
    # 将来、説明欄以外にも履歴を持たせたくなった場合は、サーバ側の
    # このセレクタ宣言を変えるだけでフロントの有効範囲を制御できる
    # （JS側に説明欄判定をハードコードしないための設計）。
    OWNER_SELECTOR = '#issue_description'

    def build(issue)
      return nil if issue.nil? || issue.new_record?

      current_text = issue.description.to_s
      desc_changes = collect_description_changes(issue)

      # journal_id -> 注記番号(1始まり) のマップを作る。
      # Redmine 本体の Journal#indice と同じ計算方式:
      #   issue の全 journal を created_on 昇順(同時刻は id 昇順)に並べ、
      #   1から順番にインデックスを振る。説明変更のない journal も含めて
      #   通し番号にすることで、Redmine 画面の #note-N と一致する。
      indice_map = {}
      issue.journals.to_a.sort_by { |j| [j.created_on, j.id] }.each_with_index do |j, i|
        indice_map[j.id] = i + 1
      end

      if desc_changes.empty?
        return {
          'issue_id'       => issue.id,
          'owner_selector' => OWNER_SELECTOR,
          'current'        => current_text,
          'current_meta'   => creation_meta(issue),
          'truncated'      => false,
          'versions'       => []
        }
      end

      # 各版の全文スナップショットを古い順に組み立てる。
      #   snapshots[0]    = 作成時(最古 detail の old_value)
      #   snapshots[1..]  = 各変更後の value
      #   snapshots[last] = 現在の説明(current_text と一致するはず)
      snapshots = []
      metas = []

      snapshots << desc_changes.first[:old_value].to_s
      metas     << creation_meta(issue)

      desc_changes.each do |c|
        snapshots << c[:value].to_s
        metas     << change_meta(c, indice_map)
      end

      last_index = snapshots.length - 1
      versions = []
      (0...last_index).each do |i|
        versions << {
          'journal_id' => metas[i][:journal_id],
          'index'      => metas[i][:index],
          'author'     => metas[i][:author],
          'created_on' => metas[i][:created_on],
          'text'       => snapshots[i]
        }
      end

      # 直近 MAX_VERSIONS 件に制限(古い方から切る)
      truncated = false
      if versions.length > MAX_VERSIONS
        truncated = true
        versions = versions.last(MAX_VERSIONS)
      end

      {
        'issue_id'       => issue.id,
        'owner_selector' => OWNER_SELECTOR,
        'current'        => current_text,
        'current_meta'   => metas.last,
        'truncated'      => truncated,
        'versions'       => versions
      }
    end

    def collect_description_changes(issue)
      journals = issue.journals.to_a.sort_by { |j| [j.created_on, j.id] }

      changes = []
      journals.each do |j|
        j.details.each do |d|
          next unless d.property == 'attr' && d.prop_key == 'description'

          changes << {
            journal:   j,
            detail:    d,
            old_value: d.old_value,
            value:     d.value
          }
        end
      end
      changes
    end

    def change_meta(change, indice_map)
      j = change[:journal]
      {
        journal_id: j.id,
        index:      indice_map[j.id] || j.id, # マップに無い場合のみ id フォールバック
        author:     author_name(j.user),
        created_on: j.created_on&.utc&.iso8601
      }
    end

    def creation_meta(issue)
      {
        journal_id: nil,
        index:      0,
        author:     author_name(issue.author),
        created_on: issue.created_on&.utc&.iso8601
      }
    end

    def author_name(user)
      return nil if user.nil?
      user.respond_to?(:name) ? user.name.to_s : user.to_s
    end
  end
end
