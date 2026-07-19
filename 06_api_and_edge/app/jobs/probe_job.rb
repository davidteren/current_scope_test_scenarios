# Records what CurrentScope::Current looks like INSIDE a job execution, so a
# test can assert the ambient subject does not flow into Active Job.
class ProbeJob < ApplicationJob
  cattr_accessor :seen_user

  def perform
    self.class.seen_user = CurrentScope::Current.user
  end
end
