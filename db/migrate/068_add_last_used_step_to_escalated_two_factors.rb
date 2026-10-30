# frozen_string_literal: true

# The TOTP time step last accepted for an enrolment, so a code works once
# (ADR 2026-10-29-configurable-access-features).
class AddLastUsedStepToEscalatedTwoFactors < ActiveRecord::Migration[7.0]
  def change
    add_column Escalated.table_name('two_factors'), :last_used_step, :bigint
  end
end
