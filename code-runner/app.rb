require 'webrick'
require 'json'
require 'stringio'
require 'timeout'

server = WEBrick::HTTPServer.new(Port: 4567, BindAddress: '0.0.0.0')

server.mount_proc '/execute' do |req, res|
  res.content_type = 'application/json'

  begin
    data = JSON.parse(req.body)
    code = data['payload']['code']
    timeout_seconds = data['timeout'] || 3
    result = nil
    output = ""
    error = nil

    begin
      Timeout.timeout(timeout_seconds) do
        old_stdout = $stdout
        $stdout = StringIO.new
        begin
          result = eval(code)
          output = $stdout.string
        rescue Exception => e
          error = e.message
        ensure
          $stdout = old_stdout
        end
      end
    rescue Timeout::Error
      error = "Execution timed out after #{timeout_seconds} seconds"
    end

    res.body = { result: result.inspect, output: output, error: error }.to_json
  rescue JSON::ParserError => e
    res.status = 400
    res.body = { error: "Invalid JSON: #{e.message}" }.to_json
  end
end

trap('INT') { server.shutdown }
server.start
