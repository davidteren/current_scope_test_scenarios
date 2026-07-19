class DashboardController < ApplicationController
  def show
    @reports = Report.all
  end
end
