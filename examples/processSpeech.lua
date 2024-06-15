-- Get the target user from the voice user map
local voiceUser = client.connection.map:get(targetUser.id)
-- Subscribe to the target user to start receiving voice data
voiceUser:subscribe()

local uv = require "uv"

local now = uv.now

local last_ts = now()
local TIMEOUT = 5000 -- The amount of time you want to wait for the target to stop speaking in milliseconds
local CHANNELS, BIT_DEPTH, SAMPLE_RATE, MS_PER_S = 2, 16, 48000, 1000
local PCM_SILENCE = string.rep("\0", SAMPLE_RATE * CHANNELS * (BIT_DEPTH / 8) / MS_PER_S)

local voiceData = ""

voiceUser:on('speaking', function(isSpeaking)
  if not isSpeaking then return end

  voiceUser:on('pcmString', function(pcmString)
    local ts = now()
    local gap = ts - last_ts
    last_ts = ts

    if gap < 100 then gap = 0 end

	-- Append the PCM data along with the calculated silence to the voiceData string
    voiceData = voiceData .. PCM_SILENCE:rep(gap) .. pcmString
  end)

  -- Wait for the target to stop speaking
  voiceUser:waitFor('speaking', TIMEOUT, function(isSpeaking)
	return not isSpeaking
  end)

  -- Unsubscribe from the target, only if you don't want to receive any more data
  voiceUser:unsubscribe()

  -- Your custom voice handling code here

  voiceData = ""
end)