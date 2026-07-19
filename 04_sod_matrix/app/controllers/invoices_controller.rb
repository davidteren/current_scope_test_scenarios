# Approvable like Expense, but Invoice has NO current_scope_initiator hook —
# scenario 3 probes the loud ConfigurationError.
class InvoicesController < ApplicationController
  def index
    @invoices = Invoice.order(:id)
    render plain: @invoices.map(&:id).join(",")
  end

  def show = render plain: "invoice #{set_invoice.id}"

  def approve = render plain: "approved invoice #{set_invoice.id}"

  private

  def set_invoice = @invoice ||= Invoice.find(params.expect(:id))

  def current_scope_record
    set_invoice if request.path_parameters[:id]
  end
end
