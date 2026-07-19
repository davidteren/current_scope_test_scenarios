class ReportsController < ApplicationController
  before_action :set_report, only: %i[show edit update destroy approve reject publish archive clone]

  # --- CRUD -----------------------------------------------------------------
  def index
    @reports = scope_for(Report).order(:id)
  end

  def show; end

  def new
    @report = Report.new
  end

  def create
    @report = Report.new(report_params.merge(requested_by: current_user))
    @report.save!
    redirect_to @report
  end

  def edit; end

  def update
    @report.update!(report_params)
    redirect_to @report
  end

  def destroy
    @report.destroy!
    redirect_to reports_path
  end

  # --- Custom member actions --------------------------------------------------
  def approve  = transition("approved")
  def reject   = transition("rejected")
  def publish  = transition("published")
  def archive  = transition("archived")

  def clone
    copy = @report.dup.tap { |r| r.state = "draft" }
    copy.save!
    redirect_to copy
  end

  # --- Custom collection actions -----------------------------------------------
  def export
    render plain: Report.order(:id).map { |r| "#{r.id},#{r.title},#{r.state}" }.join("\n")
  end

  def bulk_archive
    Report.update_all(state: "archived")
    redirect_to reports_path
  end

  # match via: [:get, :post]
  def search
    @reports = Report.where("title LIKE ?", "%#{params[:q]}%").order(:id)
    render plain: "search[#{request.method}]: #{@reports.map(&:title).join(", ")}"
  end

  def preview_all
    render plain: Report.order(:id).map(&:title).join(" | ")
  end

  private

  def set_report = @report ||= Report.find(params.expect(:id))

  # Record-level hook: member actions get the record, collection actions nil.
  def current_scope_record
    set_report if request.path_parameters[:id]
  end

  def report_params = params.expect(report: [ :title, :state ])

  def transition(state)
    @report.update!(state: state)
    redirect_to @report
  end
end
