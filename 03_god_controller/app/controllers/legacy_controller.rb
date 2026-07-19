# The god controller: 27 routed actions, three models, mixed concerns.
# Simulates a decade of accretion.
class LegacyController < ApplicationController
  # Probe 6: incremental adoption escape hatch — dashboard stays ungated while
  # the rest of the god controller is behind the gate.
  skip_before_action :current_scope_check!, only: [ :dashboard ]

  # --- dashboards & reports (render) ---
  def dashboard; end

  def stats
    render json: { customers: Customer.count, orders: Order.count, widgets: Widget.count }
  end

  def users_report
    render plain: User.pluck(:name).join("\n")
  end

  def orders_report
    render plain: Order.pluck(:number).join("\n")
  end

  # --- exports (render various formats) ---
  def export_csv
    render plain: Customer.pluck(:name).join(","), content_type: "text/csv"
  end

  def export_pdf
    render plain: "%PDF-1.4 fake", content_type: "application/pdf"
  end

  def export_xml
    render xml: { customers: Customer.count }
  end

  # --- imports (redirect) ---
  def import
    redirect_to "/legacy/dashboard", notice: "imported"
  end

  def import_preview
    render json: { preview: true }
  end

  # --- bulk ops (redirect) ---
  def bulk_update
    Customer.update_all(active: true)
    redirect_to "/legacy/dashboard", notice: "bulk updated"
  end

  def bulk_delete
    redirect_to "/legacy/dashboard", notice: "bulk deleted"
  end

  # --- :id member-ish actions, each touching a DIFFERENT model ---
  def toggle_active # Customer
    c = Customer.find(params[:id])
    c.update!(active: !c.active)
    redirect_to "/legacy/dashboard", notice: "toggled #{c.name}"
  end

  def assign # Customer
    Customer.find(params[:id])
    redirect_to "/legacy/dashboard", notice: "assigned"
  end

  def unassign # Customer
    Customer.find(params[:id])
    redirect_to "/legacy/dashboard", notice: "unassigned"
  end

  def print_view # Widget
    w = Widget.find(params[:id])
    render plain: "PRINT #{w.name}"
  end

  def duplicate_record # Widget
    w = Widget.find(params[:id])
    Widget.create!(name: "#{w.name} copy")
    redirect_to "/legacy/dashboard", notice: "duplicated"
  end

  def restore # Order
    o = Order.find(params[:id])
    o.update!(archived: false)
    render json: { restored: o.number }
  end

  # --- approvals / settings / search ---
  def approve_all
    Order.where(status: "pending").update_all(status: "approved")
    redirect_to "/legacy/dashboard", notice: "approved all"
  end

  def deny_all
    redirect_to "/legacy/dashboard", notice: "denied all"
  end

  def settings; end

  def update_settings
    redirect_to "/legacy/settings", notice: "saved"
  end

  def search
    render plain: "results for #{params[:q]}"
  end

  def advanced_search
    render json: { q: params[:q], advanced: true }
  end

  def email_report
    redirect_to "/legacy/dashboard", notice: "emailed"
  end

  def merge_records
    redirect_to "/legacy/dashboard", notice: "merged"
  end

  def archive_old
    Order.update_all(archived: true)
    redirect_to "/legacy/dashboard", notice: "archived"
  end

  def purge
    redirect_to "/legacy/dashboard", notice: "purged"
  end

  # Defined but deliberately NOT routed (probe 8): should be absent from the
  # permission catalog and unreachable.
  def secret_unrouted
    render plain: "you should never see this"
  end

  private

  # Probe 5: ONE hook per controller, but the record type depends on the
  # action. The gem gives you a single current_scope_record seam, so a god
  # controller ends up hand-maintaining an action->model dispatch table.
  # "assign"/"unassign" are deliberately ABSENT from the map to document the
  # fail direction: an :id action without record loading can never be unlocked
  # by a scoped role (fail closed).
  RECORD_CLASS_BY_ACTION = {
    "toggle_active"    => Customer,
    "print_view"       => Widget,
    "duplicate_record" => Widget,
    "restore"          => Order
  }.freeze

  def current_scope_record
    klass = RECORD_CLASS_BY_ACTION[action_name]
    return unless klass && request.path_parameters[:id]

    @current_scope_record ||= klass.find(request.path_parameters[:id])
  end
end
