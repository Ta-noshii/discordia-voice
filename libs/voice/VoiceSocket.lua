---@diagnostic disable: different-requires
local uv = require('uv')
local timer = require('timer')

local discordia = require("discordia")
local class = discordia.class
local classes = class.classes

local sodium = require('discordia/libs/voice/sodium')

local wrap = coroutine.wrap
local unpack, pack = string.unpack, string.pack -- luacheck: ignore

local ENCRYPTION_MODE = 'xsalsa20_poly1305'

local CHANNELS, BIT_DEPTH, SAMPLE_RATE, MS_PER_S = 2, 16, 48000, 1000
local PCM_SILENCE = string.rep("\0", SAMPLE_RATE * CHANNELS * (BIT_DEPTH / 8) / MS_PER_S)

local IDENTIFY           = 0
local SELECT_PROTOCOL    = 1
local READY              = 2
local HEARTBEAT          = 3
local DESCRIPTION		 = 4
local SPEAKING           = 5
local HEARTBEAT_ACK      = 6
local RESUME             = 7
local HELLO              = 8
local RESUMED            = 9
local NEW_CLIENT_CONNECT = 12
local CLIENT_DISCONNECT  = 13
-- 15 recv {"op":15,"d":{"any":100}}
-- 16 recv {"op":16,"d":{}} send: {"op":16,"d":{"voice":"0.10.0","rtc_worker":"0.4.0"}}
local CLIENT_FLAGS       = 18
local CLIENT_PLATFORM    = 20

local function checkMode(modes)
	for _, mode in ipairs(modes) do
		if mode == ENCRYPTION_MODE then
			return mode
		end
	end
end

local VoiceSocket = classes.VoiceSocket

---Handles disconnecting/reconnecting to the voice server.
function VoiceSocket:handleDisconnect()
	-- reconnecting and resuming
	local newChannelId = self._state and self._state.channel_id or nil
	local oldChannelId = self._connection._channel_id or nil
	if newChannelId and oldChannelId and newChannelId ~= oldChannelId then
		-- connect to new channel
		self:info('Connecting to %s', newChannelId)
		self._connection:_prepare(newChannelId, self)
	else
		self:info('Disconnected')
		self._connection:_cleanup()
	end
end

---Handles the WebSocket payloads.
---@param payload {d: table, op: integer} The payload.
function VoiceSocket:handlePayload(payload)

	local manager = self._manager
	local connection = self._connection
	local map = connection._map

	local d = payload.d
	local op = payload.op

	self:debug('WebSocket OP %s', op)

	if op == HELLO then

		self:info('Received HELLO')
		self:startHeartbeat(d.heartbeat_interval * 0.75) -- NOTE: hotfix for API bug
		self:identify()

	elseif op == READY then

		self:info('Received READY')
		local mode = checkMode(d.modes)
		if mode then
			self._mode = mode
			self._ssrc = d.ssrc
			self._nonce = sodium.nonce()

			-- we keep nonce in connection
			self:handshake(d.ip, d.port)
		else
			self:error('No supported encryption mode available')
			self:disconnect()
		end

	elseif op == RESUMED then

		self:info('Received RESUMED')

	elseif op == DESCRIPTION then

		if d.mode == self._mode then
			connection:_prepare(d.secret_key, self)

			map:_insert({
				user_id = self._state.user_id,
				ssrc = self._ssrc,
				flags = 0,
				platform = 0
			})

			connection:playPCM(PCM_SILENCE) -- required to start receiving UDP voice data and send voice data
		else
			self:error('%q encryption mode not available', self._mode)
			self:disconnect()
		end

	elseif op == HEARTBEAT_ACK then

		manager:emit('heartbeat', nil, self._sw.milliseconds) -- TODO: id

	elseif op == SPEAKING then

		local voiceUser = map:get(d.user_id)

		if not voiceUser then
			voiceUser = map:_insert(d)
		end

		voiceUser._audioSSRC = d.ssrc or voiceUser._audioSSRC

	elseif op == NEW_CLIENT_CONNECT then

		map:_insert(d)

	elseif op == CLIENT_DISCONNECT then

		map:disconnect(d.user_id)

	elseif op == CLIENT_FLAGS then

		local voiceUser = map:get(d.user_id)

		if voiceUser then
			voiceUser._flags = d.flags
		else
			map:_insert(d)
		end

	elseif op == CLIENT_PLATFORM then

		local voiceUser = map:get(d.user_id)

		if voiceUser then
			voiceUser._platform = d.platform
		else -- discord always sends CLIENT_FLAGS before CLIENT_PLATFORM, so we dont need to reinsert the user
			self:warning('User %s platform changed but not found in map', d.user_id)
		end

	elseif op then

		self:warning('Unhandled WebSocket payload OP %i', op)

	end

end

---Handles the WebSocket handshake.
---@param server_ip string The server IP.
---@param server_port number The server port.
---@return uv_udp_send_t|nil send The UDP send handle.
function VoiceSocket:handshake(server_ip, server_port)
	local udp = uv.new_udp()
	self._udp = udp
	self._ip = server_ip
	self._port = server_port

	udp:recv_start(function(err, data)
		if not self._handshaked then
			-- handshake
			assert(not err, err)
			self._handshaked = true
			local client_ip = unpack("xxxxxxxxz", data)
			local client_port = unpack("<I2", data, -2)
			return wrap(self.selectProtocol)(self, client_ip, client_port)
		else
			-- voice data
			assert(not err, err)

			if not data then
				return
			end

			return wrap(self._connection.onUDPPacket)(self._connection, data)
		end
	end)

	local packet = pack('>I2I2I4c64H', 0x1, 70, self._ssrc, self._ip, self._port) -- ip discovery packet
	return udp:send(packet, server_ip, server_port, function(err)
		assert(not err, err)
	end)
end

return VoiceSocket
