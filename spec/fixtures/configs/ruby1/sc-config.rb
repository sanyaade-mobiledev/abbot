# RUBY CONFIG VARIATION
# NOTE: Same test as ruby2 -- just different filename

# Test with no explicit "mode" specified
config :block do |c| # block form
  c[:a] = :a
end
config :param, :a => :a # param form

# Test with block
mode :all do
  config :block do |c|
    c[:b] = :b
  end
  
  config :param, :b => :b
end

# Test with other block
mode :debug do
  config :block do |c|
    c[:a_debug] = :a
    c[:b_debug] = :b
  end
  config :param, :a_debug => :a, :b_debug => :b
end


# Other Tests -- do not scope to a mode..
proxy '/block' do |c|
  c[:a] = :a
  c[:b] = :b
end

proxy '/param', :a => :a, :b => :b
