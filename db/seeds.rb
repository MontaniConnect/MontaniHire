User.find_or_create_by!(email: "connect@montani.ph") do |u|
  u.name = "Carlos"
end
