#
# Copyright (C) 2011 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

module Api::V1::Role
  include Api::V1::Json
  include Api::V1::Account

  def role_json(account, role, current_user, session)
    base_role_type, workflow_state = Role.get_base_role_and_workflow_state(role, account)
    json = {
      :account => account_json(account, current_user, session, []),
      :role => role,
      :base_role_type => base_role_type,
      :workflow_state => workflow_state,
      :permissions => {}
    }

    RoleOverride.manageable_permissions(account).keys.each do |permission|
      json[:permissions][permission] = permission_json(RoleOverride.permission_for(account, permission, base_role_type, role), current_user, session)
    end

    json
  end

  def permission_json(permission, current_user, session)
    permission.slice(:enabled, :locked, :readonly, :explicit, :prior_default)
  end
end

