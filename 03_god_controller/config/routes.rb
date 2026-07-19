Rails.application.routes.draw do
  mount CurrentScope::Engine => "/current_scope"
  get "up" => "rails/health#show", as: :rails_health_check

  resources :sessions, only: [ :index, :create ]
  delete "logout" => "sessions#destroy"
  root "sessions#index"

  # --- the god controller: 27 individually-routed actions, legacy style ---
  get  "legacy/dashboard"       => "legacy#dashboard"
  get  "legacy/stats"           => "legacy#stats"
  get  "legacy/users_report"    => "legacy#users_report"
  get  "legacy/orders_report"   => "legacy#orders_report"
  get  "legacy/export_csv"      => "legacy#export_csv"
  get  "legacy/export_pdf"      => "legacy#export_pdf"
  get  "legacy/export_xml"      => "legacy#export_xml"
  post "legacy/import"          => "legacy#import"
  post "legacy/import_preview"  => "legacy#import_preview"
  post "legacy/bulk_update"     => "legacy#bulk_update"
  post "legacy/bulk_delete"     => "legacy#bulk_delete"
  post "legacy/approve_all"     => "legacy#approve_all"
  post "legacy/deny_all"        => "legacy#deny_all"
  get  "legacy/settings"        => "legacy#settings"
  post "legacy/update_settings" => "legacy#update_settings"
  get  "legacy/search"          => "legacy#search"
  get  "legacy/advanced_search" => "legacy#advanced_search"
  post "legacy/email_report"    => "legacy#email_report"
  post "legacy/merge_records"   => "legacy#merge_records"
  post "legacy/archive_old"     => "legacy#archive_old"
  post "legacy/purge"           => "legacy#purge"
  # --- probe 7: subclass with its own controller_path, inheriting actions ---
  get "legacy_sub/dashboard" => "legacy_sub#dashboard"
  get "legacy_sub/stats"     => "legacy_sub#stats"
  get "legacy_sub/only_here" => "legacy_sub#only_here"

  # :id member routes — record type varies by action (Customer/Widget/Order)
  post "legacy/:id/toggle_active"    => "legacy#toggle_active"
  post "legacy/:id/assign"           => "legacy#assign"
  post "legacy/:id/unassign"         => "legacy#unassign"
  get  "legacy/:id/print_view"       => "legacy#print_view"
  post "legacy/:id/duplicate_record" => "legacy#duplicate_record"
  post "legacy/:id/restore"          => "legacy#restore"
end
