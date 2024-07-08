local discordia = require("discordia")
local enums = require("enums")

require("voice/VoiceSocket")
require("voice/VoiceConnection")
require("containers/VoiceUserMap")
require("containers/VoiceUser")

do
	local discordiaEnums = discordia.enums
	local enum = discordiaEnums.enum
	for k, v in pairs(enums) do
		discordiaEnums[k] = enum(v)
	end
end

do
---@class Member
---@field voiceUser VoiceUser|nil The voice user object for this member, if they are in your voice channel.
---<!tag:patch>
	local oldMember = discordia.class.classes.Member
	oldMember.__getters.voiceUser = function(self)
		return self._guild._connection
	end
end

return discordia
