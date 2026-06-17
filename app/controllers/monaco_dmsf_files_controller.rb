# ============================================================
# Monaco Editor 用 DMSF文書一覧エンドポイント
# ============================================================
# {{dmsf(id)}} マクロの引数補完のために、ユーザーが閲覧可能な
# DMSF文書の id / 表示パス を返す。REST API(.json) が無効な環境でも
# 使えるよう、プラグイン独自のトップレベルルート
# （/monaco_editor/dmsf_files）を使う。
#
# 設計方針:
#   - ログインユーザーのみ（require_login）。
#   - 権限を尊重し、:view_dmsf_files 権限を持つプロジェクトの文書だけ返す
#     （見えないプロジェクトの文書名・IDは漏らさない）。DMSF本体の
#     Project.allowed_to_condition(user, :view_dmsf_files) と同じ基準。
#   - 削除済み文書は DmsfFile.visible スコープで除外する。
#   - DMSF が未インストールの環境では空配列を返す（補完が出ないだけ）。
#   - 既定では現在のプロジェクト（params[:project_id]=識別子）に絞る。
#     これは {{dmsf(id)}} がそのプロジェクト内の文書を指す運用が普通で、
#     候補を膨らませない・権限評価を軽くするため。横断したい場合に備えて
#     scope=all を受けるが、その場合も権限フィルタは必ず効く。
#
# 返却形式:
#   [
#     { "id": 123,
#       "path": "設計書/ネットワーク/構成図.vsdx",  # フォルダパス込み表示名
#       "project_identifier": "sco",
#       "project_name": "SCO",
#       "is_current": true }, ...
#   ]
class MonacoDmsfFilesController < ApplicationController
  before_action :require_login

  def index
    files = collect_dmsf_files
    respond_to do |format|
      format.json { render json: files }
      format.any  { render json: files, content_type: 'application/json' }
    end
  end

  private

  def collect_dmsf_files
    # DMSF未インストールなら何もしない（クラス未定義で落とさない）。
    return [] unless defined?(DmsfFile)

    current_identifier = params[:project_id].presence
    scope_param = params[:scope].presence # 'all' で横断（既定は現在プロジェクト）

    # :view_dmsf_files 権限を持つプロジェクト。これが権限フィルタの本体。
    allowed_projects =
      begin
        Project.allowed_to(User.current, :view_dmsf_files)
      rescue => e
        Rails.logger.error "[redmine_monaco_editor] dmsf allowed_to error: #{e.class}: #{e.message}"
        Project.none
      end

    # 既定は現在のプロジェクトに絞る。識別子が来ていて scope!=all のとき。
    if scope_param != 'all' && current_identifier.present?
      allowed_projects = allowed_projects.where(identifier: current_identifier)
    end

    files =
      begin
        DmsfFile.visible
                .where(project_id: allowed_projects.select(:id))
                .includes(:project, :dmsf_folder)
      rescue => e
        Rails.logger.error "[redmine_monaco_editor] dmsf query error: #{e.class}: #{e.message}"
        return []
      end

    result = files.map do |file|
      project = file.project
      next nil unless project
      # dmsf_path_str はフォルダパス込みのフルパス（例 "設計書/構成図.vsdx"）。
      path =
        begin
          file.dmsf_path_str
        rescue
          file.title.to_s
        end
      {
        id: file.id,
        path: path.presence || file.title.to_s,
        project_identifier: project.identifier,
        project_name: project.name,
        is_current: (current_identifier.present? &&
                     project.identifier == current_identifier)
      }
    end.compact

    # 現在のプロジェクトを先頭、その後はプロジェクト名→パスで安定ソート。
    result.sort_by do |h|
      [h[:is_current] ? 0 : 1, h[:project_name].to_s, h[:path].to_s]
    end
  end
end
