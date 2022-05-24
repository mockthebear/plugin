local ngx = ngx

local _M = {}

function _M.header_filter()

   ngx.header["X-My-Header"] =  "1"

end

return _M
