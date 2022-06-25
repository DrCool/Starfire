class MyClass
  def run
    puts 'Totem provides a few class variables to simplify programming...'
    puts "  Root: #{Totem.root}"
    puts "  Environment: #{Totem.env}"
    puts

    puts 'Totem includes a logger...'
    Totem.logger.error('Example error log entry')
    puts "  Check your #{Totem.log_file_path} to see the entry."
    puts

    puts 'Enjoy!'

  end
end

