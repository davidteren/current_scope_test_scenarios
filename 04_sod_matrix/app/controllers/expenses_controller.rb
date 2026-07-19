class ExpensesController < ApplicationController
  # ponytail: test seam — scenario 4 flips this to simulate the "member action
  # whose current_scope_record returns nil" mistake without editing code.
  cattr_accessor :simulate_nil_record, default: false

  def index
    @expenses = Expense.order(:id)
  end

  def show = render plain: "expense #{set_expense.id}"

  def new = render plain: "new expense form"

  def create
    expense = Expense.create!(expense_params)
    redirect_to expense_path(expense)
  end

  def edit = render plain: "edit expense #{set_expense.id}"

  def update
    set_expense.update!(expense_params)
    redirect_to expense_path(set_expense)
  end

  def destroy
    set_expense.destroy!
    redirect_to expenses_path
  end

  def approve = render plain: "approved expense #{set_expense.id}"

  def reject = render plain: "rejected expense #{set_expense.id}"

  def approve_all = render plain: "approved all #{Expense.count} expenses"

  private

  def set_expense = @expense ||= Expense.find(params.expect(:id))

  def expense_params
    params.expect(expense: [ :description, :amount_cents, :requested_by_id, :sod_bypass_requested ])
  end

  def current_scope_record
    return nil if self.class.simulate_nil_record

    set_expense if request.path_parameters[:id]
  end
end
