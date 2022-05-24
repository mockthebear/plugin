
local ngx = ngx

local _M = {}

function _M.header_filter()
   ngx.log(ngx.ERR, "owo sussy baka")
   ngx.header["X-My-Header"] =  "2"

end


function _M.log()
   ngx.log(ngx.ERR, "The greater UwU")
end


return _M
