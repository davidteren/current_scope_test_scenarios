CurrentScope.configure do |config|
  # Probe 6: Symbol form of subject_label.
  config.subject_label = :email

  # Probe 8: custom grid groups. "workflow" names an action ("approve") routed
  # on only ONE controller (admin/reports), and overlaps "read" on "show" —
  # "show" is in two groups at once.
  config.permission_grid_groups = {
    "read" => %w[index show],
    "create" => %w[new create],
    "update" => %w[edit update],
    "destroy" => %w[destroy],
    "workflow" => %w[approve show]
  }

  # Probe 5: engine UI behind the host's admin base controller (admin flag
  # check + layout "admin").
  config.parent_controller = "Admin::BaseController"
end
