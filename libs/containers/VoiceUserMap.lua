---@diagnostic disable: different-requires
local discordia = require("discordia")
local class = discordia.class
local classes = class.classes

local Container = classes.Container
local Iterable = classes.Iterable
local Emitter = classes.Emitter

local VoiceUser = require('containers/VoiceUser')

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
    member = VoiceUser(self, data)
    table.insert(self._users, member)
    self:emit('join', member)

    return member
end

function VoiceUserMap:disconnect(user)
    local userId = type(user) == 'table' and user.id or user

    local voiceUser = self:get(userId)
    if voiceUser then
        voiceUser:unsubscribe()
        self:emit('delete', voiceUser)
        for i in ipairs(self._users) do
            if self._users[i] == voiceUser then
                table.remove(self._users, i)
                break
            end
        end
    else
        return nil, 'User not found'
    end
end

function VoiceUserMap:subscribe(userIdOrAudioSSRC)
    if type(userIdOrAudioSSRC) == 'table' then
        userIdOrAudioSSRC = userIdOrAudioSSRC.id
    end

    local voiceUser = self:find(function()
        return member.id == userIdOrAudioSSRC or member.audioSSRC == userIdOrAudioSSRC
    end)

    if voiceUser then
        return voiceUser:subscribe()
    else
        return nil, 'User not found'
    end
end

function VoiceUserMap:unsubscribe(userIdOrAudioSSRC)
    if type(userIdOrAudioSSRC) == 'table' then
        userIdOrAudioSSRC = userIdOrAudioSSRC.id
    end

    local voiceUser = self:find(function()
        return member.id == userIdOrAudioSSRC or member.audioSSRC == userIdOrAudioSSRC
    end)

    if voiceUser then
        return voiceUser:unsubscribe()
    else
        return nil, 'User not found'
    end
end

function VoiceUserMap:subscribeAll()
    self:forEach(function(user)
        user:subscribe()
    end)
end

function VoiceUserMap:unsubscribeAll()
    self:forEach(function(user)
        user:unsubscribe()
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