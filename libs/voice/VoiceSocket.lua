---@diagnostic disable: different-requires
local uv = require('uv')

local discordia = require("discordia")
local class = discordia.class
local classes = class.classes

local wrap = coroutine.wrap
local unpack, pack = string.unpack, string.pack -- luacheck: ignore

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
local CHANNEL_USERS      = 11
local NEW_CLIENT_CONNECT = 12
local CLIENT_DISCONNECT  = 13
-- 15 recv {"op":15,"d":{"any":100}}
local REQUEST_VERSIONS   = 16
local CLIENT_FLAGS       = 18
local CLIENT_PLATFORM    = 20

---@class VoiceSocket
---<!tag:patch>
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

local originalHandlePayload = VoiceSocket.handlePayload
---Handles the WebSocket payloads.
---@param payload table The payload.
function VoiceSocket:handlePayload(payload)

	local connection = self._connection
	local map = connection._map

	local d = payload.d
	local op = payload.op

	if op == DESCRIPTION then

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

	elseif op == SPEAKING then

		local voiceUser = map:get(d.user_id)

		if not voiceUser then
			voiceUser = map:_insert(d)
		end

		voiceUser._audioSSRC = d.ssrc or voiceUser._audioSSRC

	elseif op == CHANNEL_USERS then

		for _, user_id in ipairs(d.user_ids) do
			map:_insert({ user_id = user_id })
		end

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

	else

		return originalHandlePayload(self, payload)

	end

	self:debug('WebSocket OP %s', op)

	if payload.seq then
		self._seq_ack = payload.seq
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

	udp:recv_start(function(err, packet)
		assert(not err, err)

		if not self._handshaked then
			-- handshake
			self._handshaked = true

			local client_ip = unpack("xxxxxxxxz", packet)
			local client_port = unpack("<I2", packet, -2)
			return wrap(self.selectProtocol)(self, client_ip, client_port)
		else

			if not packet then
				return
			end

			if unpack('>I1', packet, 2) ~= 0x78 then -- payload_type == 0x78 (Opus audio packet)
				return
			end

			return wrap(self._connection.onAudioPacket)(self._connection, packet)
		end
	end)

	local packet = pack('>I2I2I4c64H', 0x1, 70, self._ssrc, self._ip, self._port) -- ip discovery packet
	return udp:send(packet, server_ip, server_port, function(err)
		assert(not err, err)
	end)

end

return VoiceSocket
