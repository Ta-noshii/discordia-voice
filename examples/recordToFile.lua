-- Get the target user from the voice user map
local voiceUser = client.connection.map:get(targetUser.id)
-- Subscribe to the target user to start receiving voice data
voiceUser:subscribe()

local uv = require "uv"
local fs = require "fs"

local now = uv.now

local path = "./voiceData.pcm"
local last_ts = now()
local CHANNELS, BIT_DEPTH, SAMPLE_RATE, MS_PER_S = 2, 16, 48000, 1000
local PCM_SILENCE = string.rep("\0", SAMPLE_RATE * CHANNELS * (BIT_DEPTH / 8) / MS_PER_S)

voiceUser:on('pcmString', function(pcmString)
    local ts = now()
    local gap = ts - last_ts
    last_ts = ts

    if gap < 100 then gap = 0 end

	-- Append the PCM data along with the calculated silence to the file
	local success, err = fs.appendFileSync(path, PCM_SILENCE:rep(gap) .. pcmString)
	if not success then
		print("Failed to write voice data to file: " .. err)
	end
end)

-- When you're done listening, unsubscribe from the target to stop receiving voice data
voiceUser:unsubscribe()