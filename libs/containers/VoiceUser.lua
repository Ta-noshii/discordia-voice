---@diagnostic disable: different-requires
local discordia = require("discordia")
local timer = require('timer')

local class = discordia.class
local classes = class.classes
local Emitter = classes.Emitter
local Container = classes.Container

local opus = require('discordia/libs/voice/opus')

---@class VoiceUser
---Represents a user in a VoiceUserMap.
---@field id string The user's ID.
---@field user User The user object.
---@field member Member The member object.
---@field flags number The user's flags.
---@field platform? number|nil Corresponds to enums.platformType.
---@field audioSSRC number The user's audio SSRC.
---@field videoSSRC? number The user's video SSRC.
---@field speaking boolean Whether the user is speaking.
---@field subscribed boolean Whether the user is subscribed to the audio stream.
---@field decoder? OpusDecoder The user's Opus decoder.
---@field connection VoiceConnection The voice connection.
---@field lastSequence? number The last sequence number received.
---@field map VoiceUserMap The map the user is in.
local VoiceUser, get = class('VoiceUser', Emitter, Container)

local SPEECH_TIMEOUT = 1000 -- ms
local SAMPLE_RATE = 48000
local CHANNELS = 2

local setTimeout = timer.setTimeout

function VoiceUser:__init(map, data)
    Container.__init(self, {
        id = data.user_id,
        speaking = false,
        subscribed = false,
        flags = data.flags,
        audioSSRC = data.ssrc,
        platform = data.platform, -- may be nil
        videoSSRC = nil,
        decoder = nil,
        last_seq = nil
    }, map)
    Emitter.__init(self)

    self._connection = map._connection
    self._member = map._connection._channel._parent:getMember(data.user_id) -- switch to relying on user?
end

function VoiceUser:__hash()
    return self._id
end

---Sets the user's speaking status.
---@param ssrc? number
---<!tag:mem>
function VoiceUser:setSpeaking(ssrc)
    self._audioSSRC = ssrc or self._audioSSRC

    local speaking = self._speaking
    if not speaking then
        self._speaking = true
        self._speechTimer = setTimeout(SPEECH_TIMEOUT, function()
            self._speaking = false
            self._speechTimer = nil
            self:emit('speaking', false)
        end)
        self:emit('speaking', true)
    else
        timer.clearTimeout(self._speechTimer)
        self._speechTimer = setTimeout(SPEECH_TIMEOUT, function()
            self._speaking = false
            self._speechTimer = nil
            self:emit('speaking', false)
        end)
    end
end

---Subscribes to the user's audio stream.
---@return boolean success Whether the user was successfully subscribed to.
---<!tag:mem>
function VoiceUser:subscribe()
    if self._subscribed then return true end

    self._subscribed = true
    self._decoder = opus.Decoder(SAMPLE_RATE, CHANNELS)
    self._last_seq = -1

    self._connection._socket:info('Subscribed to Member %s (%s)', self._member.name, self._id)

    return true
end

---Unsubscribes from the user's audio stream.
---@return boolean success Whether the user was successfully unsubscribed from.
---<!tag:mem>
function VoiceUser:unsubscribe()
    self._subscribed = false
    self._decoder = nil
    self._last_seq = nil

    self:emit('speaking', false)
    self:removeAllListeners()

    return true
end

---Disconnects the user from the map.
---If you're looking to disconnect a user from the channel, use `Member:setVoiceChannel(nil)`.
---@return boolean success Whether the user was found and disconnected.
---@return string|nil errorMessage The error message if the user was not found.
---<!tag:mem>
function VoiceUser:disconnect()
    return self._parent:disconnect(self._id)
end

function get.id(self)
    return self._id
end

function get.user(self)
    return self._member._user
end

function get.member(self)
    return self._member
end

function get.flags(self)
    return self._flags
end

function get.platform(self)
    return self._platform
end

function get.audioSSRC(self)
    return self._audioSSRC
end

function get.videoSSRC(self)
    return self._videoSSRC
end

function get.speaking(self)
    return self._speaking
end

function get.subscribed(self)
    return self._subscribed
end

function get.decoder(self)
    return self._decoder
end

function get.map(self)
    return self._parent
end

function get.connection(self)
    return self._connection
end

function get.lastSequence(self)
    return self._last_seq
end

return VoiceUser