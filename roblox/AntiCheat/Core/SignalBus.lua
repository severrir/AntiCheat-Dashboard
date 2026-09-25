local Signal = require(script.Parent.Signal)

-- game code can listen to these through the API module
return {
	Flagged = Signal.new(), -- (player, check, amount, score, ctx)
	Kicked = Signal.new(), -- (player, reason, score)
}
