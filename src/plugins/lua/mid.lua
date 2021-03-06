--[[
Copyright (c) 2016, Alexander Moisseev <moiseev@mezonplus.ru>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
]]--

--[[
MID plugin - suppress INVALID_MSGID and MISSING_MID for messages originating
from listed valid DKIM domains with missed or known proprietary Message-IDs
]]--

local rspamd_logger = require "rspamd_logger"
local rspamd_regexp = require "rspamd_regexp"

local settings = {
  url = '',
  symbol_known_mid = 'KNOWN_MID',
  symbol_known_no_mid = 'KNOWN_NO_MID',
  symbol_invalid_msgid = 'INVALID_MSGID',
  symbol_missing_mid = 'MISSING_MID',
  symbol_dkim_allow = 'R_DKIM_ALLOW',
  csymbol_invalid_msgid_allowed = 'INVALID_MSGID_ALLOWED',
  csymbol_missing_mid_allowed = 'MISSING_MID_ALLOWED',
}

local map = {}

local E = {}

local function known_mid_cb(task)
  local re = {}
  local header = task:get_header('Message-Id')
  local das = task:get_symbol(settings['symbol_dkim_allow'])
  if ((das or E)[1] or E).options then
    for _,dkim_domain in ipairs(das[1]['options']) do
      local v = map:get_key(dkim_domain)
      if v then
        if v == '' then
          if not header then
            task:insert_result(settings['symbol_known_no_mid'], 1, dkim_domain)
            return
          end
        else
          re[dkim_domain] = rspamd_regexp.create_cached(v)
          if header and re[dkim_domain] and re[dkim_domain]:match(header) then
              task:insert_result(settings['symbol_known_mid'], 1, dkim_domain)
              return
          end
        end
      end
    end
  end
end

local opts =  rspamd_config:get_all_opt('mid')
if opts then
  for k,v in pairs(opts) do
    settings[k] = v
  end

  map = rspamd_map_add('mid', 'source', 'map', 'Message-IDs map')
  if map then
    local id = rspamd_config:register_symbol({
      name = 'KNOWN_MID_CALLBACK',
      type = 'callback',
      callback = known_mid_cb
    })
    rspamd_config:register_symbol({
      name = settings['symbol_known_mid'],
      parent = id,
      type = 'virtual'
    })
    rspamd_config:register_symbol({
      name = settings['symbol_known_no_mid'],
      parent = id,
      type = 'virtual'
    })
    rspamd_config:add_composite(settings['csymbol_invalid_msgid_allowed'],
      settings['symbol_known_mid'] .. ' & ' .. settings['symbol_invalid_msgid'])
    rspamd_config:add_composite(settings['csymbol_missing_mid_allowed'],
      settings['symbol_known_no_mid'] .. ' & ' .. settings['symbol_missing_mid'])

    rspamd_config:register_dependency(id, settings['symbol_dkim_allow'])
  else
    rspamd_logger.infox(rspamd_config, 'source is not specified, disabling module')
  end
end
