module RedmineMonacoEditor
  # ============================================================
  # MyController パッチ
  # ============================================================
  # 個人設定（My account）の保存時に、フォームから送られた
  # monaco_settings を UserPreference#others に書き込む。
  #
  # 方式:
  #   prepend で account アクションをラップする。before_action の
  #   登録タイミング問題（includeされた時点で既にコールバック解決済みだと
  #   登録が効かない）を避けるため、メソッドを直接上書きする形にした。
  #   元の account を呼ぶ前に、送信された monaco_settings を
  #   User.current.pref へ仕込んでおく。Redmine本体の account が
  #   pref を保存するのに相乗りしつつ、念のため自前でも save する。
  #
  # パラメータ:
  #   独自トップレベル params[:monaco_settings] を使うため、
  #   Redmine の Strong Parameters 定義に手を入れる必要がない。
  module MyControllerPatch
    def account
      apply_monaco_settings
      super
    end

    private

    def apply_monaco_settings
      # 更新時（POST/PUT/PATCH）のみ対象。表示(GET)では何もしない。
      return if request.get? || request.head?

      submitted = params[:monaco_settings]
      return if submitted.blank?
      return if User.current.nil? || User.current.anonymous?

      # ActionController::Parameters でも素のHashでも安全に読めるよう
      # 文字列キーのHashへ正規化する。
      sub = submitted.respond_to?(:to_unsafe_h) ? submitted.to_unsafe_h : submitted
      sub = sub.each_with_object({}) { |(k, v), h| h[k.to_s] = v }

      pref = User.current.pref
      others = pref.others.is_a?(Hash) ? pref.others.dup : {}

      current = others[RedmineMonacoEditor::Settings::KEY]
      current = {} unless current.is_a?(Hash)
      current = current.each_with_object({}) { |(k, v), h| h[k.to_s] = v }

      merged = current.dup

      # enabled は hidden(=0)+checkbox(=1) で常に届く。true/false へ変換。
      if sub.key?('enabled')
        merged['enabled'] = !['0', 0, false, 'false', '', nil].include?(sub['enabled'])
      end

      # 将来項目（theme / font_size 等）は届いたぶんだけ取り込む。
      %w[theme font_size].each do |k|
        merged[k] = sub[k] unless sub[k].nil?
      end

      others[RedmineMonacoEditor::Settings::KEY] = merged
      pref.others = others
      pref.save

      Rails.logger.info "[redmine_monaco_editor] saved monaco_settings: #{merged.inspect}"
    rescue => e
      Rails.logger.error "[redmine_monaco_editor] apply_monaco_settings error: #{e.class}: #{e.message}"
    end
  end
end
