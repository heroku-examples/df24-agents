namespace :user do
  desc "Greet the user interactively"
  task :greet do
    puts "What's your name?"
    name = $stdin.gets.chomp
    puts "Hello, #{name}!"
  end
end
