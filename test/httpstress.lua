function httpsocketstress()
  local http = require "openbus.util.http"
  http.TIMEOUT = 1

  local array = {}
  local request = http.connect("http://localhost:51398/error")
  for i=1,5000 do
    array[#array+1] = request -- avoid garbage to be collect
    local ok, body, headers = pcall(request, "{\"item\":\"first\"}", "POST")
    if not ok then
      assert(type(body) == "table",
        "expected table as failed http request but got "..type(body))
      assert(body[1]:find("code=500"),
        "expected http status 500 but got another error message: "..tostring(body[1]))
      request = http.connect("http://localhost:51398/error")
    end
  end
end

httpsocketstress()
