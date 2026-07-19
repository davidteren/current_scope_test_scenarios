class ReportsController < ApplicationController
  def index
    @reports = Report.all
  end

  def show
    set_report
  end

  def new
    @report = Report.new
  end

  def create
    @report = Report.create!(report_params)
    redirect_to @report
  end

  def edit
    set_report
  end

  def update
    set_report.update!(report_params)
    redirect_to @report
  end

  def destroy
    set_report.destroy!
    redirect_to reports_path
  end

  private

  def set_report = @report ||= Report.find(params[:id])

  def current_scope_record
    set_report if request.path_parameters[:id]
  end

  def report_params = params.expect(report: [ :title, :state ])
end
