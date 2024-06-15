local discordia = require("discordia")
local enums = require("enums")

do
	local oldMember = discordia.class.classes.Member
	oldMember.__getters.voiceUser = function(self)
		return self._guild._connection
	end
end

discordia.voice = {
	VoiceConnection = require("voice/VoiceConnection"),
	VoiceSocket = require("voice/VoiceSocket"),
	VoiceUser = require("containers/VoiceUser"),
	VoiceUserMap = require("containers/VoiceUserMap")
}

return discordia.voice