# frozen_string_literal: true

require "async"
require "async/http/endpoint"
require "async/http/server"
require "json"
require "protocol/http/response"
require "socket"

# Local stand-in for personal.connectapi.garmin.com. Records every request and answers from
# registered routes; the token endpoint issues JWT-shaped tokens unless overridden.
class FakeGarmin
  Request = Data.define(:http_method, :path, :headers)

  API_KEY = "test-api-key"
  TOKEN_PATH = "/personalapitoken-service/personal-api/personal-api-key/token"

  attr_reader :requests, :url

  def self.jwt(exp:) = ["e30", [JSON.generate("exp" => exp)].pack("m0").tr("+/", "-_").delete("="), "sig"].join(".")

  def initialize
    @requests = []
    @routes = {}
    @issued = 0
    route("POST", TOKEN_PATH) do |request|
      next [401, {}, "invalid key"] unless request.headers["authorization"] == "ApiKey #{API_KEY}"

      @issued += 1
      [200, { "content-type" => "text/plain" }, self.class.jwt(exp: Time.now.to_i + 86_400) + ".#{@issued}"]
    end
  end

  # Handler receives a Request and returns [status, headers, body].
  def route(method, path, &handler) = @routes[[method, path]] = handler

  def json(path, data, status: 200) = route("GET", path) { [status, { "content-type" => "application/json" }, JSON.generate(data)] }

  def start(task = Async::Task.current)
    port = TCPServer.open("127.0.0.1", 0) { |server| server.addr[1] }
    @url = "http://127.0.0.1:#{port}"
    endpoint = Async::HTTP::Endpoint.parse(@url)
    server = Async::HTTP::Server.for(endpoint) { |request| handle(request) }
    @task = task.async { server.run.wait }
    self
  end

  def stop = @task&.stop

  def requests_to(path) = requests.select { |request| request.path.split("?").first == path }

  private

  def handle(request)
    headers = request.headers.to_h.transform_values { |value| Array(value).join(", ") }
    recorded = Request.new(http_method: request.method, path: request.path, headers:)
    @requests << recorded
    request.body&.finish
    handler = @routes[[request.method, request.path.split("?").first]]
    status, response_headers, body = handler ? handler.call(recorded) : [404, {}, "not found"]
    Protocol::HTTP::Response[status, response_headers.to_a, [body]]
  end
end
