# frozen_string_literal: true

module Escalated
  # When a customer (a requester, or a guest's contact) was last seen by the
  # customer portal or the widget. Only ever shown to staff.
  class CustomerPresence < ApplicationRecord
    self.table_name = Escalated.table_name('customer_presence')
  end
end
