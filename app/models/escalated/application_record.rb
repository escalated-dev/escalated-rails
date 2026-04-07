# frozen_string_literal: true

module Escalated
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
