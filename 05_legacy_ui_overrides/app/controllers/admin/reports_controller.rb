module Admin
  class ReportsController < Admin::BaseController
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
      redirect_to admin_report_path(@report)
    end

    def edit
      set_report
    end

    def update
      set_report.update!(report_params)
      redirect_to admin_report_path(@report)
    end

    def destroy
      set_report.destroy!
      redirect_to admin_reports_path
    end

    def approve
      set_report.update!(state: "approved")
      redirect_to admin_report_path(@report)
    end

    private

    def set_report = @report ||= Report.find(params[:id])

    def current_scope_record
      set_report if request.path_parameters[:id]
    end

    def report_params = params.expect(report: [ :title, :state ])
  end
end
