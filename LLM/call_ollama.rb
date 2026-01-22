# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

def call_ollama(query, temperature: 0.4, model: "llama3",
                url: "https://noncurrently-unfollowed-wes.ngrok-free.dev/api/generate",
                open_timeout: 5, read_timeout: 120)

  payload = {
    model: model,
    options: {
      temperature: temperature
    },
    think: false,
    prompt: query,
    stream: false
  }

  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == "https")
  http.open_timeout = open_timeout
  http.read_timeout = read_timeout

  req = Net::HTTP::Post.new(uri.request_uri)
  req["Content-Type"] = "application/json"
  req["ngrok-skip-browser-warning"] = "1"
  req.body = JSON.generate(payload)

  res = http.request(req)

  unless res.is_a?(Net::HTTPSuccess)
    warn "Error getting Ollama response: HTTP #{res.code} #{res.message}"
    warn res.body.to_s[0, 2000]
    warn "Is ngrok running on your Macbook? Use: ngrok http --host-header=rewrite 11434"
    return nil
  end

  data = JSON.parse(res.body)
  data["response"]

rescue JSON::ParserError => e
  warn "Error parsing Ollama JSON: #{e.message}"
  warn "Body: #{res&.body.to_s[0, 2000]}"
  nil
rescue StandardError => e
  warn "Error getting Ollama response: #{e.message}"
  warn "Is ngrok running on your Macbook? Use: ngrok http --host-header=rewrite 11434"
  nil
end