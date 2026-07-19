# The god controller: 27 routed actions, three models, mixed concerns.
# Simulates a decade of accretion. Structure is intentional for the
# current_scope retrofit probes (catalog scale, multi-model hook, grid).
class LegacyController < ApplicationController
  # Probe 6: incremental adoption escape hatch — dashboard stays ungated on
  # THIS controller only. A single `if:` (not `only:` + `if:`, and not a
  # subclass `before_action ... only:`) so subclasses can re-enable the gate
  # by overriding skip_dashboard_gate? without narrowing Guard for every action
  # (ie-audit P1 / F5).
  skip_before_action :current_scope_check!, if: :skip_dashboard_gate?

  ARCHIVE_OLD_CUTOFF = 30.days

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

  # --- imports ---
  def import
    Customer.create!(name: "Imported #{Time.current.to_i}", active: true, assigned: false)
    redirect_to "/legacy/dashboard", notice: "imported"
  end

  def import_preview
    render json: { preview: true }
  end

  # --- bulk ops ---
  def bulk_update
    Customer.update_all(active: true)
    redirect_to "/legacy/dashboard", notice: "bulk updated"
  end

  def bulk_delete
    # Treat NULL active as inactive (column is nullable with no default).
    deleted = Customer.where(active: [ false, nil ]).delete_all
    redirect_to "/legacy/dashboard", notice: "bulk deleted #{deleted}"
  end

  # --- :id member-ish actions, each touching a DIFFERENT model ---
  def toggle_active # Customer
    c = Customer.find(params[:id])
    c.update!(active: !c.active)
    redirect_to "/legacy/dashboard", notice: "toggled #{c.name}"
  end

  def assign # Customer
    c = Customer.find(params[:id])
    c.update!(assigned: true)
    redirect_to "/legacy/dashboard", notice: "assigned #{c.name}"
  end

  def unassign # Customer
    c = Customer.find(params[:id])
    c.update!(assigned: false)
    redirect_to "/legacy/dashboard", notice: "unassigned #{c.name}"
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
    denied = Order.where(status: "pending").update_all(status: "denied")
    redirect_to "/legacy/dashboard", notice: "denied #{denied}"
  end

  def settings
    @site_name = Setting["site_name"]
  end

  def update_settings
    Setting["site_name"] = params[:site_name].to_s
    redirect_to "/legacy/settings", notice: "saved"
  end

  def search
    render plain: "results for #{params[:q]}"
  end

  def advanced_search
    render json: { q: params[:q], advanced: true }
  end

  def email_report
    ReportDelivery.create!(kind: "legacy_email_report", user: current_user)
    redirect_to "/legacy/dashboard", notice: "emailed"
  end

  def merge_records
    # Treat NULL active as inactive (column is nullable with no default).
    merged = Customer.where(active: [ false, nil ]).update_all(name: "Merged")
    redirect_to "/legacy/dashboard", notice: "merged #{merged}"
  end

  def archive_old
    archived = Order.where("created_at < ?", ARCHIVE_OLD_CUTOFF.ago)
                    .where(archived: [ false, nil ])
                    .update_all(archived: true)
    redirect_to "/legacy/dashboard", notice: "archived #{archived} old"
  end

  def purge
    purged = Order.where(archived: true).delete_all
    redirect_to "/legacy/dashboard", notice: "purged #{purged}"
  end

  # Defined but deliberately NOT routed (probe 8): should be absent from the
  # permission catalog and unreachable.
  def secret_unrouted
    render plain: "you should never see this"
  end

  private

  # True only for legacy#dashboard. Override to false in subclasses that must
  # keep their own dashboard permission enforced (LegacySubController).
  def skip_dashboard_gate?
    action_name == "dashboard"
  end

  # Probe 5: ONE hook per controller, but the record type depends on the
  # action. The gem gives you a single current_scope_record seam, so a god
  # controller ends up hand-maintaining an action->model dispatch table.
  # "assign"/"unassign" are deliberately ABSENT from the map to document the
  # fail direction: an :id action without record loading can never be unlocked
  # by a scoped role (fail closed). Bodies still load the Customer for the
  # org-wide grant path so the verb actually mutates.
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
