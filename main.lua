local cjson = require("cjson")
local http = require("resty.http")
local ngx = ngx

local token = os.getenv("GOCACHE_DISCOVERY_TOKEN")
local discovery_host  = os.getenv("GOCACHE_DISCOVERY_HOSTNAME")

if not discovery_host or discovery_host == "" then 
   discovery_host = "api-inventory.gocache.com.br"
end

local gcshared = ngx.shared.gocache

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
    ["a-im"]=true,
    ["accept"]=true,
    ["accept-charset"]=true,
    ["accept-datetime"]=true,
    ["accept-encoding"]=true,
    ["accept-language"]=true,
    ["access-control-request-method"]=true,
    ["access-control-request-headers"]=true,
    ["cache-control"]=true,
    ["connection"]=true,
    ["content-encoding"]=true,
    ["content-length"]=true,
    ["content-md5"]=true,
    ["content-type"]=true,
    ["cookie"]=true,
    ["date"]=true,
    ["expect"]=true,
    ["forwarded"]=true,
    ["from"]=true,
    ["host"]=true,
    ["http2-settings"]=true,
    ["if-match"]=true,
    ["if-modified-since"]=true,
    ["if-none-match"]=true,
    ["if-range"]=true,
    ["if-unmodified-since"]=true,
    ["max-forwards"]=true,
    ["origin"]=true,
    ["pragma"]=true,
    ["prefer"]=true,
    ["proxy-authorization"]=true,
    ["range"]=true,
    ["referer"]=true,
    ["sec-fetch-dest"]=true,
    ["sec-fetch-mode"]=true,
    ["sec-fetch-site"]=true,
    ["sec-fetch-user"]=true,
    ["te"]=true,
    ["trailer"]=true,
    ["transfer-encoding"]=true,
    ["user-agent"]=true,
    ["upgrade"]=true,
    ["via"]=true,
    ["warning"]=true,
    ["upgrade-insecure-requests"]=true,
    ["x-requested-with"]=true,
    ["dnt"]=true,
    ["x-forwarded-for"]=true,
    ["x-forwarded-host"]=true,
    ["x-forwarded-proto"]=true,
    ["front-end-https"]=true,
    ["x-http-method-override"]=true,
    ["x-att-deviceid"]=true,
    ["x-wap-profile"]=true,
    ["proxy-connection"]=true,
    ["x-uidh"]=true,
    ["x-csrf-token"]=true,
    ["x-request-id"]=true,
    ["x-correlation-id"]=true,
    ["save-data"]=true,
}

local _M = {}

local function send_api_discovery_request(premature, request_collection)
   if premature then
       return
   end

   local request_info = {
      token = token,
      requests = request_collection,
   }

   local httpc = http.new()

   local res, err = httpc:request_uri("https://"..discovery_host.."/discover/push", {
       method = "POST",
       body = cjson.encode(request_info),
       headers = {
           ["Content-Type"] = "application/json",
       },
   })

   httpc:close()
   if not res then
       err = err or ""
       ngx.log(ngx.ERR,"Error while sending request to api_inventory for " .. cjson.encode(discovery_host) .. " : " .. err)
       return
   end   

   ngx.log(ngx.INFO, "Status code from sending "..(#request_info).." requests for discovery: "..res.status)                     
end

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

   if type(params) == 'table' then 
      for __, data in pairs(params) do 
         collect_cookie(final_cookies,  data)
      end
   else 
      collect_cookie(final_cookies, params)
   end
 
   return final_cookies
end


local function obfuscate_headers(params)
   local final_headers = {}
   for key, content in pairs(params) do 
      if not ignore_headers[key] then
         if type(content) == 'table' then 
            for __, ___ in pairs(content) do 
               final_headers[key] = ""
            end
         else 
            final_headers[key] = ""
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
         header_data = obfuscate_headers(request_headers),
         cookie_data = cookie_data,
      }

      gcshared:lpush("requests", cjson.encode(request_info))


      local last_sent = gcshared:get("last_sent")
      last_sent = tonumber(last_sent) or 0

      if last_sent <= ngx.now() or gcshared:llen("requests") >= 50 then 
         
         gcshared:set("last_sent", ngx.now()+60)
         local content = {}
         for i=1, 50 do 
            local req_info = gcshared:rpop("requests")
            if req_info then 
               local req_data = cjson.decode(req_info)
               content[#content+1] = req_data
            end
         end
         if #content > 0 then 

            ngx.log(ngx.ERR,"Disparando " .. cjson.encode(content))

            ngx.timer.at(1, send_api_discovery_request, content)
         end
      end
   end
end


return _M
