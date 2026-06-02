module RedmineMonacoEditor
  # ============================================================
  # ユーザー個人設定（Monaco Editor 設定）へのアクセスヘルパー
  # ============================================================
  # 設定は UserPreference#others（シリアライズされたカラム）の中の
  # :monaco_settings キーにハッシュとしてまとめて保存する。
  #   user.pref.others[:monaco_settings] = {
  #     "enabled"   => true,    # Monacoを使うか
  #     "theme"     => "vs",    # 将来: テーマ(ナイトモード等)
  #     "font_size" => 14       # 将来: フォントサイズ
  #   }
  # この方式なら設定項目を増やしてもDBマイグレーションは不要
  # （others 自体が任意のハッシュを格納できるため）。
  module Settings
    KEY = :monaco_settings

    # 既定値。未設定ユーザーや項目未保存時のフォールバック。
    # enabled は既定 true（インストール時点で全員が使える状態）。
    DEFAULTS = {
      'enabled'   => true,
      'theme'     => 'vs',
      'font_size' => 14
    }.freeze

    module_function

    # 指定ユーザーの設定ハッシュを返す（既定値とマージ済み）。
    # 文字列キーに正規化して返すため、呼び出し側はキーの型を気にしなくてよい。
    def for_user(user)
      return DEFAULTS.dup if user.nil? || user.anonymous?

      stored = user.pref.others.is_a?(Hash) ? user.pref.others[KEY] : nil
      stored = {} unless stored.is_a?(Hash)

      # シンボル/文字列キーの揺れを文字列に寄せてからマージ
      normalized = stored.each_with_object({}) do |(k, v), h|
        h[k.to_s] = v
      end
      DEFAULTS.merge(normalized)
    end

    # enabled だけを手早く取得するショートカット。
    def enabled_for?(user)
      val = for_user(user)['enabled']
      # 文字列 "0"/"false" も false として扱う（フォーム値対策）
      ![false, 'false', '0', 0, nil].include?(val)
    end
  end
end
