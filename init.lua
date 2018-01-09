
--[[

mt2fa server side mod

--]]

-- allocate API stuff

local S = minetest.settings
assert(S)

local req_reg = S:get_bool("mt2fa.require_registration") or false
local req_auth = S:get_bool("mt2fa.require_authentication") or false
local reg_api = S:get("mt2fa.api_server") or "https://mt2fa.foo-projects.org/mt2fa"
local reg_id = S:get("mt2fa.server_id") --nil when first starting server
local reg_grace = S:get("mt2fa.grace") or 300 -- period before enforcement starts

minetest.log("verbose", "mt2fa: requiring: registration(" .. tostring(req_reg) .. "), " ..
		"authentication(" .. tostring(req_auth) .. ")")

local http = minetest.request_http_api()
assert(http, "HTTP API unavailable. Please add `mt2fa` to secure.trusted_mods in minetest.conf!")

local message = {
	REG = "Registration request sent.",
	AUTH = "Authentication request sent.",
	ACCT = "Verifying account information, please wait.",
	SERVER = "Server registration request sent.",
	SERVERIP = "Server IP change request sent.",
}

local forms = {
	email =
		"size[10,8]"..
		"label[1,1;" ..
		"Please type your email address. You will need to be\n" ..
		"able to receive email and click on a link that is sent\n" ..
		"to you at the address. If you lose the email address,\n" ..
		"you may lose all access to this server.]" ..
		"button_exit[6,7;3,1;OK;OK]"..
		"field[1,6;8,1;email;email address;]",

	register =
		"size[10,8]"..
		"label[1,1;" ..
		"This server allows you to register your account using\n" ..
		"2-factor authentication and link your account to an\n" ..
		"email address. This allows you to recover your account\n" ..
		"on this server in case you forget your password. It also\n" ..
		"may prevent unauthorized access to your account on this\n" ..
		"server or any other server that uses this service. This\n" ..
		"process is voluntary. If you decide to opt out, you can\n" ..
		"at any time later opt in.]" ..
		"button_exit[1,7;3,1;nothanks;No thanks]"..
		"button_exit[6,7;3,1;register;Register]",
}

local logins = {}
local privs = {}

--
-- loop our waiting message. If the player presses `escape` it will just restart it
-- as long as our context is valid. If the network code callback is reached, we
-- invalidate the context and abort this wait screen.
--
local function do_wait(player, context)
	fsc.show(player:get_player_name(),
		"size[10,8]label[1,1;" .. context.message .. "]",
		context,
		function(p, fields, c)
			minetest.after(0.1, do_wait, p, c)
			return true
		end)
end

local function do_msg(player, context)
	fsc.show(player:get_player_name(),
		"size[10,8]label[1,1;" .. context.message .. "]" ..
		"button_exit[6,7;3,1;OK;OK]",
		context,
		function(p, fields, c)
			return true
		end)
end

local function send_request(request_type, player, context)
	minetest.log("action", "mt2fa: sending " .. request_type .. " for " .. player:get_player_name())
	-- initial player message may be needed
	if message[request_type] then
		context.message = message[request_type]
	end
	do_wait(player, context)
	-- perform the request
	http.fetch({
		url = reg_api,
		post_data = minetest.write_json({
			request_type = request_type,
			player = player:get_player_name(),
			server_id = reg_id,
			email = context.email,
			cookie = context.cookie,
			server_data = context.server_data,
		}),
		timeout = 15,
	}, function(res)
		assert(res.completed)
		if not res.succeeded then
			-- major problem, retry
			minetest.log("error", "mt2fa: server replied with an error code")
			do_wait(player, context)
			minetest.after(15, send_request, request_type, player, context)
			return
		end
		local data = minetest.parse_json(res.data)
		if not data then
			-- major problem, retry
			minetest.log("error", "mt2fa: failed to parse JSON from mt2fa server")
			do_wait(player, context)
			minetest.after(15, send_request, request_type, player, context)
			return
		end

		minetest.log("action", "mt2fa: received " .. data.result .. " for " .. player:get_player_name())

		-- update user message
		context.message = data.info

		-- process result
		if request_type == "REG" then
			if data.result == "REGPEND" then
				context.cookie = data.data.Cookie
				minetest.after(10, send_request, "REGSTAT", player, context)
			elseif data.result == "REGOK" then
				-- record email address for this user in a user attribute, permanently
				player:set_attribute("mt2fa.registered", "1")
				-- signal success to the player
				fsc.show(player:get_player_name(),
					"size[10,8]label[1,1;" .. context.message .. "]" ..
					"button_exit[6,7;3,1;OK;OK]",
					context,
					function(p, fields, c)
						-- proceed to authentication if needed
						if req_auth or p:get_attribute("mt2fa.auth_required") then
							send_request("AUTH", p, c)
						else
							send_request("ACCT", p, c)
						end
						return true
					end)
			else
				-- display error, retry new email?
				do_wait(player, context)
				minetest.after(15, send_request, request_type, player, context)
				return
			end
		elseif request_type == "REGSTAT" then
			if data.result == "REGPEND" then
				minetest.after(10, send_request, "REGSTAT", player, context)
				do_wait(player, context)
			elseif data.result == "REGOK" then
				-- record email address for this user in a user attribute, permanently
				player:set_attribute("mt2fa.registered", "1")
				-- signal success to the player
				fsc.show(player:get_player_name(),
					"size[10,8]label[1,1;" .. context.message .. "]" ..
					"button_exit[6,7;3,1;OK;OK]",
					context,
					function(p, fields, c)
						-- proceed to authentication if needed
						if req_auth or p:get_attribute("mt2fa.auth_required") then
							send_request("AUTH", p, c)
						else
							send_request("ACCT", p, c)
						end
						return true
					end)

			else
				-- error, retry?
				do_wait(player, context)
				minetest.after(15, send_request, request_type, player, context)
				return
			end
		elseif request_type == "SERVER" then
			if data.result == "SERVERPEND" then
				context.cookie = data.data.Cookie
				minetest.after(10, send_request, "SERVERSTAT", player, context)
			else
				-- error, retry?
				do_wait(player, context)
				minetest.after(15, send_request, request_type, player, context)
				return
			end
		elseif request_type == "SERVERSTAT" then
			if data.result == "SERVEROK" then
				-- signal success to the player
				S:set("mt2fa.server_id", data.data.Server_id)
				reg_id = data.data.Server_id
				do_msg(player, context)
			elseif data.result == "SERVERPEND" then
				minetest.after(10, send_request, "SERVERSTAT", player, context)
				do_wait(player, context)
			else
				-- unknown data error
				do_msg(player, context)
				return
			end
		elseif request_type == "SERVERIP" then
			if data.result == "SERVERIPPEND" then
				context.cookie = data.data.Cookie
				minetest.after(10, send_request, "SERVERIPSTAT", player, context)
			else
				-- error, retry?
				do_wait(player, context)
				minetest.after(15, send_request, request_type, player, context)
				return
			end
		elseif request_type == "SERVERIPSTAT" then
			if data.result == "SERVERIPOK" then
				-- signal success to the player
				do_msg(player, context)
			elseif data.result == "SERVERIPPEND" then
				minetest.after(10, send_request, "SERVERIPSTAT", player, context)
				do_wait(player, context)
			else
				-- unknown data error
				do_msg(player, context)
				return
			end
		elseif request_type == "ACCT" then
			if data.result == "ACCTOK" then
				if data.auth_required == "1" then
					-- do auth
					send_request("AUTH", player, context)
				end
				do_msg(player, context) -- maybe just a chat msg here?
			else
				do_msg(player, context)
			end
		elseif request_type == "AUTH" then
			if data.result == "AUTHPEND" then
				context.cookie = data.data.Cookie
				-- no need to send this right away so fast
				minetest.after(10, send_request, "AUTHSTAT", player, context)
			else
				do_msg(player, context)
			end
		elseif request_type == "AUTHSTAT" then
			if data.result == "AUTHOK" then
				local name = player:get_player_name()
				minetest.close_formspec(player:get_player_name(), "")
				minetest.chat_send_player(name, context.message)
				-- mark successful
				minetest.set_player_privs(name, privs[name])
				logins[name] = nil
				privs[name] = nil
			elseif data.result == "AUTHPEND" then
				minetest.after(10, send_request, "AUTHSTAT", player, context)
			else
				do_msg(player, context)
				-- boot player?
			end
		else
			assert("we sent an incorrect request, our bad")
		end
	end)
end

-- join/leave stuff

minetest.after(0, function()
	--
	-- warn through log entries that registration has not been completed yet
	--
	if not reg_id then
		minetest.log("error", "mt2fa: This server needs to be registered with a mt2fa server in order to" ..
			"allow players without the \"server\" priv to log on. To register, use `/mt2fa register <email>` " ..
			"to start the registation process.")
	end
end)

minetest.register_on_joinplayer(function(player)
	--
	-- if uninitialized, reject non-admin players
	--
	if not reg_id then
		if minetest.check_player_privs(player, {server = true}) then
			minetest.chat_send_player(player:get_player_name(),
				"This server needs to be registered with a mt2fa server in order to allow " ..
				"players without the \"server\" priv to log on. To register, use `/mt2fa register <email>` " ..
				"to start the registration process.")
			return
		else
			minetest.kick_player(player:get_player_name(),
				"This server is not properly initialized yet. Come back later.")
			return
		end
	end

	--
	-- Player registration and Authentication
	--

	-- start the process
	local name = player:get_player_name()
	logins[name] = os.time() + reg_grace
	privs[name] = minetest.get_player_privs(name)
	minetest.set_player_privs(name, {})

	local reg = player:get_attribute("mt2fa.registered")
	if req_reg or player:get_attribute("mt2fa.auth_required") == "1" then
		if reg ~= "1" then
			-- ask for email
			fsc.show(name, forms.email, {},
				function(p, fields, c)
					if not fields.email then
						fields.quit = nil
						return
						--FIXME reopen
					end
					send_request("REG", p, {
						required = true,
						email = fields.email,
					})
				end
			)
		else
			-- already registered
			send_request("AUTH", player, {required = true})
		end
	else
		-- offer to register
		fsc.show(name, forms.register, {required = false},
			function(p, fields, c)
				if not fields.register then
					return true
				end
				-- ask for email
				fsc.show(name, forms.email, c,
					function(pl, f, co)
						if not f.email then
							return
						end
						send_request("REG", pl, {email = f.email})
					end
				)
				return true
			end)

		if req_auth then
			if reg == "1" then
				-- authentication must be performed
				send_request("AUTH", player, {required = true})
			end
		else
			if reg == "1" then
				-- check if the user account on the server has
				-- been marked as `require 2fa authentication`
				send_request("ACCT", player, {})
			end
		end
	end
end)

minetest.register_on_leaveplayer(function(player)
	-- cleanup stuff
	local name = player:get_player_name()
	logins[name] = nil
	if privs[name] then
		minetest.set_player_privs(name, privs[name])
		privs[name] = nil
	end
end)

local function do_grace()
	minetest.after(7, do_grace)

	local t = os.time()
	for k, v in pairs(logins) do
		if v > t then
			minetest.kick_player(k, "You did not authenticate or register within the allowed time limit.")
		end
	end
end
minetest.after(reg_grace, do_grace)

local function do_updates(first)
	minetest.after(15 * 60, do_updates, false)

	if not reg_id then
		return
	end

	local post_data = {
		request_type = "UPDATES",
		server_id = reg_id,
	}
	if first then
		post_data.server_data = {
			owner = S:get("name"),
			name = S:get("server_name"),
			address = S:get("server_address"),
			url = S:get("server_url"),
			announce = S:get("server_announce"),
			announce_url = S:get("serverlist_url"),
		}
	end

	http.fetch({
		url = reg_api,
		post_data = minetest.write_json(post_data),
		timeout = 15,
	}, function(res)
		assert(res.completed)
		if not res.succeeded then
			-- major problem, retry
			minetest.log("error", "mt2fa: server replied with an error code")
			return
		end
		local data = minetest.parse_json(res.data)
		if not data then
			-- major problem, retry
			minetest.log("error", "mt2fa: failed to parse JSON from mt2fa server")
			return
		end

		minetest.log("action", "mt2fa: received " .. data.result)
	end)
end
minetest.after(3, do_updates, true)
--
-- admin/server command
--
minetest.register_chatcommand("mt2fa", {
	params = "mt2fa server",
	description = "Administrate 2-factor authentication services",
	privs = {server = true},
	func = function(name, param)
		if param:sub(1,9) == "register " then
			if reg_id then
				return false, "This server already has a server ID - you have already registered it."
			end
			local email = param:sub(10)
			local player = minetest.get_player_by_name(name)
			assert(player)
			send_request("SERVER", player, {
				email = email,
				server_data = {
					owner = S:get("name"),
					name = S:get("server_name"),
					address = S:get("server_address"),
					url = S:get("server_url"),
					announce = S:get("server_announce"),
					announce_url = S:get("serverlist_url"),
				},
			})
		elseif param:sub(1,9) == "ipchange " then
			local email = param:sub(10)
			local player = minetest.get_player_by_name(name)
			assert(player)
			send_request("SERVERIP", player, {
				email = email,
				server_data = {
					owner = S:get("name"),
					name = S:get("server_name"),
					address = S:get("server_address"),
					url = S:get("server_url"),
					announce = S:get("server_announce"),
					announce_url = S:get("serverlist_url"),
				},
			})
		else
			return true, "Usage: /mt2fa [register|ipchange] <email>"
		end
	end
})

--
-- TODO: add cli commands for server operator to obtain and renew mt2fa tokens
-- for the server.
--

-- TODO: cli for modifying auth_required for local players
