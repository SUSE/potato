def silence_stdout
  @original_stdout = $stdout

  $stdout = StringIO.new

  yield

  $stdout = @original_stdout
  @original_stdout = nil
end

def file_human_size(size_in_bytes)
  ActiveSupport::NumberHelper.number_to_human_size(size_in_bytes)
end
