# frozen_string_literal: true

# Picks every external TestFlight group. Internal groups stay out.
# A group is external only when is_internal_group is false.
def external_beta_group_names(groups)
  list = Array(groups)
  found = list.map { |group| beta_group_name(group) }.reject(&:empty?)
  external = list.select { |group| external_beta_group?(group) }
                  .map { |group| beta_group_name(group) }
                  .reject(&:empty?)
  { external: external, found: found }
end

def beta_group_name(group)
  beta_group_value(group, :name).to_s.strip
end

def external_beta_group?(group)
  flag = beta_group_value(group, :is_internal_group)
  flag == false || flag.to_s == "false"
end

def beta_group_value(group, key)
  return group.public_send(key) if group.respond_to?(key)
  return nil unless group.respond_to?(:[])

  value = group[key]
  value.nil? ? group[key.to_s] : value
end
