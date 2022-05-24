local cjson = require("cjson")
local ngx = ngx
--local gcshared = ngx.shared.gocache

local inventory_max_body_size = 2048

local accepted_request_content_types = {
    "application/json",
    "application/x%-www%-form%-urlencoded",
    "text/plain"
}

local accepted_response_content_types = {
            "application/json",
            "application/xml",
            "text/xml"
}

local ignore_headers = {
   ["host"]                = false,
   ["cookie"]              = false,
   ["user-agent"]          = false,
   ["content-type"]        = false,
   ["content-lenght"]      = false,
}

local _M = {}

local function collect_cookie(collector, content)
   content = content .. ';'
   for segment in content:gmatch("(.-);") do 
      local name = segment:match("[%s%t]*(.-)=.+")
      if name then
         collector[name] = ""
      end
   end
end

local function obfuscate_cookies(params)
   local final_cookies = {}
   for key, content in pairs(params) do 
      if type(content) == 'table' then 
         for __, data in pairs(content) do 
            collect_cookie(final_cookies,  data)
         end
      else 
         collect_cookie(final_cookies, content)
      end
   end
   return final_cookies
end


local function obfuscate_headers(params)
   local final_headers = {}
   for key, content in pairs(params) do 
      ngx.log(ngx.ERR, "Add is: "..cjson.encode(key).." - "..cjson.encode(content))
      if not ignore_headers[key] then
         if type(content) == 'table' then 
            for __, ___ in pairs(content) do 
               final_headers[#final_headers+1] = key
            end
         else 
            final_headers[#final_headers+1] = key
         end
      end
   end
   return final_headers
end

local function obfuscate_parameters(params)

   local check_type = {}
            
   check_type["table"] = function()
      if params[1] ~= nil then
         local arrElement = params[1]
         params = nil
         params = {obfuscate_parameters(arrElement)}
      else
         for k, v in pairs(params) do
            params[k] = obfuscate_parameters(v)
         end
      end
      return params
   end
   check_type["string"] = function()
       return ""
   end
   check_type["boolean"] = function()
       return false
   end
   check_type["number"] = function()
       return 0
   end

   return check_type[type(params)]()
end


function _M.log()

   local response_headers = ngx.resp.get_headers()
   local res_content_type = response_headers["content_type"]

   local add = false
   if tonumber(ngx.var.status) == 200 and res_content_type ~= nil then
      for _, ct in ipairs(accepted_response_content_types) do
         if res_content_type:match(ct) then
            add = true 
         end
      end
   end
   ngx.log(ngx.ERR, "Add is: "..cjson.encode(add))

   if add then
      local request_headers = ngx.req.get_headers()

      local req_content_type = request_headers.content_type

      local body_data
      for _, ct in ipairs(accepted_request_content_types) do
          if req_content_type:match(ct) then
              local raw_body_data = ngx.req.get_body_data()
              if raw_body_data ~= nil and #raw_body_data < inventory_max_body_size then

                  local success, jsonData = pcall(cjson.decode, raw_body_data) 
                  if success then
                      body_data = jsonData
                  else
                      body_data = ngx.req.get_post_args()
                  end
                  break
              end
          end
      end
      local body_info

      if body_data ~= nil then
          local obfuscated_body_data = obfuscate_parameters(body_data)
          body_info = cjson.encode(obfuscated_body_data)
      end

      local cookie_data
      local cookies = request_headers['cookie']
      if cookies then 
         cookie_data = obfuscate_cookies(cookies)
      end
               
      local request_info = {
          hostname = ngx.var.http_host,
          uri = ngx.var.request_uri,
          status = ngx.status,
          method = ngx.var.request_method,
          res_content_type = res_content_type,
          req_content_type = req_content_type,
          body_data = body_info,
          headers = obfuscate_headers(request_headers),
          cookie_data = cookie_data,
      }


      ngx.log(ngx.ERR, "Request data: "..cjson.encode(request_info))
   end


end


return _M
