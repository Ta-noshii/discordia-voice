---@diagnostic disable: different-requires
--[=[
@c VoiceConnection
@d Represents a connection to a Discord voice server.
]=]
local discordia = require("discordia")
local class = discordia.class
local classes = class.classes

local VoiceUserMap = require('containers/VoiceUserMap')

local ffi = require('ffi')
local constants = require('discordia/libs/constants')
local opus = require('discordia/libs/voice/opus') or {}
local sodium = require('discordia/libs/voice/sodium') or {}

local CHANNELS = 2
local SAMPLE_RATE = 48000 -- Hz
local FRAME_DURATION = 20 -- ms
local COMPLEXITY = 5

local MIN_BITRATE = 8000 -- bps
local MAX_BITRATE = 128000 -- bps
local MIN_COMPLEXITY = 0
local MAX_COMPLEXITY = 10

local MAX_SEQUENCE = 0xFFFF
local MAX_TIMESTAMP = 0xFFFFFFFF
local MAX_NONCE = 0xFFFFFFFF

local HEADER_FMT = '>BBI2I4I4'  -- rtp_version, payload_type, seq, timestamp, ssrc
local PADDING = string.rep('\0', 12)

local MS_PER_NS = 1 / (constants.NS_PER_US * constants.US_PER_MS)
local MS_PER_S = constants.MS_PER_S

local FRAME_SIZE = SAMPLE_RATE * FRAME_DURATION / MS_PER_S -- 960
local MAX_FRAME_SIZE = FRAME_SIZE * CHANNELS * 2 -- 3840
local BIT_DEPTH = 16

local ffi_string = ffi.string
local format, unpack = string.format, string.unpack -- luacheck: ignore
local wrap = coroutine.wrap

---@class VoiceConnection
---@field map VoiceUserMap The VoiceUserMap for this connection.
---<!tag:patch>
local VoiceConnection = classes.VoiceConnection
local get = VoiceConnection.__getters

function VoiceConnection:__init(channel)
	self._channel = channel
	self._pending = {}
	self._map = VoiceUserMap(self)
end

function VoiceConnection:_prepare(key, socket)

	self._key = sodium.key(key)
	self._socket = socket
	self._ip = socket._ip
	self._port = socket._port
	self._udp = socket._udp
	self._ssrc = socket._ssrc
	self._mode = socket._mode
	self._nonce = socket._nonce
	self._manager = socket._manager
	self._client = socket._client

	self._s = 0
	self._t = 0

	self._encoder = opus.Encoder(SAMPLE_RATE, CHANNELS)
	self._decoder = opus.Decoder(SAMPLE_RATE, CHANNELS)

	self:setBitrate(self._client._options.bitrate)
	self:setComplexity(COMPLEXITY)

	self._ready = true
	self:_continue(true)

end

---The function that handles the UDP packets received by the voice connection.
---@param packet string The UDP packet received by the voice connection.
function VoiceConnection:onUDPPacket(packet)
	local warning, _error = function(...) -- hoping to remove this after debugging
		self._socket:warning(...)
	end, function(...)
		self._socket:error(...)
	end

	-- if #packet == 48 then -- 0xc9, no idea how to parse, sent periodically
	-- 	return warning('Ignored UDP packet (%i == 48) %s', #packet, hex(packet))
	-- end

	if #packet <= 8 then
		return -- warning('Ignored UDP packet (%i <= 8) %s', #packet, hex(packet))
	end

	if unpack('>I1', packet, 2) ~= 0x78 then -- (payload_type ~= 0x78) ignore non-Opus packets, usually just receiver reports (0xc9)
		return -- warning('Ignored non-Opus UDP packet (0x%s) %s', format('%x', unpack('>I1', packet, 2)), hex(packet))
	end

	if not self._socket then return end

	return wrap(function()
		local ssrc = unpack('>I4', packet, 9)
		local voiceUser = self._map:find(function(voiceUser)
			return voiceUser._audioSSRC == ssrc
		end)

		if not voiceUser then return warning('Received audio data for unknown SSRC %i', ssrc) end
		voiceUser:setSpeaking()
		if not voiceUser._subscribed then return end
		local key = self._key

		if not key then
			return _error('Secret key not available')
		end

		local _end
		if self._mode == 'xsalsa20_poly1305_lite' then -- read -4
			_end = 4
		elseif self._mode == 'xsalsa20_poly1305_suffix' then -- read -24
			_end = 24
		else -- read all xsalsa20_poly1305
			_end = 0
		end

		local header, encrypted = packet:sub(1, 12), packet:sub(13, #packet - _end)
		local nonce = header .. PADDING
		local decoder, last_sequence = voiceUser._decoder, voiceUser._last_seq
		local rtp_version, payload_type, sequence, timestamp = unpack(HEADER_FMT, packet) -- we are discarding ssrc

		-- ignore out of order packets
		if (last_sequence > sequence) and (last_sequence - sequence <= 10) then
			return warning('[#%i | %s] Ignored out of order packet #%i seq %i ts %i', ssrc, voiceUser.member.name, #encrypted, sequence, timestamp)
		else
			voiceUser._last_seq = sequence
		end

		-- debug('[#%i | %s] Received %sRTP 0x%s packet #%i seq %i ts %i', ssrc, voiceUser.member.name, (rtp_version == 0x80 and '' or 'S'), format('%x', payload_type), #encrypted, sequence, timestamp)

		if rtp_version ~= 0x80 and rtp_version ~= 0x90 then
			return _error('Invalid RTP version %i', rtp_version) -- 0x80 = RTP, 0x90 = SRTP
		end

		local success, decrypted, decrypted_len = pcall(sodium.decrypt, encrypted, #encrypted, nonce, key)
		if not success then
			return _error('Decryption failed %i: %s', #packet, decrypted)
		end

		-- Strip RTP Header Extensions (one-byte only) RFC 5285
		-- ..check if this is an extended header
		-- for extended header the bit at 000X is set
		local offset = 0
		if bit.band(packet:byte(1), 0x10) ~= 0 then
			-- read header length from packet
			local header_length = unpack(">xxH", ffi_string(decrypted, decrypted_len))
			offset = offset + 4 + (header_length * 4)
		end

		if payload_type == 0x78 then -- 0x78 = 120 = opus
			decrypted, decrypted_len = decrypted + offset, tonumber(decrypted_len) - offset

			local success, pcm = pcall(decoder.decode, decoder, decrypted, decrypted_len, FRAME_SIZE, MAX_FRAME_SIZE)

			if success then
				voiceUser:emit('pcm', pcm, MAX_FRAME_SIZE, sequence, last_sequence)
				voiceUser:emit('pcmString', ffi_string(pcm, MAX_FRAME_SIZE))
			else
				_error('Opus decode failed: %s', pcm)
			end
		else
			_error('Unknown payload type %i', payload_type)
		end
	end)()
end

function get.map(self)
	return self._map
end

return VoiceConnection
