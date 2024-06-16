---@diagnostic disable: different-requires
local discordia = require("discordia")
local class = discordia.class
local classes = class.classes

local Container = classes.Container
local Iterable = classes.Iterable
local Emitter = classes.Emitter

local VoiceUser = require('containers/VoiceUser')

---@class VoiceUserMap : Container, Emitter, Iterable
---Represents a map of users in a voice channel.
---@field id string The channel's ID.
---@field connection VoiceConnection The voice connection.
---@field channel VoiceChannel The voice channel.
---@field me VoiceUser The client's user in the channel.
local VoiceUserMap, get = class('VoiceUserMap', Container, Emitter, Iterable)

function VoiceUserMap:__init(connection)
    Container.__init(self, {}, connection)
    Emitter.__init(self)

    self._channel = connection._channel
    self._id = self._channel._id
    self._connection = connection
    self._users = {}
end

function VoiceUserMap:__hash()
    return self._id
end

function VoiceUserMap:iter()
    local i = 0

    return function()
        i = i + 1
        return self._users[i]
    end
end

function VoiceUserMap:_insert(data)
    local voiceUser = VoiceUser(self, data)
    table.insert(self._users, voiceUser)
    self:emit('join', voiceUser)

    return voiceUser
end

---Removes a user from the map.
---If you're looking to disconnect a user from the channel, use `Member:setVoiceChannel(nil)`.
---@param user VoiceUser|table|string
---@return boolean success Whether the user was found and disconnected.
---@return string|nil errorMessage The error message if the user was not found.
---<!tag:mem>
function VoiceUserMap:disconnect(user)
    local userId = type(user) == 'table' and user.id or user
    local voiceUser = self:get(userId)

    if voiceUser then
        voiceUser:unsubscribe()
        self:emit('leave', voiceUser)
        for i in ipairs(self._users) do
            if self._users[i] == voiceUser then
                table.remove(self._users, i)
                break
            end
        end
    else
        return false, 'User not found'
    end

	return true
end

---Subscribes to a user in the map to start processing their audio stream.
---@param userIdOrAudioSSRC string|number
---@return VoiceUser|nil TargetUser
---@return string|nil ErrorMessage
---<!tag:mem>
function VoiceUserMap:subscribe(userIdOrAudioSSRC)
    if type(userIdOrAudioSSRC) == 'table' then
        userIdOrAudioSSRC = userIdOrAudioSSRC.id
    end

    local voiceUser = self:find(function(voiceUser)
        return voiceUser.id == userIdOrAudioSSRC or voiceUser.audioSSRC == userIdOrAudioSSRC
    end)

    if voiceUser then
        return voiceUser:subscribe()
    else
        return nil, 'User not found'
    end
end

---Unsubscribes from a user in the map to stop processing their audio stream.
---@param userIdOrAudioSSRC string|number
---@return VoiceUser|nil
---@return string|nil
---<!tag:mem>
function VoiceUserMap:unsubscribe(userIdOrAudioSSRC)
    if type(userIdOrAudioSSRC) == 'table' then
        userIdOrAudioSSRC = userIdOrAudioSSRC.id
    end

    local voiceUser = self:find(function(voiceUser)
        return voiceUser.id == userIdOrAudioSSRC or voiceUser.audioSSRC == userIdOrAudioSSRC
    end)

    if voiceUser then
        return voiceUser:unsubscribe()
    else
        return nil, 'User not found'
    end
end

---Subscribes to all users in the channel.
---<!tag:mem>
function VoiceUserMap:subscribeAll()
    self:forEach(function(voiceUser)
        voiceUser:subscribe()
    end)
end

---Unsubscribes from all users in the channel.
---<!tag:mem>
function VoiceUserMap:unsubscribeAll()
    self:forEach(function(voiceUser)
        voiceUser:unsubscribe()
    end)
end

function get.id(self)
    return self._id
end

function get.connection(self)
    return self._connection
end

function get.channel(self)
    return self._channel
end

function get.me(self)
	return self:get(self._channel.client._user._id)
end

return VoiceUserMap